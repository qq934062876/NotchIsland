import CoreGraphics

// ---------------------------------------------------------------------------
// 尺寸档位表：岛展开后的宽高提前定好，不跟内容走
// 取档顺序：宿主应用精确匹配 -> bundle id 前缀匹配 -> 场景默认档
// 新增应用只需在覆盖表加一行；新增场景才需要加 IslandScene 分支并给默认档
// 宽度另有下限保护：顶栏要装下刘海两侧的图标与电量信息，由实测刘海宽决定
// 编译由 build.sh 统一处理，源文件清单见 build.sh 的 SOURCES
// ---------------------------------------------------------------------------

/// 一套尺寸档位：宽度写死，封面边长顺带决定展开态内容行高
struct IslandMetrics: Equatable {
    var width: CGFloat
    var artworkSide: CGFloat
}

/// 岛要展示的场景：媒体播放 / 主页（无音频时）/ 文件托盘（刚收完文件）
/// Hashable 只为了让顶栏页签用 ForEach 生成；页签顺序与图标见下面的扩展
enum IslandScene: Hashable {
    case media
    case home
    case files
}

extension IslandScene {
    /// 顶栏顺序：音乐、文件、主页。音乐页签只在读到曲目时出现
    /// （2026-11-03 用户要求：没有音乐播放软件就只留主页，音乐板块与图标都不出现）
    static func tabs(hasMusic: Bool) -> [IslandScene] {
        hasMusic ? [.media, .files, .home] : [.files, .home]
    }

    /// 选中用实心变体；音乐符号没有 fill 变体，靠不透明度与常驻淡底区分
    var filledSymbol: String {
        switch self {
        case .media: return "music.note"
        case .files: return "tray.fill"
        case .home: return "house.fill"
        }
    }

    var outlineSymbol: String {
        switch self {
        case .media: return "music.note"
        case .files: return "tray"
        case .home: return "house"
        }
    }

    /// 同时作为页签的 accessibilityLabel，不另起一套口语叫法
    var tabTitle: String {
        switch self {
        case .media: return "音乐"
        case .files: return "文件"
        case .home: return "主页"
        }
    }
}

enum IslandSizeTable {
    // 展开态留白：高度 = 刘海高 + 上留白 + 封面边长 + 进度行间距 + 进度行高 + 下留白
    // 进度行只在媒体场景出现；没有进度时留同样高度，保证展开高度不随内容变
    static let horizontalPadding: CGFloat = 22
    static let expandedTopPadding: CGFloat = 18
    static let expandedBottomPadding: CGFloat = 20

    /// 内容行与进度行之间的间距
    static let progressGap: CGFloat = 8
    /// 进度行高度：时间文字 11 + 间距 4 + 进度条 3，整行留作点击热区（≥28）
    static let progressRowHeight: CGFloat = 28

    /// 收起态有曲目时比刘海宽多出的总宽度（每侧 20）：右侧 20 装 18pt 宽的波形，
    /// 左右各余 1pt。没有曲目时一律不加宽，岛体与物理刘海等大
    /// （2026-11-03 用户要求：默认态与刘海大小一致，只有出现音频律动波形才加长）
    static let collapsedExtraWidth: CGFloat = 40

    /// 收起态单侧状态槽宽：波形 18 居中后距岛体边缘 1
    static let collapsedStatusSideWidth: CGFloat = 20

    /// 收起态波形：4 根 3pt 柱 + 2pt 间距 = 18pt 宽，落在 20pt 槽内居中；
    /// 柱高跟刘海高走（32pt 刘海 → 顶 14 / 底 4），换机型时比例不变，也不会顶出刘海
    static let collapsedWaveBarCount = 4
    static let collapsedWaveBarWidth: CGFloat = 3
    static let collapsedWaveBarSpacing: CGFloat = 2

