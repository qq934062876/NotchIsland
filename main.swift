import Cocoa
import SwiftUI

// ---------------------------------------------------------------------------
// 刘海灵动岛 · 入口与窗口层
// 黑块贴合刘海 + 光标沉入刘海展开 + 点击穿透 + 岛内媒体控制（视图在 IslandView.swift）
// 构建：./build.sh（swiftc 手工编译，源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

// 找到带刘海的屏幕，返回 (屏幕, 刘海几何)。没刘海返回 nil。
// 尺寸由 NotchSpecResolver 解析：系统探测优先（任何机型都对，不靠机型白名单），
// 系统暂时给不出宽度时才用缓存/兜底，见 NotchGeometry.swift。
func notchInfo() -> (NSScreen, NotchSpec)? {
    let override = debugSpecOverride()
    for screen in NSScreen.screens {
        guard let detected = NotchSpecResolver.resolve(for: screen) else { continue }
        // 覆盖值只在真有刘海的屏上生效，别把兜底尺寸画到外接屏上
        return (screen, override ?? detected)
    }
    return nil
}

/// 调试用刘海尺寸覆盖：`NOTCH_DEBUG=1 NOTCH_SPEC=200x38` 时生效。
/// 手上只有一台机器时用它验证「换成别的刘海尺寸后岛体是否仍贴齐、波形会不会顶出刘海」；
/// 生产运行（NOTCH_DEBUG 未开）完全不受影响
func debugSpecOverride() -> NotchSpec? {
    guard IslandDebug.enabled,
          let raw = ProcessInfo.processInfo.environment["NOTCH_SPEC"] else { return nil }
    let parts = raw.lowercased().split(separator: "x")
    guard parts.count == 2,
          let width = Double(parts[0]), let height = Double(parts[1]),
          width > 0, height > 0 else { return nil }
    return NotchSpec(width: CGFloat(width), height: CGFloat(height), source: .override)
}

/// 机型标识（如 Mac14,2）：和刘海尺寸一起写进启动日志，
/// 换机器排查时能直接看出「系统给这块屏报了多大的刘海」
func hardwareModel() -> String {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
    return String(cString: buffer)
}

/// 面板尺寸按当前刘海几何算：最宽档位 + 两侧阴影余量。
/// 不写死 640×240——换机型或换缩放时刘海宽高变了，展开档位也跟着变，窗口仍要装得下
func panelFrame(for spec: NotchSpec, screenFrame: NSRect) -> NSRect {
    let widest = IslandSizeTable.widestMetrics(notchWidth: spec.width)
    let winW = widest.width + IslandSizeTable.windowMargin * 2
    let winH = IslandSizeTable.expandedHeight(notchHeight: spec.height,
                                              artworkSide: widest.artworkSide)
        + IslandSizeTable.windowMargin
    return NSRect(x: screenFrame.midX - winW / 2,
                  y: screenFrame.maxY - winH,
                  width: winW, height: winH)
}

// 无边框、不抢焦点、盖在菜单栏之上的面板
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }   // 不抢焦点，点它不切 App
    override var canBecomeMain: Bool { false }
}

// 命中检测：只认岛的真实形状，其余区域点击穿透到下层窗口
final class PassthroughView: NSHostingView<NotchRootView> {
    /// 岛的实际命中区域（NSView 坐标，y 轴向上）
    var islandRect: NSRect = .zero

    /// 拖放语义接收者：AppKit 把拖拽事件送到这里，再由它判左右半边。
    /// NSHostingView 的 init(rootView:) 是 required，只能走 convenience 注入
    private(set) var drop: DropReceiver!

    required init(rootView: NotchRootView) {
        super.init(rootView: rootView)
        // 只收文件拖放：拖一段文本不该把岛撑开
        registerForDraggedTypes([.fileURL])
    }

    convenience init(rootView: NotchRootView, drop: DropReceiver) {
        self.init(rootView: rootView)
        self.drop = drop
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 不被使用")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard islandRect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    // 窗口永远不是 key，默认第一次点击会被吞掉；这里放行，保证按钮一点就响
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - 拖放
    // 岛外仍然穿透；光标进刘海那一刻岛已由 PointerMonitor 展开，
    // 命中区随之扩大，所以拖拽进入后能一路收到 updated 与 perform。

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        drop.beginDrag(side: side(of: sender))
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        drop.update(side: side(of: sender))
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        drop.endDrag()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else {
            drop.endDrag()
            return false
        }
        drop.handleDrop(urls)
        return true
    }

