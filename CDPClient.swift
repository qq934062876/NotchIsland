import Cocoa

// ---------------------------------------------------------------------------
// CDP 通信层：只负责「连上某端口上的页面，跑一段 JS，拿回字符串」
//
// 从 NeteaseSource 抽出来的通用部分：/json/list 找 target、WebSocket 连接、
// Runtime.evaluate 收发、请求 id 匹配、单请求 1.2s 超时、teardown 清未决回调。
// 不带任何播放器选择器，也不做退避与封面缓存——那些在 CDPPlayerSource。
//
// 约定：回包但 value 为空串是「正常空态」，返回 ""；超时 / 连接断开 / 端口没开
// 返回 nil，调用方据此计失败退避。两者必须分开，否则「先静音、后放歌」会被
// 退避窗口挡住（2026-11-03 踩过）。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

final class CDPClient {
    private let port: Int
    private let session: URLSession

    private var webSocket: URLSessionWebSocketTask?
    private var pageURL: String?
    /// 未决请求按 id 存回调，只在主线程读写
    private var pending: [Int: (String?) -> Void] = [:]
    private var nextRequestID = 1

    /// 连接中的并发合并：轮询与控制可能同时触发，只连一次
    private var connecting = false
    private var connectWaiters: [(Bool) -> Void] = []

    init(port: Int) {
        self.port = port
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    deinit {
        teardown()
    }

    /// 跑一段 JS，回包值原样返回（通常是字符串）；nil 表示这次没拿到回包
    func evaluate(_ js: String, done: @escaping (String?) -> Void) {
        ensureReady { [weak self] ready in
            guard let self = self, ready else { return done(nil) }
            self.send(js, done: done)
        }
    }

    /// 只探端口是否开着：GET /json/version，0.6s 收不到就当没开。
    /// 与 evaluate 分开是因为「拿不到 page target」不等于端口没开（页面可能还没加载完），
    /// 主页的「重启客户端」入口只认端口这一件事，猜错会把提示乱闪
    func probe(_ done: @escaping (Bool) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:\(port)/json/version") else {
            return done(false)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.6
        session.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { done(ok) }
        }.resume()
    }

    /// 断开并唤醒所有等待者：对象销毁、连续失败时调用
    func teardown() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        pageURL = nil
        connecting = false
        let waiters = connectWaiters
        connectWaiters.removeAll()
        for waiter in waiters { waiter(false) }

        let waiting = pending
        pending.removeAll()
        for callback in waiting.values { callback(nil) }
    }

    // MARK: - 连接

    private func ensureReady(_ done: @escaping (Bool) -> Void) {
        if webSocket != nil, pageURL != nil { return done(true) }
        connectWaiters.append(done)
        guard !connecting else { return }
        connecting = true

        resolveTarget { [weak self] url in
            guard let self = self else { return }
            guard let url = url else {
                self.finishConnecting(false)
                return
            }
            self.connect(url) { ok in
                self.finishConnecting(ok)
            }
        }
    }

    private func finishConnecting(_ ok: Bool) {
        connecting = false
        let waiters = connectWaiters
        connectWaiters.removeAll()
        for waiter in waiters { waiter(ok) }
    }

    /// 从 /json/list 找页面 target 的 WebSocket 地址；0.6s 收不到就当端口没开
    private func resolveTarget(_ done: @escaping (String?) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:\(port)/json/list") else { return done(nil) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.6

        session.dataTask(with: request) { data, _, _ in
            var found: String?
            if let data = data,
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for item in list {
                    guard let type = item["type"] as? String, type == "page",
                          let ws = item["webSocketDebuggerUrl"] as? String else { continue }
                    found = ws
                    break
                }
            }
            DispatchQueue.main.async { done(found) }
        }.resume()
    }

    private func connect(_ url: String, done: @escaping (Bool) -> Void) {
        guard let target = URL(string: url) else { return done(false) }
        teardown()

        let socket = session.webSocketTask(with: target)
        webSocket = socket
        pageURL = url
        socket.resume()
        receiveNext()
        // WebSocket 握手是异步的，立刻 send 有可能打在握手完成之前
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { done(true) }
    }

    private func receiveNext() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.dispatch(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { self.dispatch(text) }
                @unknown default:
                    break
                }
                self.receiveNext()
            case .failure:
                DispatchQueue.main.async { self.teardown() }
            }
        }
    }

    /// 回包按 id 匹配，超时那条已经清掉就丢弃
    private func dispatch(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? Int else { return }

        var value: String?
        if let result = object["result"] as? [String: Any],
           let inner = result["result"] as? [String: Any] {
            value = (inner["value"] as? String) ?? ""
        }
        DispatchQueue.main.async { [weak self] in
            self?.pending.removeValue(forKey: id)?(value)
        }
    }

    private func send(_ js: String, done: @escaping (String?) -> Void) {
        guard let socket = webSocket else { return done(nil) }

        let id = nextRequestID
        nextRequestID += 1
        let payload: [String: Any] = [
            "id": id,
            "method": "Runtime.evaluate",
            "params": ["expression": js, "returnByValue": true]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return done(nil)
        }

        pending[id] = done
        socket.send(.string(text)) { [weak self] error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pending.removeValue(forKey: id)?(nil)
                self.teardown()
            }
        }
        // 回包超时兜底，防止一条请求把后续采样全堵住
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.pending.removeValue(forKey: id)?(nil)
        }
    }
}