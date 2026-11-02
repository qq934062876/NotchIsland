import Cocoa
import SwiftUI

// ---------------------------------------------------------------------------
// 岛体视图：容器两档插值、封面/歌名/进度、hover 展开与点击穿透联动
//
// 内容按最终档位尺寸排一次版，容器只在「收起」与「展开」两档之间插值，
// 窄下来的部分靠 clipShape 裁掉，动画期不重排文本与封面（见 AGENTS.md 3.5）。
// 窗口、面板与命中区在 main.swift；尺寸档位在 IslandLayout.swift。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

/// 弹出：略快、带一点回弹，跟手
private let islandExpandSpring = Animation.spring(response: 0.34, dampingFraction: 0.82)
/// 收起：更快、几乎无回弹，干脆落地；拖长尾巴会被看成「卡一下」
private let islandCollapseSpring = Animation.spring(response: 0.20, dampingFraction: 0.98)

/// 出场：比展开略慢（入场要让人看清），回弹收在 0.86，不过冲
private let islandEntranceSpring = Animation.spring(response: 0.42, dampingFraction: 0.86)
/// 退场：跟收起同档，干脆落地；退了还在慢慢淡会被当成「关不掉」
private let islandExitSpring = Animation.spring(response: 0.24, dampingFraction: 0.98)
/// 出场起始缩放：**横向缩得比纵向多**——岛收起时正好等于刘海，只缩纵向看不出变化，
/// 横向缩到 0.92 才能看见黑块从刘海两侧长出来；纵向只缩 0.86 太狠会像弹窗
private let islandPresenceScale = CGSize(width: 0.92, height: 0.86)

/// 退场协调：右键退出时先播收回动画，动画落定再真正 terminate。
/// 入口在 AppKit（`main.swift` 的右键菜单），视图只能靠这个单例收到信号，所以放在视图文件给两边共用
final class IslandExit: ObservableObject {
    static let shared = IslandExit()

    /// 视图据此把自己缩回刘海（出场动画的逆过程）
    @Published private(set) var isLeaving = false

    /// 与退场 spring 的可见时长对齐：0.24s 的 spring 到 0.26s 已基本落定，
    /// 再晚就会看见「已经透明了、进程还赖着」
    private let settleDelay: TimeInterval = 0.26

    func leave(then completion: @escaping () -> Void) {
        guard !isLeaving else { return }   // 右键连点只退一次
        isLeaving = true
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) { completion() }
    }
}

/// 「锁定不弹出」：收缩之后不再自动展开。语义是**禁止悬停自动展开**，
/// 不是「常驻展开」——2026-11-04 用户当面纠正，两者不是同一个功能。
/// 右键菜单在 AppKit 层（`main.swift` 的 `PassthroughView`），顶栏锁图标在 SwiftUI 层，
/// 两处要改同一份状态，所以用单例——与 `IslandExit` 同一个理由，放在视图文件供两边共用。
/// 只存状态、不做展开判定：展开仍由 `NotchRootView` 的 `syncExpansion` 统一算，
/// 避免「右键锁定」和「顶栏锁定」走出两条不同的展开路径。
final class IslandLock: ObservableObject {
    static let shared = IslandLock()

    /// 启动时读回上次的锁定状态：产品化后锁定要跨启动保留
    @Published private(set) var blocksAutoExpand = AppSettings.shared.locked

    func set(_ blocked: Bool) {
        guard blocksAutoExpand != blocked else { return }
        blocksAutoExpand = blocked
        // 唯一写入口：右键菜单、顶栏锁按钮、菜单栏菜单、设置窗都走这里
        AppSettings.shared.locked = blocked
    }

    func toggle() { set(!blocksAutoExpand) }
}

