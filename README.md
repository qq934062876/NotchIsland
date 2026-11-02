# NotchIsland

常驻 MacBook 刘海的系统小工具：媒体控制、天气与日程、文件托盘。纯 Swift + SwiftUI，无 Xcode 工程、无第三方依赖，一条命令构建。

> 需要带刘海的 MacBook（macOS 14 及以上）。没有刘海的机型、外接显示器会给出提示后退出。

## 功能

- **收起态贴合刘海**：默认与物理刘海等大；读到曲目时左右各加 20pt，右侧放 4 根跳动波形。光标沉进刘海才展开。
- **展开态**：顶栏（音乐 / 文件 / 主页三个页签 + 锁定 + 电量 / 循环次数 / 充电状态）+ 内容区。媒体页是圆形旋转封面、歌名歌手、上一首 / 播放暂停 / 下一首、可拖进度条；外翻顶角、双层投影、底边柔化描边。
- **主页**：今日天气（现象 / 高低温 / 降水概率 / 日落）、今日日程（进行中 / N 分钟后）、内存与磁盘占用。
- **文件托盘**：拖文件到岛左半走隔空投送、右半进托盘；托盘最多 8 个、单个 200MB，关掉 App 再开还在。
- **不抢焦点、点击穿透**：岛外区域不拦截鼠标，菜单栏照常可用。

## 环境要求

| 项 | 要求 |
|---|---|
| 系统 | macOS 14.0+（`Info.plist` 的 `LSMinimumSystemVersion` = `14.0`） |
| 机型 | 带刘海的 MacBook（Apple Silicon；构建目标为 `arm64`） |
| 工具链 | Xcode Command Line Tools（提供 `swiftc`、`codesign`、`iconutil`）：`xcode-select --install` |

不需要 Homebrew，不需要 Xcode 工程，不需要 Apple 开发者账号。

## 构建

```bash
git clone <本仓库地址> NotchIsland
cd NotchIsland
./build.sh
open NotchIsland.app
```

App 图标已随仓库提供（`Assets/AppIcon.icns`）。要改成自己的图标，重跑生成脚本后再构建；脚本同样需要与 `swiftc` 匹配的 SDK：

```bash
swift -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk tools/make-icon.swift
```

`build.sh` 会：挑一个与当前 `swiftc` 匹配的 SDK → 以 `arm64-apple-macos14.0` 为部署目标编译 `SOURCES` 里的全部 `.swift` → 组装 `NotchIsland.app`（`Info.plist` + 二进制 + 图标）→ ad-hoc 签名。

可选环境变量：

| 变量 | 作用 | 默认 |
|---|---|---|
| `SDK` | 指定 SDK 路径 | 自动探测兼容的 SDK |
| `OUT` | 二进制输出路径 | `./NotchIsland` |
| `APP_DIR` | app 包输出路径 | `./NotchIsland.app` |
| `SKIP_SIGN` | 设为 `1` 跳过 ad-hoc 签名 | 不跳过 |
| `MACOS_MIN` | 最低系统版本 | `14.0` |

不覆盖现有产物地试编译：

```bash
OUT=/tmp/ni/NotchIsland APP_DIR=/tmp/ni/NotchIsland.app ./build.sh
```

**关于 Gatekeeper**：本机 `./build.sh` 产出的 app 没有 quarantine 属性，双击即可运行。如果你下载的是别人打包的 zip，系统可能提示「无法验证开发者」，需要执行一次：

```bash
xattr -dr com.apple.quarantine /path/to/NotchIsland.app
```

本项目不做 Developer ID 签名与公证，因此**没有**「双击即装」的官方安装包。

## 首次运行

第一次启动会弹出引导，三项能力**默认全部关闭**，逐项说明后由你决定是否打开：

| 开关 | 打开后会发生什么 | 关闭时 |
|---|---|---|
| 读取正在播放 | 读系统「正在播放」（私有框架）与 Apple Music / Spotify 的脚本接口；首次会弹「控制其他 App」授权 | 不读任何播放器、不弹授权框 |
| 允许岛管理播放器 | 网易云没运行时由岛带调试端口拉起；已运行但没端口时主页给手动重启入口 | 不启动、不重启任何客户端 |
| 在主页显示今日日程 | 首次会弹 macOS 日历授权 | 不读日历，主页显示「日历未开启」 |

