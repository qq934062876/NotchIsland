import Cocoa
import Combine

// ---------------------------------------------------------------------------
// 播放状态
//
// 2026-11-03 用户当面改口径：音乐板块不再「有声音就出现」，改为「白名单播放器里
// 读到真实曲目才出现」。判定统一交给 MusicGate：
//   - 只认网易云 / 汽水音乐 / Apple Music / Spotify；浏览器、视频、会议出声都不算
//   - 暂停也算有内容（页签保留，能点播放继续）；读不到曲目就整块消失、回主页
//   - 多家同时在跑时显示「正在播放优先、同级取最后打开」的那一家
//
// 三条通道并行采样，只收白名单应用的结果，再交给 MusicGate.select 选唯一一家：
//   系统直连（MediaRemote，老系统快路径，本机 macOS 26 恒空）
//   osascript 代理（Apple Music / Spotify 的脚本字典）
//   CDP（网易云、汽水音乐这类 Chromium/CEF 客户端，走客户端自带的调试端口）
//
// 进度不靠提高采样频率：每次采样只更新锚点（秒数 + 采样时刻），界面用本地时钟插值，
// 换歌、seek、暂停恢复时锚点才重设。失败一律静默返回空快照，不弹窗、不打日志刷屏。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

/// 进度锚点：采样那一刻的已播秒数，以及那一刻的时间
struct PlaybackAnchor {
    var seconds: TimeInterval = 0
    var date = Date()
}

final class MediaStore: ObservableObject {
    @Published var title = ""
    @Published var artist = ""
    @Published var artwork: NSImage?
    @Published var isPlaying = false
    /// 音源应用的 bundle id，用于查尺寸档位；取不到就是 nil（回落场景默认档）
    @Published var bundleID: String?
    /// 音源应用图标，右下角展示用；只随 bundleID 变化解析一次
    @Published var appIcon: NSImage?
    @Published var progress = PlaybackAnchor()
    @Published var duration: TimeInterval = 0
    @Published var canSeek = false
    /// 唯一场景开关：白名单播放器里读到了真实曲目（暂停也算）。
    /// 音乐页签显隐、主页/音乐页回落都只看它
    @Published private(set) var hasMusic = false
    /// 主页唯一会出现的失败提示：客户端在跑但没开调试端口。
    /// 只有这一种情况给入口，其余读不到一律静默（2026-11-03 用户改口径）
    @Published private(set) var portNotice: MusicPortNotice?

    /// 能力开关：默认关闭（见 AppSettings），关闭时 system / bridge 两条通道不取数
    private let settings = AppSettings.shared
    private var settingsBag: Set<AnyCancellable> = []

    /// 懒加载：构造里会 dlopen 私有框架并注册系统通知，用户没同意读取前不碰
    private lazy var system = SystemNowPlayingSource()
    /// 15.4+ 的代理通道：只问带脚本字典的那几家
    private let bridge = MediaBridge()
    /// CDP 客户端：抓取里先看进程在不在，没开就不会去碰端口
    private let cdpSources: [CDPPlayerSource] = [NeteaseSource(), SodaSource()]
    private let audio = AudioActivity()

    /// 上次代理通道返回的标题，用来决定是否回传封面 base64
    private var bridgeTitle = ""

    /// 当前展示的是哪条通道，决定控制命令发给谁
    private var activeSource: PlaybackSourceKind = .system
    private var anchorValid = false
    /// 上次解析图标用的 bundle id，避免每轮采样都查一遍磁盘
    private var iconBundleID: String?

    private var pollTimer: Timer?
    /// 轮询序号：异步回调可能乱序返回，旧序号的回调直接丢弃
    private var tick = 0
    /// 正在带端口重启客户端：期间不让探测结果把「正在重启…」改写掉
    private var portFixBusy = false

    private static let pollInterval: TimeInterval = 1.5

    init() {
        // 系统通道要等用户同意后才创建（见 activateSystemChannel）
        if settings.readNowPlaying { activateSystemChannel() }
        // 封面下载完成后立刻刷一次，不让占位图停到下一个周期
        for source in cdpSources {
            source.onChange = { [weak self] in self?.poll() }
            // 端口开/关变化时补采一次：主页那行重启入口的显隐只跟这个状态
            source.onPortStateChange = { [weak self] in self?.poll() }
        }
        bridge.onChange = { [weak self] in self?.poll() }
        // CoreAudio 起播/停止事件：去抖后立刻采样。
        // 这条是「岛先常驻、之后才放歌」能立刻出内容的关键，1.5s 轮询只做兜底
        audio.onChange = { [weak self] in self?.poll() }
        audio.start()

        observeSettings()
        // 只有用户同意「允许岛管理播放器」才带端口拉起，否则一个进程都不碰
        if settings.autoLaunchPlayers { launchClients() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    /// 设置改动即时生效：关掉读取就立刻清空音乐页并回主页，打开就立刻补采一次
    private func observeSettings() {
        settings.$readNowPlaying
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if enabled { self.activateSystemChannel() } else { self.clearNowPlaying() }
                    self.poll()
                }
            }
            .store(in: &settingsBag)

        settings.$autoLaunchPlayers
            .dropFirst()
            .sink { [weak self] enabled in
                // 打开那一刻补一次拉起；关闭时不动已经在跑、已经带端口的客户端
                guard enabled else { return }
                DispatchQueue.main.async { self?.launchClients() }
            }
            .store(in: &settingsBag)
    }

