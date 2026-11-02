import Cocoa

// ---------------------------------------------------------------------------
// 配置驱动的 CDP 播放器源
//
// 网易云、汽水音乐这类 Chromium/Electron 客户端不向系统注册 Now Playing，
// 但都能用客户端自带的 --remote-debugging-port 走 CDP 读页面。两家只差选择器，
// 所以把「通信」交给 CDPClient，把「选择器」收进 CDPPlayerProfile，
// 这个类只做三件事：按需采样、解析成快照、失败退避与封面缓存。
//
// 退避与封面规则与 osascript 代理共用 ChannelSupport（同一套参数，别在这里另写一份）。
// 约定：探针脚本返回一行 JSON，字段 title / artist / cover / pos / dur / playing；
// 页面没有曲目时返回空串（正常空态，不计失败）。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

/// 一家 CDP 播放器的选择器与端口；全部选择器只写在这里的 *JS 常量里，改版只改它们
struct CDPPlayerProfile {
    let bundleID: String
    /// 客户端自带的调试端口；网易云实测用 9222（CEF 默认端口，见 NeteaseSource）
    let debugPort: Int
    /// 一次取齐歌名、歌手、封面、进度、时长、播放状态
    let probeJS: String
    let toggleJS: String
    let nextJS: String
    let previousJS: String
    /// 按秒数生成 seek 脚本
    let seekJS: (TimeInterval) -> String
    /// 岛启动时是否由岛带 `--remote-debugging-port` 拉起。
    /// 只有真能带参启动的才开：汽水音乐是 MAS 沙盒版，argv 会被它自己的重启逻辑丢掉
    var preparesPortOnLaunch: Bool = false
}

class CDPPlayerSource {
    /// 封面数据变化时通知上层重新采样，避免等下一个轮询周期
    var onChange: (() -> Void)?
    /// 端口从开到关 / 关到开时通知上层：主页那行「重启客户端」入口只跟这个状态走
    var onPortStateChange: (() -> Void)?

    /// 端口三态：unknown 是「还没探过」，此时不给提示，避免主页闪一下再消失
    enum PortState { case unknown, open, closed }
    private(set) var portState: PortState = .unknown
    /// 上次探测时刻：这是给提示用的状态，3s 一次足够，不必跟 1.5s 采样同频
    private var lastProbe = Date.distantPast

    let profile: CDPPlayerProfile
    private let client: CDPClient

    /// 端口没开也走这条退避，省掉无谓的 HTTP 探测
    private var backoff = ChannelBackoff()
    private let cover = CoverCache()

    init(profile: CDPPlayerProfile) {
        self.profile = profile
        self.client = CDPClient(port: profile.debugPort)
        // 封面下载完成后立刻刷一次，不让占位图停到下一个周期
        cover.onChange = { [weak self] in self?.onChange?() }
    }

    /// 客户端当前是否在跑：没跑就完全不碰端口（既省开销，也不会误拉起用户没开的软件）
    var isRunning: Bool { MusicGate.isRunning(profile.bundleID) }

    // MARK: - 采样

    func fetch(_ done: @escaping (NowPlayingSnapshot) -> Void) {
        guard isRunning else {
            // 客户端退出后重新打开时不该等退避走完
            backoff.reset()
            return done(.empty)
        }
        let wait = backoff.wait
        guard wait <= 0 else {
            if wait >= 1 {
                IslandDebug.log("cdp", "\(profile.bundleID) 退避中，剩 \(Int(wait.rounded(.up)))s")
            }
            return done(.empty)
        }

        client.evaluate(profile.probeJS) { [weak self] body in
            guard let self = self else { return done(.empty) }
            // 只有「没回包」才算故障（超时/连接断）。有回包但页面没有曲目属正常空态
            guard let body = body else {
                self.backoff.noteFailure(category: "cdp", subject: self.profile.bundleID)
                return done(.empty)
            }
            self.backoff.reset()
            self.notePortOpen()
            guard var snapshot = self.parse(body) else { return done(.empty) }
            self.attachArtwork(snapshot.coverURL ?? "", into: &snapshot)
            done(snapshot)
        }
    }

    // MARK: - 端口状态

    /// 周期探一次端口；客户端没在跑就直接清成 unknown（下次重开要重新判断）。
    /// 用途只有一个：决定主页要不要给「重启客户端」入口
    /// - Parameters:
    ///   - force: 重启客户端后要立刻拿到结论，绕过节流
    ///   - done: 探测结果；被节流挡下时直接回缓存值
    func probePort(force: Bool = false, done: ((Bool) -> Void)? = nil) {
        guard isRunning else {
            lastProbe = .distantPast
            if portState != .unknown {
                portState = .unknown
                onPortStateChange?()
            }
            done?(false)
            return
        }
        guard force || Date().timeIntervalSince(lastProbe) >= 3 else {
            done?(portState == .open)
            return
        }
        lastProbe = Date()
        client.probe { [weak self] open in
            guard let self = self else {
                done?(open)
                return
            }
            let next: PortState = open ? .open : .closed
            if next != self.portState {
                self.portState = next
                IslandDebug.log("cdp", "\(self.profile.bundleID) 调试端口\(open ? "已开" : "未开")")
                self.onPortStateChange?()
            }
            done?(open)
        }
    }

    /// 重启客户端后端口立刻可用：清掉退避，否则要等最多 60s 才恢复采样
    func resetBackoff() { backoff.reset() }

    /// 采样拿到回包＝端口一定开着，顺手把状态改对：省掉一次探测，也纠正误判
    private func notePortOpen() {
        guard portState != .open else { return }
        portState = .open
        onPortStateChange?()
    }

    // MARK: - 控制

    func send(_ command: PlaybackCommand) {
        let js: String
        switch command {
        case .toggle: js = profile.toggleJS
        case .next: js = profile.nextJS
        case .previous: js = profile.previousJS
        case .seek(let seconds): js = profile.seekJS(seconds)
        }
        // 没写脚本 = 这家没有可靠入口（例如汽水音乐的上下首），宁可不发也不乱点
        guard isRunning, !js.isEmpty else { return }
        client.evaluate(js) { _ in }
    }

    // MARK: - 解析与封面

    private func parse(_ body: String) -> NowPlayingSnapshot? {
        guard let data = body.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = dict["title"] as? String, !title.isEmpty else { return nil }

        var snapshot = NowPlayingSnapshot()
        snapshot.title = title
        snapshot.artist = dict["artist"] as? String ?? ""
        snapshot.coverURL = dict["cover"] as? String
        snapshot.isPlaying = dict["playing"] as? Bool ?? false
        snapshot.progress = dict["pos"] as? Double ?? 0
        snapshot.duration = dict["dur"] as? Double ?? 0
        snapshot.canSeek = snapshot.duration > 0
        snapshot.bundleID = profile.bundleID
        snapshot.source = .cdp(profile.bundleID)
        return snapshot
    }

    /// 页面没给封面就清空缓存：宁可这轮显示占位，也不把上一首的图挂到新歌上
    private func attachArtwork(_ url: String, into snapshot: inout NowPlayingSnapshot) {
        guard !url.isEmpty else {
            cover.clear()
            return
        }
        snapshot.artwork = cover.image(for: url)
    }
}