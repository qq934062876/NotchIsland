# 参与贡献

提 PR 前请先读本文件与 [`AGENTS.md`](AGENTS.md)（实现规则与 UI 硬规）。两者冲突时以 `AGENTS.md` 为准。

## 环境与构建

```bash
xcode-select --install          # 只需要 Command Line Tools
git clone <本仓库地址> && cd NotchIsland
OUT=/tmp/ni/NotchIsland APP_DIR=/tmp/ni/NotchIsland.app ./build.sh
```

- 构建只走 `./build.sh`，不要在仓库里新增 Xcode 工程或包管理依赖。
- 新增 `.swift` 文件必须加进 `build.sh` 的 `SOURCES`。
- 验证产物请用 `OUT` / `APP_DIR` 指到 `/tmp`，不要覆盖仓库内的 `NotchIsland.app`。
- 本项目没有自动化测试，验证口径是「构建退出码 0 + 实际运行观察」。PR 描述里写清你怎么跑的、看到了什么。

## 提交前检查

1. `./build.sh` 通过，且是在最低系统 `MACOS_MIN=14.0` 下通过。
2. 手动跑一遍受影响的功能：展开/收起、页签切换、右键菜单、菜单栏菜单。
3. 没有新增十六进制色值、自定义字体、PNG/SVG 图标；图标只用 SF Symbols（见 `AGENTS.md` 第 3 节）。
4. 文案是中文短句、无感叹号；失败态有明确说明，不出现「什么都没发生」。
5. 诊断日志只在 `NOTCH_DEBUG=1` 时输出，不落盘、不打印文件路径与封面二进制。

## 代码约定

- Swift 语言版本固定 5（`-swift-version 5`），不启用 Swift 6 严格并发。
- `main.swift` 只放入口、面板、命中区与宿主装配；具体能力放对应文件（分层见 `AGENTS.md` 第 4 节）。
- 私有 API 只能出现在 `MediaSources.swift` 的系统通道里，取不到符号必须静默降级。
- 新增播放器：往 `MusicGate.players` 加一行，再补 `CDPPlayerProfile`（CDP）或 `MediaBridge` 脚本（脚本型）；不要在视图里判断 bundle id。
- 新增用户可配置项：加进 `AppSettings`（带默认值），再在设置窗与首启引导里给出说明；需要授权或会打断他人的能力默认关闭。

## 提交信息与 PR

- 提交信息用中文，一句话说清改了什么、为什么；一次提交只做一件事。
- PR 描述包含：问题、改法、验证方式、影响面（是否涉及权限、私有 API、默认值变更）。
- 涉及 UI 的 PR 请附截图或录屏；涉及权限的 PR 请说明首次运行的弹窗顺序。

## 许可证

本项目以 GPL-3.0 发布。提交 PR 即表示你同意以同一许可证分发你的贡献，并确认你有权提交这些代码。
