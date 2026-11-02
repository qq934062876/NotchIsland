import Cocoa
import SwiftUI

// ---------------------------------------------------------------------------
// 岛体外壳组件：图标按钮的共用观感、进度条、音源图标、收起态状态条与波形、
// 圆形旋转封面、顶栏（页签 + 锁定 + 电量簇）
//
// 只放「岛内装饰件」，不读播放数据（只接参数）、不碰窗口逻辑；
// 场景与档位映射在 IslandLayout.swift，容器排版与命中在 IslandView.swift。
// 按钮反馈：悬停只加一层白色淡底，按下缩放 + 压暗，全部走 spring，不用颜色表达状态。
// 透明度只用三档：1 主信息 / 0.55 次级信息 / 0.12 悬停底，不另造灰阶。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

/// 岛内图标按钮：28×28 热区，悬停淡出底色，按下回弹
/// 用 Button 而不是 onTapGesture，才能拿到稳定的按下态；宿主已放行首次点击
/// isSelected 为 nil 时保持旧观感（白色、只有悬停底色）；
/// 页签传 true/false 才有选中态：选中常驻淡底，未选中降到次级信息档
struct IslandIconButton: View {
    let symbol: String
    var pointSize: CGFloat = 13
    var isSelected: Bool? = nil
    var accessibilityText: String? = nil
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var showsBackground: Bool {
        hovering || isSelected == true
    }

    private var iconOpacity: Double {
        isSelected == false ? 0.55 : 1
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: pointSize, weight: .semibold))
                .foregroundStyle(.white.opacity(iconOpacity))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: IslandSizeTable.iconButtonCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(showsBackground ? 0.12 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle())
        .onHover { inside in
            withAnimation(reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.16)) {
                hovering = inside
            }
        }
        .accessibilityLabel(Text(accessibilityText ?? symbol))
    }
}

/// 按下反馈：缩放 0.92 + 轻微压暗，松手用同一条曲线回弹
/// 阻尼取 0.82：够跟手，但不做过冲（AGENTS.md 3.5）
struct IslandPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(reduceMotion
                       ? .linear(duration: 0.01)
                       : .spring(response: 0.22, dampingFraction: 0.82),
                       value: configuration.isPressed)
    }
}

/// 电池符号按电量分五档；充电时用带闪电的变体，不依赖颜色表达状态
func batterySymbolName(percentage: Int, charging: Bool) -> String {
    let level: String
    switch percentage {
    case 88...: level = "battery.100"
    case 63..<88: level = "battery.75"
    case 38..<63: level = "battery.50"
    case 13..<38: level = "battery.25"
    default: level = "battery.0"
    }
    return charging ? "\(level).bolt" : level
}

/// 进度条本体：轨道 + 填充，展开态可拖进度条专用；
/// 收起态不再画那条 2pt 进度线（改为左音源图标 + 右波形），进度只在展开态出现
struct IslandProgressBar: View {
    /// 0...1 的播放比例，越界值在这里夹住
    let ratio: Double

    var body: some View {
        // 用 scaleEffect 而不是再套一层 GeometryReader：调用方已经在量宽度，
        // 这里再量一次等于每次刷新多跑一遍布局
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.55))
                .scaleEffect(x: min(max(ratio, 0), 1), anchor: .leading)
        }
    }
}

/// 右下角音源图标：换源淡入淡出，用于区分 Apple Music / Spotify / 网易云 / 浏览器
/// 没有音源时位置照占、图标透明，进度条宽度不会跟着跳
struct AppIconView: View {
    let image: NSImage?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 无音源时用透明占位，只为了占住 16×16，不让进度条宽度跟着跳
        Color.clear
            .frame(width: 16, height: 16)
            .overlay {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        // 16pt 图标按系统图标比例取 4，比小控件 6–8 更贴近原生观感
                        .clipShape(RoundedRectangle(cornerRadius: IslandSizeTable.appIconCornerRadius, style: .continuous))
                        .transition(.opacity)   // 换源淡入淡出，不硬切
                }
            }
            .animation(reduceMotion ? .smooth(duration: 0.12) : .smooth(duration: 0.22),
                       value: image != nil)
    }
}

// MARK: - 收起态状态条

