import Cocoa
import CoreAudio

// ---------------------------------------------------------------------------
// 谁在出声：CoreAudio 进程级采样 + 属性监听
//
// 「后台只有一个音乐软件在播」不能靠 Now Playing 判断：MediaRemote 只认最后一次
// 注册的那一个，浏览器标签、网易云、Music 同时出声时它照样只报一个。
// 这里改成读系统的音频进程列表（kAudioHardwarePropertyProcessObjectList，macOS 14.2+），
// 逐个问 kAudioProcessPropertyIsRunningOutput，按 app 去重，浏览器多标签自然只算一个。
//
// 只认真实 App（activationPolicy == .regular）：XPC、helper、系统音效进程不算
// 「音频软件」，否则一次提示音就会把岛打成「多个音频软件」。
//
// 除 1.5s 轮询兜底外，还监听两类 CoreAudio 属性做事件驱动：
//   kAudioHardwarePropertyProcessObjectList（谁起播/退出，进程对象列表变了）
//   kAudioProcessPropertyIsRunningOutput（起停直接触发）
// 这样「岛先常驻、之后才放歌」也能在 120ms 去抖后立刻刷新，不用等下一个轮询周期。
// 采样成本极低（列表通常 < 20 条），监听回调只发一个「变了」信号，不在回调里做采样。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

/// 一个正在输出音频的 app；bundleID 已去重
struct AudioApp: Equatable {
    var bundleID: String
    var name: String
}

final class AudioActivity {
    /// 「谁在出声」可能变了；只在主队列触发，调用方在那里重新采样即可
    var onChange: (() -> Void)?

    /// 监听回调专用串行队列：CoreAudio 在 IO 线程上调用 block，
    /// 不能直接在 block 里碰 UI 或做长活
    private let listenerQueue = DispatchQueue(label: "local.notch.island.audio.listeners")
    private var listening = false
    /// 同一时刻只保留一个待触发的通知：起播一瞬间 process list 与 IsRunningOutput
    /// 会先后各报一次，去抖后只刷一行界面
    private var pendingNotify: DispatchWorkItem?

    /// 进程对象监听：移除时必须传回注册时那一份 block，所以按对象存起来
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var systemListener: AudioObjectPropertyListenerBlock?

    /// 当前正在出声的 app，按名字排序；空数组代表没有任何音频软件在播
    func sample() -> [AudioApp] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        var seen = Set<String>()
        var apps: [AudioApp] = []

        for object in processObjects() {
            guard isRunningOutput(object), let pid = pid(of: object), pid != selfPID else { continue }
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)
            apps.append(AudioApp(bundleID: bundleID,
                                 name: app.localizedName ?? bundleID))
        }

        return apps.sorted { $0.name < $1.name }
    }

    // MARK: - 事件监听

    /// 幂等：重复调用不会重复注册，便于视图 onAppear 与测试路径各调一次。
    /// 注册与注销都串行落到 listenerQueue：回调也在这个队列上跑，
    /// 否则主线程 stop 时回调线程可能正在重建监听，字典会被并发读写
    func start() {
        listenerQueue.sync {
            guard !listening else { return }
            listening = true
            addSystemListener()
            rebuildProcessListeners()
        }
    }

    func stop() {
        listenerQueue.sync {
            guard listening else { return }
            listening = false
            pendingNotify?.cancel()
            pendingNotify = nil

            if let block = systemListener {
                var address = systemAddress
                AudioObjectRemovePropertyListenerBlock(systemObject, &address, listenerQueue, block)
                systemListener = nil
            }
            for (object, block) in processListeners {
                var address = outputAddress
                // 进程可能已经退出、对象已销毁，移除失败是正常情况，不当作错误处理
                AudioObjectRemovePropertyListenerBlock(object, &address, listenerQueue, block)
            }
            processListeners.removeAll()
        }
    }

    deinit {
        stop()
    }

    /// 进程对象有增减时重建监听：新对象要挂，旧对象要摘，否则回调会打到已销毁的对象上
    private func rebuildProcessListeners() {
        let current = Set(processObjects())
        // 先收集再删：边遍历 keys 边 removeValue 会触发「集合在遍历中被修改」崩溃
        let stale = processListeners.keys.filter { !current.contains($0) }
        for object in stale {
            var address = outputAddress
            AudioObjectRemovePropertyListenerBlock(object, &address, listenerQueue,
                                                   processListeners[object]!)
            processListeners.removeValue(forKey: object)
        }
        for object in current where processListeners[object] == nil {
            var address = outputAddress
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.scheduleNotify()
            }
            if AudioObjectAddPropertyListenerBlock(object, &address, listenerQueue, block) == noErr {
                processListeners[object] = block
            }
        }
    }

    private func addSystemListener() {
        var address = systemAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self else { return }
            // 列表变化后先补挂新对象的监听，再通知界面刷新
            self.rebuildProcessListeners()
            self.scheduleNotify()
        }
        if AudioObjectAddPropertyListenerBlock(systemObject, &address, listenerQueue, block) == noErr {
            systemListener = block
        }
    }

    /// 120ms 去抖：一次起播常伴随两个属性回调，合并成一次采样；
    /// 只发信号不在这里采样，真正的读取仍由 MediaStore.poll 统一做
    private func scheduleNotify() {
        pendingNotify?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.listening else { return }
            self.onChange?()
        }
        pendingNotify = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    // MARK: - CoreAudio

    private var systemObject: AudioObjectID { AudioObjectID(kAudioObjectSystemObject) }

    private var systemAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private var outputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func processObjects() -> [AudioObjectID] {
        var address = systemAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }

        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &list) == noErr else {
            return []
        }
        return list
    }

    /// 进程当前是否在往输出设备写音频；旧系统或已退出的对象读不到，按「没在播」处理
    private func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var address = outputAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }

    private func pid(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              value > 0 else { return nil }
        return value
    }
}