    /// 首次打开「读取正在播放」时构造系统通道并挂上变化回调。
    /// 重复调用只会把回调再赋一次，代价可以忽略
    private func activateSystemChannel() {
        system.onChange = { [weak self] in self?.poll() }
    }

    /// 用户关掉读取通道：把界面侧状态一起清掉，不留上一首的残影
    private func clearNowPlaying() {
        apply(.empty)
        portNotice = nil
        activeSource = .system
        IslandDebug.log("settings", "已关闭读取，清空播放状态")
    }

    deinit {
        pollTimer?.invalidate()
        audio.stop()
    }

    // MARK: - 轮询

    func poll() {
        tick += 1
        let sequence = tick

        // 谁在跑、谁在出声。只有「在跑」的客户端才值得去碰端口/起子进程；
        // 「在出声」只作为同等条件下的优先依据，不再决定场景
        let running = MusicGate.runningPlayers()
        var launchDates: [String: Date] = [:]
        for item in running { launchDates[item.player.bundleID] = item.launchDate }
        let sounding = Set(audio.sample().map(\.bundleID)).filter { MusicGate.isPlayer($0) }

        var results: [NowPlayingSnapshot] = []
        var remaining = 0

        let finish: () -> Void = { [weak self] in
            guard let self = self, sequence == self.tick else { return }
            let snapshot = MusicGate.select(Self.whitelisted(results)) { launchDates[$0] ?? .distantPast }
            self.apply(snapshot)
            self.updatePortNotice(ready: snapshot.bundleID)
            IslandDebug.log("pick",
                            "hasMusic=\(self.hasMusic) source=\(snapshot.source) "
                            + "title=\(snapshot.title) bundle=\(snapshot.bundleID ?? "-") "
                            + "running=\(running.map(\.player.bundleID).joined(separator: ",")) "
                            + "sounding=\(sounding.sorted().joined(separator: ","))")
        }
        let collect: (NowPlayingSnapshot) -> Void = { snapshot in
            results.append(snapshot)
            remaining -= 1
            if remaining == 0 { finish() }
        }

        // 1. 系统直连：一次读到全局 Now Playing。浏览器、视频软件也可能注册过，
        //    所以只收白名单应用的快照（见 whitelisted），其余一律丢弃。
        //    私有框架与 TCC 授权都在这一条上，用户没打开就完全不碰
        if settings.readNowPlaying {
            remaining += 1
            system.fetch { snapshot in collect(snapshot) }
        }

        // 2. 代理通道：只对在跑的脚本型播放器 spawn 子进程，一轮只问一家。
        //    起子进程比读端口贵得多（约 0.1s），所以只在三种情况下问：
        //    这家正在出声 / 它就是当前音源（暂停中也要跟手，但 6s 一次够）/
        //    每 10 拍（15s）探一次静默发现——岛启动时播放器可能正停在某首歌上。
        //    osascript 会触发「控制其他 App」授权，同样受 readNowPlaying 控制
        if settings.readNowPlaying,
           let target = Self.bridgeTarget(running.map(\.player), sounding: sounding),
           Self.shouldProbeBridge(target.bundleID, sounding: sounding.contains(target.bundleID),
                                  active: bundleID, tick: tick) {
            remaining += 1
            bridge.fetch(app: target.bundleID, lastTitle: bridgeTitle) { [weak self] snapshot in
                // 只有真拿到封面才记住这首；否则下一轮让脚本再传一次
                self?.bridgeTitle = snapshot.artwork != nil ? snapshot.title : ""
                collect(snapshot)
            }
        }

        // 3. CDP 客户端：进程在跑才探测，端口没开的退避由通道自己管。
        //    同样是「读播放器信息」，与系统通道受同一个开关控制
        if settings.readNowPlaying {
            for source in cdpSources where source.isRunning {
                remaining += 1
                source.fetch { snapshot in collect(snapshot) }
            }
        }

        // 端口状态独立于采样计数：客户端退出也要清掉，否则主页会挂着一行过时的提示。
        // 不读播放器、或不管理播放器时都不用探端口，这一圈白花
        if settings.readNowPlaying && settings.autoLaunchPlayers {
            for source in cdpSources where source.profile.preparesPortOnLaunch {
                source.probePort()
            }
        }

        if remaining == 0 { finish() }
    }