    /// 落点按岛体内 x 分左右：左半 AirDrop、右半托盘
    private func side(of sender: NSDraggingInfo) -> DropSide {
        let point = convert(sender.draggingLocation, from: nil)
        return point.x < islandRect.midX ? .airDrop : .tray
    }

    // MARK: - 右键菜单

    /// 岛体上右键：退出 + 锁定 / 解除锁定，不改展开态、不抢焦点。
    /// hitTest 已把命中区限制在 islandRect 内，这里不必再判坐标；
    /// 用 AppKit 菜单而不是 SwiftUI 的 contextMenu，是因为面板不是 key window，
    /// SwiftUI 那套手势在非激活面板上拿不到稳定的事件路由。
    override func rightMouseDown(with event: NSEvent) {
        // 每次弹出都按当前锁定态重建：菜单是临时对象，不缓存状态
        let locked = IslandLock.shared.blocksAutoExpand
        let menu = NSMenu()
        // 关掉自动启用：NSMenu 默认按 validateMenuItem 判可用性，
        // 这里没有实现那个方法，必须自己写 isEnabled 才不会两项都常亮
        menu.autoenablesItems = false

        let settingsItem = NSMenuItem(title: "设置…",
                                      action: #selector(openSettings),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 NotchIsland",
                              action: #selector(quitIsland),
                              keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        menu.addItem(.separator())

        // 锁定 / 解除互斥：只把当前不成立的那一项置灰，两个动作位置固定，
        // 不必先回想现在是哪个状态
        let lock = NSMenuItem(title: "锁定不弹出",
                              action: #selector(lockIsland),
                              keyEquivalent: "")
        lock.target = self
        lock.isEnabled = !locked
        menu.addItem(lock)

        let unlock = NSMenuItem(title: "解除锁定不弹出",
                                action: #selector(unlockIsland),
                                keyEquivalent: "")
        unlock.target = self
        unlock.isEnabled = locked
        menu.addItem(unlock)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    /// 打开设置窗：与菜单栏「设置…」同一入口，两处不各建一套窗口
    @objc private func openSettings() {
        IslandDebug.log("lifecycle", "右键打开设置")
        AppWindows.shared.showSettings()
    }

    /// 走正常终止流程：让 Timer、CoreAudio 监听与子进程都有机会收尾，不用 exit(0)。
/// 先让岛缩回刘海再 terminate：直接退会让岛「啪」地消失（动画时长见 IslandExit）
    @objc private func quitIsland() {
        IslandDebug.log("lifecycle", "右键退出")
        IslandExit.shared.leave { NSApp.terminate(nil) }
    }

    /// 锁定不弹出：锁定后悬停刘海不再展开；视图侧由 onChange(of: lock.blocksAutoExpand) 统一收放
    @objc private func lockIsland() {
        IslandDebug.log("lifecycle", "右键锁定不弹出")
        IslandLock.shared.set(true)
    }

    /// 解除锁定：解锁后光标还在岛上就当场展开，不在岛上则等下一次悬停
    @objc private func unlockIsland() {
        IslandDebug.log("lifecycle", "右键解除锁定不弹出")
        IslandLock.shared.set(false)
    }
}

/// 找不到刘海屏时给一个看得见的说明再退出。
/// 双击启动的 App 没有终端，只写 stderr 用户什么都看不到，会以为「点了没反应」
func alertNoNotchScreen() -> Never {
    let text = "未检测到刘海屏，退出"
    FileHandle.standardError.write((text + "\n").data(using: .utf8)!)

    let alert = NSAlert()
    alert.messageText = "这台 Mac 没有刘海屏"
    alert.informativeText = "NotchIsland 需要带刘海的 MacBook（macOS 14 及以上）。"
        + "外接显示器、没有刘海的机型暂时不可用。"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "退出")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let (screen, spec) = notchInfo() else {
    alertNoNotchScreen()
}

let media = MediaStore()
// 刘海几何：屏幕参数变化时更新它，视图侧据此重算热区与命中区
let geometry = NotchGeometry(notchWidth: spec.width,
                             notchHeight: spec.height,
                             screenFrame: screen.frame)
IslandDebug.log("env",
                "NOTCH_DEBUG on; model=\(hardwareModel()) "
                + "screen=\(IslandDebug.rect(screen.frame)) "
                + "notch=\(spec.width)x\(spec.height) source=\(spec.source.rawValue)")

// 窗口只需装下最宽的档位与最高展开态，外加阴影余量；尺寸从刘海几何推导（见 panelFrame）
// 之前是写死 900×400：透明图层面积是岛体的 6 倍以上，每帧全量合成是白给的掉帧
let frame = panelFrame(for: spec, screenFrame: screen.frame)
IslandDebug.log("env", "panel=\(IslandDebug.rect(frame))（按最宽档位 + 余量推导）")

let panel = NotchPanel(contentRect: frame,
                       styleMask: [.borderless, .nonactivatingPanel],
                       backing: .buffered, defer: false)
panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.hidesOnDeactivate = false
panel.isMovable = false
panel.acceptsMouseMovedEvents = true

var hostRef: PassthroughView!
let drop = DropReceiver()
let root = NotchRootView(geometry: geometry,
                         store: media,
                         drop: drop) { size, expanded in
    guard let host = hostRef else { return }
    let w = size.width, h = size.height
    // 岛水平居中、顶在屏幕最上沿。注意 NSHostingView 是 flipped 坐标（y 从上往下），
    // 所以命中区以 y = 0 为顶边，不要写成 bounds.height - h（那会把热区挪到窗口底部，
    // 表现就是按钮点不动、而下方空白区又挡住了别的窗口）。
    // 收起态只认物理刘海本身：有曲目时岛比刘海左右各宽 20（右侧放波形）、再外扩的话，
    // 鼠标在菜单栏左右两侧也会被吃掉点击——这正是「点不到正常文本按钮」的来源。
    // 那 40pt 黑块只做展示，不能拿来当热区
    if expanded {
        host.islandRect = NSRect(x: (host.bounds.width - w) / 2 - 4,
                                 y: 0,
                                 width: w + 8,
                                 height: h + 8)
    } else {
        // 内缩量与 IslandView 的指针热区共用 IslandSizeTable.pointerInset：
        // 两处差 2pt 就会出现「光标已经让岛展开、点击却穿透下去」
        let inset = IslandSizeTable.pointerInset
        let notchW = geometry.notchWidth
        host.islandRect = NSRect(x: (host.bounds.width - notchW) / 2 + inset,
                                 y: 0,
                                 width: notchW - inset * 2,
                                 height: geometry.notchHeight)
    }
}
hostRef = PassthroughView(rootView: root, drop: drop)
let host = hostRef!
// 动画交给 Core Animation 合成，避免每帧走 CPU 重绘整块 hosting view
host.wantsLayer = true
host.layerContentsRedrawPolicy = .duringViewResize
panel.contentView = host
panel.orderFrontRegardless()

// 外接屏 / 分辨率变化时重新吸附
NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                       object: nil, queue: .main) { _ in
    guard let (s, spec) = notchInfo() else {
        IslandDebug.log("geometry", "屏幕参数变化后未找到刘海屏")
        return
    }
    // 换屏/换缩放后刘海宽高可能变，窗口尺寸与位置一起按新几何重算。
    // 这里也要打 source：插拔屏/换缩放恰恰是最可能只拿到缓存或兜底的时候
    let newFrame = panelFrame(for: spec, screenFrame: s.frame)
    IslandDebug.log("geometry",
                    "屏幕参数变化；notch=\(spec.width)x\(spec.height) source=\(spec.source.rawValue) "
                    + "panel=\(IslandDebug.rect(newFrame))")
    panel.setFrame(newFrame, display: true)
    // 窗口挪了，热区也得跟着挪；只更新几何对象，重算由视图侧 onChange 完成
    geometry.update(screenFrame: s.frame, notchWidth: spec.width, notchHeight: spec.height)
}

// 菜单栏图标：收起态下唯一能发现「设置 / 退出」的入口
AppMenuBar.shared.install()
IslandDebug.log("lifecycle", "启动完成 version=\(AppInfo.version)")

// 首启引导等 runloop 起来再弹：此时面板已上屏，用户能看到岛在哪
DispatchQueue.main.async {
    AppWindows.shared.showOnboardingIfNeeded()
}

app.run()