三项都能在「设置」里随时改，改完立即生效，不用重启 App。引导只出现一次；关窗未点「开始使用」的话，下次启动会再出现。

## 菜单栏与设置

菜单栏有一个矩形图标（收起态的岛是一块黑，没它找不到退出入口）：

- **设置…**：播放能力开关、天气城市（8 个预设）、日程开关、锁定不弹出、版本信息。
- **锁定不弹出**：打勾状态与岛体右键、顶栏锁按钮同一份状态，跨启动保留。
- **退出 NotchIsland**：先播收回动画再退出。

岛体上右键同样有「设置… / 退出 / 锁定 / 解除锁定」。

## 权限与数据

| 能力 | 系统权限 | 数据去向 |
|---|---|---|
| 读取正在播放 | 「控制其他 App」（Apple Events） | 只在本机内存里，不上传 |
| 今日日程 | 日历（EventKit） | 只读今天的事件，不落盘 |
| 天气 | 网络 | 只向 Open-Meteo 请求你选的城市坐标，无密钥、无账号 |
| 文件托盘 | 无 | 复制到 `~/Library/Application Support/local.notch.island/Tray/` |

诊断日志默认关闭。需要排查时从终端启动并加 `NOTCH_DEBUG=1`，日志只写 stderr，不落盘：

```bash
NOTCH_DEBUG=1 ./NotchIsland.app/Contents/MacOS/NotchIsland 2>&1 | grep -E 'env|geometry|pick'
```

## 可选能力：网易云音乐

网易云客户端是 Chromium/CEF 应用，不向系统注册「正在播放」，只能走客户端自带的调试端口（`9222`）读页面状态。打开「允许岛管理播放器」后：

- 岛启动时若发现网易云没在运行，会带 `--remote-debugging-port=9222` 拉起（不激活窗口、不抢焦点）。已经在跑的实例不碰。
- 已运行但没开端口时，主页底行显示「网易云音乐没开调试端口 · 点此重启」。**点了才会重启**，正在播的歌会断一下。
- 调试端口只监听本机回环地址；关闭岛不影响客户端继续运行。
- 客户端改版会改变页面 DOM，选择器集中在 `NeteaseSource.swift`，失效时改那一处。

汽水音乐（`SodaSource.swift`）走同一套 CDP 通道，但 App Store 沙盒版拿不到端口，当前恒为空。

## 主页

没有读到曲目时显示主页（也可以点顶栏房子页签手动切过去）：

- 天气走 Open-Meteo，30 分钟刷新；城市在设置里选。取不到数据时保留上一次成功的值，第二次仍失败则显示占位。
- 日程走 EventKit，只取今天，最多两条，超出折成「还有 N 项」。拒绝授权后只显示「日历未授权」，不重复询问。
- 底行右侧是内存占用与磁盘可用空间（30 秒采样）。

## 文件拖放

拖文件到岛上（光标进刘海时自动展开），松手即执行：

| 落点 | 行为 |
|---|---|
| 左半「隔空投送」 | 用 `NSSharingService` 打开 AirDrop 面板 |
| 右半「文件托盘」 | 复制到应用支持目录，岛内切到托盘场景 |

托盘里的文件：点一下在 Finder 显示，可直接拖到别的应用，底部「清空」全删。

## 项目结构