/// 收起态状态条：只在右侧留跳动波形，中间让开物理刘海（左槽留空）。
/// 宽度由外层容器给定（刘海宽 + collapsedExtraWidth），这里只按右侧固定槽排布；
/// 有曲目时容器才左右各加 20，没有曲目时容器等于刘海宽、整条一并消失，
/// 暂停时仍留着压平的波形（说明「还是这一首」），只有彻底空态才隐藏。
/// 纯展示：不加按钮、不加手势，点击继续穿透到菜单栏
struct CollapsedStatusBar: View {
    let isPlaying: Bool
    /// 是否还有可展示的播放内容：决定整条淡入淡出，不受暂停影响
    let hasMedia: Bool
    /// 当前机型的刘海高：波形的槽高与柱高都按它缩放，换机型不会顶出刘海
    let notchHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)   // 左侧留空 + 刘海区域：不画任何东西
            sideSlot {
                WaveformBars(isPlaying: isPlaying, notchHeight: notchHeight)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(hasMedia ? 1 : 0)
        .animation(reduceMotion ? .smooth(duration: 0.12) : .smooth(duration: 0.22), value: hasMedia)
    }

    /// 右侧 20pt 状态槽：18pt 波形居中后距岛体边缘 1pt；槽高按波形最高点给，不额外占位
    private func sideSlot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: IslandSizeTable.collapsedStatusSideWidth,
                   height: IslandSizeTable.collapsedWaveMaxHeight(notchHeight: notchHeight))
    }
}

/// 收起态波形：4 根 3pt 竖条按拍点起伏（起音冲顶 + 指数回落），播放中才动、暂停压回基线。
/// 真实振幅要 Core Audio process tap + 系统音频录制授权，这里按 115 BPM 的拍点模拟，
/// 每拍每柱的峰值用确定性哈希错开，避免「匀速正弦」那种机械感。
/// TimelineView 暂停时停表不空转；减弱动态效果时同样静止。
/// 只改 4 个矩形高度，不触发文本与容器重新布局
struct WaveformBars: View {
    let isPlaying: Bool
    /// 刘海高：柱高上下限按它缩放（32pt 刘海 → 顶 14 / 底 4）
    let notchHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isActive: Bool {
        isPlaying && !reduceMotion
    }

    private var maxHeight: CGFloat {
        IslandSizeTable.collapsedWaveMaxHeight(notchHeight: notchHeight)
    }

    private var minHeight: CGFloat {
        IslandSizeTable.collapsedWaveMinHeight(notchHeight: notchHeight)
    }

    private var totalWidth: CGFloat {
        CGFloat(IslandSizeTable.collapsedWaveBarCount) * IslandSizeTable.collapsedWaveBarWidth
            + CGFloat(IslandSizeTable.collapsedWaveBarCount - 1) * IslandSizeTable.collapsedWaveBarSpacing
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: IslandSizeTable.collapsedWaveInterval,
                                paused: !isActive)) { context in
            HStack(alignment: .center, spacing: IslandSizeTable.collapsedWaveBarSpacing) {
                ForEach(0..<IslandSizeTable.collapsedWaveBarCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.55))
                        .frame(width: IslandSizeTable.collapsedWaveBarWidth,
                               height: barHeight(index: index, at: context.date))
                }
            }
        }
        .frame(width: totalWidth, height: maxHeight)
        .accessibilityHidden(true)   // 播放状态已由图标与岛体整体语义表达，不重复朗读
    }

    /// 柱高 = 底线 + 拍点包络；暂停或减弱动态效果时全部回到基线
    private func barHeight(index: Int, at date: Date) -> CGFloat {
        guard isActive else { return minHeight }

        let time = date.timeIntervalSinceReferenceDate
        let beats = time / IslandSizeTable.collapsedWaveBeatPeriod
        let beat = beats.rounded(.down)
        // 柱与柱只错开一点点：看起来像同时被一拍打起来，不是一条从左跑到右的波
        var inBeat = beats - beat + Double(index) * IslandSizeTable.collapsedWaveSkew
        if inBeat >= 1 { inBeat -= 1 }

        // 起音线性冲顶，之后指数回落；拍与拍之间停在底线附近
        let attack = IslandSizeTable.collapsedWaveAttack
        let envelope = inBeat < attack
            ? inBeat / attack
            : exp(-(inBeat - attack) * IslandSizeTable.collapsedWaveDecay)

        // 每拍每柱一个 0.45–1 的幅度：用拍号哈希，不存状态也能每次算出同一个值
        let amplitude = 0.45 + 0.55 * noise(beat, salt: Double(index) + 1)
        let ripple = 0.5 + 0.5 * sin(time * 2 * .pi * IslandSizeTable.collapsedWaveRippleHz
            + Double(index) * 1.7)

        let idle = IslandSizeTable.collapsedWaveIdleRatio
        let normalized = min(1, idle + (1 - idle) * envelope * amplitude * (0.6 + 0.4 * ripple))
        return minHeight + (maxHeight - minHeight) * normalized
    }

    /// 确定性伪随机（0...1）：同一拍号 + 同一柱号永远同一个值，视图可无状态重算
    private func noise(_ beat: Double, salt: Double) -> Double {
        let value = sin(beat * 12.9898 + salt * 78.233) * 43758.5453
        return value - value.rounded(.down)
    }
}