    /// 只留白名单应用的快照，并按 bundle id 去重：
    /// 同一家可能同时被系统通道与专用通道读到，取「有进度信息」的那条更完整
    private static func whitelisted(_ snapshots: [NowPlayingSnapshot]) -> [NowPlayingSnapshot] {
        var kept: [String: NowPlayingSnapshot] = [:]
        for snapshot in snapshots where snapshot.hasContent {
            guard let id = snapshot.bundleID, MusicGate.isPlayer(id) else { continue }
            if let existing = kept[id] {
                kept[id] = quality(existing) >= quality(snapshot) ? existing : snapshot
            } else {
                kept[id] = snapshot
            }
        }
        return Array(kept.values)
    }

    /// 进度可拖且有时长 > 正在播放 > 其它
    private static func quality(_ snapshot: NowPlayingSnapshot) -> Int {
        var score = 0
        if snapshot.canSeek && snapshot.duration > 0 { score += 2 }
        if snapshot.isPlaying { score += 1 }
        return score
    }

    /// 代理通道一轮只问一家：先挑正在出声的脚本型播放器，否则挑在跑的第一家
    /// （暂停时也要读一次，用户要求暂停仍保留音乐页）
    private static func bridgeTarget(_ running: [MusicPlayer], sounding: Set<String>) -> MusicPlayer? {
        let scriptable = running.filter { $0.channel == .scriptable }
        if let playing = scriptable.first(where: { sounding.contains($0.bundleID) }) { return playing }
        return scriptable.first
    }

    /// osascript 子进程启动约 0.1s，静默时不能 1.5s 一次白跑（AGENTS「静默时零 spawn」）
    private static func shouldProbeBridge(_ target: String, sounding: Bool,
                                          active: String?, tick: Int) -> Bool {
        if sounding { return true }
        if target == active { return tick % 4 == 1 }   // 暂停中：6s 一次，改歌/续播照样跟手
        return tick % 10 == 1                          // 静默发现：15s 一次，启动时停在旧歌上也能出
    }

    private func apply(_ snapshot: NowPlayingSnapshot) {
        let trackChanged = title != snapshot.title || activeSource != snapshot.source
        // 场景开关只看「有没有曲目」，暂停也算；读不到就 false，界面回主页并收起音乐页签
        let hasContent = snapshot.hasContent
        if hasMusic != hasContent { hasMusic = hasContent }

        if title != snapshot.title { title = snapshot.title }
        if artist != snapshot.artist { artist = snapshot.artist }
        if isPlaying != snapshot.isPlaying { isPlaying = snapshot.isPlaying }
        if bundleID != snapshot.bundleID {
            bundleID = snapshot.bundleID
            updateAppIcon(for: snapshot.bundleID)
        }
        if duration != snapshot.duration { duration = snapshot.duration }
        if canSeek != snapshot.canSeek { canSeek = snapshot.canSeek }
        activeSource = snapshot.source
        // 系统通道缓存了解码后的图，同一首歌引用不变，不会重复赋值
        if artwork !== snapshot.artwork { artwork = snapshot.artwork }

        updateAnchor(snapshot.progress, trackChanged: trackChanged)
    }

    /// 只在音源变化时取一次图标；取不到就显示占位，不阻塞任何采样
    private func updateAppIcon(for id: String?) {
        guard id != iconBundleID else { return }
        iconBundleID = id
        appIcon = id.flatMap { AppIconCache.icon(for: $0) }
    }

    /// 换歌或与插值结果偏差过大（seek、暂停恢复）时才重设锚点，
    /// 其余情况保留原锚点，进度条靠本地时钟连续前进，不会被采样点拽回去
    private func updateAnchor(_ seconds: TimeInterval, trackChanged: Bool) {
        let elapsed = isPlaying ? Date().timeIntervalSince(progress.date) : 0
        let projected = progress.seconds + elapsed

        if trackChanged || !anchorValid || abs(projected - seconds) > 0.8 {
            progress = PlaybackAnchor(seconds: seconds, date: Date())
            anchorValid = true
        }
    }

    // MARK: - 客户端端口