    /// 波形最高点：32pt 刘海 → 14（约 h×0.44，留出上下各 9pt 不贴边）
    static func collapsedWaveMaxHeight(notchHeight: CGFloat) -> CGFloat {
        (notchHeight * 0.4375).rounded()
    }

    /// 波形最低点：32pt 刘海 → 4（约 h×0.125），暂停时柱子压到这里
    static func collapsedWaveMinHeight(notchHeight: CGFloat) -> CGFloat {
        max(2, (notchHeight * 0.125).rounded())
    }
    /// 波形刷新间隔：0.05s（20fps）足够顺，又比逐帧省；暂停时直接停表
    static let collapsedWaveInterval: Double = 0.05
    /// 一拍的时长（秒）：0.52s ≈ 115 BPM，是「像在踩拍」而不是匀速摆动的关键；
    /// 真实振幅要 Core Audio tap + 系统音频录制授权，这里按拍点模拟
    static let collapsedWaveBeatPeriod: Double = 0.52
    /// 起音占一拍的比例：够慢才不会在 20fps 下跳成一格一格（约 0.08s ≈ 2 帧）
    static let collapsedWaveAttack: Double = 0.16
    /// 起音后的回落速度：越大衰减越快，拍与拍之间回到底线附近
    static let collapsedWaveDecay: Double = 2.8
    /// 拍与拍之间的静止高度比例：柱子不完全塌成一条线，留着「还在播」的底
    static let collapsedWaveIdleRatio: Double = 0.18
    /// 相邻柱子的起音错开量（拍的比例）：4 根几乎同时冲顶，只有一点先后
    static let collapsedWaveSkew: Double = 0.04
    /// 叠在拍点上的细起伏频率（Hz）：让每一拍的峰值形状略有不同
    static let collapsedWaveRippleHz: Double = 2.3

    /// 顶部两角向外翻出的宽度：顶边比身体宽 2×topFlare
    /// 展开取 8 才看得出喇叭口；收起态分两种：
    /// - 没有曲目：岛体与物理刘海等宽，顶边再外扩就会比刘海宽一圈、
    ///   盖住菜单栏图标，取 0（2026-11-03 用户要求）
    /// - 有曲目：岛体比刘海宽 40（每侧 20），顶角取与展开同一个弧度，
    ///   否则加宽区的两个顶角是直角，看着像贴了一块方块
    ///   （2026-11-04 用户要求补回收起态的外翻弧）
    static let expandedTopFlare: CGFloat = 8
    static let collapsedTopFlare: CGFloat = 0
    static let collapsedMusicTopFlare: CGFloat = 8

    /// 收起态热区内缩：贴着刘海边缘时不抖，也避免把菜单栏文字区的点击吃掉
    /// 指针热区与点击命中区必须用同一个值，两处口径差 2pt 就会出现
    /// 「看着已经展开，实际点在缝里」
    static let pointerInset: CGFloat = 2

    /// 岛体下两角：展开按 44pt 封面同步放大；收起跟刘海高走（32pt → 11），
    /// 换机型时圆角比例不变，不会出现「小圆角配高刘海」或反过来
    static let expandedBottomCornerRadius: CGFloat = 22

    /// 收起态下圆角：32pt 刘海 → 11
    static func collapsedCornerRadius(notchHeight: CGFloat) -> CGFloat {
        (notchHeight / 3).rounded()
    }

    /// 岛体投影：近层压实轮廓、远层拉开与桌面的距离；只挂在纯黑形状上
    static let shadowNearOpacity: CGFloat = 0.40
    static let shadowNearRadius: CGFloat = 5
    static let shadowNearOffsetY: CGFloat = 3
    static let shadowFarOpacity: CGFloat = 0.26
    static let shadowFarRadius: CGFloat = 14
    static let shadowFarOffsetY: CGFloat = 8

