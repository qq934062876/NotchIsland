import Cocoa

// ---------------------------------------------------------------------------
// 带调试端口启动 / 重启播放器客户端
//
// 网易云这类 CEF 客户端只有在带 --remote-debugging-port 启动时才有端口，从
// Dock / 访达打开的那次永远读不到（2026-11-03 实测：主进程 argv 里没有该参数、
// 9222 无监听）。用户 2026-11-03 改口径：岛负责拉起，不再「不支持就忽略」。
//   - 没在跑：岛启动时带参数拉起一次，不抢焦点（activates = false）
//   - 已在跑：绝不打断，交给主页那行可点提示，用户点了才重启（会先退出当前实例）
// 启动走 NSWorkspace 的 OpenConfiguration：arguments 只对「新起的进程」生效，
// 所以「已有一个无端口的实例在跑」时 open 只会激活旧实例、参数被丢掉 —— 这正是
// 必须先让旧进程真的退出、再拉起的原因。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

enum PlayerLauncher {
    /// 带 `--remote-debugging-port` 启动；调用方负责先确认它没在跑
    /// - Parameter activates: 自动拉起传 false（不抢焦点），用户点重启传 true（他就是要用它）
    static func launch(port: Int, bundleID: String, activates: Bool,
                       done: ((Bool) -> Void)? = nil) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            IslandDebug.log("cdp", "找不到 \(bundleID) 的安装位置，无法带端口启动")
            done?(false)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--remote-debugging-port=\(port)"]
        config.activates = activates
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            // 回调可能在非主线程，后续要写界面状态，统一回主队列
            DispatchQueue.main.async {
                if let error = error {
                    IslandDebug.log("cdp", "带端口启动 \(bundleID) 失败：\(error.localizedDescription)")
                } else {
                    IslandDebug.log("cdp", "带端口启动 \(bundleID)（端口 \(port)）")
                }
                done?(error == nil)
            }
        }
    }

    /// 已在跑但没有调试端口：先 terminate 等它自己退，3s 不退再 forceTerminate，
    /// 进程真的消失后才带端口拉起
    /// - Parameter done: true 表示新实例已启动（端口是否就绪由调用方再探）
    static func restart(port: Int, bundleID: String, done: @escaping (Bool) -> Void) {
        guard MusicGate.isRunning(bundleID) else {
            launch(port: port, bundleID: bundleID, activates: true, done: done)
            return
        }
        // terminate 走正常退出流程，客户端能存住登录态与播放列表，比直接 force 温和
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .forEach { $0.terminate() }
        waitForExit(bundleID: bundleID, attempts: 20) { stopped in
            if stopped {
                launch(port: port, bundleID: bundleID, activates: true, done: done)
                return
            }
            IslandDebug.log("cdp", "\(bundleID) 3s 未退出，强制终止")
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .forEach { $0.forceTerminate() }
            waitForExit(bundleID: bundleID, attempts: 10) { stopped in
                guard stopped else {
                    IslandDebug.log("cdp", "\(bundleID) 退不掉，放弃带端口重启")
                    return done(false)
                }
                launch(port: port, bundleID: bundleID, activates: true, done: done)
            }
        }
    }

    /// 每 0.15s 查一次进程还在不在：terminate 是异步的，立刻 open 会撞上旧实例，
    /// 旧实例的单实例锁会把新参数丢掉，最后还是没端口
    private static func waitForExit(bundleID: String, attempts: Int,
                                    done: @escaping (Bool) -> Void) {
        guard attempts > 0 else { return done(false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if MusicGate.isRunning(bundleID) {
                waitForExit(bundleID: bundleID, attempts: attempts - 1, done: done)
            } else {
                done(true)
            }
        }
    }
}