    /// 岛先起来、播放器后开时，只有带调试端口的客户端读得到东西（实测：从 Dock 直接
    /// 打开网易云，argv 里没有 --remote-debugging-port，9222 不监听）。
    /// 只在客户端没跑时带端口拉起一次；已经在跑的实例一概不碰，不打断正在播的歌
    private func launchClients() {
        guard settings.autoLaunchPlayers else { return }
        for source in cdpSources where source.profile.preparesPortOnLaunch {
            guard !source.isRunning else { continue }
            PlayerLauncher.launch(port: source.profile.debugPort,
                                  bundleID: source.profile.bundleID,
                                  activates: false)
        }
    }

    /// 主页唯一会出现的失败提示：在跑 + 端口确实没开 + 这家没有曲目，三条同时成立才给。
    /// 一旦读到曲目（端口必然通着）立刻收起，不占用户的主页
    private func updatePortNotice(ready: String?) {
        guard !portFixBusy else { return }
        // 没同意「允许岛管理播放器」就不要提重启：那会打断正在播的歌
        guard settings.autoLaunchPlayers else {
            if portNotice != nil { portNotice = nil }
            return
        }
        let blocked = cdpSources.first {
            $0.profile.preparesPortOnLaunch && $0.isRunning
                && $0.portState == .closed && $0.profile.bundleID != ready
        }
        guard let source = blocked else {
            if portNotice != nil {
                portNotice = nil
                IslandDebug.log("pick", "端口提示收起")
            }
            return
        }
        let notice = MusicPortNotice(text: "\(MusicGate.name(of: source.profile.bundleID))没开调试端口 · 点此重启",
                                     busy: false)
        if portNotice != notice {
            portNotice = notice
            IslandDebug.log("pick", "端口提示：\(notice.text)")
        }
    }

    /// 主页提示的动作：带端口重启客户端。用户点了才做，平时绝不自动杀进程
    func fixMusicPort() {
        guard settings.autoLaunchPlayers else { return }
        guard !portFixBusy else { return }
        guard let source = cdpSources.first(where: {
            $0.profile.preparesPortOnLaunch && $0.isRunning && $0.portState == .closed
        }) else { return }
        portFixBusy = true
        let name = MusicGate.name(of: source.profile.bundleID)
        portNotice = MusicPortNotice(text: "正在重启\(name)…", busy: true)
        PlayerLauncher.restart(port: source.profile.debugPort,
                               bundleID: source.profile.bundleID) { [weak self] launched in
            guard let self = self else { return }
            guard launched else {
                self.portFixBusy = false
                self.portNotice = MusicPortNotice(text: "重启\(name)失败 · 点此重试", busy: false)
                return
            }
            // 新实例刚起来，端口要一两秒才就绪：等一会儿强制探一次再收尾，
            // 免得提示在「正在重启」和「没开端口」之间来回抖
            source.resetBackoff()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                source.probePort(force: true) { open in
                    self.portFixBusy = false
                    self.portNotice = open
                        ? nil
                        : MusicPortNotice(text: "重启\(name)失败 · 点此重试", busy: false)
                    self.poll()
                }
            }
        }
    }

    // MARK: - 控制

    func togglePlayPause() { send(.toggle) }
    func next() { send(.next) }
    func previous() { send(.previous) }

    /// 进度跳转只对能真正执行 seek 的通道开放：网易云 CDP 与 osascript 代理；
    /// 直连通道没有可用的 seek 符号，保持禁用
    func seek(to seconds: TimeInterval) {
        guard canSeek, duration > 0 else { return }
        let target = min(max(0, seconds), duration)
        switch activeSource {
        case .cdp(let id): cdpSource(id)?.send(.seek(target))
        // 代理通道按当前音源的 bundle id 发，脚本据此决定控制哪一家
        case .bridge: bridge.send(.seek(target), app: bundleID ?? "")
        case .system: return
        }
        // 松手就落到目标位置，不等下一次采样
        progress = PlaybackAnchor(seconds: target, date: Date())
        anchorValid = true
        refreshSoon()
    }

    private func cdpSource(_ bundleID: String) -> CDPPlayerSource? {
        cdpSources.first { $0.profile.bundleID == bundleID }
    }

    private func send(_ command: PlaybackCommand) {
        switch activeSource {
        case .cdp(let id): cdpSource(id)?.send(command)
        case .system: system.send(command)
        case .bridge: bridge.send(command, app: bundleID ?? "")
        }
        refreshSoon()
    }

    /// 命令下发后系统异步生效，稍等再读一次，避免界面滞后一拍
    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.poll()
        }
    }
}

/// 应用图标按 bundle id 缓存：换源只查一次磁盘，之后命中字典零开销
/// 只在主线程读写（都由 MediaStore.apply 调用）
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage? {
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}