    /// 边缘柔化描边：1pt 宽，只有底边一小段淡白线，轻微模糊后当作「光线吃掉边缘」
    /// 顶部与两侧必须是 0：岛体要与刘海一样是纯黑边缘，顶部一亮就成了「白边」
    /// （2026-11-03 用户反馈顶部有白边，改为只留底边）
    static let edgeStrokeWidth: CGFloat = 1
    static let edgeStrokeBlur: CGFloat = 1.1
    static let edgeStrokeTopOpacity: CGFloat = 0
    static let edgeStrokeBottomOpacity: CGFloat = 0.05
    /// 开始显色的位置（0–1，自上而下）：此位置以上全透明，只有底部一段有淡线
    static let edgeStrokeVisibleStart: CGFloat = 0.65

    /// 图标按钮圆角，落在外壳与小控件两档里
    /// 封面已改成正圆，不再有封面圆角常量
    static let iconButtonCornerRadius: CGFloat = 7

    /// 圆形封面转一圈的时长与刷新间隔：12s 比系统 Music 慢一点，
    /// 0.05s（20fps）足够顺又不逐帧；暂停/收起/减弱动态效果时 TimelineView 停表
    static let artworkRotationPeriod: Double = 12
    static let artworkRotationInterval: Double = 0.05
    /// 16pt 音源图标按系统图标比例取 4，比小控件档 6–8 更接近原生观感
    static let appIconCornerRadius: CGFloat = 4

    /// 拖放落点左右两半的圆角：面积大，比小控件档再放大一档
    static let dropTargetCornerRadius: CGFloat = 12

    /// 托盘条目行高与行间距：两条 20 + 间距 4 正好等于封面行 44
    static let trayRowHeight: CGFloat = 20
    static let trayRowSpacing: CGFloat = 4

    /// 顶栏内边距与簇内间距；顶栏贴屏幕顶，图标必须落在刘海左右两侧
    static let topBarPadding: CGFloat = 14
    static let topBarSpacing: CGFloat = 4

    /// 顶栏左右两簇的最小宽度（不含内边距）。两侧内容不对称，不能再用「单侧 × 2」：
    /// 左簇 = 音乐 / 文件 / 主页三个 28pt 页签 + 两个 4pt 间距 = 92
    private static let topBarLeftMinimum: CGFloat = 92
    /// 右簇 = 锁定 28 + 间距 4 + 电量簇 120（电池 26 + 百分比 30 + 插头 15 + 三个间距 12
    /// + 两位数字的「循环 N」36 ≈ 119），合计 152，再留 3pt 余量取 155。
    /// 循环次数是唯一可截断项，但下限要保证两位数字显示时不出现省略号。
    private static let topBarRightMinimum: CGFloat = 155

    /// 场景默认档：未播放、私有符号取不到、表外应用都走它，保证宽度恒定不抖
    static let mediaDefault = IslandMetrics(width: 448, artworkSide: 44)

    /// 主页档：与媒体同宽同高，来回切场景时岛体尺寸不变
    static let homeDefault = IslandMetrics(width: 448, artworkSide: 44)

    /// 主页左右两栏：天气固定宽，日程吃余量；间距比媒体行的 12 略大，两栏才分得开
    static let homeWeatherWidth: CGFloat = 152
    static let homeColumnSpacing: CGFloat = 16

    /// 浏览器网页播放：信息比本地播放器多，封面略大
    private static let browserMedia = IslandMetrics(width: 456, artworkSide: 48)

    /// 宿主应用覆盖档，键为 bundle id
    /// 顶栏加宽后，媒体类档位都被刘海下限保护抬到 520，这里保留各行是为了
    /// 表达「按应用配宽度」的入口；要更宽只需改本行，要更窄则受下限约束不生效
    private static let mediaOverrides: [String: IslandMetrics] = [
        "com.apple.Music": IslandMetrics(width: 448, artworkSide: 44),
        "com.apple.podcasts": IslandMetrics(width: 448, artworkSide: 44),   // 播客标题偏长
        "com.spotify.client": IslandMetrics(width: 448, artworkSide: 44),
        // 网易云多了进度行，歌名也偏长
        "com.netease.163music": IslandMetrics(width: 448, artworkSide: 44),
        "com.apple.Safari": browserMedia,
        "com.google.Chrome": browserMedia,
        "com.microsoft.edgemac": browserMedia,
        "org.mozilla.firefox": browserMedia,
    ]