struct NotchRootView: View {
    /// 刘海宽高与所在屏幕：改成可观察对象，插拔屏/改分辨率后热区能跟着重算
    @ObservedObject var geometry: NotchGeometry
    /// 以下三个是转发出来的计算属性，视图内其余代码不必逐个改调用点
    private var notchHeight: CGFloat { geometry.notchHeight }
    private var notchWidth: CGFloat { geometry.notchWidth }
    /// 刘海所在屏幕的 frame（屏幕坐标，左下原点）：热区判定要把岛换算回屏幕坐标
    private var screenFrame: NSRect { geometry.screenFrame }
    @ObservedObject var store: MediaStore
    /// 拖放状态与托盘列表：事件在 main.swift 的 PassthroughView 收，这里只读结果
    @ObservedObject var drop: DropReceiver
    @StateObject private var battery = BatteryMonitor()
    /// 全局鼠标监视：收起态只认刘海本身，避免路过菜单栏就展开
    @StateObject private var pointer = PointerMonitor()
    /// 系统「减弱动态效果」：用环境值而不是启动时读一次的全局常量，运行中开关也即时生效
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    /// 光标是否在热区内；展开条件是 pointerInside && !blocksAutoExpand，
    /// 两者分开才能做到「锁定 = 光标进来也不弹」
    @State private var pointerInside = false
    /// 锁定不弹出：锁定后悬停刘海不再展开，岛停在收缩态；再点一次解锁恢复。
    /// 状态放在单例里：右键菜单（AppKit）与顶栏锁按钮（SwiftUI）都能改
    @ObservedObject private var lock = IslandLock.shared
    private var blocksAutoExpand: Bool { lock.blocksAutoExpand }
    /// 退场信号：右键退出先缩回刘海再终止（见 IslandExit）
    @ObservedObject private var exit = IslandExit.shared
    /// 出场/退场的可见度：false = 缩在刘海里的透明初始态
    @State private var appeared = false
    /// 当前场景：媒体 / 文件 / 主页；没有任何音频软件在播时落回主页
    @State private var scene: IslandScene = .media
    /// 用户手动点过页签后固定当前页：换歌之前不再被「谁在出声」自动抢走；
    /// 换歌时会清空，回到「在播」语境（与旧 manualHome 语义一致）
    @State private var pinnedScene: IslandScene?
    /// 主页的三个数据源：随视图常驻，切场景不重拉，定时器也只有一个
    @StateObject private var weather = WeatherSource()
    @StateObject private var calendar = CalendarSource()
    /// 用户偏好：日历开关与天气城市即时生效
    @ObservedObject private var settings = AppSettings.shared
    /// 内存 / 磁盘：init 里起 30s 定时器，不放在 onAppear，避免切场景重复启动
    @StateObject private var system = SystemMetricsMonitor()
    

    /// 岛的命中区上报：只在展开态/档位变化时给一次，不做逐帧几何测量
    /// 带上 expanded：收起态命中区要收紧成刘海本身，展开态才是整块面板
    var onIslandSize: (CGSize, Bool) -> Void = { _, _ in }

    /// 当前档位：由场景 + 音源应用查表得出，宽度写死，不跟内容走
    private var metrics: IslandMetrics {
        IslandSizeTable.metrics(scene: scene, bundleID: store.bundleID, notchWidth: notchWidth)
    }

    /// 展开高度由档位推导：刘海高 + 上留白 + 封面边长 + 进度行 + 下留白
    /// 进度行高度是常量，空态也占位，展开高度不随有无内容变化
    private var expandedHeight: CGFloat {
        // 与面板尺寸共用同一条公式：换机型（刘海更高）时两边一起变
        IslandSizeTable.expandedHeight(notchHeight: notchHeight, artworkSide: metrics.artworkSide)
    }

