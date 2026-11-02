import Cocoa
import Combine

// ---------------------------------------------------------------------------
// 天气：Open-Meteo（免密钥、无依赖）
//
// 城市从设置里取固定坐标预设（见 WeatherCities）：不做定位授权，避免为了一个
// 温度多弹一次系统框。30 分钟拉一次；失败静默保留上一次成功的值。主页底行显示
// 现象、降水概率与日落时刻，不再显示「更新于」，旧值靠 30 分钟刷新周期兜底。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

struct WeatherSnapshot: Equatable {
    var temperature: Int
    var high: Int
    var low: Int
    /// 今日降水概率上限（%）；接口没给这个字段时为 nil
    var precipitationChance: Int?
    /// 日落时刻（HH:mm）；接口没给这个字段时为 nil
    var sunset: String?
    var symbol: String
    var condition: String
}

final class WeatherSource: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var updatedAt: Date?
    /// 当前城市：由设置的城市 id 决定；改城市后立刻清空旧值重拉
    @Published private(set) var city = AppSettings.shared.city

    /// 界面上显示的城市名（主页第二行常驻）
    var cityName: String { city.name }

    private var timer: Timer?
    private var task: URLSessionDataTask?

    private static let refreshInterval: TimeInterval = 30 * 60

    /// 设置里换城市：值没变就不重拉，避免设置窗一开一关就打一次网络
    func setCity(id: String) {
        let next = WeatherCities.city(id: id)
        guard next != city else { return }
        city = next
        // 旧城市的温度不能留在界面上，宁可先显示占位
        snapshot = nil
        updatedAt = nil
        IslandDebug.log("weather", "城市 -> \(next.name)")
        guard timer != nil else { return }
        fetch()
    }

    /// 按城市拼接口地址：timezone 交给 URLComponents 编码，日落时刻才是当地时间
    private var endpoint: String {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(city.latitude)),
            URLQueryItem(name: "longitude", value: String(city.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily",
                         value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunset"),
            URLQueryItem(name: "timezone", value: city.timeZone),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        return components?.string ?? ""
    }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    deinit {
        stop()
    }

    func start() {
        guard timer == nil else { return }
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.fetch()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        task?.cancel()
        task = nil
    }

    private func fetch() {
        guard let url = URL(string: endpoint) else { return }
        task?.cancel()
        task = session.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data else { return }
            guard let response = try? JSONDecoder().decode(Response.self, from: data),
                  let first = response.daily.temperature_2m_max.first,
                  let low = response.daily.temperature_2m_min.first else { return }
            let condition = Self.condition(for: response.current.weather_code)
            let chance = response.daily.precipitation_probability_max?.first
            let sunset = response.daily.sunset?.first.flatMap(Self.timeOfDay(from:))
            let next = WeatherSnapshot(temperature: Int(response.current.temperature_2m.rounded()),
                                       high: Int(first.rounded()),
                                       low: Int(low.rounded()),
                                       precipitationChance: chance,
                                       sunset: sunset,
                                       symbol: condition.symbol,
                                       condition: condition.text)
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.snapshot != next { self.snapshot = next }
                self.updatedAt = Date()
            }
        }
        task?.resume()
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            /// 新加的字段都按可选解析：接口临时不返回时退化成不显示，不影响整条快照
            let precipitation_probability_max: [Int]?
            let sunset: [String]?
        }
        let current: Current
        let daily: Daily
    }

    /// Open-Meteo 的日落是 ISO 时间（如 2026-11-04T17:42），只留 HH:mm
    private static func timeOfDay(from iso: String) -> String? {
        guard let separator = iso.firstIndex(of: "T") else { return nil }
        return String(iso[iso.index(after: separator)...].prefix(5))
    }

    /// WMO 天气代码 -> SF Symbol + 中文现象，只覆盖常见档位，其余归到多云
    private static func condition(for code: Int) -> (symbol: String, text: String) {
        switch code {
        case 0: return ("sun.max.fill", "晴")
        case 1, 2: return ("cloud.sun.fill", "多云")
        case 3: return ("cloud.fill", "阴")
        case 45, 48: return ("cloud.fog.fill", "雾")
        case 51, 53, 55, 56, 57: return ("cloud.drizzle.fill", "毛毛雨")
        case 61, 63, 65, 66, 67: return ("cloud.rain.fill", "雨")
        case 71, 73, 75, 77: return ("snowflake", "雪")
        case 80, 81, 82: return ("cloud.heavyrain.fill", "阵雨")
        case 85, 86: return ("cloud.snow.fill", "阵雪")
        case 95: return ("cloud.bolt.rain.fill", "雷阵雨")
        case 96, 99: return ("cloud.bolt.fill", "雷暴冰雹")
        default: return ("cloud.sun.fill", "多云")
        }
    }
}