    /// 实际档位：先查表，再按刘海宽兜住顶栏所需空间（只由刘海尺寸决定，不随内容变）
    static func metrics(scene: IslandScene, bundleID: String?, notchWidth: CGFloat) -> IslandMetrics {
        let base: IslandMetrics
        switch scene {
        case .media:
            base = lookup(bundleID, table: mediaOverrides, fallback: mediaDefault)
        case .home, .files:
            // 主页与托盘不跟音源走，恒定一档；宽度仍受刘海下限保护
            base = homeDefault
        }
        return IslandMetrics(width: max(base.width, minimumWidth(notchWidth: notchWidth)),
                             artworkSide: base.artworkSide)
    }

    /// 顶栏两侧各有一簇图标，每侧可用宽度 =（总宽 − 刘海宽）/ 2 − 内边距，
    /// 所以下限必须按较宽的一侧算（右侧锁定 + 电量 155 > 左侧页签 92），
    /// 不能把左右两簇相加——相加会把右侧簇挤进刘海下面。
    /// 本机刘海 179 → 179 + 2 ×（14 + 155）= 517 → 向上取 4 的倍数 520
    private static func minimumWidth(notchWidth: CGFloat) -> CGFloat {
        let side = max(topBarLeftMinimum, topBarRightMinimum)
        let raw = notchWidth + 2 * (side + topBarPadding)
        return (raw / 4).rounded(.up) * 4
    }

    /// 面板相对岛体的余量：展开态两侧各 +4 命中余量、远层阴影 24 半径 + 12 下偏移，40 够用。
    /// 面板尺寸由刘海几何推导（见 main.swift 的 panelFrame），换机型不会裁掉岛体
    static let windowMargin: CGFloat = 40

    /// 展开高度：刘海高 + 上留白 + 封面边长 + 进度行间距 + 进度行高 + 下留白。
    /// 视图与面板尺寸共用这一条公式，改一处不会两边对不上
    static func expandedHeight(notchHeight: CGFloat, artworkSide: CGFloat) -> CGFloat {
        notchHeight + expandedTopPadding + artworkSide + progressGap + progressRowHeight + expandedBottomPadding
    }

    /// 最宽的一档（已叠加刘海下限）与其中最大的封面边长：
    /// 面板宽高按它算，无论当前落在哪个场景、哪台机型都不会超出面板被裁。
    /// 封面取 48 不是「跨档拼出来的」：浏览器档 456/48 被刘海下限抬到 520 后仍是 48，
    /// 展开态确实会出现 520×48，所以面板高度必须按 48 留
    static func widestMetrics(notchWidth: CGFloat) -> IslandMetrics {
        let candidates = [mediaDefault, homeDefault, browserMedia] + Array(mediaOverrides.values)
        let widest = candidates.max { $0.width < $1.width } ?? mediaDefault
        let side = candidates.map(\.artworkSide).max() ?? widest.artworkSide
        return IslandMetrics(width: max(widest.width, minimumWidth(notchWidth: notchWidth)),
                             artworkSide: side)
    }

    /// 精确匹配 -> 逐段去尾的前缀匹配（兜住 com.apple.Safari.WebContentProcess 一类）-> 默认档
    private static func lookup(_ bundleID: String?,
                               table: [String: IslandMetrics],
                               fallback: IslandMetrics) -> IslandMetrics {
        guard let id = bundleID, !id.isEmpty else { return fallback }
        if let hit = table[id] { return hit }

        var parts = id.split(separator: ".").map(String.init)
        while parts.count > 2 {
            parts.removeLast()
            if let hit = table[parts.joined(separator: ".")] { return hit }
        }
        return fallback
    }
}