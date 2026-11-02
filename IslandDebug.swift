import Foundation

// ---------------------------------------------------------------------------
// 诊断日志：排查「莫名收起」用，默认完全关闭
//
// 打开方式：NOTCH_DEBUG=1 ./NotchIsland.app/Contents/MacOS/NotchIsland
// 分类共 10 个，便于 grep：ptr / zone / expand / scene / geometry / env（窗口与热区）、
// lifecycle（启动与退出）、pick（本轮选了哪家）、audio（CoreAudio 采样）、
// bridge（osascript 代理）、cdp（CDP 客户端）：
//   NOTCH_DEBUG=1 ... 2>&1 | grep -E 'expand|zone|scene'
// 关闭时只是一次静态布尔判断，不做字符串拼接（autoclosure 延迟求值）。
// 只写 stderr，不落盘、不写仓库产物，不打印封面二进制与文件路径。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

enum IslandDebug {
    /// 进程启动时读一次环境变量；运行中改环境不影响
    static let enabled = ProcessInfo.processInfo.environment["NOTCH_DEBUG"] == "1"

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// 所有调用都在主线程（鼠标事件、SwiftUI 状态变更、屏幕参数通知），
    /// 共用 DateFormatter 是安全的
    static func log(_ category: String, _ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "\(formatter.string(from: Date())) [\(category)] \(message())\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    /// 热区/命中区统一格式，方便对比两个矩形差了几个点
    static func rect(_ rect: CGRect) -> String {
        String(format: "x=%.1f y=%.1f w=%.1f h=%.1f",
               rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
    }

    static func point(_ point: CGPoint) -> String {
        String(format: "%.1f,%.1f", point.x, point.y)
    }
}