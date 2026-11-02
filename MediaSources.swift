import Cocoa

// ---------------------------------------------------------------------------
// 播放数据源：系统通道（MediaRemote 私有框架）与共享快照类型
//
// Apple Music / Spotify / Safari / Chrome 等注册过 Now Playing 的应用都能读到，
// 控制命令也走它。取不到符号或系统没在播时静默返回空快照，不弹窗、不抛错。
//
// Chromium/CEF 应用（网易云客户端）不向系统注册 Now Playing，改由 NeteaseSource
// 走客户端自带的 CEF 调试端口取数；15.4+ 直连被拒时由 MediaBridge 用 osascript
// 代读各播放器脚本字典。本文件只留系统通道与三条通道共用的快照结构。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

/// 播放控制命令
enum PlaybackCommand {
    case toggle
    case next
    case previous
    /// 跳转到指定秒数，只有 canSeek 的通道支持
    case seek(TimeInterval)
}

/// 快照来自哪条通道：系统直连优先，其次 osascript 代理，最后 Chromium/CEF 客户端的 CDP
enum PlaybackSourceKind: Equatable {
    case system
    /// macOS 15.4+ 的直连被系统拒绝，改由 osascript 代理读各播放器的脚本字典
    case bridge
    /// 带 bundle id 是为了多家 CDP 客户端（网易云、汽水音乐）各自路由控制命令
    case cdp(String)
}

/// 一次采样得到的状态
struct NowPlayingSnapshot {
    var title = ""
    var artist = ""
    /// 系统通道直接给解码好的图
    var artwork: NSImage?
    var isPlaying = false
    var bundleID: String?
    /// 封面远端地址，只有网易云通道用：系统通道直接给解码好的图
    var coverURL: String?
    /// 已播放秒数，只有网易云通道给真值；系统通道留 0
    var progress: TimeInterval = 0
    /// 总时长秒数，0 表示未知
    var duration: TimeInterval = 0
    /// 进度条是否可拖：系统通道不接管 seek，避免和播放器抢状态
    var canSeek = false
    var source: PlaybackSourceKind = .system

    var hasContent: Bool { !title.isEmpty }
    static let empty = NowPlayingSnapshot()
}

// MARK: - 系统通道

final class SystemNowPlayingSource {
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias SendCmdFn = @convention(c) (Int32, CFDictionary?) -> UInt8
    private typealias GetPidFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void

    /// 系统播报「正在播放」变化时回调，用来替代纯轮询的延迟
    var onChange: (() -> Void)?

    private var getInfoFn: GetInfoFn?
    private var sendCmdFn: SendCmdFn?
    private var getPidFn: GetPidFn?
    private var observer: NSObjectProtocol?

    private var lastArtworkData: Data?
    private var lastArtwork: NSImage?
    private var cachedPID: Int32 = -1
    private var cachedBundleID: String?

    private enum Command: Int32 {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else {
            NSLog("NotchIsland: MediaRemote 打开失败 \(String(cString: dlerror()))")
            return
        }

        if let p = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getInfoFn = unsafeBitCast(p, to: GetInfoFn.self)
        }
        if let p = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCmdFn = unsafeBitCast(p, to: SendCmdFn.self)
        }
        if let p = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") {
            getPidFn = unsafeBitCast(p, to: GetPidFn.self)
        }
        if let p = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            unsafeBitCast(p, to: RegisterFn.self)(DispatchQueue.main)
        }

        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onChange?()
        }
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func fetch(_ done: @escaping (NowPlayingSnapshot) -> Void) {
        guard let getInfoFn = getInfoFn else { return done(.empty) }
        getInfoFn(DispatchQueue.main) { [weak self] info in
            guard let self = self else { return }
            let d = (info as? [String: Any]) ?? [:]
            guard !d.isEmpty else { return done(.empty) }

            var snap = NowPlayingSnapshot()
            snap.title = d["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            snap.artist = d["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            snap.isPlaying = (d["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0) > 0

            // 封面只在数据变化时解码，轮询每次都解一遍太浪费
            if let art = d["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                if art != self.lastArtworkData {
                    self.lastArtworkData = art
                    self.lastArtwork = NSImage(data: art)
                }
                snap.artwork = self.lastArtwork
            } else {
                self.lastArtworkData = nil
                self.lastArtwork = nil
            }

            self.resolveBundleID { bundleID in
                snap.bundleID = bundleID
                done(snap)
            }
        }
    }

    func send(_ command: PlaybackCommand) {
        let raw: Int32
        switch command {
        case .toggle: raw = Command.togglePlayPause.rawValue
        case .next: raw = Command.nextTrack.rawValue
        case .previous: raw = Command.previousTrack.rawValue
        // 系统通道没有公开的 seek 符号，进度跳转只给网易云通道用
        case .seek: return
        }
        _ = sendCmdFn?(raw, nil)
    }

    /// 取音源进程的 bundle id，用于查尺寸档位；pid 不变就复用上次结果
    private func resolveBundleID(_ done: @escaping (String?) -> Void) {
        guard let getPidFn = getPidFn else { return done(nil) }
        getPidFn(DispatchQueue.main) { [weak self] pid in
            guard let self = self else { return done(nil) }
            if pid == self.cachedPID, let cached = self.cachedBundleID {
                return done(cached)
            }
            self.cachedPID = pid
            let bundleID = pid > 0
                ? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                : nil
            self.cachedBundleID = bundleID
            done(bundleID)
        }
    }
}
