import Cocoa
import Combine

// ---------------------------------------------------------------------------
// 全局鼠标位置 → 热区判定
//
// 为什么不继续用 onHover：收起态视图比刘海宽 80pt（两侧各 40，放音源图标与波形），onHover 会把菜单栏左右两侧
// 一起算进热区，光标只是路过菜单栏就把岛撑开，展开后又挡住下面的文本与按钮。
// 这里改成只认物理刘海本身（由调用方给出热区矩形）。
//
// 判定模型：进入严格、停留宽容
// - 进入：光标必须真的落进热区（与 main.swift 的命中区口径一致，不扩大可展开范围）
// - 停留：热区外扩 staySlop，光标贴在面板底沿/左右沿时不会因为亚像素抖动被踢出去
// - 离开：不再单次采样拍板，改成每 0.12s 采一次、连续 3 次都在宽容热区外才收
//   （合计 ≈0.36s，与原来 0.35s 的手感一致，但抗单次误判）
// - 热区变更：若光标仍在「旧热区」里，保留展开状态，等下一轮采样再判，
//   避免换档位差 4pt、屏幕参数刷新时把正在看面板的用户收掉
// 拖拽文件时系统不发 mouseMoved，但 mouseDragged 同样带位置，所以拖进刘海也能判到。
// 全局监听鼠标移动不需要辅助功能授权；监听器只在 stop/deinit 移除，不重复注册。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

/// 没有 @Published：位置每帧都在变，发布出去只会让整个岛每帧重渲染；
/// 对外只暴露「进入/离开」这一次翻转（onInsideChange）
final class PointerMonitor: ObservableObject {
    /// 进入/离开热区时回调一次；只在状态真正翻转时触发，不是每帧都调
    var onInsideChange: ((Bool) -> Void)?

    /// 热区（屏幕坐标，左下角原点）。收起态是刘海矩形，展开态是整块面板
    private var zone: CGRect = .zero
    private var inside = false
    private var monitors: [Any] = []
    private var leaveChecks: DispatchWorkItem?

    /// 停留宽容量：只在「已经展开」后生效，避免光标贴边抖动导致反复收起
    private static let staySlop: CGFloat = 6
    /// 离开确认的采样间隔与次数：0.12 × 3 ≈ 0.36s，与原来的 0.35s 宽限等价
    private static let leaveCheckInterval: TimeInterval = 0.12
    private static let leaveConfirmCount = 3

    deinit {
        stop()
    }

    func start() {
        guard monitors.isEmpty else { return }
        // 只监听「移动」类事件：keyDown 才需要授权，这里不需要
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged,
                                           .rightMouseDragged, .otherMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.evaluate()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.evaluate()
            return event
        }) {
            monitors.append(local)
        }
        IslandDebug.log("ptr", "start monitors=\(monitors.count)")
    }

    func stop() {
        cancelLeave()
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
    }

    /// 展开/收起、换档位、换场景、屏幕几何变化时调用：光标没动也要重新判一次
    /// - Parameter reason: 只用于诊断日志，标明这次热区来自哪条路径
    func update(zone rect: CGRect, reason: String) {
        let old = zone
        zone = rect
        let mouse = NSEvent.mouseLocation
        IslandDebug.log("zone",
                        "reason=\(reason) inside=\(inside) mouse=\(IslandDebug.point(mouse)) "
                        + "old=[\(IslandDebug.rect(old))] new=[\(IslandDebug.rect(rect))]")

        // 光标还在旧热区里：这次缩的是热区（换档位差几 pt、屏幕几何刷新），
        // 不是用户真的移开，先保留展开，别把正在看面板的人收掉
        if inside, !stayZone.contains(mouse), old.contains(mouse) {
            IslandDebug.log("zone", "keep-inside: 光标仍在旧热区，暂不判离开")
            cancelLeave()
            return
        }
        evaluate()
    }

    /// 已展开时的宽容热区：向外扩 staySlop
    private var stayZone: CGRect {
        zone.insetBy(dx: -Self.staySlop, dy: -Self.staySlop)
    }

    private func evaluate() {
        let mouse = NSEvent.mouseLocation

        if inside {
            // 已展开：用宽容热区判停留，贴边不算离开
            if stayZone.contains(mouse) {
                cancelLeave()
            } else {
                scheduleLeaveChecks()
            }
            return
        }

        // 未展开：用原始热区判进入，不扩大可唤出范围
        guard zone.contains(mouse) else {
            cancelLeave()
            return
        }
        cancelLeave()
        inside = true
        IslandDebug.log("ptr", "enter mouse=\(IslandDebug.point(mouse)) zone=[\(IslandDebug.rect(zone))]")
        onInsideChange?(true)
    }

    /// 起一轮离开确认；已经在跑就不重置（连续出界的计时不能被多次事件拉长）
    private func scheduleLeaveChecks() {
        guard leaveChecks == nil else { return }
        IslandDebug.log("ptr", "leave-arm mouse=\(IslandDebug.point(NSEvent.mouseLocation))")
        runLeaveCheck(remaining: Self.leaveConfirmCount)
    }

    private func runLeaveCheck(remaining: Int) {
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.leaveChecks = nil

            let mouse = NSEvent.mouseLocation
            // 任一采样回到宽容热区就取消整轮确认
            guard !self.stayZone.contains(mouse) else {
                IslandDebug.log("ptr", "leave-cancel mouse=\(IslandDebug.point(mouse))")
                return
            }
            guard remaining <= 1 else {
                self.runLeaveCheck(remaining: remaining - 1)
                return
            }
            self.inside = false
            IslandDebug.log("ptr", "leave-confirmed mouse=\(IslandDebug.point(mouse))")
            self.onInsideChange?(false)
        }
        leaveChecks = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.leaveCheckInterval, execute: work)
    }

    private func cancelLeave() {
        guard leaveChecks != nil else { return }
        leaveChecks?.cancel()
        leaveChecks = nil
        IslandDebug.log("ptr", "leave-cancel")
    }
}