    var body: some View {
        ZStack(alignment: .top) {
            island
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 出场/退场：从刘海向外缩放 + 淡入，锚点钉在顶部中心（岛贴屏幕顶，只能往上长）。
        // 减弱动态效果时只淡入不缩放，见 presenceScale
        .scaleEffect(x: presenceScale.width, y: presenceScale.height, anchor: .top)
        .opacity(appeared ? 1 : 0)
        // 全透明期也别吃点击：命中区仍按 islandRect 算，不能截走菜单栏的点击
        .allowsHitTesting(appeared)
        .animation(presenceAnimation, value: appeared)
        .onAppear {
            // 回调只翻状态；展开目标交给 onChange 用最新的 blocksAutoExpand 计算，
            // 避免闭包捕获初始化那一刻的旧值
            pointer.onInsideChange = { inside in pointerInside = inside }
            pointer.start()
            // 首帧就上报一次尺寸与热区，先 start 再上报：热区要落到已经在跑的监视器上
            refreshLayout("appear")
            // 主页数据源在这里起：主页不一定是首屏，挂在 HomeScene 的 onAppear
            // 上会在「一整天都在放歌」时永远不拉天气与日程
            weather.start()
            // 日历要读 EventKit：用户没在引导/设置里打开就不请求授权
            if settings.calendarEnabled { calendar.start() }
            // 启动时先落一次场景：白名单播放器里没读到曲目就直接进主页，
            // 而不是先显示「未在播放」等下一次采样
            syncScene(hasMusic: store.hasMusic)
            // 上屏首帧必须是「缩在刘海里的透明态」，隔一拍再置 true 才有入场动画：
            // 与 orderFrontRegardless 同一轮 runloop 里改状态会被合成器并成一帧，等于没动画
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                // 启动后 50ms 内就点了退出的极端情况：别在淡出中途又亮回来
                guard !exit.isLeaving else { return }
                appeared = true
            }
            
        }
        .onChange(of: expanded) { _, newValue in
            refreshLayout(newValue ? "expand" : "collapse")
        }
        .onChange(of: metrics) { _, _ in
            refreshLayout("metrics")
        }
        .onChange(of: geometry.notchSize) { _, _ in
            refreshLayout("geometry")
        }
        .onChange(of: geometry.screenFrame) { _, _ in
            refreshLayout("geometry")
        }
        .onChange(of: pointerInside) { _, newValue in
            // 锁定期间光标进出一律不展开，岛停在收缩态
            syncExpansion(target: newValue && !blocksAutoExpand)
        }
        .onChange(of: lock.blocksAutoExpand) { _, blocked in
            // 锁定/解锁可能来自右键菜单（AppKit）或顶栏锁按钮（SwiftUI），
            // 展开与否只在这里统一判定：点锁定时若岛是展开的就地收起，
            // 解锁后光标已不在岛上就保持收起，等下一次悬停再弹
            syncExpansion(target: pointerInside && !blocked)
        }
        .onChange(of: store.hasMusic) { _, hasMusic in
            syncScene(hasMusic: hasMusic)
        }
        // 设置窗里改了这两项就立刻生效，不用重启 App
        .onChange(of: settings.calendarEnabled) { _, enabled in
            if enabled { calendar.start() } else { calendar.stop() }
        }
        .onChange(of: settings.weatherCityID) { _, id in
            weather.setCity(id: id)
        }
        .onChange(of: exit.isLeaving) { _, leaving in
            // 退场：先在视图里缩回刘海，IslandExit 到点再 terminate
            if leaving { appeared = false }
        }
        .onChange(of: drop.trayItems) { old, new in
            // 收进新文件才跳到托盘场景；删空不自动跳走，让用户自己决定去哪
            guard new.count > old.count else { return }
            pinnedScene = nil
            switchScene(.files)
        }
        .onDisappear {
            pointer.stop()
            weather.stop()
            calendar.stop()
        }
    }

    /// 目标档位尺寸：动画只在这两档之间插值。
    /// 收起态默认与物理刘海等大，只有要显示右侧波形时才左右各外扩 20，
    /// 因此宽度跟着 hasMusic 走（2026-11-03 用户要求，覆盖此前「收起宽度固定」的条文）
    private var containerSize: CGSize {
        if expanded {
            return CGSize(width: metrics.width, height: expandedHeight)
        }
        let extra = store.hasMusic ? IslandSizeTable.collapsedExtraWidth : 0
        return CGSize(width: notchWidth + extra, height: notchHeight)
    }

