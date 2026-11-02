import Cocoa
import Combine
import SwiftUI

// ---------------------------------------------------------------------------
// 拖放：左半隔空投送、右半文件托盘
//
// 事件入口在 main.swift 的 PassthroughView（registerForDraggedTypes）。
// 这里只做语义：当前落点在哪半边、松手之后交给谁、托盘列表怎么发布。
//
// 岛体展开仍由 PointerMonitor 负责：拖拽期间系统不发 mouseMoved，
// 但 mouseDragged 带位置，光标进刘海那一刻岛就展开了，随后才谈落点。
// 左右判定按落点在岛体内的 x：左半 AirDrop、右半托盘。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

enum DropSide: Equatable {
    case airDrop
    case tray
}

final class DropReceiver: ObservableObject {
    /// 是否有文件正拖在岛上（决定落点提示显不显示）
    @Published private(set) var isDragging = false
    /// 当前落点；nil 表示拖拽中但还没判定
    @Published private(set) var side: DropSide?
    /// 托盘列表：由这里统一发布，TrayStore 只管磁盘
    @Published private(set) var trayItems: [TrayItem] = []
    /// 一行提示（超限/复制失败），显示在托盘底部，不弹窗
    @Published private(set) var notice: String?

    private let tray = TrayStore()
    private let airDrop = AirDropService()

    init() {
        trayItems = tray.items
    }

    // MARK: - 拖拽会话

    func beginDrag(side: DropSide?) {
        if !isDragging { isDragging = true }
        if self.side != side { self.side = side }
    }

    func update(side: DropSide?) {
        guard self.side != side else { return }
        self.side = side
    }

    func endDrag() {
        if isDragging { isDragging = false }
        if side != nil { side = nil }
    }

    /// 松手：先收起落点提示，再按半边分发
    func handleDrop(_ urls: [URL]) {
        let target = side ?? .tray
        endDrag()
        switch target {
        case .airDrop:
            airDrop.send(urls)
        case .tray:
            notice = nil
            // 复制可能上百 MB，由 TrayStore 放后台；回主线程后才写列表
            tray.importFiles(urls) { [weak self] notice in
                guard let self = self else { return }
                self.trayItems = self.tray.items
                self.notice = notice
            }
        }
    }

    // MARK: - 托盘操作

    func clearTray() {
        tray.clear()
        trayItems = tray.items
        notice = nil
    }

    func reveal(_ item: TrayItem) {
        TrayStore.reveal(item)
    }
}

/// 隔空投送：面板不抢焦点，但分享面板要先有前台应用才会正常呈现
final class AirDropService {
    /// 分享服务是异步的，持有到下一次发送，避免中途被释放
    private var activeService: NSSharingService?

    func send(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)

        if let service = NSSharingService(named: .sendViaAirDrop) {
            activeService = service
            service.perform(withItems: urls)
            return
        }

        // 系统没给 AirDrop 服务时退回通用分享面板，至少不吞文件
        activeService = nil
        guard let window = NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView else { return }
        // 锚在岛体正中偏下：宿主视图是 flipped 坐标，.maxY 才是「往下弹」
        let anchor = NSRect(x: view.bounds.midX - 1,
                            y: view.bounds.height / 4,
                            width: 2,
                            height: 2)
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: anchor,
                    of: view,
                    preferredEdge: .maxY)
    }
}

// MARK: - 落点提示

/// 拖拽中盖在内容上的两半提示；当前落点一侧提亮，另一侧保持 0.55
/// 底色用岛体本色（纯黑）盖住内容，落点靠「0.12 淡底 + 白色文字」表达，
/// 不新造中间灰阶、也不加第二圈描边（AGENTS.md 3.1 / 3.4）
struct DropTargetsView: View {
    let side: DropSide?

    var body: some View {
        HStack(spacing: 12) {
            half(icon: "airdrop", title: "隔空投送", isActive: side == .airDrop)
            half(icon: "tray.and.arrow.down", title: "文件托盘", isActive: side == .tray)
        }
        .padding(12)
        .background(Color.black)
        .allowsHitTesting(false)   // 拖拽由 AppKit 事件处理，这里只负责显示
    }

    private func half(icon: String, title: String, isActive: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(isActive ? 1 : 0.55))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: IslandSizeTable.dropTargetCornerRadius, style: .continuous)
                .fill(Color.white.opacity(isActive ? 0.12 : 0))
        )
    }
}