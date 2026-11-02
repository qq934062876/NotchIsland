import SwiftUI

// ---------------------------------------------------------------------------
// 展开态媒体列：封面 / 标题 / 控制键 + 进度
//
// 从 IslandView 拆出来是为了守住 400 行线：容器只负责尺寸、裁剪与场景分发，
// 这一列只读 MediaStore 的展示状态，不碰 CoreAudio、不起子进程。
//
// 2026-11-03 用户要求去掉「其他音频播放的效果」：没有元数据时不再摆应用图标 +
// 「正在播放音频」+ 波形占位，也不再有「后台有多个音频软件」提示与「重启」入口。
// 现在这一列只在真的读到曲目时才会被看到（音乐页签没有曲目就整枚不画）。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

struct IslandMediaColumn: View {
    @ObservedObject var store: MediaStore
    let metrics: IslandMetrics
    let expanded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 拖动进度条时的预览比例（0...1），松手才真正下发 seek
    @State private var dragRatio: Double?
    /// 进度条悬停时略微加粗，给出「可拖」的暗示
    @State private var hoveringProgress = false

    // 两排都按最终档位尺寸排版一次，动画期只由外层容器裁剪，不做条件分支切换
    var body: some View {
        VStack(spacing: IslandSizeTable.progressGap) {
            mediaRow
            footerRow
        }
    }

    private var titleText: String {
        store.title.isEmpty ? "未在播放" : store.title
    }

    private var subtitleText: String {
        store.artist.isEmpty ? "打开网易云或音乐试试" : store.artist
    }

    private var mediaRow: some View {
        HStack(spacing: 12) {
            artworkView

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitleText)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)   // 余量由档位宽度决定，长标题尾部截断

            controls
        }
        .frame(height: metrics.artworkSide)   // 行高锁死，封面裁切有余量时列高也不抖
    }

    private var controls: some View {
        HStack(spacing: 14) {
            IslandIconButton(symbol: "backward.fill", accessibilityText: "上一首") { store.previous() }
            IslandIconButton(symbol: store.isPlaying ? "pause.fill" : "play.fill",
                             accessibilityText: store.isPlaying ? "暂停" : "播放") { store.togglePlayPause() }
            IslandIconButton(symbol: "forward.fill", accessibilityText: "下一首") { store.next() }
        }
        .fixedSize()
    }

    /// 底行：有进度就画时间与进度条，没有进度（通道不给时长）就整条留空占位。
    /// 最右侧固定留出音源图标位，图标显隐不影响进度条宽度
    private var footerRow: some View {
        HStack(spacing: 8) {
            progressRow
                .opacity(showsProgress ? 1 : 0)
                .allowsHitTesting(showsProgress)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: IslandSizeTable.progressRowHeight)

            AppIconView(image: store.appIcon)
        }
        .frame(height: IslandSizeTable.progressRowHeight)
    }

    private var showsProgress: Bool {
        !store.title.isEmpty && store.duration > 0
    }

    /// 进度条只在这里按 0.25s 重算，不动岛体尺寸，也不提高通道采样频率；
    /// 收起或暂停时停表：这一行虽然不可见，但 reprocess 仍会跑一遍文字布局
    private var progressRow: some View {
        TimelineView(.animation(minimumInterval: 0.25,
                                paused: !expanded || !store.isPlaying)) { context in
            HStack(spacing: 8) {
                Text(timeText(elapsed(at: context.date)))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize()
                progressBar(at: context.date)
                Text(timeText(store.duration))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize()
            }
        }
    }

    private func progressBar(at date: Date) -> some View {
        let ratio = dragRatio ?? playedRatio(at: date)
        return GeometryReader { geo in
            IslandProgressBar(ratio: ratio)
            .frame(height: hoveringProgress ? 4 : 3)   // 悬停略微加粗，给出「可拖」暗示
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard store.canSeek, geo.size.width > 0 else { return }
                        dragRatio = min(max(0, value.location.x / geo.size.width), 1)
                    }
                    .onEnded { value in
                        let target = min(max(0, value.location.x / geo.size.width), 1)
                        dragRatio = nil
                        guard store.canSeek else { return }
                        store.seek(to: store.duration * target)
                    }
            )
        }
        .frame(height: IslandSizeTable.progressRowHeight)
        .animation(reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.16), value: hoveringProgress)
        .onHover { inside in
            hoveringProgress = inside
        }
    }

    private func playedRatio(at date: Date) -> Double {
        guard store.duration > 0 else { return 0 }
        return min(max(0, elapsed(at: date) / store.duration), 1)
    }

    /// 采样点 + 本地时钟插值；暂停时停在锚点，不跟系统时间跑
    private func elapsed(at date: Date) -> TimeInterval {
        let extra = store.isPlaying ? date.timeIntervalSince(store.progress.date) : 0
        return max(0, store.progress.seconds + extra)
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 圆形封面：角度按「累计播放秒数」算，暂停时 elapsed 冻结 -> 角度停住，
    /// 恢复从原角度继续。收起态与减弱动态效果下不刷新，省掉看不见的逐帧
    private var artworkView: some View {
        TimelineView(.animation(minimumInterval: IslandSizeTable.artworkRotationInterval,
                                paused: !store.isPlaying || !expanded || reduceMotion)) { context in
            RotatingArtwork(image: store.artwork,
                            side: metrics.artworkSide,
                            angle: artworkAngle(at: context.date))
        }
        .frame(width: metrics.artworkSide, height: metrics.artworkSide)
        .fixedSize()
    }

    /// 封面角度 = 已播秒数占一圈周期的比例；12s 一圈比系统 Music 慢一点，不抢注意力。
    /// 减弱动态效果时角度固定为 0：只停表会让封面停在某个随机角度上，
    /// 看上去像「转了一半卡住」，所以要真正摆正（读数走环境值，系统设置改了立即生效）
    private func artworkAngle(at date: Date) -> Double {
        guard !reduceMotion else { return 0 }
        let period = IslandSizeTable.artworkRotationPeriod
        let seconds = elapsed(at: date).truncatingRemainder(dividingBy: period)
        return seconds / period * 360
    }
}