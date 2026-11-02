import Cocoa
import Combine
import EventKit

// ---------------------------------------------------------------------------
// 今日日程：EventKit
//
// 首次进主页时请求「完整访问日历」，用户拒绝就静默降级成只显示「日历未授权」，
// 不重复弹框、不做二次引导。日程只取今天、按开始时间排序、最多留两条，
// 超出部分由主页自己折成「还有 N 项」；另给一条 next（进行中 / 即将开始 / 全天），
// 主页用它画第一行的倒计时。
// 刷新靠 60s 定时器 + EKEventStoreChanged 通知（改日程时立刻更新）。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

struct CalendarEntry: Equatable, Identifiable {
    var id: String
    var time: String
    var title: String
    /// 开始时间：主页据此算「N 分钟后」与「进行中」
    var startDate: Date
    /// 全天事件没有具体时刻，倒计时行显示「全天」
    var isAllDay: Bool
}

final class CalendarSource: ObservableObject {
    enum Access: Equatable {
        case unknown
        case denied
        case granted
    }

    @Published private(set) var entries: [CalendarEntry] = []
    /// 主页第一行那条：进行中的优先，其次即将开始，最后才是全天；
    /// 三者都为空（今天没有日程 / 未授权 / 正在读）时由视图给降级文案
    @Published private(set) var next: CalendarEntry?
    @Published private(set) var access: Access = .unknown
    /// 是否已被用户允许读取日历（设置里的开关）；关着时不请求授权、主页给「未开启」
    @Published private(set) var isEnabled = false
    /// 今日事件总数，用来显示「还有 N 项」
    @Published private(set) var totalCount = 0

    private let store = EKEventStore()
    private var timer: Timer?
    private var changeObserver: NSObjectProtocol?
    private var isRequesting = false

    /// 只算今天、只留两条：主页放不下更多，也不值得为它加滚动
    private static let visibleCount = 2

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    deinit {
        timer?.invalidate()
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
        guard timer == nil else { return }
        isEnabled = true
        requestAccessIfNeeded()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        // 视图消失或被用户关掉：不发新请求，主页回到「未开启」而不是「未授权」
        isEnabled = false
        access = .unknown
        timer?.invalidate()
        timer = nil
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
            changeObserver = nil
        }
    }

    private func requestAccessIfNeeded() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess:
            access = .granted
        case .denied, .restricted, .writeOnly:
            access = .denied
        case .notDetermined:
            guard !isRequesting else { return }
            isRequesting = true
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isRequesting = false
                    self.access = granted ? .granted : .denied
                    self.refresh()
                }
            }
        @unknown default:
            access = .denied
        }
    }

    func refresh() {
        guard access == .granted else {
            publish([], nextEntry: nil)
            return
        }
        let calendar = Calendar.current
        let now = Date()
        guard let start = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: now),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let today = store.events(matching: predicate)
            .filter { !$0.title.isEmpty }
            .sorted { $0.startDate < $1.startDate }

        let entries = today.prefix(Self.visibleCount).map(Self.makeEntry)
        // 进行中的排在最前：此刻「正在开什么会」比「下一个会几点」更值得看
        let ongoing = today.first { !$0.isAllDay && $0.startDate <= now && $0.endDate > now }
        let upcoming = today.first { $0.startDate >= now && !$0.isAllDay }
        let allDay = today.first { $0.isAllDay }
        publish(Array(entries), nextEntry: (ongoing ?? upcoming ?? allDay).map(Self.makeEntry), total: today.count)
    }

    private static func makeEntry(_ event: EKEvent) -> CalendarEntry {
        CalendarEntry(id: event.eventIdentifier ?? UUID().uuidString,
                      time: event.isAllDay ? "全天" : timeFormatter.string(from: event.startDate),
                      title: event.title ?? "",
                      startDate: event.startDate,
                      isAllDay: event.isAllDay)
    }

    private func publish(_ entries: [CalendarEntry], nextEntry: CalendarEntry?, total: Int = 0) {
        if self.entries != entries { self.entries = entries }
        if next != nextEntry { next = nextEntry }
        if totalCount != total { totalCount = total }
    }
}