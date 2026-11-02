import Foundation
import Combine

// ---------------------------------------------------------------------------
// 偏好设置：所有跨启动保留的用户选择都在这里
//
// 三个能力开关默认全部关闭（产品化口径：先征得同意再启用）：
//   - readNowPlaying：系统「正在播放」通道（MediaRemote 私有框架）与 osascript 代理。
//     关闭时不起子进程、不碰私有符号，因此不会弹「控制其他 App」的授权框
//   - autoLaunchPlayers：允许岛带 --remote-debugging-port 启动 / 重启播放器客户端
//   - calendarEnabled：允许读今日日程（EventKit，首次启用才弹系统授权）
// 首启引导逐项说明后由用户打开；设置窗随时可改，改完立即生效（见 MediaStore / IslandView）
// 认的是 UserDefaults.standard，域名跟着 Info.plist 的 bundle id 走
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

/// 天气城市：只做固定坐标预设，不引入定位授权与地理编码
struct WeatherCity: Identifiable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    /// Open-Meteo 的 timezone 参数：日落时刻按当地时间返回
    let timeZone: String
}

enum WeatherCities {
    /// 预设城市：换城市只改这一张表，坐标取各市主城区
    static let all: [WeatherCity] = [
        WeatherCity(id: "zhuhai", name: "珠海", latitude: 22.2707, longitude: 113.5767, timeZone: "Asia/Shanghai"),
        WeatherCity(id: "beijing", name: "北京", latitude: 39.9042, longitude: 116.4074, timeZone: "Asia/Shanghai"),
        WeatherCity(id: "shanghai", name: "上海", latitude: 31.2304, longitude: 121.4737, timeZone: "Asia/Shanghai"),
        WeatherCity(id: "guangzhou", name: "广州", latitude: 23.1291, longitude: 113.2644, timeZone: "Asia/Shanghai"),
        WeatherCity(id: "shenzhen", name: "深圳", latitude: 22.5431, longitude: 114.0579, timeZone: "Asia/Shanghai"),
        WeatherCity(id: "hangzhou", name: "杭州", latitude: 30.2741, longitude: 120.1551, timeZone: "Asia/Shanghai"),
        WeatherCity(id: "chengdu", name: "成都", latitude: 30.5728, longitude: 104.0668, timeZone: "Asia/Shanghai"),
        WeatherCity(id: "hongkong", name: "香港", latitude: 22.3193, longitude: 114.1694, timeZone: "Asia/Hong_Kong")
    ]

    static let fallback = all[0]

    static func city(id: String) -> WeatherCity {
        all.first { $0.id == id } ?? fallback
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let readNowPlaying = "settings.readNowPlaying"
        static let autoLaunchPlayers = "settings.autoLaunchPlayers"
        static let calendarEnabled = "settings.calendarEnabled"
        static let weatherCity = "settings.weatherCity"
        static let locked = "settings.locked"
        static let onboardingDone = "settings.onboardingDone"
    }

    private let defaults: UserDefaults

    /// 是否允许读播放器信息：系统直连（MediaRemote）与 osascript 代理都受它控制
    @Published var readNowPlaying: Bool {
        didSet {
            guard readNowPlaying != oldValue else { return }
            defaults.set(readNowPlaying, forKey: Key.readNowPlaying)
            IslandDebug.log("settings", "readNowPlaying=\(readNowPlaying)")
        }
    }

    /// 是否允许岛带调试端口启动 / 重启播放器客户端（网易云等 CEF 客户端）
    @Published var autoLaunchPlayers: Bool {
        didSet {
            guard autoLaunchPlayers != oldValue else { return }
            defaults.set(autoLaunchPlayers, forKey: Key.autoLaunchPlayers)
            IslandDebug.log("settings", "autoLaunchPlayers=\(autoLaunchPlayers)")
        }
    }

    /// 是否允许读今日日程；关掉时不会请求 EventKit 授权
    @Published var calendarEnabled: Bool {
        didSet {
            guard calendarEnabled != oldValue else { return }
            defaults.set(calendarEnabled, forKey: Key.calendarEnabled)
            IslandDebug.log("settings", "calendarEnabled=\(calendarEnabled)")
        }
    }

    /// 天气城市 id（见 WeatherCities.all）
    @Published var weatherCityID: String {
        didSet {
            guard weatherCityID != oldValue else { return }
            defaults.set(weatherCityID, forKey: Key.weatherCity)
            IslandDebug.log("settings", "weatherCity=\(weatherCityID)")
        }
    }

    /// 锁定不弹出：岛与菜单栏两处入口共用这一份状态
    @Published var locked: Bool {
        didSet {
            guard locked != oldValue else { return }
            defaults.set(locked, forKey: Key.locked)
        }
    }

    /// 首启引导是否已完成（点过「开始使用」）
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            guard hasCompletedOnboarding != oldValue else { return }
            defaults.set(hasCompletedOnboarding, forKey: Key.onboardingDone)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 未写过时一律 false / 珠海：默认关闭是产品口径，不靠注册默认值兜底
        readNowPlaying = defaults.bool(forKey: Key.readNowPlaying)
        autoLaunchPlayers = defaults.bool(forKey: Key.autoLaunchPlayers)
        calendarEnabled = defaults.bool(forKey: Key.calendarEnabled)
        weatherCityID = defaults.string(forKey: Key.weatherCity) ?? WeatherCities.fallback.id
        locked = defaults.bool(forKey: Key.locked)
        hasCompletedOnboarding = defaults.bool(forKey: Key.onboardingDone)
    }

    var city: WeatherCity {
        WeatherCities.city(id: weatherCityID)
    }
}