    /// 投影强度：贴齐刘海且没有波形时为 0，否则刘海四周会留一圈暗影，
    /// 与「岛就是刘海」的观感冲突；展开态与有曲目时照常投影。
    /// 用透明度而不是增删视图——纯黑填充层必须始终在，删掉投影会把黑块一起关掉
    private var shadowStrength: CGFloat {
        expanded || store.hasMusic ? 1 : 0
    }

    // 顶部两角向外翻出：顶边比身体宽 2×topFlare，外弧终点落在垂直侧线右边。
    // 展开态固定 8；收起态只有「有曲目」时才外翻——那时岛体比刘海宽 40，
    // 两个顶角不外翻就是直角方块；与刘海等宽时不外翻，否则黑边会盖到菜单栏上。
    // 底部展开固定 22；收起跟刘海高走（32pt 刘海 → 11），换机型圆角比例不变。
    // 两档参数不同，动画期由容器插值带走
    private var islandShape: IslandShape {
        IslandShape(
            topFlare: topFlare,
            bottomRadius: expanded
                ? IslandSizeTable.expandedBottomCornerRadius
                : IslandSizeTable.collapsedCornerRadius(notchHeight: notchHeight)
        )
    }

    /// 顶角外翻量：展开 8；收起时有曲目 8（与展开同一个弧度）、无曲目 0
    private var topFlare: CGFloat {
        if expanded { return IslandSizeTable.expandedTopFlare }
        return store.hasMusic
            ? IslandSizeTable.collapsedMusicTopFlare
            : IslandSizeTable.collapsedTopFlare
    }

    // 岛本体：内容按最终档位尺寸排版一次，容器变窄时靠 clipShape 裁掉
    // 这样尺寸动画期间不会逐帧重排文本、重算封面，也就不会顿。
    // 内容、收起态状态条、投影三块各自独立，改哪块都不必在长链里找位置
    private var island: some View {
        islandBody
            .frame(width: metrics.width, height: expandedHeight, alignment: .top)   // 固定最终尺寸，不随 expanded 变
            .opacity(expanded ? 1 : 0)
            // 收起态内容不可点：透明不等于不可命中，否则会挡住岛下方的窗口
            .allowsHitTesting(expanded)
            .frame(width: containerSize.width, height: containerSize.height, alignment: .top)   // 容器：逐帧插值
            .overlay(collapsedStatusBar)
            .clipShape(islandShape)
            .background(shadowBackdrop)
            // 边缘虚化：只在底边留一段淡线，顶部与两侧保持纯黑
            .overlay(IslandEdgeStroke(shape: islandShape))
            .animation(metricsAnimation, value: metrics)   // 换音源换档位同样平滑
            // 收起态按有无曲目加宽/收窄：跟收起走，别拖尾
            .animation(collapsedResizeAnimation, value: store.hasMusic)
    }

