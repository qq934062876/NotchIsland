import Cocoa

// ---------------------------------------------------------------------------
// 播放信息代理通道（osascript + 各播放器的脚本字典）
//
// 为什么需要代理进程：macOS 15.4 起 MediaRemote 只放行 bundle id 为 com.apple.*
// 的进程，本 app 直连查询恒空、SendCommand 同样被拒（见 MediaSources.swift）。
// /usr/bin/osascript 属 com.apple.*，所以让它代读、代发命令，且零第三方依赖。
//
// 为什么代理里不读 MediaRemote（2026-11-03 本机 macOS 26 实测，逐条都验过）：
//   1. NSBundle.bundleWithPath 必须传 .framework 目录，传内部二进制返回 undefined，
//      脚本第一行就会判成「加载失败」；
//   2. ObjC.bindFunction 绑出来的函数挂在 $ 上（$.MRMediaRemoteGetNowPlayingInfo），
//      写成全局名直接 ReferenceError；
//   3. 第一个参数传 nil（没有 dispatch_get_main_queue 可用）会 SIGSEGV；
//   4. 换成 dispatch_get_global_queue 后回调能到，但 JXA 把 JS 函数桥成的 block
//      是零参数的（arguments.length == 0），Now Playing 字典根本传不进 JS；
//      用 block 类型编码 @?<v@?@> 则直接 SIGTRAP。
// 结论：osascript 里拿不到 Now Playing 字典，只能退回各播放器自带的脚本字典。
//
// 覆盖范围：Apple Music、Spotify（能读曲目/播放态/位置/封面，也能控制）。
// 浏览器、QQ 音乐等没有可用脚本字典的软件不在这里硬猜：表外软件一律返回空快照，
// 由 MediaStore 判定「没有曲目」后整块不显示（2026-11-03 已删除通用音频态）。
//
// 首轮 osascript 可能弹「想控制 Music」的授权框，被拒绝会静默失败（ok=false），
// 界面按「没有曲目」处理，不弹窗、不卡轮询。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

final class MediaBridge {
    /// 封面下载完成后触发一次刷新，别让占位图停到下一个采样周期
    var onChange: (() -> Void)?
    /// 脚本里认识的播放器；不在表里的 app 一律返回空快照（MediaStore 据此判定没有曲目）
    static let scriptableApps: Set<String> = ["com.apple.Music", "com.spotify.client"]

    /// 同一时刻只允许一个子进程：poll 可能被事件驱动连续触发
    private var inFlight = false
    private var backoff = ChannelBackoff()

    /// Apple Music 的封面由脚本回传 base64，只在换歌时传；其余轮次用这份缓存
    private var artworkTitle = ""
    private let cover = CoverCache()

    /// 脚本执行（含首次授权等待）留够余量；超时就 terminate，再 0.3s SIGKILL
    private static let timeout: TimeInterval = 3.5
    private static let killGrace: TimeInterval = 0.3