/// 圆形封面：只负责「圆形裁剪 + 按给定角度旋转」，角度由调用方按播放进度算，
/// 暂停时自然冻结（不要用 repeatForever，SwiftUI 停不下来、恢复还会跳回 0°）
struct RotatingArtwork: View {
    let image: NSImage?
    let side: CGFloat
    let angle: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.36, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .rotationEffect(.degrees(angle))
    }
}

/// 顶栏页签：把场景映射成图标与中文名，选中态由 IslandIconButton 承担
struct PageTabButton: View {
    let scene: IslandScene
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        IslandIconButton(symbol: isSelected ? scene.filledSymbol : scene.outlineSymbol,
                         pointSize: 12,
                         isSelected: isSelected,
                         accessibilityText: scene.tabTitle,
                         action: action)
    }
}

/// 展开态顶栏：左上音乐 / 文件 / 主页三个页签，右侧锁定、电量、百分比、循环次数与充电状态
/// 固定在刘海两侧，中间靠 Spacer 让开物理挖孔；尺寸由档位给定，不随文字变
struct IslandTopBar: View {
    let width: CGFloat
    let height: CGFloat
    let battery: BatteryStatus
    let scene: IslandScene
    /// 是否读到曲目：没有就整枚音乐页签都不画
    let hasMusic: Bool
    /// 锁定不弹出：已禁止悬停自动展开
    let autoExpandBlocked: Bool
    let onSelectScene: (IslandScene) -> Void
    let onToggleLock: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: IslandSizeTable.topBarSpacing) {
                ForEach(IslandScene.tabs(hasMusic: hasMusic), id: \.self) { tab in
                    PageTabButton(scene: tab, isSelected: scene == tab) {
                        onSelectScene(tab)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: IslandSizeTable.topBarSpacing) {
                // 锁定态靠符号本身表达，不靠颜色
                IslandIconButton(symbol: autoExpandBlocked ? "lock.fill" : "lock.open",
                                 pointSize: 12,
                                 accessibilityText: autoExpandBlocked ? "解锁" : "锁定",
                                 action: onToggleLock)
                batteryCluster
            }
        }
        .padding(.horizontal, IslandSizeTable.topBarPadding)
        .frame(width: width, height: height)
    }

    private var batteryCluster: some View {
        HStack(spacing: IslandSizeTable.topBarSpacing) {
            Image(systemName: batterySymbolName(percentage: battery.percentage,
                                                charging: battery.isCharging))
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.55))
            Text("\(battery.percentage)%")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .fixedSize()
            // 系统没给循环次数时占位显示「循环 —」，不整块消失，避免顶栏宽度跳动
            // 不 fixedSize：空间不足时尾部截断，宁缺也不挤进刘海
            Text(battery.cycleCount.map { "循环 \($0)" } ?? "循环 —")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
            powerStateSymbol
        }
        // 台式机没有电池：只隐藏电量这一簇，主页/锁定图标照常可用
        .opacity(battery.isAvailable ? 1 : 0)
        .accessibilityHidden(!battery.isAvailable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// 充电中已由带闪电的电池符号表达；外接电源未充电再用插头补一档，纯电池供电不加标记
    @ViewBuilder
    private var powerStateSymbol: some View {
        if !battery.isCharging && battery.isExternalConnected {
            Image(systemName: "powerplug.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var accessibilityText: String {
        let state = battery.isCharging
            ? "充电中"
            : (battery.isExternalConnected ? "已接电源" : "使用电池")
        let cycles = battery.cycleCount.map { "，循环 \($0) 次" } ?? ""
        return "电量 \(battery.percentage)%，\(state)\(cycles)"
    }
}