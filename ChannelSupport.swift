import Cocoa

// ---------------------------------------------------------------------------
// 播放通道共用的两件小工具：失败退避与封面缓存
//
// osascript 代理（MediaBridge）与 CDP（CDPPlayerSource）是两条独立通道，但退避与
// 封面规则必须一致，否则同一首歌换条通道就换一套刷新节奏：
//   - 退避：5s 起步翻倍、封顶 60s、正常回包清零、不永久关停
//   - 封面：URL 变了才下载、同一 URL 不重复请求、下载完回主线程写图并触发刷新
// 规则只在这里写一份，两条通道各自只留通道特有的状态。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

/// 连续失败退避：5s 起步翻倍，封顶 60s
struct ChannelBackoff {
    private(set) var count = 0
    private var nextAttempt = Date.distantPast

    /// 距离下次可尝试还剩几秒；≤ 0 表示现在就能试
    var wait: TimeInterval { nextAttempt.timeIntervalSinceNow }
    var canAttempt: Bool { wait <= 0 }

    /// 正常回包就清零——包括「页面没有曲目」这类正常空态，
    /// 否则正常空态会把退避越推越远，起播时要等窗口走完才恢复
    mutating func reset() {
        count = 0
        nextAttempt = .distantPast
    }

    /// 封顶 60s 但不永久关停：一次冷启动超时或一次授权框没点，
    /// 永久停用会让本次运行再也读不到内容
    mutating func noteFailure(category: String, subject: String) {
        count += 1
        let delay = min(60, 5 * pow(2, Double(count - 1)))
        nextAttempt = Date().addingTimeInterval(delay)
        IslandDebug.log(category, "\(subject) 失败 \(count) 次，\(Int(delay))s 后重试")
    }
}

/// 主页那行「客户端没开调试端口」的提示：文案由 `MediaStore` 决定，视图只负责画与转发点击。
/// 只有「客户端在跑、端口确实没开」才出现，读到曲目立刻收起
struct MusicPortNotice: Equatable {
    var text: String
    /// 重启进行中：文案换成「正在重启…」，按钮不再响应重复点击
    var busy: Bool
}

/// 封面缓存：按 URL 缓存解码后的图，换 URL 才重新下载
/// 只在主线程读写（都由各通道的采样回调调用），下载回调也回主线程
final class CoverCache {
    /// 图换新后通知上层重新采样，别让占位图停到下一个轮询周期
    var onChange: (() -> Void)?
    /// 当前缓存的图；通道自己给图（Music 的 base64）或按标题复用上一首时读它
    private(set) var image: NSImage?
    /// 当前图对应的 URL：变了说明换歌，通道据此清掉「同一首」的标题关联
    private(set) var url: String?

    private var downloading: String?
    private let session: URLSession

    init() {
        // 封面走各家 CDN，被运营商拦截时会一路等到超时；8s 够用又不挂太久
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        session = URLSession(configuration: config)
    }

    deinit {
        // 退出时取消在飞的请求，别让回调打到已销毁的通道对象
        session.invalidateAndCancel()
    }

    /// 取这张 URL 的封面：与缓存不同就清图并开始下载，本轮先返回已有的图
    func image(for url: String) -> NSImage? {
        if url != self.url {
            self.url = url
            image = nil
            download(url)
        }
        return image
    }

    /// 通道直接给了整张图（脚本回传 base64）：存起来并让 URL 失效，
    /// 下次给 URL 时会重新走下载
    func store(_ image: NSImage) {
        self.image = image
        url = nil
    }

    /// 通道本轮没有封面：清空，避免把上一首的图挂到新歌上
    func clear() {
        url = nil
        image = nil
    }

    private func download(_ url: String) {
        guard downloading != url, let target = URL(string: url) else { return }
        downloading = url
        session.dataTask(with: target) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.downloading = nil
                // 下载期间可能已经换歌，URL 对不上就丢弃这张图
                guard self.url == url, let data = data, let image = NSImage(data: data) else { return }
                self.image = image
                self.onChange?()
            }
        }.resume()
    }
}