import Cocoa
import Combine

// ---------------------------------------------------------------------------
// 刘海几何：刘海宽高 + 所在屏幕 frame
//
// 之前这三个值是 NotchRootView 的 let 常量，启动时定死。插拔外接屏、合盖、
// 改分辨率后窗口跟着挪了位置，热区还按旧屏幕算，光标明明在岛上也会被判成
// 「已离开」→ 0.35s 后收起，表现为「莫名收起」。
// 现在改成可观察对象：main.swift 在 didChangeScreenParametersNotification 里
// 调 update(...)，视图侧 onChange 重算热区与命中区。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

final class NotchGeometry: ObservableObject {
    /// 刘海宽：收起态热区与宽度下限都由它决定
    @Published private(set) var notchWidth: CGFloat
    /// 刘海高：收起态黑块高、展开高度基准
    @Published private(set) var notchHeight: CGFloat
    /// 刘海所在屏幕的 frame（屏幕坐标，左下原点）：热区换算回屏幕坐标用
    @Published private(set) var screenFrame: NSRect

    init(notchWidth: CGFloat, notchHeight: CGFloat, screenFrame: NSRect) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.screenFrame = screenFrame
    }

    /// 刘海尺寸作为一个值发布，视图侧只需监听一次
    var notchSize: CGSize {
        CGSize(width: notchWidth, height: notchHeight)
    }

    /// 屏幕参数变化后更新；值没变就不发布，避免无谓地重算热区
    func update(screenFrame: NSRect, notchWidth: CGFloat, notchHeight: CGFloat) {
        let changed = screenFrame != self.screenFrame
            || notchWidth != self.notchWidth
            || notchHeight != self.notchHeight
        guard changed else { return }

        IslandDebug.log("geometry",
                        "old=\(IslandDebug.rect(self.screenFrame)) \(self.notchWidth)x\(self.notchHeight) "
                        + "new=\(IslandDebug.rect(screenFrame)) \(notchWidth)x\(notchHeight)")
        self.screenFrame = screenFrame
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
    }
}

// MARK: - 刘海尺寸解析

/// 一套刘海尺寸（点）与它的来源：来源要写进日志，
/// 换机型出问题时一眼就能看出走的是系统探测、缓存还是兜底常量
struct NotchSpec: Equatable {
    var width: CGFloat
    var height: CGFloat
    var source: Source

    enum Source: String {
        /// NSScreen 的安全区 + 左右辅助区（任何机型都对）
        case system
        /// 上次在这块屏上探测到的值（系统暂时给不出宽度时）
        case cached
        /// 系统与缓存都拿不到，只剩保守常量
        case fallback
        /// 调试覆盖（`NOTCH_SPEC=200x38`），只在 NOTCH_DEBUG=1 时出现
        case override
    }
}

/// 刘海尺寸解析：**不维护「机型 → 尺寸」白名单**。
/// 每台带刘海的 Mac，系统都会按物理挖孔换算成点坐标给出
/// `safeAreaInsets.top`（刘海高）与 `auxiliaryTopLeftArea/RightArea`（两者夹出刘海宽），
/// 缩放分辨率、改分辨率都由系统换算好，所以 179×32 / 200×38 这类差异天然覆盖。
/// 只有系统暂时给不出宽度时（全屏或菜单栏自动隐藏时辅助区为 nil）才依次退到
/// 本机缓存、通用常量；高度始终以系统 `safeAreaInsets.top` 为准。
enum NotchSpecResolver {
    /// 兜底宽度按高度推：实测宽高比 179/32 ≈ 5.59、200/38 ≈ 5.26，取偏窄的 5.3。
    /// 宁可窄不可宽——窄出来的是同一块物理黑，连成一片看不出来；宽出来每侧都会盖住菜单栏图标。
    /// 只在系统与缓存都给不出时使用，日志里会标 `source=fallback`
    static func fallbackWidth(height: CGFloat) -> CGFloat {
        (height * 5.3).rounded()
    }

    private static let defaults = UserDefaults.standard
    private static let keyPrefix = "notchSpec."

    /// 系统探测：高度 = 安全区上边距，宽度 = 左右两块可用区之间的空隙
    static func systemSpec(for screen: NSScreen) -> NotchSpec? {
        let inset = screen.safeAreaInsets.top
        guard inset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        let width = right.minX - left.maxX
        guard width > 0 else { return nil }
        return NotchSpec(width: width, height: inset, source: .system)
    }

    /// 解析顺序：系统 → 本机缓存 → 通用兜底。
    /// `safeAreaInsets.top == 0` 表示这块屏没有刘海，返回 nil 让调用方跳过
    static func resolve(for screen: NSScreen) -> NotchSpec? {
        if let spec = systemSpec(for: screen) {
            remember(spec, for: screen)
            return spec
        }
        let inset = screen.safeAreaInsets.top
        guard inset > 0 else { return nil }
        if let spec = cachedSpec(for: screen) { return spec }
        return NotchSpec(width: fallbackWidth(height: inset), height: inset, source: .fallback)
    }

    /// 缓存键：优先显示器 UUID（同一块屏挪位置、换缩放都还认得出），
    /// 拿不到 UUID 时退到显示器编号（外接屏热插拔后编号可能变，只作最后手段）
    private static func cacheKey(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let display = CGDirectDisplayID(number.uint32Value)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
           let text = CFUUIDCreateString(nil, uuid) as String? {
            return keyPrefix + text
        }
        return keyPrefix + "display-\(display)"
    }

    /// 缓存 [宽, 高, 当时的屏幕点宽, 点高]：后两项用来识别「换过缩放 / 分辨率」，
    /// 那种情况下旧点宽不再适用，宁可当没缓存，等系统下次给得出辅助区时重写
    private static func remember(_ spec: NotchSpec, for screen: NSScreen) {
        guard let key = cacheKey(for: screen) else { return }
        defaults.set([Double(spec.width), Double(spec.height),
                      Double(screen.frame.width), Double(screen.frame.height)],
                     forKey: key)
    }

    private static func cachedSpec(for screen: NSScreen) -> NotchSpec? {
        guard let key = cacheKey(for: screen),
              let values = defaults.array(forKey: key), values.count == 4,
              let width = (values[0] as? NSNumber)?.doubleValue, width > 0,
              let cachedScreenWidth = (values[2] as? NSNumber)?.doubleValue,
              let cachedScreenHeight = (values[3] as? NSNumber)?.doubleValue,
              abs(cachedScreenWidth - screen.frame.width) < 1,
              abs(cachedScreenHeight - screen.frame.height) < 1 else { return nil }
        // 宽度用缓存（系统给不出的就是这一项），高度仍取系统现值
        return NotchSpec(width: CGFloat(width),
                         height: screen.safeAreaInsets.top,
                         source: .cached)
    }
}