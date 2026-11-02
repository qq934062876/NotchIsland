import Cocoa

// ---------------------------------------------------------------------------
// 音乐闸门：谁算「音乐播放软件」，以及同时有多家时显示哪一家
//
// 2026-11-03 用户当面定的口径（覆盖此前「任何 app 出声即显示音乐页」）：
//   - 只认白名单播放器；浏览器网页歌、视频、会议软件出声都不算音乐
//   - 暂停也算「有音乐」（播放器里还停着这首），只有读不到任何曲目才整块消失
//   - 多家同时在跑时显示「最后打开的那一家」，正在播放者优先
//
// 这里只做纯判定，不碰通道、不发命令、不读 DOM：
//   isPlayer 给 MediaStore 过滤 CoreAudio 采样，
//   select 给 MediaStore 选快照；加一家播放器只需往 players 表加一行。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

/// 白名单里的一个播放器
struct MusicPlayer: Equatable {
    /// 走哪个通道取数：带脚本字典的走 osascript 代理，Electron/CEF 的走 CDP 调试端口
    enum Channel: Equatable {
        case scriptable
        case cdp
    }

    let bundleID: String
    let name: String
    let channel: Channel
}

enum MusicGate {
    /// 白名单。新增一家：加一行，再在对应通道文件里补选择器（CDP）或补脚本（代理）
    static let players: [MusicPlayer] = [
        MusicPlayer(bundleID: "com.netease.163music", name: "网易云音乐", channel: .cdp),
        MusicPlayer(bundleID: "com.soda.music", name: "汽水音乐", channel: .cdp),
        MusicPlayer(bundleID: "com.apple.Music", name: "音乐", channel: .scriptable),
        MusicPlayer(bundleID: "com.spotify.client", name: "Spotify", channel: .scriptable),
    ]

    /// 精确匹配，不做前缀放宽：白名单里的 id 都是主进程 bundle id，
    /// 放宽会把浏览器 helper、XPC 一类进程算进来，那正好是用户要排除的
    static func isPlayer(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        return players.contains { $0.bundleID == bundleID }
    }

    /// 正在运行的播放器（按白名单顺序），带启动时间用于「最后打开」比较
    static func runningPlayers() -> [(player: MusicPlayer, launchDate: Date)] {
        players.compactMap { player in
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID)
            guard let app = apps.first else { return nil }
            // 取不到启动时间（极少数情况）就当作很久以前，排在其它家后面
            return (player, app.launchDate ?? .distantPast)
        }
    }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// 白名单里的显示名：提示文案要用同一套叫法，查不到就退回 bundle id
    static func name(of bundleID: String) -> String {
        players.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    /// 从候选快照里选唯一要展示的一家：
    ///   1. 先只留有曲目的（暂停也算，用户要求暂停保留音乐页）
    ///   2. 正在播放的优先——不能因为另一家开得晚就把正在响的那家顶掉
    ///   3. 同级取启动时间最新的一家（「最后打开的那家」）
    /// - Parameter launchDate: bundleID -> 启动时间，取不到的实现返回 distantPast
    static func select(_ candidates: [NowPlayingSnapshot],
                       launchDate: (String) -> Date) -> NowPlayingSnapshot {
        let usable = candidates.filter { $0.hasContent }
        guard !usable.isEmpty else { return .empty }

        let playing = usable.filter { $0.isPlaying }
        let pool = playing.isEmpty ? usable : playing
        return pool.max { lhs, rhs in
            launchDate(lhs.bundleID ?? "") < launchDate(rhs.bundleID ?? "")
        } ?? .empty
    }
}