import SwiftUI

// ---------------------------------------------------------------------------
// 主页：左边天气、右边今日日程与倒计时，底行天气 / 内存 / 磁盘
//
// 只在「没有任何音频软件在播」时出现，也是顶栏房子图标的落点。
// 行高与媒体场景的封面行一致（artworkSide），所以两个场景来回切时岛体尺寸不变，
// 不会出现展开高度跳一下的观感。
// 日期与菜单栏重复，2026-11-04 去掉，原位置改放「进行中 / N 分钟后」的日程引导。
// 天气没取到显示占位而不是空白，日历没授权说明原因，两种情况都不弹框。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

struct HomeScene: View {
    /// 可用内容宽（已扣掉岛体左右内边距）
    let width: CGFloat
    /// 上排高度：与媒体场景封面行一致
    let rowHeight: CGFloat
    /// 下排高度：与媒体场景进度行一致
    let footerHeight: CGFloat

    @ObservedObject var weather: WeatherSource
    @ObservedObject var calendar: CalendarSource
    /// 内存与磁盘：30s 采样，取不到的项不画
    @ObservedObject var system: SystemMetricsMonitor
    /// 读不到曲目时唯一允许出现的失败提示：客户端没开调试端口（其余一律静默）
    let portNotice: MusicPortNotice?
    /// 点提示行：带调试端口重启客户端
    let onFixMusic: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: IslandSizeTable.progressGap) {
            HStack(alignment: .top, spacing: IslandSizeTable.homeColumnSpacing) {
                weatherBlock
                    .frame(width: IslandSizeTable.homeWeatherWidth, alignment: .leading)
                calendarBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: rowHeight, alignment: .top)

            footer
                .frame(height: footerHeight)
        }
        // 数据源由宿主的 onAppear 统一启动：主页不一定是首屏，
        // 挂在 onAppear 里会在「一直在放歌」时永远不拉天气与日程
        .frame(width: width)
    }

    // MARK: - 天气

    private var weatherBlock: some View {
        HStack(spacing: 12) {
            // 符号 16 与封面占位里的 music.note 同档，不另造一套图标尺寸
            Image(systemName: weather.snapshot?.symbol ?? "thermometer.medium")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 24)
                // 换天气现象时淡入，不硬切
                .animation(reduceMotion ? .smooth(duration: 0.12) : .smooth(duration: 0.22),
                           value: weather.snapshot?.symbol)

            VStack(alignment: .leading, spacing: 2) {
                Text(temperatureText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(rangeText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    /// 取不到时给占位，不留空：岛体宽度是写死的，文字短一点不会让布局跳
    private var temperatureText: String {
        guard let snapshot = weather.snapshot else { return "--°" }
        return "\(snapshot.temperature)°"
    }

    /// 城市常驻：没数据时只留城市名，取到后与高低温同一行，位置不跳
    private var rangeText: String {
        guard let snapshot = weather.snapshot else { return weather.cityName }
        return "\(weather.cityName) \(snapshot.high)° / \(snapshot.low)°"
    }

    // MARK: - 日程

    private var calendarBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 第一行是日程引导（进行中 / N 分钟后 / 今天没有更多日程），
            // 每分钟走一次 TimelineView：CalendarSource 的 60s 刷新只在数据变化时发布，
            // 倒计时本身不会触发重绘，所以相对时间由这里的时间轴驱动
            TimelineView(.periodic(from: .now, by: 60)) { context in
                calendarLeadRow(now: context.date)
            }

            ForEach(calendar.entries) { entry in
                HStack(spacing: 8) {
                    Text(entry.time)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize()
                    Text(entry.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 引导行：左边主信息（13 semibold）配标题（11 次级），右端是折叠掉的日程数
    private func calendarLeadRow(now: Date) -> some View {
        HStack(spacing: 6) {
            if let lead = leadText(now: now) {
                Text(lead.time)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                if let title = lead.title {
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                // 「还有 N 项」只在有引导条目时出现：降级文案配「还有 2 项」会自相矛盾
                if hiddenCalendarCount > 0 {
                    Text("还有 \(hiddenCalendarCount) 项")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .fixedSize()
                }
            } else {
                // 没有可引导的日程：三种降级都要说清原因，不然「什么都没有」会被看成坏了
                Text(calendarHint)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }

    private var hiddenCalendarCount: Int {
        max(0, calendar.totalCount - calendar.entries.count)
    }

    /// 进行中优先于即将开始；没有未来日程就不返回，交给降级文案
    private func leadText(now: Date) -> (time: String, title: String?)? {
        guard calendar.access == .granted, let entry = calendar.next else { return nil }
        if entry.isAllDay { return ("全天", entry.title) }
        let minutes = Int(entry.startDate.timeIntervalSince(now) / 60)
        if minutes < 0 { return ("进行中", entry.title) }
        if minutes < 1 { return ("即将开始", entry.title) }
        if minutes < 60 { return ("\(minutes) 分钟后", entry.title) }
        return ("\(minutes / 60) 小时后", entry.title)
    }

    private var calendarHint: String {
        switch calendar.access {
        case .granted: return calendar.entries.isEmpty ? "今日无日程" : "今天没有更多日程"
        case .denied: return "日历未授权"
        case .unknown:
            // 用户没在设置里打开时不能显示「正在读取」，否则看起来像卡住了
            return calendar.isEnabled ? "正在读取日历" : "日历未开启"
        }
    }

    // MARK: - 底行

    private var footer: some View {
        HStack(spacing: 8) {
            if let notice = portNotice {
                portFixButton(notice)
            } else {
                Text(weatherLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let systemLine = systemLine {
                Text(systemLine)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// 底行那行可点的失败提示。文案（未开端口 / 正在重启 / 重启失败）由 store 给，
    /// 这里只负责把它做成 28 高的热区，并在重启途中不再响应点击
    private func portFixButton(_ notice: MusicPortNotice) -> some View {
        Button {
            onFixMusic()
        } label: {
            Text(notice.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .frame(minHeight: 28)   // 文字只有 14 高，补到 28 才够点
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle())
        .disabled(notice.busy)
    }

    private var weatherLine: String {
        guard let snapshot = weather.snapshot else { return "天气读取中" }
        var parts = [snapshot.condition]
        if let chance = snapshot.precipitationChance { parts.append("\(chance)%") }
        if let sunset = snapshot.sunset { parts.append("日落 \(sunset)") }
        return parts.joined(separator: " · ")
    }

    /// 取不到就当没有这一块：不写「--」占位，避免底行出现无意义字符
    private var systemLine: String? {
        var parts: [String] = []
        if let memory = system.metrics.memoryUsage { parts.append("内存 \(memory)%") }
        if let free = system.metrics.diskFreeGB { parts.append("磁盘 \(free)G") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}