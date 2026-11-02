import Cocoa
import Darwin
import IOKit
import IOKit.ps

// ---------------------------------------------------------------------------
// 系统状态：电池电量 / 充电状态 / 循环次数（顶栏）+ 内存占用 / 磁盘可用（主页底行）
//
// 电量与充电态走 IOKit 电源快照（IOPSCopyPowerSourcesInfo），循环次数读
// AppleSmartBattery 注册表项的 CycleCount（部分机型放在 BatteryData 字典里）。
// 内存走 Mach 的 host_statistics64，磁盘走 FileManager 的文件系统属性。
// 刷新频率 20s / 30s：这些都变得慢，不并入 1.5s 播放轮询，避免白跑 IO。
// 读不到电池（台式机 / 快照失败）时 isAvailable = false，界面整体隐藏电量区；
// 内存与磁盘取不到的字段留 nil，主页只画取到的项，不显示占位。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

/// 一次采样的电池状态；数值取不到时保持默认值并由 isAvailable 标记整体可用性
struct BatteryStatus: Equatable {
    var percentage = 0
    var isCharging = false
    var isExternalConnected = false
    /// 电池循环次数，系统不提供时为 nil
    var cycleCount: Int?
    var isAvailable = false
}

final class BatteryMonitor: ObservableObject {
    @Published private(set) var status = BatteryStatus()

    private var timer: Timer?
    private static let refreshInterval: TimeInterval = 20

    init() {
        refresh()
        // 电源插拔与电量跳变由低频定时器兜住；本类不订阅通知，避免多一处悬挂回调
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let next = Self.read()
        if next != status { status = next }
    }

    // MARK: - 读取

    private static func read() -> BatteryStatus {
        var status = BatteryStatus()

        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let raw = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue(),
                      let desc = raw as? [String: Any],
                      desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

                status.isAvailable = true
                // IOPS 给的是一对数值（当前容量 / 最大容量），按两者之比折算百分比，
                // 不要直接当 0-100 用：部分机型最大容量不是 100（如 98），会高估电量
                let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
                let maximum = desc[kIOPSMaxCapacityKey] as? Int ?? 100
                status.percentage = maximum > 0
                    ? Int((Double(current) / Double(maximum) * 100).rounded())
                    : current
                status.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
                status.isExternalConnected = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                break
            }
        }

        status.cycleCount = readCycleCount()
        return status
    }

    /// AppleSmartBattery 是系统自带的 IO 对象，只读取、不写；取不到就返回 nil
    private static func readCycleCount() -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        if let value = IORegistryEntryCreateCFProperty(service,
                                                       "CycleCount" as CFString,
                                                       kCFAllocatorDefault,
                                                       0)?.takeRetainedValue() as? Int {
            return value
        }

        // 新机型把循环次数收进 BatteryData，路径变了但字段名不变
        if let data = IORegistryEntryCreateCFProperty(service,
                                                      "BatteryData" as CFString,
                                                      kCFAllocatorDefault,
                                                      0)?.takeRetainedValue() as? [String: Any],
           let value = data["CycleCount"] as? Int {
            return value
        }
        return nil
    }
}

// ---------------------------------------------------------------------------
// 主页底行的系统信息：内存占用百分比 + 磁盘可用空间
//
// 两项都是近似值：内存按 active + wired + compressed 占物理内存的比例算，
// 与活动监视器的「已用内存」口径接近但不是逐字节相同；磁盘取
// systemFreeSize 并按十进制 GB 折算，与 Finder 显示的量级一致。
// 取不到就留 nil，界面只画取到的项，不写「--」占位（这块随时可能没有）。
// ---------------------------------------------------------------------------

struct SystemMetrics: Equatable {
    /// 内存占用百分比；Mach 调用失败时为 nil
    var memoryUsage: Int?
    /// 磁盘可用空间（GB，十进制）；读不到文件系统属性时为 nil
    var diskFreeGB: Int?
}

final class SystemMetricsMonitor: ObservableObject {
    @Published private(set) var metrics = SystemMetrics()

    private var timer: Timer?
    /// 30s 一次：内存有起伏但不必更密，磁盘变化更慢
    private static let refreshInterval: TimeInterval = 30

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let next = SystemMetrics(memoryUsage: Self.readMemoryUsage(),
                                 diskFreeGB: Self.readDiskFreeGB())
        if next != metrics { metrics = next }
    }

    // MARK: - 读取

    private static func readMemoryUsage() -> Int? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count)
                    + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return nil }
        return Int((used / total * 100).rounded())
    }

    private static func readDiskFreeGB() -> Int? {
        guard let values = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = values[.systemFreeSize] as? Int64 else { return nil }
        return Int(free / 1_000_000_000)
    }
}