    /// 脚本落成临时文件而不是每次 -e 传参：省掉重复解析，也避开引号与长度问题
    private static let scriptURL: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notch-island-nowplaying.js")
        try? script.write(to: url, atomically: true, encoding: .utf8)
        return url
    }()

    init() {
        // 封面下载完成后立刻刷一次，不让占位图停到下一个周期
        cover.onChange = { [weak self] in self?.onChange?() }
    }

    private static func isScriptable(_ bundleID: String) -> Bool {
        scriptableApps.contains(bundleID)
    }

    // MARK: - 读取

    /// - Parameters:
    ///   - app: 唯一在出声的 app 的 bundle id；不是可脚本化播放器时直接返回空
    ///   - lastTitle: 上一轮标题，脚本据此决定要不要回传封面
    func fetch(app: String, lastTitle: String, done: @escaping (NowPlayingSnapshot) -> Void) {
        guard Self.isScriptable(app), backoff.canAttempt, !inFlight else { return done(.empty) }
        inFlight = true

        run(["get", app, lastTitle]) { [weak self] output in
            guard let self = self else { return }
            self.inFlight = false

            guard let output = output, let parsed = Self.parse(output) else {
                self.backoff.noteFailure(category: "bridge", subject: app)
                return done(.empty)
            }
            self.backoff.reset()
            done(self.attachArtwork(to: parsed))
        }
    }

    // MARK: - 控制

    /// 控制也走代理：直连 SendCommand 在 15.4+ 同样被拒，
    /// 而且按钮点的是哪个 app 就发给哪个 app，不靠系统猜
    func send(_ command: PlaybackCommand, app: String) {
        guard Self.isScriptable(app) else { return }
        let mode: String
        var argument = ""
        switch command {
        case .toggle: mode = "toggle"
        case .next: mode = "next"
        case .previous: mode = "previous"
        case .seek(let seconds):
            mode = "seek"
            argument = String(format: "%.1f", max(0, seconds))
        }
        // 命令不撞在飞请求：同时起两个 osascript 只会互相拖慢
        guard !inFlight else { return }
        run([mode, app, argument]) { _ in }
    }

    // MARK: - 子进程

    /// 起 osascript 取一行 JSON；超时先 terminate 再 SIGKILL，保证一定有回调
    private func run(_ arguments: [String], done: @escaping (String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", Self.scriptURL.path] + arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        var finished = false
        let finish: (String?) -> Void = { result in
            guard !finished else { return }
            finished = true
            done(result)
        }

        do {
            try process.run()
        } catch {
            IslandDebug.log("bridge", "启动失败 \(error.localizedDescription)")
            finish(nil)
            return
        }

        // 必须一启动就排空管道：封面 base64 有几十到上百 KB，超过管道缓冲区后
        // 子进程会写阻塞、永不退出，最后只能被超时误杀成「失败」
        let reader = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            let data = reader.readDataToEndOfFile()
            // 必须等进程真的退出再读 terminationStatus：它在 task 还活着时会抛
            // NSInvalidArgumentException（首次访问 Music 会卡在自动化授权弹窗上，
            // 正好走到「管道已关但进程未退」这条路），整个 app 会被带走
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let status = process.terminationStatus
            DispatchQueue.main.async {
                if status == 0, !trimmed.isEmpty {
                    finish(trimmed)
                } else {
                    finish(nil)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) {
            guard process.isRunning else { return }
            IslandDebug.log("bridge", "超时 \(Int(Self.timeout))s，终止子进程")
            process.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.killGrace) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }

    // MARK: - 解析

    /// 只有「脚本跑完但 JSON 不合法 / ok=false」才算失败；
    /// 空快照是正常状态（没在播、或这家 app 没有脚本字典），不能触发退避
    private static func parse(_ text: String) -> NowPlayingSnapshot? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any],
              (dict["ok"] as? Bool) == true else { return nil }

        if (dict["empty"] as? Bool) == true { return .empty }

        var snapshot = NowPlayingSnapshot()
        snapshot.title = dict["title"] as? String ?? ""
        guard !snapshot.title.isEmpty else { return .empty }
        snapshot.artist = dict["artist"] as? String ?? ""
        snapshot.duration = (dict["duration"] as? NSNumber)?.doubleValue ?? 0
        snapshot.progress = (dict["elapsed"] as? NSNumber)?.doubleValue ?? 0
        snapshot.isPlaying = ((dict["rate"] as? NSNumber)?.doubleValue ?? 0) > 0
        // 脚本通道可以设 playerPosition，能真跳
        snapshot.canSeek = snapshot.duration > 0
        snapshot.coverURL = dict["coverURL"] as? String
        if let appID = dict["appID"] as? String, !appID.isEmpty {
            snapshot.bundleID = appID
        }
        snapshot.source = .bridge

        if let base64 = dict["artwork"] as? String,
           let data = Data(base64Encoded: base64),
           let image = NSImage(data: data) {
            snapshot.artwork = image
        }
        return snapshot
    }

    /// 封面三路：脚本直接给图（Music）→ 用图并记住这首；
    /// 只给 URL（Spotify）→ 换 URL 才下载；都没有 → 同一首沿用缓存
    private func attachArtwork(to snapshot: NowPlayingSnapshot) -> NowPlayingSnapshot {
        var result = snapshot
        if let image = snapshot.artwork {
            // 只有真的拿到图才更新缓存，否则换歌但本轮无图时会把缓存清空，
            // 之后脚本因 title 相同不再回传，这首曲子就永远没有封面
            artworkTitle = snapshot.title
            cover.store(image)
            result.artwork = image
        } else if let url = snapshot.coverURL, !url.isEmpty {
            // URL 变了说明换歌，标题匹配不再成立，别把上一首的图挂到新歌上
            if url != cover.url { artworkTitle = "" }
            result.artwork = cover.image(for: url)
        } else if snapshot.title == artworkTitle {
            result.artwork = cover.image
        }
        return result
    }

    // MARK: - JXA 脚本

    /// 改脚本只改这一段。argv：0 命令，1 bundle id，2 上一首标题（get）或秒数（seek）。
    /// 输出单行 JSON；任何异常都以 ok=false 收场，Swift 侧据此退避。
    private static let script = #"""
    function read(app, bundleID, lastTitle) {
      var out = { ok: true, empty: true, title: '', artist: '', duration: 0,
                  elapsed: 0, rate: 0, appID: bundleID, artwork: null, coverURL: '' };
      var state = '';
      try { state = String(app.playerState()); } catch (e) {}
      // 没播过东西时 currentTrack 会抛「不能获取对象」，这属于空态不是故障
      var track = null;
      try { track = app.currentTrack; } catch (e) { return out; }
      if (!track) return out;
      var title = '';
      try { title = String(track.name() || ''); } catch (e) {}
      if (!title) return out;
      out.empty = false;
      out.title = title;
      try { out.artist = String(track.artist() || ''); } catch (e) {}
      var duration = 0;
      try { duration = Number(track.duration()) || 0; } catch (e) {}
      // Spotify 的 duration 是毫秒，Apple Music 是秒
      if (bundleID === 'com.spotify.client') duration = duration / 1000;
      out.duration = duration;
      try { out.elapsed = Number(app.playerPosition()) || 0; } catch (e) {}
      out.rate = state === 'playing' ? 1 : 0;
      // 封面只在换歌时回传，避免每轮把几百 KB base64 搬过管道
      if (title !== lastTitle) {
        try {
          // artworks() 在 JXA 里既可能桥成 JS 数组也可能仍是 NSArray，两种都试
          var arts = track.artworks();
          var first = null;
          try { first = arts[0]; } catch (e) {}
          if (!first) { try { first = arts.objectAtIndex(0); } catch (e) {} }
          if (first) {
            var data = first.rawData();
            if (data) out.artwork = String(data.base64EncodedStringWithOptions(0));
          }
        } catch (e) {}
      }
      // Spotify 没有 artwork 对象，只有远端地址，交给 Swift 侧下载缓存
      if (bundleID === 'com.spotify.client') {
        try { out.coverURL = String(track.artworkUrl() || ''); } catch (e) {}
      }
      return out;
    }

    function run(argv) {
      var mode = argv[0] || 'get';
      var bundleID = argv[1] || '';
      var argument = argv[2] || '';

      // 只认带脚本字典的播放器；其余 app 直接给空快照（Swift 侧当作没有曲目）
      var scripted = { 'com.apple.Music': 'Music', 'com.spotify.client': 'Spotify' };
      var appName = scripted[bundleID];
      if (!appName) return JSON.stringify({ ok: true, empty: true });

      var app;
      try { app = Application(appName); } catch (e) {
        return JSON.stringify({ ok: true, empty: true });
      }
      var running = false;
      try { running = app.running(); } catch (e) {
        return JSON.stringify({ ok: true, empty: true });
      }
      if (!running) return JSON.stringify({ ok: true, empty: true });

      try {
        if (mode === 'get') return JSON.stringify(read(app, bundleID, argument));
        if (mode === 'toggle') { app.playpause(); return JSON.stringify({ ok: true }); }
        if (mode === 'next') { app.nextTrack(); return JSON.stringify({ ok: true }); }
        if (mode === 'previous') { app.previousTrack(); return JSON.stringify({ ok: true }); }
        if (mode === 'seek') {
          app.playerPosition = Number(argument) || 0;
          return JSON.stringify({ ok: true });
        }
      } catch (e) {
        return JSON.stringify({ ok: false, error: mode + ': ' + e });
      }
      return JSON.stringify({ ok: false, error: 'mode ' + mode });
    }
    """#
}