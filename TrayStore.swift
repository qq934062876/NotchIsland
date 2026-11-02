import Cocoa

// ---------------------------------------------------------------------------
// 文件托盘：把拖进右半的文件收进 App 自己的暂存区
//
// 落盘位置：~/Library/Application Support/local.notch.island/Tray/
// 文件名前缀 uuid，避免同名覆盖；展示名去掉前缀，回到原来的名字。
// 常驻到磁盘：关掉 App 再开，托盘里还是那些文件（这是「暂存」而不是「中转」的区别）。
// 上限 8 条、单个 200MB：超了只回一句提示，不弹窗、不静默丢文件。
// 不是 ObservableObject：列表状态由 DropReceiver 统一发布，
// 嵌套 ObservableObject 不会把 objectWillChange 透出去，容易白改一场。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

struct TrayItem: Identifiable, Equatable {
    /// 落盘文件名（uuid_原名），同时当稳定的 id
    let id: String
    /// 展示用的原名
    let name: String
    let url: URL
    /// 导入时取一次的图标，避免每次重绘都读磁盘
    let icon: NSImage?

    static func == (lhs: TrayItem, rhs: TrayItem) -> Bool {
        lhs.id == rhs.id
    }
}

final class TrayStore {
    static let limit = 8
    static let maxBytes: Int64 = 200 * 1024 * 1024

    private(set) var items: [TrayItem] = []
    private let folder: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        folder = support
            .appendingPathComponent("local.notch.island", isDirectory: true)
            .appendingPathComponent("Tray", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        items = Self.loadItems(in: folder)
    }

    /// 收文件：先按当前条数算余量，复制放后台，回主线程才写 items。
    /// items 只在主线程写，避免后台复制与界面读列表撞在一起
    func importFiles(_ urls: [URL], completion: @escaping (String?) -> Void) {
        // 余量在主线程算：items 的唯一写者就是这里
        let capacity = max(0, Self.limit - items.count)
        let folder = self.folder
        DispatchQueue.global(qos: .userInitiated).async {
            let staged = Self.stage(urls, into: folder, capacity: capacity)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // 图标走 AppKit，只能在主线程取，所以复制与建条目分两步
                let newItems = staged.files.map { url in
                    TrayItem(id: url.lastPathComponent,
                             name: Self.displayName(for: url.lastPathComponent),
                             url: url,
                             icon: NSWorkspace.shared.icon(forFile: url.path))
                }
                self.items.append(contentsOf: newItems)
                completion(staged.notice)
            }
        }
    }

    /// 纯复制，不碰 items、不碰 AppKit，可在后台线程跑；返回落地文件与一行提示
    private static func stage(_ urls: [URL],
                              into folder: URL,
                              capacity: Int) -> (files: [URL], notice: String?) {
        var staged: [URL] = []
        var tooLarge = 0
        var full = 0
        var failed = 0

        for url in urls where url.isFileURL {
            guard staged.count < capacity else {
                full += 1
                continue
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            guard size <= Self.maxBytes else {
                tooLarge += 1
                continue
            }
            let id = "\(UUID().uuidString)_\(url.lastPathComponent)"
            let destination = folder.appendingPathComponent(id)
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                staged.append(destination)
            } catch {
                failed += 1
            }
        }

        var notices: [String] = []
        if full > 0 { notices.append("最多 \(TrayStore.limit) 个") }
        if tooLarge > 0 { notices.append("单个不超过 200MB") }
        if failed > 0 { notices.append("\(failed) 个复制失败") }
        return (staged, notices.isEmpty ? nil : notices.joined(separator: "，"))
    }

    func clear() {
        for item in items {
            try? FileManager.default.removeItem(at: item.url)
        }
        items.removeAll()
    }

    static func reveal(_ item: TrayItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: - 磁盘

    private static func loadItems(in folder: URL) -> [TrayItem] {
        let keys: [URLResourceKey] = [.creationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder,
                                                                      includingPropertiesForKeys: keys,
                                                                      options: [.skipsHiddenFiles]) else {
            return []
        }
        let sorted = files.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return left > right   // 新的在前
        }
        // 超出上限的旧文件顺手清掉：只显示 8 条却把多余文件留在磁盘上，
        // 用户以为清空了、实际上还在吃空间
        for stale in sorted.dropFirst(limit) {
            try? FileManager.default.removeItem(at: stale)
        }
        return sorted.prefix(limit).map { url in
            TrayItem(id: url.lastPathComponent,
                     name: displayName(for: url.lastPathComponent),
                     url: url,
                     icon: NSWorkspace.shared.icon(forFile: url.path))
        }
    }

    /// 去掉 "<uuid>_" 前缀；格式不对就原样返回
    private static func displayName(for id: String) -> String {
        guard let separator = id.firstIndex(of: "_") else { return id }
        let prefix = id[id.startIndex..<separator]
        guard prefix.count == 36 else { return id }
        return String(id[id.index(after: separator)...])
    }
}