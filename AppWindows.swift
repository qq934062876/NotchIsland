import Cocoa
import SwiftUI

// ---------------------------------------------------------------------------
// 首启引导与设置窗
//
// 与岛面板不同，这两个是普通窗口：需要抢焦点、可关闭、可由菜单栏随时打开。
// 引导只做一件事——把三项需要授权/可能打断他人的能力逐项说明，默认全部关闭，
// 用户勾选后才写进 AppSettings，各通道由 MediaStore / IslandView 自行响应。
// 视觉沿用系统控件与语义色，不自造皮肤（见 AGENTS.md 第 3 节）。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

enum AppInfo {
    /// 版本号来自 Info.plist，界面与日志共用一处
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }
}

// MARK: - 首启引导

struct OnboardingView: View {
    @ObservedObject private var settings = AppSettings.shared
    /// 点「开始使用」：标记已看过并关窗，由 AppWindows 负责
    var onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("欢迎使用 NotchIsland")
                    .font(.system(size: 20, weight: .semibold))
                Text("它常驻刘海，提供媒体控制、天气日程与文件托盘。下面三项都要你同意后才启用，之后随时能在「设置」里改。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ConsentRow(
                icon: "waveform",
                title: "读取正在播放",
                detail: "通过系统「正在播放」（含未公开接口）与 Apple Music / Spotify 的脚本接口读曲目。"
                    + "未公开接口在 macOS 升级后可能失效；关闭时不会读取，也不会弹出任何授权框。",
                isOn: $settings.readNowPlaying
            )

            ConsentRow(
                icon: "play.circle",
                title: "允许岛管理播放器",
                detail: "网易云等客户端只有带调试端口启动时才能读到曲目。打开后，岛会在它没运行时带端口拉起；"
                    + "已运行但没端口时，主页给一个手动重启入口——重启会打断正在播放的歌。",
                isOn: $settings.autoLaunchPlayers
            )

            ConsentRow(
                icon: "calendar",
                title: "在主页显示今日日程",
                detail: "只读今天的系统日历事件。首次打开会弹出 macOS 的日历授权框，拒绝后不再询问。",
                isOn: $settings.calendarEnabled
            )

            Divider()

            HStack(alignment: .center, spacing: 12) {
                Text("天气来自 Open-Meteo，无需密钥；城市可在设置里改。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("开始使用") { onFinish() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

/// 引导里的一行：图标 + 标题 + 说明 + 开关，说明按窗口宽换行
private struct ConsentRow: View {
    let icon: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

// MARK: - 设置窗

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    /// 锁定状态以 IslandLock 为准，设置窗只是又一个入口
    @ObservedObject private var lock = IslandLock.shared

    var body: some View {
        Form {
            Section("播放") {
                Toggle("读取正在播放", isOn: $settings.readNowPlaying)
                Text("系统「正在播放」走未公开接口（无法上架 App Store），macOS 升级后可能失效；"
                     + "Apple Music / Spotify 走脚本接口，首次会请求「控制其他 App」。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Toggle("允许岛管理播放器", isOn: $settings.autoLaunchPlayers)
                Text("允许岛带调试端口启动网易云等客户端；已运行但没端口时主页才会给重启入口。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("主页") {
                Toggle("显示今日日程", isOn: $settings.calendarEnabled)
                Text("首次打开会请求日历授权；关闭后不再读取，主页显示「日历未开启」。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("天气城市", selection: $settings.weatherCityID) {
                    ForEach(WeatherCities.all) { city in
                        Text(city.name).tag(city.id)
                    }
                }
            }

            Section("岛") {
                Toggle("锁定不弹出", isOn: Binding(
                    get: { lock.blocksAutoExpand },
                    set: { lock.set($0) }
                ))
                Text("锁定后光标移进刘海也不展开。右键岛体或菜单栏图标同样可切换，状态跨启动保留。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("版本", value: AppInfo.version)
                Text("以 GPL-3.0 发布，源码与构建脚本随仓库提供。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }
}

// MARK: - 窗口装配

/// 窗口都放这里：设置窗复用同一个实例，引导窗只出现一次
final class AppWindows: NSObject {
    static let shared = AppWindows()

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    /// 菜单栏「设置…」与右键菜单共用
    func showSettings() {
        if settingsWindow == nil {
            let window = makeWindow(title: "NotchIsland 设置",
                                    size: NSSize(width: 460, height: 560))
            let host = NSHostingController(rootView: SettingsView())
            // 不让 SwiftUI 反过来改窗口尺寸：设置窗是固定尺寸，内容超出由 Form 自己滚动
            host.sizingOptions = []
            window.contentViewController = host
            settingsWindow = window
        }
        present(settingsWindow)
    }

    /// 首启引导：只有没点过「开始使用」才出现
    func showOnboardingIfNeeded() {
        guard !AppSettings.shared.hasCompletedOnboarding else { return }
        if onboardingWindow == nil {
            let host = NSHostingController(rootView: OnboardingView { [weak self] in
                AppSettings.shared.hasCompletedOnboarding = true
                IslandDebug.log("lifecycle", "首启引导完成")
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            })
            let window = makeWindow(title: "欢迎使用 NotchIsland",
                                    size: NSSize(width: 520, height: 520))
            window.contentViewController = host
            // 关键：sizingOptions 默认会把窗口压回 SwiftUI 的紧凑高度（实测 414），
            // 三行说明会被裁掉底部按钮；清空后窗口按下面设定的尺寸走
            host.sizingOptions = []
            window.setContentSize(NSSize(width: 520, height: 520))
            onboardingWindow = window
        }
        present(onboardingWindow)
    }

    private func makeWindow(title: String, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    /// LSUIElement 应用默认不抢焦点，打开窗口前必须显式激活一次
    private func present(_ window: NSWindow?) {
        guard let window = window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