| 文件 | 作用 |
|---|---|
| `main.swift` | 入口（顶层代码，**文件名不能改**）：找刘海屏、无边框面板、命中检测、拖放事件、右键菜单、宿主装配 |
| `AppSettings.swift` | 偏好层：能力开关、天气城市、锁定状态、引导完成标记 |
| `AppWindows.swift` | 首启引导与设置窗 |
| `AppMenuBar.swift` | 菜单栏图标与菜单 |
| `IslandView.swift` | 岛体容器：尺寸插值、场景切换、指针热区与锁定 |
| `IslandChrome.swift` | 顶栏、页签、图标按钮、收起态波形、圆形封面 |
| `IslandMediaColumn.swift` | 展开态媒体列 |
| `IslandLayout.swift` | 尺寸档位表与顶栏宽度下限 |
| `IslandShape.swift` | 外翻顶角轮廓与边缘描边 |
| `PointerMonitor.swift` | 全局鼠标位置与热区判定 |
| `HomeScene.swift` / `WeatherSource.swift` / `CalendarSource.swift` | 主页视图与天气、日程数据源 |
| `TrayStore.swift` / `TrayScene.swift` / `DropReceiver.swift` | 文件托盘与拖放语义 |
| `SystemStatus.swift` | 电量 / 循环次数 / 内存 / 磁盘采样 |
| `MediaStore.swift` | 三通道聚合、场景开关、进度插值、命令路由 |
| `MediaSources.swift` / `MediaBridge.swift` | 系统通道（MediaRemote）与 osascript 代理通道 |
| `CDPClient.swift` / `CDPPlayerSource.swift` / `NeteaseSource.swift` / `SodaSource.swift` | CDP 通道与各家选择器 |
| `MusicGate.swift` / `PlayerLauncher.swift` | 播放器白名单与带调试端口启动 |
| `NotchGeometry.swift` | 刘海尺寸运行时探测（系统 → 缓存 → 兜底） |
| `AudioActivity.swift` / `ChannelSupport.swift` / `IslandDebug.swift` | CoreAudio 采样、通道共用件、诊断日志 |
| `Info.plist` / `build.sh` / `tools/make-icon.swift` | 元数据、构建脚本、图标生成 |
| `NotchIsland` / `NotchIsland.app/` | 构建产物，不入库 |

新增 `.swift` 文件必须同步 `build.sh` 的 `SOURCES`，否则链接阶段报 undefined symbol。

## 已知限制

- **依赖私有框架** `MediaRemote`：仅源码分发，不能上架 App Store；macOS 大版本升级后符号可能失效，表现为无歌名 / 按钮无反应。失效时不影响其它功能。
- **仅支持带刘海的 Apple Silicon MacBook**：构建目标 `arm64`，`LSMinimumSystemVersion` 14.0。没有刘海时弹提示后退出，不提供菜单栏降级形态。
- **多屏只跟随一块屏**：取第一块有刘海的屏幕；插拔外接屏、改缩放后会自动重算，但不支持同时在多块刘海屏上各画一个岛。
- **网页播放读不到**：需要浏览器开放「Apple 事件执行 JavaScript」，本项目不实现该通道。
- **通知会被系统限流**：因此保留 1.5 秒兜底轮询。
- **AirDrop 需要另一台设备**才能看到实际传输，本机只能确认分享面板弹出。
- **内存 / 磁盘是近似值**：口径接近活动监视器，但不是逐字节相同。
- **无自动更新**：更新靠 `git pull` 后重新 `./build.sh`。

## 参与贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请按 [SECURITY.md](SECURITY.md) 私下报告，不要开公开 issue。变更记录见 [CHANGELOG.md](CHANGELOG.md)。

## 许可证与致谢

- 代码以 **GPL-3.0** 发布，全文见 [LICENSE](LICENSE)。分发修改版时必须一并提供源码。
- 天气数据来自 [Open-Meteo](https://open-meteo.com/)，数据以 CC BY 4.0 提供。
- 图标与界面符号使用 SF Symbols，仅可在 Apple 平台应用中使用。
- 「灵动岛 / Dynamic Island」是 Apple Inc. 的商标。本项目名称与实现均为独立作品，与 Apple 无关联、未获其背书。

## English

NotchIsland is a small macOS utility that lives in the MacBook notch: media controls, weather, today's calendar, and a drag-and-drop file tray. Pure Swift + SwiftUI, no Xcode project, no third-party dependencies.

**Requirements**: macOS 14.0+, a MacBook with a notch (Apple Silicon), Xcode Command Line Tools. Build with `./build.sh`, then `open NotchIsland.app`.

**Privacy defaults**: reading now-playing info (private MediaRemote framework + Apple Events) and managing players (launching clients with a debugging port) are **off by default**. A first-run onboarding explains each and asks for consent; everything can be changed later in Settings. Weather uses Open-Meteo with a fixed city you pick (no location permission, no API key). Calendar access is only requested if you enable it.

**Distribution**: source-only. Builds are ad-hoc signed, not notarized, so there is no double-click installer. If you downloaded a zip, run `xattr -dr com.apple.quarantine NotchIsland.app` once.

**License**: GPL-3.0. See [LICENSE](LICENSE). Weather data by [Open-Meteo](https://open-meteo.com/) (CC BY 4.0). SF Symbols are used under Apple's license, Apple platforms only. "Dynamic Island" is a trademark of Apple Inc.; this project is independent and not affiliated with or endorsed by Apple.
