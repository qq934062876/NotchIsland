import Cocoa

// ---------------------------------------------------------------------------
// 菜单栏图标：岛收起时的唯一可见入口
//
// 之前退出与锁定只能右键岛体，收起态就是一块黑，普通用户找不到。
// 菜单每次打开时重建：锁定项打勾状态要跟 IslandLock 一致，不做常驻校验。
// 走 SF Symbols 模板图，自动适配深浅色菜单栏。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

final class AppMenuBar: NSObject, NSMenuDelegate {
    static let shared = AppMenuBar()

    private var statusItem: NSStatusItem?

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            // 旧系统若没有这个符号就退到通用矩形，保证菜单栏一定看得见入口
            let symbol = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                 accessibilityDescription: "NotchIsland")
                ?? NSImage(systemSymbolName: "menubar.rectangle",
                           accessibilityDescription: "NotchIsland")
            symbol?.isTemplate = true
            button.image = symbol
            button.setAccessibilityLabel("NotchIsland")
        }
        let menu = NSMenu()
        // 自己控可用性与勾选，不依赖 validateMenuItem
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        statusItem = item
        IslandDebug.log("lifecycle", "菜单栏图标已安装")
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let settings = NSMenuItem(title: "设置…",
                                  action: #selector(openSettings),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let locked = IslandLock.shared.blocksAutoExpand
        let lock = NSMenuItem(title: "锁定不弹出",
                              action: #selector(toggleLock),
                              keyEquivalent: "")
        lock.target = self
        lock.state = locked ? .on : .off
        menu.addItem(lock)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 NotchIsland",
                              action: #selector(quitIsland),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func openSettings() {
        AppWindows.shared.showSettings()
    }

    @objc private func toggleLock() {
        let next = !IslandLock.shared.blocksAutoExpand
        IslandDebug.log("lifecycle", "菜单栏锁定=\(next)")
        IslandLock.shared.set(next)
    }

    /// 与右键退出同一条路径：先缩回刘海再终止
    @objc private func quitIsland() {
        IslandDebug.log("lifecycle", "菜单栏退出")
        IslandExit.shared.leave { NSApp.terminate(nil) }
    }
}