    /// 顶栏 + 当前场景：按最终档位尺寸排一次版，不参与容器插值
    private var islandBody: some View {
        // 顶栏占刘海那一档高度，内容从刘海下方开始；两者按最终尺寸排一次版
        VStack(spacing: 0) {
            IslandTopBar(width: metrics.width,
                         height: notchHeight,
                         battery: battery.status,
                         scene: scene,
                         hasMusic: store.hasMusic,
                         autoExpandBlocked: blocksAutoExpand,
                         onSelectScene: { selectScene($0) },
                         onToggleLock: { toggleLock() })
            // 三个场景同宽同高，切换不做尺寸插值，只做一次淡入，
            // 所以这里用分支不会踩「动画期切换子树」的坑
            Group {
                if scene == .home {
                    HomeScene(width: metrics.width - IslandSizeTable.horizontalPadding * 2,
                              rowHeight: metrics.artworkSide,
                              footerHeight: IslandSizeTable.progressRowHeight,
                              weather: weather,
                              calendar: calendar,
                              system: system,
                              portNotice: store.portNotice,
                              onFixMusic: { store.fixMusicPort() })
                } else if scene == .files {
                    TrayScene(width: metrics.width - IslandSizeTable.horizontalPadding * 2,
                              rowHeight: metrics.artworkSide,
                              footerHeight: IslandSizeTable.progressRowHeight,
                              items: drop.trayItems,
                              notice: drop.notice,
                              onClear: { drop.clearTray() },
                              onReveal: { drop.reveal($0) })
                } else {
                    mediaColumn
                }
            }
            .padding(.horizontal, IslandSizeTable.horizontalPadding)
            .padding(.top, IslandSizeTable.expandedTopPadding)   // 内容从刘海下方开始
            .padding(.bottom, IslandSizeTable.expandedBottomPadding)
            // 拖拽中盖住内容：左半隔空投送、右半文件托盘，当前落点一侧提亮
            .overlay {
                if drop.isDragging {
                    DropTargetsView(side: drop.side)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? .smooth(duration: 0.12) : .smooth(duration: 0.2),
                       value: drop.isDragging)
            // 切页只换内容：尺寸两档都不变，淡入即可，不跑容器插值
            .animation(sceneAnimation, value: scene)
        }
    }

    /// 收起态状态条：只在右侧画波形，宽度由容器给定，不参与内容布局。
    /// 命中区收起态仍只认物理刘海，这里显式关掉命中，绝不截走菜单栏点击
    private var collapsedStatusBar: some View {
        CollapsedStatusBar(isPlaying: store.isPlaying && !expanded,
                           hasMedia: store.hasMusic,
                           notchHeight: notchHeight)
            .opacity(expanded ? 0 : 1)
            .allowsHitTesting(false)
            .animation(reduceMotion ? .smooth(duration: 0.12) : .smooth(duration: 0.2),
                       value: expanded)
    }

    /// 两层阴影各自挂在一个独立的纯色形状上，不能链式挂同一个形状：
    /// 第二个 .shadow 的输入是第一个 .shadow 渲染出的位图，而位图的图层边界
    /// 是矩形，再模糊一次就把矩形边界放大成「四边形阴影」（2026-11-03 用户反馈）。
    /// 分两层后每层只对 IslandShape 的真实路径做一次模糊，轮廓才会跟着外翻弧走。
    /// 不挂到文本与封面上，避免动画期放大重绘范围。
    /// 透明度乘 shadowStrength：贴齐刘海且无波形时不投，避免刘海四周一圈暗影
    private var shadowBackdrop: some View {
        ZStack {
            // 远层在下：拉开岛体与桌面的距离
            islandShape
                .fill(Color.black)
                .shadow(color: .black.opacity(IslandSizeTable.shadowFarOpacity * shadowStrength),
                        radius: IslandSizeTable.shadowFarRadius,
                        y: IslandSizeTable.shadowFarOffsetY)
            // 近层在上：压实轮廓，让边缘不糊
            islandShape
                .fill(Color.black)
                .shadow(color: .black.opacity(IslandSizeTable.shadowNearOpacity * shadowStrength),
                        radius: IslandSizeTable.shadowNearRadius,
                        y: IslandSizeTable.shadowNearOffsetY)
        }
    }

    /// 换档位用弹出那条曲线；减弱动态效果时退化成固定短时长
    private var metricsAnimation: Animation {
        reduceMotion ? .smooth(duration: 0.16) : islandExpandSpring
    }

    /// 切页只做内容淡入：尺寸不变，别把尺寸 spring 借给它
    private var sceneAnimation: Animation {
        reduceMotion ? .smooth(duration: 0.12) : .smooth(duration: 0.2)
    }

    /// 收起态因有无曲目而加宽/收窄：用收起那条更快的曲线，慢了会被看成「卡一下」
    private var collapsedResizeAnimation: Animation {
        reduceMotion ? .smooth(duration: 0.12) : islandCollapseSpring
    }

    /// 出场缩放：减弱动态效果时完全不缩放，只做淡入（AGENTS 3.8 要求动效可关）
    private var presenceScale: CGSize {
        appeared || reduceMotion ? CGSize(width: 1, height: 1) : islandPresenceScale
    }

    /// 出现用入场那条 spring，退场用更快的那条：退场拖长会被看成「关不掉」
    private var presenceAnimation: Animation {
        if reduceMotion { return .linear(duration: 0.12) }
        return appeared ? islandEntranceSpring : islandExitSpring
    }

    private func hoverAnimation(expanding: Bool) -> Animation {
        if reduceMotion { return .smooth(duration: 0.16) }
        return expanding ? islandExpandSpring : islandCollapseSpring
    }

    /// 展开条件只有一个入口：鼠标在岛上且没被锁定，避免多处写 expanded 导致状态打架
    private func syncExpansion(target: Bool) {
        guard expanded != target else { return }
        IslandDebug.log("expand",
                        "-> \(target) pointerInside=\(pointerInside) blocked=\(blocksAutoExpand) "
                        + "scene=\(scene) metrics=\(metrics.width)x\(expandedHeight)")
        withAnimation(hoverAnimation(expanding: target)) { expanded = target }
    }

    /// 锁定只拦「悬停自动展开」，不锁鼠标：锁定瞬间若岛是展开的，由
    /// onChange(of: lock.blocksAutoExpand) 就地收起；解锁后要重新悬停才会再弹
    private func toggleLock() { lock.toggle() }

    /// 尺寸 / 档位 / 屏幕 / 场景一变都要做同一对事：把新尺寸报给窗口算命中区，
    /// 再重算指针热区。两件事必须成对，收成一个入口——漏掉一半就会出现
    /// 「光标已经把岛顶开、点下去却穿透」
    private func refreshLayout(_ reason: String) {
        onIslandSize(containerSize, expanded)
        updatePointerZone(reason: reason)
    }

    /// 场景跟随「有没有读到曲目」：读不到就整块消失并回主页；
    /// 读到了、且用户没固定到别页时自动进音乐页（新打开播放器即加载同步）
    private func syncScene(hasMusic: Bool) {
        if !hasMusic {
            // 音乐页签此时已经不画了，停在 .media 会看到空列，必须回主页
            guard scene == .media else { return }
            switchScene(.home)
            return
        }
        let fixedElsewhere = pinnedScene != nil && pinnedScene != .media
        guard scene == .home, !fixedElsewhere else { return }
        pinnedScene = nil
        switchScene(.media)
    }

    /// 顶栏页签：点过就固定住这一页，避免下一次 hasMusic 变化把用户弹走；
    /// 点音乐页时即使当前没声音也停在这里，显示「未在播放」而不是被切回主页
    private func selectScene(_ next: IslandScene) {
        pinnedScene = next
        switchScene(next)
    }

    private func switchScene(_ next: IslandScene) {
        guard scene != next else { return }
        IslandDebug.log("scene", "\(scene) -> \(next)")
        scene = next
        refreshLayout("scene")
    }

    /// 热区：收起态只认物理刘海（内缩 2pt 防贴边抖动），展开态认整块面板。
    /// 屏幕坐标左下原点，岛在屏幕水平居中、顶边贴屏幕最上沿
    /// - Parameter reason: 来源标记，只用于诊断日志
    private func updatePointerZone(reason: String) {
        let zone: CGRect
        if expanded {
            // 展开态把外翻弧一起算进来：顶边比身体宽 2×topFlare，
            // 只量身体宽会让光标停在喇叭口上却判成「已离开」
            let size = containerSize
            let flare = IslandSizeTable.expandedTopFlare
            zone = CGRect(x: screenFrame.midX - size.width / 2 - flare,
                          y: screenFrame.maxY - size.height,
                          width: size.width + flare * 2,
                          height: size.height)
        } else {
            // 内缩量与 main.swift 的 islandRect 用同一个常量，两处口径必须一致
            let inset = IslandSizeTable.pointerInset
            zone = CGRect(x: screenFrame.midX - notchWidth / 2 + inset,
                          y: screenFrame.maxY - notchHeight,
                          width: notchWidth - inset * 2,
                          height: notchHeight)
        }
        pointer.update(zone: zone, reason: reason)
    }

    // 展开态内容搬到 IslandMediaColumn：容器只负责尺寸、裁剪与场景分发
    private var mediaColumn: some View {
        IslandMediaColumn(store: store, metrics: metrics, expanded: expanded)
    }
}
