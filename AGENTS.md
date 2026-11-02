# AGENTS.md — NotchIsland 项目规则

本仓库是 **AI coding 项目**。本文件是本项目唯一的实现规则源：怎么改、怎么验、UI 长什么样算合格、哪些事不许做。面向使用者（怎么构建、怎么运行）的说明在 `README.md`。

本文件面向维护者与 AI 协作者；面向使用者的说明在 `README.md`，协作流程在 `CONTRIBUTING.md`。通用协作规则（结论先行、Git 操作先给方案、不编造结果等）由各人自备，本文件不引用仓库外路径，只写本项目特有内容。

## 0 项目身份

- 定位：AI 承担主要实现，人负责提需求、审阅、验收。
- 事实优先级：**用户当面交代 > 本文件 > 代码现状 > 推断**。四者冲突时停下来说明，不自行取舍。
- 沟通与文档一律中文、结论先行；日期写绝对日期（如 2026-11-02）。
- 规则与代码有偏差时，先指出偏差并给方案，不在「顺手统一」的名义下大改无关实现。

## 1 开工流程

- 动手前先读要改的那段代码（`main.swift`、`MediaStore.swift`），不凭记忆改。
- 结构性改动（调整分层、换实现方式、动 `Info.plist`）先给方案，明确同意再执行。
- 一次只推进一件事；途中出现新需求，先停下确认范围，再回到原任务。
- 改完必须构建验证，并说明「怎么验的、看到了什么」；构建失败贴原始报错，不概括、不编造。
- 不确定就说不确定，不拿推测当结论。

## 2 构建与验证

- 构建只走 `./build.sh`，它已处理 SDK 探测、编译、组装 app 包、ad-hoc 签名。
- **不要手写死 `-sdk .../MacOSX27.0.sdk`**：本机默认 SDK 由 Swift 6.4 构建，而 `swiftc` 是 6.3.3，会报
  `error: failed to build module 'Swift'; this SDK is not supported by the compiler`。脚本已自动回退到 `MacOSX26.5.sdk`。
- 需要覆盖时用环境变量：`SDK=`、`OUT=`、`APP_DIR=`、`SKIP_SIGN=1`。
- 试编译与回归把 `OUT`、`APP_DIR` 指向临时目录（如 `/tmp/ni-verify/`），不覆盖仓库里现有的 `NotchIsland` 与 `NotchIsland.app`。
- 产物 `NotchIsland`、`NotchIsland.app/` 不进版本库；新增任何产物先把路径写进 `.gitignore`。
- 验证口径：**构建退出码 0 + 实际运行观察**（本项目无自动化测试）。能编译不等于功能完成。

## 3 Apple 原生 UI 硬规

原则：像系统自带控件，不做「仿苹果」的自定义皮肤；拿不准就少做。

### 3.1 颜色与材质

- 优先语义色与系统材质：`Color(nsColor: .windowBackgroundColor)` 一类、`.regularMaterial`、`.thinMaterial`。
- 禁止新写十六进制色值或自造调色板；岛体 `Color.black` 是唯一有意例外。
- 透明度只用三档：主信息 `1` / 次级信息 `.white.opacity(0.55)` / 悬停底与轨道 `.white.opacity(0.12)`，不另造灰阶（0.82、0.9 这类中间值已统一回三档）。

### 3.2 字体

- 只用 SF Pro：`.font(.system(size:weight:))`；现用正文 13 semibold、副标题 11、顶栏状态信息 10（电量百分比与循环次数，高度只有 32 的刘海行，放 11 会挤）。
- 会变动的数字（时间、进度）用 `.monospacedDigit()`，避免宽度跳动。
- 不引入自定义字体，不用 `.font(.custom(...))`。

### 3.3 图标

- 只用 SF Symbols：`Image(systemName:)`；现用 `backward.fill`、`pause.fill`、`play.fill`、`forward.fill`、`music.note`；顶栏页签用 `music.note`（选中/未选中同符号，靠不透明度与淡底区分）、`tray` / `tray.fill`、`house` / `house.fill`，锁定用 `lock.fill` / `lock.open`，电量用 `battery.*`（充电态带 `.bolt`）、外接未充时的 `powerplug.fill`；封面占位用 `music.note`；主页用 `sun.max.fill` / `cloud.*` / `snowflake` / `thermometer.medium`；拖放与托盘用 `airdrop`、`tray.and.arrow.down`、`doc.fill`。
- 收起态波形不是图标：4 根 `Capsule` 按相位起伏，不用 SF Symbol 代替（`waveform` 那类符号是静态图，动不起来）。
- 图标与同排文字同档字重（`.semibold`）、视觉尺寸对齐（13pt 文字配 13pt 图标）；顶栏图标 12 配 10pt 状态文字。
- 不拿 PNG/SVG/emoji 当图标；新图标先在 SF Symbols 里找，确实没有再说。

### 3.4 圆角、阴影、描边

- 圆角统一 `.continuous`（连续曲率）：小控件 6–8（图标按钮 7），岛体底部展开 22、收起取 `刘海高 / 3`（32pt 刘海 → 11，换机型按比例走）；右下角的 16pt 音源图标例外取 4，与系统 Dock/图标比例一致。数值集中在 `IslandSizeTable`，不在视图里写裸数字。
- **展开态封面是正圆**（2026-11-03 用户当面要求，覆盖此前「圆角方形」）：`Circle()` 裁剪、播放时以 12s 一圈缓慢旋转，暂停保留角度、恢复续转；外圈只有 `.white.opacity(0.12)` 圆底，无描边无高光。因此不再有封面圆角常量，画布尺寸仍等于 `artworkSide`（44 / 48），圆形直径不另设。
- 顶部两角不是圆角，是**向外翻出的弧度**：顶边比身体宽 2×`topFlare`（展开 8；收起无曲目 0——岛体与刘海等宽时再外扩会盖住菜单栏；收起有曲目 8，否则那 40pt 加宽区的两个顶角是直角方块，2026-11-04 用户要求补回），以右侧为例外弧终点在身体右边界右侧，轮廓由 `IslandShape` 手写路径绘制（`UnevenRoundedRectangle` 表达不了外凸角），见 3.6。
- 岛体投**两层**柔和外投影（2026-11-03 用户当面要求「加强阴影」，覆盖此前「只投一层」的条文）：近层 `.black.opacity(0.40), radius: 5, y: 3` 压实轮廓，远层 `.black.opacity(0.26), radius: 14, y: 8` 拉开与桌面的距离；两层只落在岛背景的纯色形状上，不挂文本与封面；`panel.hasShadow` 仍为 `false`（系统再加一层会重影）。除这两层外不加其它外发光。收起态且没有曲目（岛体贴齐刘海）时投影透明度归零（`shadowStrength`），否则刘海四周会留一圈暗影（2026-11-03 用户要求）。
- 阴影半径必须**明显小于轮廓细节**才不像「四边形」：外翻弧纵向只有 `expandedTopFlare`(8)，模糊半径一旦远超 8，顶部两角与底部 22pt 圆角就被抹平成直边。因此远层半径上限按 14 走，别为「更柔」往回加到 20 以上（2026-11-04 用户反馈「展开后有四边形阴影块」，实测 24 时外沿比近层多出 35pt、岛底一条 573pt 宽的平直暗带）。
- 顶部外翻弧必须在屏幕最上沿可见：背景形状不要再套 `padding(.top, -40)` 把顶角藏到屏幕外，否则弧度在屏幕外、看不见（2026-11-03 踩过）。
- 分隔线仍只用 `.white.opacity(0.1)` 一档；岛体边缘另有一条 1pt **柔化描边**（`IslandEdgeStroke`），但**只有底边一小段**：渐变 stop 在高度 65% 以上全透明（`edgeStrokeVisibleStart`），底部到 `.white.opacity(0.05)`，再 1.1pt 模糊。顶部与两侧必须纯黑——顶部一亮就是「白边」（2026-11-03 用户反馈后收窄，覆盖同日「白 0.16 → 0.05 全程渐变」的条文）。除此一条不加高光、不加第二圈、不用彩色光晕。

### 3.5 动效

- 时长 0.2–0.45s，交互反馈 ≤0.3s。弹出 `.spring(response: 0.34, dampingFraction: 0.82)`，收起 `.spring(response: 0.20, dampingFraction: 0.98)`：收起要更快更干，拖尾会被看成「卡一下」。
- 用 `spring` 或 `.smooth`；位移与尺寸动画不用 `.linear`。
- `dampingFraction ≥ 0.8`，不做夸张过冲。
- **动画只改容器尺寸，内容不跟着重排**：内容按最终档位尺寸排一次版，容器在收起/展开两档之间插值，窄下来的部分靠 `clipShape` 裁掉。这样文本截断、封面裁剪在动画期间零重排，帧率才稳。
- 不用 `.geometryGroup()`：它会让整块子树（含封面图、文本）在动画期逐帧重新栅格化，反而更卡。
- 不用 `if expanded {} else {}` 两套子树：分支切换会销毁、重建视图并使内容随中间宽度逐帧重排。
- 不做逐帧几何回报：命中区域按档位算，只在 `expanded` / `metrics` 变化时上报一次，不要 `GeometryReader` + `PreferenceKey` 挂在动画视图上（等于每帧多跑一次布局）。
- 出场/退场是**缩放 + 淡入**，不再硬切（2026-11-03 用户要求「不要生硬出现或退出」）：`NotchRootView` 用一个 `appeared` 状态驱动顶部锚点的 `.scaleEffect` 与 `.opacity`，入场 `spring(0.42, 0.86)`、退场 `spring(0.24, 0.98)`。起始缩放刻意「横 0.92 / 纵 0.86」——收起态岛正好等于刘海，只缩纵向看不出变化，横向缩才看得见黑块从刘海两侧长出来。上屏首帧必须是透明缩态，`onAppear` 里 `asyncAfter(0.05)` 再置位；与 `orderFrontRegardless` 同一轮 runloop 里改状态会被合成器并成一帧，等于没有动画。透明期 `.allowsHitTesting(false)`，不能截走菜单栏点击。
- 退场由 `IslandExit` 统一协调：右键「退出灵动岛」先播收回动画，0.26s 后（与退场 spring 的可见时长对齐）才 `NSApp.terminate`。直接 terminate 会让岛「啪」地消失。其它退出路径（SIGTERM、系统注销）不拦——拦了要走 `terminateLater`，处理不当会让注销卡住。
- 进场/退场的位移与缩放都由 `.opacity` 与 scale 表达，不做位移动画（岛贴屏幕顶，往下挪会露出缝隙），位移类过渡幅度仍 ≤12pt。
- 图标按钮统一用 `IslandIconButton`：悬停加一层 `.white.opacity(0.12)` 圆角底（`.smooth(0.16)`），按下 `scale 0.92` + `opacity 0.72`（`spring(0.22, dampingFraction: 0.82)`）；减弱动态效果打开时退化为 0.01s 线性。按钮一律用 `Button` + `IslandPressStyle`，不用 `onTapGesture`，否则拿不到按下态。
- 进度条悬停由 3pt 加粗到 4pt（`.smooth(0.16)`），拖动期间只改预览比例，松手才下发 seek；轨道 `.white.opacity(0.12)`、填充 `.white.opacity(0.55)`。收起态不再有进度线（2026-11-03 删除），进度只在展开态出现。
- 页签的选中/悬停走 `IslandIconButton` 的 `.smooth(0.16)`；切页只做内容淡入 `.smooth(0.2)`，岛体宽高不变，不跑尺寸插值（三个场景同宽同高）。
- **没有曲目就整块不出现，不再有通用音频态**（2026-11-03 用户当面要求「原来其他音频播放的效果去掉」）：读不到歌名时既不摆应用图标、也不写「正在播放音频」、不拿波形占位，连音乐页签都不画（见 3.6 页签规则）。因此媒体列只有一种形态——封面 + 歌名 + 歌手 + 三枚控制键 + 进度行，不再需要「同宽占位」来避免标题截断位置跳动。
- 收起态波形与封面旋转都靠 `TimelineView` 的 `paused:` 停表，**不用 `.repeatForever`**：后者停不下来，恢复还会跳回 0°。波形 0.05s 一次、封面 0.05s 一次，都只改矩形高度与图层旋转，不触发文本或容器重新布局；收起、暂停、减弱动态效果时各自停表。

### 3.6 尺寸档位与布局

- **尺寸提前定好，不跟内容走**：展开宽度由档位表给定，文字超长靠 `lineLimit(1)` + 截断处理。禁止 `minWidth`、禁止按内容自适应宽度。
- 取档三步：宿主应用 bundle id 精确匹配 → 逐段去掉末尾的前缀匹配（兜住 `com.apple.Safari.WebContentProcess` 一类变体）→ 未命中回落场景默认档。因此来源未知（未播放、私有符号取不到、表外应用）时宽度同样固定，不抖。
- 档位表在 `IslandLayout.swift` 的 `IslandSizeTable`：新增应用只加一行 `bundle id: IslandMetrics(宽, 封面边长)`，不改布局代码；新增场景（通知、进度）先加 `IslandScene` 分支，再给该场景一个默认档。
- 展开高度不单独配，由档位推导：`刘海高 + 18 上留白 + 封面边长 + 8 行间距 + 28 进度行 + 20 下留白`；要调高度就调 `expandedTopPadding` / `expandedBottomPadding` / `progressRowHeight`。进度行高度是常量，空态也占位，展开高度不随有无内容变化。
- 当前档位（2026-11-03）：

| 场景 | 宿主应用 | 岛体总宽 | 封面 |
|---|---|---|---|
| media | 默认（来源未知） | 448 | 44 |
| media | Apple Music `com.apple.Music` | 448 | 44 |
| media | 播客 `com.apple.podcasts` | 448 | 44 |
| media | Spotify `com.spotify.client` | 448 | 44 |
| media | 网易云音乐 `com.netease.163music` | 448 | 44 |
| media | 浏览器（Safari / Chrome / Edge / Firefox） | 456 | 48 |
| home | 恒定（无音频软件在播） | 448 | 44 |
| files | 恒定（刚收进托盘） | 448 | 44 |

- 主页与托盘刻意与媒体默认档同宽同行高：切场景不改尺寸，岛体不跳一下；内容区高度仍是 `封面边长 + 8 + 28`。
- 托盘内容区两条可见条目：行高 `trayRowHeight`(20) + 间距 `trayRowSpacing`(4) + 20 = 44，正好等于封面行；第 3 条起折进底部一行「还有 N 个」，不新增高度、不留溢出。
- 场景切换（2026-11-03 二次改版）：页签由 `IslandScene.tabs(hasMusic:)` 生成——读到曲目时是音乐 / 文件 / 主页三枚，读不到时**只有文件 / 主页两枚**，音乐页签整枚不画。判定唯一依据是 `MediaStore.hasMusic`（白名单播放器读到曲目，暂停也算），与「谁在出声」无关：浏览器、视频、会议出声既不进音乐页也不影响页签。没固定页时，`hasMusic == true` → 音乐页，`false` → 主页（启动时按 `hasMusic` 判一次）；固定后不再自动跳（用户自己选的页就留着），但 `hasMusic` 转 false 且停在音乐页时**必须**回主页（页签已消失，停着只会看到空列）。点过音乐页再暂停仍停在音乐页，显示「未在播放」。
- 宽度下限保护：`max(档位宽, 向上取 4 的倍数(刘海宽 + 2 × (max(左簇最小宽, 右簇最小宽) + 14)))`。左簇按最多三枚 28pt 页签算 = 三个页签 + 两个 4pt 间距 = 92（没有音乐时只画两枚，实际更窄，但下限仍按 92 算，岛体宽度不因此变化）；右簇 = 锁定 28 + 4 + 电量簇约 123（电池 26 + 百分比 30 + 插头 15 + 三个间距 12 + 两位循环次数 36）= 155。**左右两簇不能相加**——每侧的可用空间都是 (总宽 − 刘海宽)/2，相加会把右侧簇挤进刘海下面。本机刘海 179pt → `179 + 2 × (14 + 155) = 517` → 向上取 4 的倍数 **520**，所以当前所有场景实际都是 520（档位表里的 448 / 456 只作表意，被下限抬平），顶栏宽度只由刘海尺寸决定、不随内容变。
- 展开态顶栏（`IslandTopBar`，高度 = 刘海高，左右内边距 14、簇内间距 4）：**左上 28×28 页签，最多三枚**（音乐 `music.note` / 文件 `tray`·`tray.fill` / 主页 `house`·`house.fill`；读不到曲目时音乐那枚不画，见 `IslandScene.tabs(hasMusic:)`；选中实心 + 常驻 `.white.opacity(0.12)` 淡底，未选中描边变体 + 降到 0.55 白、只在悬停出淡底）；**右侧顺序为锁定 → 电量簇**，电量簇 = 电池符号（充电时带 `.bolt`）+ 百分比 + `循环 N` + 外接未充时的 `powerplug.fill`。中间靠 `Spacer` 让开物理挖孔，两侧信息不得压进刘海；循环次数是唯一可截断项（`lineLimit(1)` + 尾部省略），其余项固定宽度，不允许把岛体撑开。
- 顶栏只在展开态显示（随内容整体 `opacity`），收起态是纯黑刘海块 + **左音源图标 / 右跳动波形**（2026-11-03 取代原来的 2pt 进度线）。
- 右下角 `AppIconView` 固定 16×16 占位：有音源时显示该应用图标，无音源时透明但仍占位，进度条宽度不跳。

- 新增档位约束：宽度 320–560 且为 4 的倍数；封面 40–48；超范围先讨论。
- 档位切换（换播放源）用弹出那条 spring（0.34 / 0.82）；收起另用更快的一条，不跳变。
- 收起态**默认与物理刘海等大**：宽 = 刘海宽、高 = 刘海高、`collapsedTopFlare` 为 0、不投投影（2026-11-03 用户要求「默认状态灵动岛和刘海大小一致」，覆盖此前「收起宽度固定 259」的条文）。只有 `store.hasMusic` 为真（读到曲目，暂停也算）时才加宽 `collapsedExtraWidth`(**40**，每侧 20，右 20 装波形 + 左右各 1pt 余量)，本机 179 → 有曲目 **219pt**，此时顶角同步外翻 `collapsedMusicTopFlare`(8)，与展开态同一弧度（2026-11-04 补，见第 3.4 节）。这一档不进档位表，加宽/收窄跟收起那条更快的 spring。
- **刘海尺寸运行时探测，不写死机型**（2026-11-03）：`NotchSpecResolver`（`NotchGeometry.swift`）用 `safeAreaInsets.top` 取刘海高、`auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 夹出刘海宽，缩放分辨率与换屏都由系统换算好，因此不需要「机型 → 尺寸」白名单；系统暂时给不出宽度（全屏、菜单栏自动隐藏）时退到本机缓存 `notchSpec.<displayUUID>`（附带当时的屏幕点尺寸，换过缩放就不认），最后才按 `刘海高 × 5.3` 推一个**偏窄**的兜底宽度（宁可窄不可宽：宽出来每侧都会盖住菜单栏图标）。启动日志 `[env]` 会打 `model=… notch=WxH source=system|cached|fallback|override`，换机器先看这一行。调试可用 `NOTCH_DEBUG=1 NOTCH_SPEC=200x38` 模拟别的机型。收起状态下圆角、波形柱高与面板尺寸都由这套几何推导。
- 收起态状态条（`CollapsedStatusBar`）挂在容器上、不参与内容布局：左槽留空（2026-11-03 用户当面要求，不再显示音源图标），右槽 `collapsedStatusSideWidth`(20) 放波形（18pt 宽，距岛体边缘 1），中间 `Spacer` 让开物理刘海；**暂停时仍显示**压平的波形，完全没有播放内容才整条 `opacity 0`（`hasMedia`）并同时收窄回刘海宽。波形 = 4 根 3pt 柱 + 2pt 间距（共 18pt），柱高按刘海高缩放（32pt 刘海 → 4–14），播放中才动。
- 波形是**拍点模拟**，不是真实振幅（2026-11-03 用户确认此版）：0.52s 一拍（≈115 BPM），每拍起音线性冲顶、之后指数回落，拍间停在 `idleRatio` 底线；每拍每柱的峰值用拍号哈希错开，柱间只错开 `skew`(0.04 拍)，看起来是「被一拍打起来」而不是一条从左跑到右的波。真实振幅要 Core Audio process tap + 系统音频录制授权，本轮明确不做。
- 波形参数全部在 `IslandSizeTable`：`collapsedWaveBeatPeriod` / `Attack` / `Decay` / `IdleRatio` / `Skew` / `RippleHz`；改手感只动这几个值，不动公式。
- 收起态那 40pt 加宽区（仅在有曲目时出现）**只展示、不拦截点击**：容器显式 `.allowsHitTesting(false)`，`islandRect` 收起态仍只认物理刘海。所以光标停在收起态波形上不会展开岛（设计如此，见 3.9）。
- 外翻顶角的参数（`expandedTopFlare` 8 / `collapsedTopFlare` 0 / `collapsedMusicTopFlare` 8）不能大于单侧余量与半高：`IslandShape` 内部已按 `min(w/3, h/2)` 收口，但调大前先确认收起态不越过刘海黑块（`collapsedMusicTopFlare` 不超过 `collapsedExtraWidth / 2` = 20，也别超过刘海高一半 16）。
- 间距取 4 的倍数（现有 22 / 18 / 12 / 14 / 44 保留；行内文字微调可用 2）；点击热区不小于 28×28，控件之间留 ≥8 空隙。
- 对齐沿用现状：整体贴屏幕顶部居中，内容从刘海下方开始（`padding(.top, notchHeight + 18)`）。

### 3.7 文案

- 必须有空态与失败态文案。现用：「未在播放」「打开网易云或音乐试试」（暂停时也走这两条，页签仍在，可点播放继续）。
- 读不到曲目时**不出现任何失败文案**：没有音乐页签、没有通用音频态、没有「多个音频软件」提示，整块消失并回主页（2026-11-03 用户选择「不支持就忽略」）。浏览器网页歌、视频、会议软件因此天然不占位。唯一例外是「客户端在跑、但调试端口没开」——这种状态下一个字节都读不到，用户又看不出原因，所以在主页底行给一行可点提示（见本节最后一条）。
- 主页：「今日无日程」「日历未授权」「日历未开启」「正在读取日历」「今天没有更多日程」「天气读取中」，天气块第二行是「珠海 22° / 29°」（城市常驻 + 今日高低温，城市名取 `weather.cityName`，跟随设置里的城市），天气没取到时这一行只留城市名；底行天气行显示「毛毛雨 · 100% · 日落 17:47」（现象 / 今日降水概率 / 日落时刻）。主页第一行是日程引导：「进行中 周会」「25 分钟后 周会」「2 小时后 周会」「全天 出差」，标题走 11pt 次级白，右端是「还有 N 项」；底行右侧是「内存 62% · 磁盘 389G」（30s 采样，取不到就不画）。**日期与星期已移除**（2026-11-04 用户要求：与菜单栏重复），不要再加回来。
- 托盘：「拖文件进来暂存」「拖到别处即可取出」「还有 N 个 · 拖到别处即可取出」「最多 8 个」「单个不超过 200MB」「N 个复制失败」。
- 托盘不提供单条删除：行高只有 20，塞一个 28×28 的删除热区会压掉相邻条目；需求只要求拖出、Finder 显示、一键清空。
- 顶栏页签的中文名固定为「音乐」「文件」「主页」（`IslandScene.tabTitle`），同时作为 `accessibilityLabel`；文件名不另起别名，避免口语与文案两套叫法。
- 失败态只有一种给入口的情况：**客户端在跑，但没开调试端口**。主页底行画「网易云音乐没开调试端口 · 点此重启」，点了才带端口重启（`MediaStore.fixMusicPort`），途中显示「正在重启网易云音乐…」并禁用重复点击，失败显示「重启网易云音乐失败 · 点此重试」。除此之外读不到内容一律整块不显示、不提示、不自动重启播放器（2026-11-03 用户第二次改口，推翻当日上午「绝不提示、绝不杀进程」的条文，依据见变更记录）。这行占的是底行天气位，读到曲目后立刻换回天气。
- 中文短句，不加感叹号，不堆客套词；术语与系统一致（「正在播放」「播放中」）。

### 3.8 可访问性

- 正文与背景对比度 ≥ 4.5:1；纯黑底白字，次级文字透明度不低于 0.55 的量级。
- 尊重系统「减弱动态效果」「增强对比度」：新增动效要能被关掉，不靠颜色单独表达状态。
- 「减弱动态效果」用 `@Environment(\.accessibilityReduceMotion)` 读取，不要写成启动时求值的全局常量——那样用户在系统设置里开关要重启 app 才生效（2026-11-03 改）。
- 减弱动态效果打开时：收起态波形静止在基线、封面**角度归 0**（只停表会让封面卡在某个随机角度，看着像转坏了）、切页与展开动画退化成 0.12–0.16s 的 `smooth`。
- 图标按钮的含义由 SF Symbols 名称承担，不自造图形代替语义。

### 3.9 窗口与面板

- 不抢焦点：`canBecomeKey = false`、`canBecomeMain = false`、`styleMask` 含 `.nonactivatingPanel`、`setActivationPolicy(.accessory)`。
- 岛外点击穿透：`hitTest` 只认 `islandRect`，其余返回 `nil`。展开态用展开尺寸 + 4pt；**收起态只认物理刘海本身**（不加宽、不外扩），否则岛比刘海宽 40 的那部分会吃掉菜单栏左右两侧的点击（2026-11-03 用户反馈「点不到正常文本按钮」）。
- 收起态的内缩量用 `IslandSizeTable.pointerInset`(2)，**指针热区与点击命中区必须同一个常量**：两处各写一个数就会出现「光标已经把岛顶开、点下去却穿透」。
- 展开判定不走 `onHover`：`onHover` 的命中范围等于收起态容器（有曲目时比刘海宽 40），光标路过菜单栏就展开。改由 `PointerMonitor` 读全局鼠标位置，热区 = 物理刘海矩形内缩 `pointerInset`；展开后热区换成整块面板**并把外翻弧算进去**（宽 = 身体宽 + 2×`expandedTopFlare`），光标下移进面板不会立刻收起；离开改为每 0.12s 采一次、连续 3 次（≈0.36s）都在宽容热区外才收，拖拽时不闪。停留判定用外扩 6pt 的宽容热区、进入判定仍用原始热区，避免光标贴边抖动导致「收起又打开」。
- 拖放走 AppKit：`PassthroughView` `registerForDraggedTypes([.fileURL])`，`draggingEntered/Updated/Exited/performDragOperation` 转发给 `DropReceiver`；左半（x < 岛中线）隔空投送，右半进托盘。拖拽期间系统不发 `mouseMoved`，但 `mouseDragged` 带位置，热区判定照常工作。
- 右键菜单在 `PassthroughView.rightMouseDown`，用 `NSMenu` + `popUpContextMenu`，不用 SwiftUI `.contextMenu`（面板不是 key window，SwiftUI 手势在非激活面板上拿不到稳定事件路由）。当前三项：`退出灵动岛` / `锁定不弹出` / `解除锁定不弹出`，后两项互斥——只把当前不成立的那一项置灰（`menu.autoenablesItems = false` + 手写 `isEnabled`，否则默认按 `validateMenuItem` 判、两项都会常亮）。锁定状态放 `IslandLock.shared`（与 `IslandExit` 同放在 `IslandView.swift`，字段名 `blocksAutoExpand`）：右键菜单在 AppKit 层、顶栏锁按钮在 SwiftUI 层，两处必须改同一份状态；展开与否仍只由 `NotchRootView` 的 `onChange(of: lock.blocksAutoExpand)` → `syncExpansion` 一条路径决定，不要在菜单 action 里直接调展开。
- **「锁定不弹出」= 禁止悬停自动展开，不是「锁定后常驻展开」**（2026-11-04 用户当面纠正，覆盖同日早些时候「锁定后鼠标移开也保持展开」的条文，两者不是一个功能）：展开唯一条件写成 `pointerInside && !blocksAutoExpand`；锁定瞬间若岛是展开的，由 `onChange` 就地收起并停在收缩态，此后光标进出一律不弹，解锁后要重新悬停才会再展开（光标还在岛上则当场展开）。锁定期间没有其它展开入口（收缩态不认点击），只能右键或顶栏锁按钮解锁，因此右键菜单必须保持对收缩态刘海可点（见上一条命中区规则）。
- **`NSHostingView` 是 flipped 坐标（y 从上往下）**：`islandRect` 必须以 `y = 0` 为顶边。写成 `bounds.height - h` 会把热区挪到窗口底部，表现是按钮点不动、而窗口下方大片空白挡住别的应用（2026-11-03 踩过，合成点击日志里 `hitTest inside=false` 可一眼看出）。
- 层级保持 `NSWindow.Level.mainMenu + 1`，不随意抬高（会盖住系统弹窗）。
- `collectionBehavior` 保持 `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`。
- **窗口开够用就好，尺寸由刘海几何推导**（2026-11-03 由写死 640×240 改）：`winW = 最宽档位宽 + 2 × windowMargin(40)`、`winH = 展开高度 + windowMargin`，本机 179×32 → **600×194**；不要用远大于岛体的窗口，透明图层面积每帧都要合成。改档位上限（560）、`windowMargin` 或换机型时核对 `main.swift` 的 `panelFrame`。
- 不画自定义标题栏与红黄绿按钮：这不是普通窗口，别加 macOS 窗口装饰。

## 4 Swift 代码规则

- 语言版本固定 5（`-swift-version 5`），不擅自启用 Swift 6 严格并发。
- `main.swift` 文件名不可改：入口是顶层语句，改名会破坏 `swiftc` 的 main 识别。
- 职责分层：`main.swift` 只放刘海探测、`NSPanel`、命中区（含右键菜单：退出 / 锁定 / 解锁）与宿主装配；`IslandView.swift` 放岛体容器（尺寸插值、裁剪、场景分发、hover 与锁定）；`IslandMediaColumn.swift` 放展开态媒体列（封面/标题/控制键/进度，只读 `MediaStore`）；`IslandChrome.swift` 放顶栏、页签、图标按钮、音源图标、收起态状态条（含波形）与圆形封面等装饰件（只接参数、不读 `MediaStore`）；`SystemStatus.swift` 放电池采样与内存 / 磁盘采样；`MediaStore.swift` 放状态聚合、进度锚点与命令路由；`MediaSources.swift` 放系统直连通道与快照类型；`MediaBridge.swift` 放 osascript 代理通道（脚本常量、子进程、超时与退避）；`MusicGate.swift` 放白名单与「是否有音乐 / 多家选谁」的纯判定；`CDPClient.swift` 放 CDP 协议层（找 target、连接、`Runtime.evaluate` 收发、超时）；`CDPPlayerSource.swift` 放配置驱动的 CDP 播放器源（解析、封面缓存、退避、端口三态）；`NeteaseSource.swift` / `SodaSource.swift` 只放各家端口的 `CDPPlayerProfile`（选择器常量 + 类壳）；`PlayerLauncher.swift` 放「带调试端口启动 / 重启客户端」的进程操作。新能力按此归位，不往顶层堆逻辑。
- 私有 API（MediaRemote）只出现在一处：`MediaSources.swift` 的系统直连通道（`dlopen` 探测 + 可选链降级）。取不到符号就静默停用该通道，不崩、不弹窗。
- **播放数据源三条，由 `MediaStore` 聚合**：系统直连（MediaRemote，老系统快路径，本机 macOS 26 恒空）、osascript 代理（macOS 15.4+ 直连被系统拒绝后，由脚本宿主读播放器自带脚本字典，控制也走它）与 CDP（`CDPPlayerSource` 子类，走 Chromium/CEF 客户端自带的调试端口）。三条并行采，**只收白名单应用**的结果，再交给 `MusicGate.select` 选唯一一家：正在播放的优先，同级取启动时间（`NSRunningApplication.launchDate`）最新的一家；都只是暂停时取有曲目且最后打开的一家。读不到就回落空态，**不保留上一条旧数据**。
- **白名单集中在 `MusicGate.players`**（现网易云 `com.netease.163music`、汽水音乐 `com.soda.music`、Apple Music、Spotify），加一家只加一行 + 在对应通道文件里补配置。白名单之外的应用（浏览器、优酷/爱奇艺、会议软件）**连核心判定都进不去**：系统通道读到它们的快照也一律丢弃，不显示、不占位、不提示。
- **代理通道只认带脚本字典的播放器**（现 `com.apple.Music` / `com.spotify.client`，表在 `MediaBridge.scriptableApps`），读曲目、播放态、位置、封面，控制与 seek 也发同一家；表外软件一律返回空快照。新增一家先确认它真的有脚本字典或等价可读通道，再往表里加一行。子进程贵（约 0.1s），因此一轮轮询只在「这家正在出声 / 它就是当前音源（6s 一次）/ 每 10 拍静默发现（15s 一次）」三种情况下 spawn，静默时零 spawn。
- **代理里不要再试 MediaRemote**（2026-11-03 本机 macOS 26 逐条实测）：`NSBundle.bundleWithPath` 必须传 `.framework` 目录（传内部二进制返回 `undefined`）；`ObjC.bindFunction` 绑出来的函数挂在 `$` 上而不是全局；queue 传 `nil` 会 SIGSEGV（`139`），改用 `dispatch_get_global_queue` 后回调能到，但 JXA 把 JS 函数桥成的 block 是**零参数**（`arguments.length == 0`），字典传不进 JS，用块类型编码 `@?<v@?@>` 直接 SIGTRAP（`133`）。结论：osascript 读不到 Now Playing 字典，别再花时间。
- 同一家被多条通道同时读到时按 bundle id 去重，取「有时长且可 seek」的那条（信息更全）：`MediaStore.whitelisted` 负责过滤与去重，不再有「多家同时出声就谁都不读」的闸门。
- 网易云这类 Chromium/CEF 客户端不注册 Now Playing，只能走 CDP。**不做依赖用户改系统/浏览器开关的通道**（2026-11-02 已否决浏览器 AppleScript 通道，需用户开 Chrome「允许 Apple 事件执行 JavaScript」）；也不用窗口标题、AX 树那类实测取不到值的路径。
- CDP 分三层：`CDPClient` 只管协议（`/json/list` 取 target、WebSocket、`Runtime.evaluate`、1.2s 单请求超时、`teardown` 清未决回调）；`CDPPlayerSource` 管通用逻辑（探针结果解析成 `NowPlayingSnapshot`、封面按 URL 缓存、5s→60s 退避、`onChange`）；`NeteaseSource` / `SodaSource` 只声明 `CDPPlayerProfile`（端口 + `probeJS` / 控制 JS）。改版只改各家的 `*JS` 常量（现测版本网易云 3.1.12）。
- **CDP 的空态不算故障**（2026-11-03 修）：`Runtime.evaluate` 有回包、但页面没有曲目时 value 是空串，属正常空态，只有「无回包（超时 / 连接断开）」才计入失败退避，且空态要重置退避计数。原实现把空串也当失败，退避涨到 60s 后开始播放要等窗口走完才恢复，期间界面掉成空态、`activeSource` 退回 `.system`，点播放键发给了系统通道，表现就是「放歌了没反应、控制也失效」。
- **封面下载失败不等于通道故障**：网易云封面走 `p*.music.126.net`，被运营商/路由器类设备拦截时（302 到 `1.1.1.3/disable`，HTTPS 证书校验同样不过）必然取不到图，界面回落占位图标即可，不重试、不报错。
- 拉起与重启（2026-11-03 用户第二次改口，推翻当日上午「不支持就忽略」）：
  - **岛启动时**：带 `preparesPortOnLaunch` 的客户端（现只有网易云）若没在跑，由岛以 `--remote-debugging-port=9222` 拉起（`PlayerLauncher.launch`，`activates = false` 不抢焦点）；已经在跑的实例**绝不碰**，不打断正在播的歌。
  - **已在跑却没有端口**（用户手动退出后又从 Dock 打开）：主页底行给可点入口，点了才 `terminate` → 等进程真的退出（3s 不退才 `forceTerminate`）→ 带端口重新拉起（`PlayerLauncher.restart`）。必须等旧进程消失：`open --args` 碰到已存在的实例只会激活旧窗口、参数被丢掉。
  - 除这条路径外**永不终止播放器进程**，也不做「自动重试播放器」。
  - 汽水音乐的 `preparesPortOnLaunch` 保持 false：MAS 沙盒版会丢掉 argv，带参数启动只是白多开一个窗口。
- 失败静默 + 退避：5s 起翻倍到 60s 上限，不刷日志、不弹窗；请求一律带超时，未决回调在 `teardown` 里清空，防止回调打到已销毁对象。
- 外部进程调用（现用 `/usr/bin/osascript -l JavaScript`）一律带超时、失败静默、连续失败退避：脚本先落到临时文件再执行，3.5s 未退 `terminate()`、再 0.3s 未退 `SIGKILL`；管道必须在启动后立刻排空（封面 base64 会超过管道缓冲，否则子进程写阻塞、只能被误杀）；失败按 5s→10s→20s→40s→60s 退避，封顶 60s 但不永久关停（否则一次冷启动超时会让本次运行再也读不到内容）。空快照是正常状态，不算失败。首次授权弹窗不能拖死轮询。
- 注释中文，解释「为什么」和取值来源，不复述代码字面；文件头保留一行构建命令。
- 单文件超 400 行考虑拆分：`IslandView.swift` 已按「容器 / 媒体列 / 场景分发」拆出 `IslandMediaColumn.swift`（330 / 179 行）、`NeteaseSource.swift` 已按「通信 / 选择器 / 缓存」拆成 `CDPClient` + `CDPPlayerSource` + 各家配置（190 / 124 / 网易云约 100 行，全部达标）、`main.swift` 208、`IslandChrome.swift` 360（装饰件仍在一档，未过线）。拆分要同步 `build.sh` 的 `SOURCES`。新模块直接建新文件，不再往 `main.swift` 里加。
- **两条播放通道的退避与封面缓存共用 `ChannelSupport.swift`**（`ChannelBackoff` / `CoverCache`）：规则写两份必然漂移（一边改成 3s 起步、另一边不动，同一首歌换条通道就换一套刷新节奏），所以 5s→60s 退避、封顶不永久关停、URL 变了才下载、下载完回主线程写图 + `onChange` 这些只写一份；通道各自只留自己的状态（`inFlight`、`artworkTitle`）。
- 电池数据只走 IOKit：充电态用 `IOPSCopyPowerSourcesInfo`，百分比要按 `kIOPSCurrentCapacityKey / kIOPSMaxCapacityKey` 折算（快照给的是一对容量值，不是 0–100），循环次数读 `AppleSmartBattery` 的 `CycleCount`（取不到再读 `BatteryData.CycleCount`）。独立 20s 定时器，不并入 1.5s 播放轮询，`deinit` 里 `invalidate`；读不到就整条隐藏，不弹窗。
- 应用图标按 bundle id 缓存（`AppIconCache`），只在 `bundleID` 变化时用 `NSWorkspace` 解析一次，不在每轮采样里取图。
- 新 API 先确认在 `LSMinimumSystemVersion`（14.0）之上可用；构建目标由 `build.sh` 的 `MACOS_MIN` 固定为 14.0，本机 SDK 版本高于它不代表能直接用新 API。
- 需要系统授权、或会启动/终止其它 App 的能力必须默认关闭，开关进 `AppSettings`，并在首启引导与设置窗两处说明；未开启时不得弹授权框、不得 spawn 子进程。

## 5 性能与资源

- `MediaStore` 的 1.5s 轮询是兜底（通知会被系统限流），不提高频率；确要改先说明代价。
- 封面只在 URL / `artworkData` 变化时下载解码（现做法），不在每次刷新或每帧里 `NSImage(data:)`。
- 进度流畅靠插值不靠加采样：1.5s 采样只写锚点（秒数 + 采样时刻），界面用 `TimelineView(.animation(minimumInterval: 0.25, paused:))` 在进度条子视图内部插值，不新建全局 Timer、不触发岛体重新布局。**三个 `TimelineView` 都要带 `paused:`**（进度条 `!expanded || !store.isPlaying`、波形 `!isPlaying`、封面 `!isPlaying || !expanded || reduceMotion`）：停表比「画了再藏起来」省得多，收起态也不该按 4Hz 重排隐藏的文字。
- 主线程不做重活，UI 更新回主队列。
- 新增 `Timer`、`NotificationCenter` 观察者、`dlopen` 句柄必须在 `deinit` 或退出路径释放，不留悬挂回调。
- 常驻资源保持「菜单栏级别」的轻量：不为小功能引入后台线程池或大依赖。

## 6 Git 纪律

- 只本地提交；不加 remote、不推送、不打 tag，除非用户明确要求。
- 一事一提交：一次提交不要混「功能改动 + 无关格式化」。
- 提交信息中文一句话说清改了什么，必要时下一行补原因。
- 禁止 `reset --hard`、force push、rebase 改历史；要回退先给方案。
- 产物不进库；新增产物先更新 `.gitignore` 再提交。
- 提交前核对 `git status`：只应出现本次预期的文件。

## 7 红线

- 不引入第三方依赖（SPM 包、CocoaPods、Homebrew 工具都不行），保持零依赖；确有需要先征求同意。
- 不改 `CFBundleIdentifier`（`local.notch.island`）、`CFBundleExecutable`、`LSUIElement`，除非需求明确要求。
- 不上架、不做分发签名与公证配置，仅本机自用。
- 不把密钥、token、内网地址写进仓库或文档。
- 不删、不覆盖用户既有产物（`NotchIsland`、`NotchIsland.app`）与未提交改动。
- 不为「看起来更炫」加功能：当前范围是「媒体播放 + 主页（天气/日程/内存磁盘）+ 文件拖放」，通知与多屏适配留给后续阶段；新场景先讨论再加。

## 8 现状速查

| 文件 | 职责 |
|---|---|
| `main.swift` | 刘海命中检测、`NSPanel`、点击穿透、拖放事件入口（`NSDraggingDestination`）、宿主装配 |
| `IslandView.swift` | 岛体容器：两档插值、场景切换（媒体/主页/托盘）、指针热区与锁定、阴影与外翻轮廓 |
| `IslandMediaColumn.swift` | 展开态媒体列：封面/通用态应用图标、标题/副标题、控制键/波形占位、进度与状态行（只读 `MediaStore`） |
| `IslandShape.swift` | 外翻顶角轮廓（手写 `Path`）与边缘柔化描边 |
| `PointerMonitor.swift` | 全局鼠标位置 → 热区判定；进入严格、停留外扩 6pt、离开 0.12s×3 连续确认；热区缩小但光标仍在旧热区时保留展开 |
| `AudioActivity.swift` | CoreAudio 进程级采样：谁在往输出设备写音频（按 app 去重）；进程列表与 IsRunningOutput 属性监听，起播即触发采样 |
| `HomeScene.swift` | 主页：天气块、日程引导（进行中 / N 分钟后）、今日日程（最多 2 条）、底行的天气详情与内存磁盘、「客户端没开调试端口 · 点此重启」提示 |
| `WeatherSource.swift` | Open-Meteo（城市取设置里的预设坐标）：30 分钟刷新、WMO 代码 → SF Symbol、降水概率与日落 |
| `CalendarSource.swift` | EventKit 今日日程：首次请求完整访问，拒绝则降级；另发布进行中 / 下一条 |
| `DropReceiver.swift` | 拖放语义：左右落点、AirDrop 调用、托盘列表发布、落点提示视图 |
| `TrayStore.swift` | 文件托盘落盘、追加、清空（Application Support，常驻）；复制在后台、`items` 只在主线程写 |
| `TrayScene.swift` | 托盘场景：两条可见条目（20+4+20）、拖出、Finder 显示、清空 |
| `IslandChrome.swift` | 展开态顶栏（音乐/文件/主页页签、锁定、电量/百分比/循环/充电态）、图标按钮样式、右下角音源图标、收起态状态条与波形、圆形旋转封面 |
| `SystemStatus.swift` | 电池状态：IOKit 电量与充电态、`AppleSmartBattery` 循环次数、20s 低频刷新；另含 `SystemMetricsMonitor`（内存占用 + 磁盘可用，30s） |
| `MediaStore.swift` | 三通道并行采样与白名单过滤（`hasMusic` 是唯一场景开关）、多通道去重、进度锚点插值、命令路由（按音源发往系统/代理/CDP）、音源图标缓存 |
| `MediaSources.swift` | 系统直连通道（MediaRemote）+ 通用播放快照与命令类型（`PlaybackSourceKind.cdp(bundleID)` 用于多家 CDP 路由） |
| `MediaBridge.swift` | osascript 代理通道：各播放器脚本字典的 JXA 脚本常量、子进程超时与存活、封面三路（图/URL/同曲复用）、命令下发 |
| `ChannelSupport.swift` | 通道共用件：`ChannelBackoff`（5s→60s 退避、正常回包清零）与 `CoverCache`（按 URL 缓存封面、换 URL 才下载、下载完回主线程写图） |
| `MusicGate.swift` | 白名单播放器表、`isPlayer`、`runningPlayers`（含 `launchDate`）、`select`（正在播放优先、同级取最后打开） |
| `CDPClient.swift` | CDP 协议层：`/json/list` 找 target、WebSocket、`Runtime.evaluate` 收发与 id 匹配、1.2s 超时、`teardown` |
| `CDPPlayerSource.swift` | 配置驱动的 CDP 播放器源：解析探针 JSON 成快照、复用 `ChannelSupport` 的退避与封面缓存、`onChange` |
| `NeteaseSource.swift` | 网易云 `CDPPlayerProfile`：端口 9222 与页面选择器（footer 标题/作者、range 进度、播放态、封面规整、指针事件 seek） |
| `SodaSource.swift` | 汽水音乐 `CDPPlayerProfile`：MAS 沙盒版实测拿不到调试端口，恒返回空快照；探针走 mediaSession + `<audio>`，上下首不做 |
| `PlayerLauncher.swift` | 带 `--remote-debugging-port` 启动 / 重启客户端：岛启动时补端口、主页提示被点时先等旧进程真退出再重拉 |
| `IslandLayout.swift` | 尺寸档位表：场景默认档、宿主应用覆盖档、布局常量与取档函数 |
| `NotchGeometry.swift` | 刘海宽高与所在屏幕 frame（`ObservableObject`）：屏幕参数变化后热区/命中区跟着重算 |
| `IslandDebug.swift` | 诊断日志：`NOTCH_DEBUG=1` 时按 `ptr/zone/expand/scene/audio/geometry/env` 分类写 stderr，默认零开销 |
| `AppSettings.swift` | 偏好层（UserDefaults）：读播放器 / 管理播放器 / 读日历三个开关、天气城市、锁定状态、引导完成标记 |
| `AppWindows.swift` | 首启引导与设置窗（普通窗口，需抢焦点） |
| `AppMenuBar.swift` | 菜单栏图标与菜单：设置 / 锁定 / 退出 |
| `Info.plist` | app 元数据：`local.notch.island`、`LSUIElement`、最低 macOS 14、日历与 Apple 事件用途说明 |
| `build.sh` | 探测可用 SDK、按 `MACOS_MIN` 设部署目标、编译、组装 app 包（含图标）、临时签名 |
| `tools/make-icon.swift` | 生成 `Assets/AppIcon.icns`，产物入库、iconset 不入库 |
| `README.md` | 给使用者：怎么构建、怎么运行 |
| `AGENTS.md` | 给实现者：怎么改、什么算合格（本文件） |

- 当前范围：媒体播放（圆形旋转封面、歌名、歌手、上一首/播放暂停/下一首、进度与 seek、指针悬停展开、锁定展开、收起态右波形、岛外点击穿透、展开态顶栏状态信息、右下角音源图标）+ 展开态页签（有曲目时音乐/文件/主页三枚，否则只有文件/主页，点过即固定）+ 主页（天气 / 日程倒计时 / 内存磁盘）+ 文件拖放（左半隔空投送、右半托盘）。
- 构建 `./build.sh`；运行 `open NotchIsland.app`。
- 已知限制：多音频判定读 CoreAudio 进程列表，只认 `activationPolicy == .regular` 的真实 App，命令行播放器（`afplay` 等）与静音播放不算、可能漏判；托盘不提供单条删除（只给拖出、Finder 显示、清空），超出 8 条时启动阶段会删掉磁盘上多出来的旧文件；AirDrop 面板需要另一台设备才看得到实际传输；天气依赖外网（Open-Meteo）且城市由设置里的预设决定，底行不再显示更新时间（靠 30 分钟刷新周期兜底）；日历首次会弹系统授权，拒绝后只显示「日历未授权」、不重复询问；内存与磁盘是近似值（内存 = active + wired + compressed 占物理内存，磁盘 = `systemFreeSize` 按十进制 GB 折算），与活动监视器 / Finder 口径接近但非逐字节相同；系统通道依赖私有框架 MediaRemote，系统升级可能失效（macOS 15.4 起直连只放行 `com.apple.*` 进程，已由 osascript 代理兜底；代理在本机 macOS 26 实测：脚本可执行、停止态与未运行态都正常回落空快照，但 osascript 读不到 MediaRemote 字典（原因见第 4 节），所以只覆盖 `com.apple.Music` / `com.spotify.client` 两家；`Info.plist` 已补 `NSAppleEventsUsageDescription`（缺这个键时系统不弹窗直接拒，表现就是「在放歌但岛里什么都没有」），但本机 Music 曲库 0 首，**播放中的歌名/封面/控制键仍未实机验到**；Spotify 本机未安装，其分支只做了代码自洽）；读不到元数据时整块不显示（无音乐页签、不重启播放器），唯一例外是「客户端在跑但没开调试端口」时主页底行那行可点提示（见第 3.7 节），QQ 音乐等白名单外软件永远不会显示歌名；收起态右键只在物理刘海范围内有效（命中区与左键同一套收紧策略，岛比刘海宽出来那 40pt 不接右键）；网易云通道依赖客户端以 `--remote-debugging-port=9222` 启动（需在设置里开启「允许岛管理播放器」，岛启动时才会带端口拉起；用户手动退出后再从 Dock 打开的那次没有端口，主页底行给重启入口），且依赖页面 DOM 选择器，客户端升级改版可能失效；汽水音乐本机是 MAS 沙盒版，实测无法开调试端口（`open --args` 与直跑主程序都被它自己的重启逻辑丢掉 argv），因此当前恒为空，只保留通道与通用探针；未开 Now Playing 注册的网页读不到；无自动化测试；展开宽度按档位表预设，表外应用用默认档，实际被刘海下限抬到 520；有曲目时收起态比刘海宽 40（每侧 20），这 40pt 只展示波形、不响应点击（命中仍是物理刘海）；无曲目时与刘海等大；顶栏信息依赖 IOKit 私有注册表键（`AppleSmartBattery`），系统改键名时循环次数显示为空（电量与充电态不受影响）；刘海特别窄时「循环 N」会尾部省略，不影响其它信息。
- 验证口径：构建退出码 0 + 实际运行观察（合成点击可用 `CGEvent` + `mouseEventClickState = 1`；截图核对用 `screencapture` + 像素统计 / OCR，判断展开宽度看封面彩块与按钮图标位置）。

## 变更记录

- 2026-11-02 新增本文件，确立项目身份、Apple 原生 UI 硬规与工程纪律。
- 2026-11-02 尺寸规则改为「按场景 + 宿主应用查档位表」，新增 `IslandLayout.swift`，删除 `minWidth` 等随内容自适应的兜底写法。
- 2026-11-02 弹出动效重做（顿挫修复）：内容按最终尺寸排一次版、容器插值 + `clipShape` 裁剪；去掉 `.geometryGroup()`、`if expanded` 双分支与逐帧 `PreferenceKey` 回报；弹出/收起拆成两条 spring；宿主视图开图层；窗口由 900×400 收到 640×240。
- 2026-11-02 播放能力改为三源聚合（新增 `MediaSources.swift`）：系统通道（MediaRemote）→ 浏览器通道（AppleScript 执行 JS 读 `navigator.mediaSession.metadata`）→ 网易云客户端（窗口标题）。原因是 Chromium/CEF 客户端不向系统注册 Now Playing，系统通道恒为空；网易云客户端实测窗口标题与 AX 树都取不到歌名，该通道仅作兜底。
- 2026-11-02 撤回上一条的降级通道，恢复单条系统通道（删除 `WebMediaSources.swift` 与 `AppleScriptRunner`）。原因：浏览器通道需要用户开 Chrome「允许 Apple 事件执行 JavaScript」开关，用户明确不动该设置；客户端通道五条路径逐一实测均取不到歌名（窗口标题为空、`AXManualAccessibility` 返回 `-25205`、`127.0.0.1:20017` 非 HTTP、日志 `CTENFDAM` 加密）。同时移除 `canControl` 相关置灰逻辑与封面 URL 下载。
- 2026-11-03 新增网易云通道（`NeteaseSource.swift`，CDP over `--remote-debugging-port=9222`），第 4 节「只有系统通道一条」改为双通道聚合。原因：网易云 3.1.12 是 CEF 客户端、不注册 Now Playing，但它是自绘播放器，状态全在页面 DOM 上，`Runtime.evaluate` 能一次读齐歌名/歌手/封面/进度/时长/播放态，并可直接点按钮、派发指针事件做 seek；这条通道不要求用户改任何系统或浏览器开关。
- 2026-11-03 快照扩成通用播放快照（`progress` / `duration` / `canSeek` / `source`），`MediaStore` 改为双源聚合 + 进度锚点插值；新增 `PlaybackCommand.seek`。视图层只读快照，以后加音源只需加一个 source。
- 2026-11-03 新增 `MediaBridge.swift`（osascript 代理通道）与 `IslandMediaColumn.swift`（媒体列拆分），`AudioActivity` 加 CoreAudio 属性监听，`MediaStore` 增通用音频态与代理回落，`PassthroughView` 加右键「退出灵动岛」，阴影从链式两层改为两层独立单阴影。原因：macOS 15.4+ 直连 MediaRemote 只放行 `com.apple.*` 进程，导致「岛先常驻、之后才放歌」读不到内容；链式 `.shadow` 会把第一层位图的矩形边界二次模糊成四边形阴影。
- 2026-11-03 同日修正代理通道方向：原实现让 osascript 代调 MediaRemote，实测在 JXA 里拿不到回调字典（block 零参数，详见第 4 节），改为读各播放器自带脚本字典（`com.apple.Music` / `com.spotify.client`）；表外软件一律走通用音频态。已知代价：浏览器里放歌只显示通用态、不给歌名。
- 2026-11-03 展开高度公式纳入进度行（`progressGap 8` + `progressRowHeight 28`），档位表新增网易云 404×44（4 的倍数），收起态加 2pt 进度线。
- 2026-11-03 UI 改版：岛体加一层柔和外投影、顶部两角改外凸小圆角（展开 10 / 收起 8，收起态每侧露宽收到 24）、媒体档位整体加宽到 424–456 并加刘海宽下限保护；新增展开态顶栏（左上主页/锁定，右侧电量、百分比、循环次数与充电状态）、右下角音源图标；所有图标按钮统一悬停淡底 + 按压缩放（0.22 / 0.72），锁定后移开鼠标保持展开；视图拆出 `IslandView.swift` / `IslandChrome.swift` / `SystemStatus.swift`，`main.swift` 只留窗口与宿主。
- 2026-11-03 修命中区 bug：`NSHostingView` 是 flipped 坐标，`islandRect` 之前用 `bounds.height - h` 把热区算到了窗口底部，导致岛上按钮点不动、窗口下方空白却挡住别的应用。改为 `y = 0`，并把该坑写进第 3.9 节。
- 2026-11-03 代码审查整改：透明度收敛回 1 / 0.55 / 0.12 三档（进度条填充 0.82→0.55，收起态进度线与展开态统一）；顶栏簇内间距 6→4 并在宽度下限里计入插头图标（`topBarSideMinimum` 108→120，媒体档位随之统一到 448）；电池百分比按 Current/Max 折算；「减弱动态效果」从启动时的全局常量改为 `@Environment` 读取；`collapsedSideBleed` 更名 `collapsedExtraWidth` 消除「每侧 12」与总值 24 的歧义；去掉 `AppIconView` 的死分支与 `controlButton` 中间层；圆角数值收进 `IslandSizeTable`；进度条本体抽成 `IslandProgressBar`，收起态细线与展开态可拖条共用一份；循环次数取不到时显示「循环 —」占位而不是整块消失。
- 2026-11-03 视觉改版（用户当面要求，覆盖 3.4 旧条文）：顶部两角改成向外翻出的弧度（`IslandShape` 手写路径，展开 8 / 收起 6，外弧终点落在垂直侧线右侧），投影改成近/远两层，岛体加一条 1pt 柔化描边（白 0.16→0.05 + 1.1pt 模糊）。
- 2026-11-03 弹出条件收紧：新增 `PointerMonitor`（全局鼠标位置，热区 = 物理刘海内缩 2pt，离开 0.35s 宽限），删掉容器 `onHover`；收起态 `islandRect` 收紧成刘海本身，解决「鼠标在菜单栏两侧点不到正常文本按钮」。
- 2026-11-03 播放源独占：新增 `AudioActivity`（CoreAudio 进程列表，按 app 去重），多个 app 同时出声时不读任何一家、显示「后台有多个音频软件 / 请保留一个」并禁用控制命令；一个都没有则回主页。
- 2026-11-03 音乐板块口径重写（用户当面要求，一次推翻上一条的多音频独占方案）：新增 `MusicGate.swift`（白名单 + `select` 选家），场景开关从「有 app 出声」改为 `MediaStore.hasMusic`（白名单播放器读到曲目，暂停也算），页签由 `IslandScene.tabs(hasMusic:)` 动态生成，读不到就只剩文件/主页并回主页；删除通用音频态（`genericApp` / `WaveformBars` 占位 / `IslandSizeTable.genericArtwork*` / `mediaControlsWidth`）、多音频提示（`hasMultipleAudioApps`）、网易云状态行与「重启」入口（`restartNetease`），`PlaybackSourceKind.netease` 改为 `.cdp(bundleID)` 以支持多家 CDP 客户端。同时把 `NeteaseSource.swift`（429 行）拆成 `CDPClient`（协议）+ `CDPPlayerSource`（解析/缓存/退避）+ 各家 `CDPPlayerProfile`，新增 `SodaSource.swift`（汽水音乐；本机 MAS 版拿不到调试端口，恒空）。覆盖冲突：第 3.7 节原「失败态要给可操作入口」被用户明确废弃，改为「读不到即整块不显示、不提示、不重启」。
- 2026-11-03 新增主页与拖放：`IslandScene` 扩出 `home` / `files`；主页接 Open-Meteo（固定珠海，30 分钟）与 EventKit（今日日程最多 2 条，拒绝授权降级），顶栏房子图标改为回主页；`PassthroughView` 接文件拖放，左半隔空投送、右半进 `TrayStore`（Application Support 常驻，8 条 / 200MB 上限，可拖出、Finder 显示、清空）。窗口仍是 640×240：三个场景同宽同行高，内容没有长高。- 2026-11-03 三批功能复核整改：拖放高亮与主页排版收敛回既定档位（去掉 0.72/0.04/0.22 等中间透明度、裸 `cornerRadius: 10` / `spacing: 10` / 26pt 字号，落点圆角与托盘行高进 `IslandSizeTable`）；托盘去掉每条一个 14×14 的删除钮（热区不足 28，需求也没要求），行高改 20/间距 4 正好占满封面行，第 3 条起折成「还有 N 个」；`TrayStore` 复制放后台、`items` 只在主线程写，启动时顺手删掉超出 8 条的旧文件；`IslandView` 启动即判定场景（无音频直接进主页）、主页/天气数据源改为宿主启停、换歌时从托盘与主页切回媒体、隐藏的「重启」不再可点；指针热区与 `islandRect` 统一用 `pointerInset`，展开热区把外翻弧算进去；仅一个软件出声时按它的 bundle id 认领音源；删掉无调用方的 `MediaStore.revealPlayer()` 与 `TrayStore.remove`。
- 2026-11-03 收起态与顶栏改版（用户当面要求）：删掉收起态 2pt 进度线，改成左 16pt 音源图标 + 右 4 根跳动波形（`CollapsedStatusBar` / `WaveformBars`，纯展示、不拦点击），`collapsedExtraWidth` 24→**80**（总宽 259）；展开态封面改正圆并在播放时 12s 一圈旋转（`RotatingArtwork`，暂停冻结、减弱动态效果归 0°）；顶栏左上改音乐/文件/主页三个页签（`PageTabButton`，选中实心 + 常驻淡底）、锁定移到右侧电量簇之前；`manualHome` 换成 `pinnedScene`（点页签即固定，仅换歌时从主页/文件页回媒体）；宽度下限改为按较宽一侧算（左 92 / 右 155，本机 179 → **520**）。同轮修：`WaveformBars` 周期进 `IslandSizeTable`、展开进度行 `TimelineView` 补 `paused`、切页加 0.2s 内容淡入、`main.swift` 过期注释按新宽度改写。
- 2026-11-03 收起态去掉左音源图标（用户当面要求）：`CollapsedStatusBar` 只保留右侧波形，删掉只服务图标的 `collapsedStatusIconSide`，左槽留空、`collapsedExtraWidth` 仍 80（总宽 259 不变，播放状态切换不抖）。
- 2026-11-03 波形改成拍点模拟（用户当面要求「跟着音乐节奏跳」）：`WaveformBars` 从匀速正弦改为 0.52s（≈115 BPM）一拍、起音冲顶 + 指数回落、每拍每柱哈希幅度 + 细起伏叠加，周期常量 `collapsedWavePeriod`(1.2 单一正弦) 拆成 `BeatPeriod`/`Attack`/`Decay`/`IdleRatio`/`Skew`/`RippleHz`。真实振幅需 Core Audio tap 与「系统音频录制」授权，本轮按用户选择不引入。
- 2026-11-03 修启动场景抖动（`home -> media` 闪一下）：`onChange(of: store.title)` 的「换歌回媒体」加 `!oldTitle.isEmpty` 前置条件——启动后首轮采样带回来的第一首歌常是播放器里暂停着的旧歌，会让「0 个在出声 → 主页」的结论被顶成媒体页；顺带给 `MediaStore.refreshAudioApps` 加 `[audio]` 采样日志（tick / count / bundle id），排查独占判定与启动落页用。
- 2026-11-03 收起态贴齐刘海（用户当面要求「默认状态灵动岛和刘海大小一致，只有音频律动图标才加长」）：`collapsedExtraWidth` 80→**40**、`collapsedStatusSideWidth` 40→**20**、`collapsedTopFlare` 6→**0**；收起宽度改为 `刘海宽 + (hasMusic ? 40 : 0)`（默认与刘海等大，本机 179），加宽/收窄走收起那条 spring；`shadowStrength` 让「贴齐刘海且无曲目」时不投投影；描边收成只有底边一段（`edgeStrokeTopOpacity` 0.16→**0**，新增 `edgeStrokeVisibleStart` 0.65，三段渐变避免两侧染白）。命中区与指针热区不变。
- 2026-11-03 修「莫名收起 / 收起又打开」：`PointerMonitor` 判定改「进入严格、停留宽容」——停留用外扩 6pt 的 `staySlop` 热区，离开由单次 0.35s 采样改为 0.12s×3 连续确认，`update(zone:)` 在光标仍落在旧热区时保留展开（覆盖换档位差 4pt、屏幕几何刷新）；新增 `NotchGeometry`（屏幕参数变化时更新刘海宽高与 screen frame，视图侧 `onChange` 重算热区与 `islandRect`，此前这三个值是启动时定死的 `let`，插拔屏/合盖后热区会错位）；新增 `IslandDebug`（`NOTCH_DEBUG=1` 分类日志，默认零开销），`updatePointerZone` 增加来源标记便于 grep。
- 2026-11-03 结构整理：新增 `ChannelSupport.swift`（`ChannelBackoff` + `CoverCache`），`MediaBridge` 与 `CDPPlayerSource` 里逐字重复的退避公式与封面下载各收一份（约 50 行）；`IslandScene` 的页签顺序 / 图标 / 中文名从 `IslandChrome.swift` 挪回 `IslandLayout.swift`（类型定义处）；删掉无人调用的 `MusicGate.player(_:)` 与 `AudioApp.pid`，`MediaBridge.isScriptable` 收为 `private`，`IslandDebug` 头部分类按实际补齐为 10 类。验证：构建退出码 0，空态起跑 6s 无崩溃（封面与退避路径本轮未实机跑到有歌状态）。
- 2026-11-03 加出场/退场动画（用户要求「不要生硬出现或退出」）：`NotchRootView` 新增 `appeared` 状态，外挂 `.scaleEffect(横 0.92 / 纵 0.86, anchor: .top)` + `.opacity`，入场 `spring(0.42, 0.86)`、退场 `spring(0.24, 0.98)`，透明期 `.allowsHitTesting(false)`；`onAppear` 里 `asyncAfter(0.05)` 才置位（同帧改状态会被合成器合并，等于没动画）；新增 `IslandExit`（`IslandView.swift`）协调退场，`quitIsland` 改为「先播动画、0.26s 后 `NSApp.terminate`」，右键连点只退一次；减弱动态效果下只淡入不缩放。验证：构建退出码 0；启动后连拍三帧量得黑块 173pt / 块内最亮 18 → 179pt / 最亮 0，确认入场确实在插值而非硬切；退场因需真实右键（`osascript` 控制在本机报语法错误、未能自动触发），只核对了代码路径，需手动看一眼。
- 2026-11-03 刘海尺寸自动适配（用户要求「覆盖市面主流刘海大小 / 按机型自动适配」）：新增 `NotchSpec` + `NotchSpecResolver`（`NotchGeometry.swift`），按 `safeAreaInsets.top` 与左右辅助区探测，失败时退到 `UserDefaults` 的 `notchSpec.<displayUUID>` 缓存（附带当时的屏幕点尺寸，换过缩放就不认）、最后才按 `刘海高 × 5.3` 推兜底宽度，日志带 `source`；`main.swift` 的 `notchInfo()` 改用它，面板尺寸由 `panelFrame` 从最宽档位与展开高度推导（本机 600×194，替换写死的 640×240），屏幕参数变化时同步重算；`IslandLayout` 新增 `expandedHeight` / `widestMetrics` / `collapsedCornerRadius` / 波形高下限函数（32pt 刘海取值与旧常量一致），收起圆角与波形柱高改为跟刘海高缩放；新增调试覆盖 `NOTCH_DEBUG=1 NOTCH_SPEC=200x38`。验证：构建退出码 0；本机运行日志 `notch=179.0x32.0 source=system`、`panel=600×194`；以 200×38 覆盖运行，日志与截图像素一致（顶宽 200pt、高 38pt、块内最亮 0）。
- 2026-11-03 修「岛先开、播放器后开抓不到」+ 补 Apple Music 通道权限：实测从 Dock 手开网易云时主进程 argv 没有 `--remote-debugging-port`、9222 不监听，CDP 通道永远连不上，按当时口径整块不显示，用户完全看不出原因。按用户改口（A+B 都做）新增 `PlayerLauncher.swift`——岛启动时对 `preparesPortOnLaunch` 的客户端（现网易云）在「没在跑」时带端口拉起、`activates = false` 不抢焦点；「已在跑却没端口」时由 `CDPPlayerSource.probePort`（GET `/json/version`，3s 节流，三态 unknown/open/closed）报到 `MediaStore.portNotice`，主页底行画一行 28 高可点提示，点了才 `terminate` → 等进程真退出 → 带端口重拉，成功后 `resetBackoff` 免得等满 60s。同批补 `Info.plist` 的 `NSAppleEventsUsageDescription`（缺这个键 TCC 不弹窗直接拒）。顺带修一个必崩：`MediaBridge.run` 在管道 EOF 后立刻读 `terminationStatus`，此时 task 可能还没退，抛 `NSInvalidArgumentException` 把整个 app 带走——首次访问 Music 会卡在自动化授权弹窗上，正好走到这条路；改为先 `waitUntilExit()` 再读。覆盖冲突：第 3.7 节「失败态不给入口」与第 4 节「永不终止播放器进程」按用户当面交代改为「只有『在跑但没开调试端口』这一种情况给入口，且只在该入口里终止进程」。
- 2026-11-04 补回收起态顶角外翻弧（用户当面要求「有音乐播放时收起态的左上/右上连接处往外的弧度没有了」）：新增 `IslandSizeTable.collapsedMusicTopFlare`(8)，`IslandView` 的顶角外翻量改为按状态取——展开 8 / 收起有曲目 8 / 收起无曲目 0（无曲目时岛体与刘海等宽，外扩会盖菜单栏，仍保持 0，覆盖 2026-11-03「收起态 `collapsedTopFlare` 恒 0」的结论）。同时更新第 3.4、3.6 节条文。验证：`OUT=/tmp/ni-verify` 构建退出码 0；带 `NOTCH_DEBUG=1` 运行 4s，`hasMusic=true` 时形状走 8pt 外翻分支、进程未崩溃；外翻弧的实际观感需重启 app 目视确认。
- 2026-11-04 主页天气补城市（用户要求「天气显示需要有城市」）：`WeatherSource` 新增 `static let city = "珠海"`（与坐标放一处，换城市两个一起改），`HomeScene.rangeText` 改为「珠海 22° / 29°」，没取到数据时仍只留城市名。宽度未动（天气栏 152pt 内可容纳），同步第 3.7 节文案与 `README.md` 主页段。
- 2026-11-04 主页去掉日期并补信息（用户要求「日期显示去掉、保留天气，其他地方加什么」）：`HomeScene` 删掉 `M月d日 EEEE` 与 `dayFormatter`，原位置改日程引导行（`进行中` / `N 分钟后` / `N 小时后` / `全天` + 标题，`TimelineView` 每 60s 走一次，因为 `CalendarSource` 的 60s 刷新只在数据变化时发布，倒计时不会自己重绘）；`CalendarEntry` 加 `startDate` / `isAllDay`，`CalendarSource` 新增 `next`（进行中 > 即将开始 > 全天）与「今天没有更多日程」降级文案。底行天气从「现象 · 更新 HH:mm」改为「现象 · 降水概率% · 日落 HH:mm」，`WeatherSource` 的 daily 请求加 `precipitation_probability_max,sunset`（两者按可选解析，缺字段退化成不显示）；底行右侧新增内存占用与磁盘可用（`SystemStatus.swift` 新增 `SystemMetricsMonitor`，30s 采样，内存走 Mach `host_statistics64`，磁盘走 `attributesOfFileSystem`），原右端「还有 N 项日程」移到日程引导行尾。同步第 4 节职责分层、第 7 节范围、第 8 节表格与已知限制、第 3.7 节文案、`README.md`。验证：`OUT=/tmp/ni-verify` 构建退出码 0；`curl` 核对 Open-Meteo 实际返回 `precipitation_probability_max:[100]` / `sunset:["2026-11-04T17:47"]`，解析取 T 后 5 位；用同公式的独立脚本跑出内存 60% / 磁盘 389G（24GB 内存机，数值合理）；**展开态观感未实机验证**——合成鼠标事件被系统拒绝（本机未给终端辅助功能权限），日志里 `mouse` 坐标未变，需手动把指针移到刘海看一眼。
- 2026-11-04 右键菜单补锁定（用户要求「右键有退出灵动 / 锁定不弹出 / 解除锁定不弹出」）：`PassthroughView.rightMouseDown` 从单项「退出灵动岛」扩成三项，退出项后加分隔线，后两项按当前状态互斥置灰（`menu.autoenablesItems = false` + 手写 `isEnabled`）。新增 `IslandLock`（`IslandView.swift`，与 `IslandExit` 并列）持有锁定态：右键菜单在 AppKit 层、顶栏锁按钮在 SwiftUI 层，必须同一份状态；`NotchRootView` 的 `isLocked` 从 `@State` 改为 `@ObservedObject lock = IslandLock.shared` + 计算属性，`toggleLock()` 收成 `lock.toggle()`，展开收放统一走新增的 `onChange(of: lock.isLocked)` → `syncExpansion`，两条入口不再各写一遍。同步第 3.9 节右键条文、第 4 节职责分层、第 8 节已知限制。验证：`OUT=/tmp/ni-verify` 构建退出码 0；`NOTCH_DEBUG=1` 起跑 3s 进程存活、日志只有 `[env]` 两行；**菜单弹出与置灰未实机验证**——本机终端没有辅助功能权限，`CGEvent` 投递不生效，需手动右键看一眼（重点看：未锁定时「解除锁定不弹出」应为灰、锁定后反过来）。
- 2026-11-04 阴影收窄（用户反馈「展开后有四边形阴影块」）：`IslandSizeTable` 六参数由近 `0.45 / radius 8 / y 4`、远 `0.30 / radius 24 / y 12` 改为近 `0.40 / 5 / 3`、远 `0.26 / 14 / 8`。原因：结构本身没错（两层各自对 `IslandShape` 真实路径模糊），但远层 24pt 模糊远超外翻弧的 8pt 纵向高度，把顶部两角与底部 22pt 圆角抹平成直边，观感成了罩在岛外的方块。验证：临时把 `panel.backgroundColor` 设为白、`expanded` 设 `true`，`screencapture -R435,0,600,194` 抓区域图后按亮度阈值量外沿——改前岛体两侧（luma<250）外扩 35pt、岛底一条 573pt 宽平直暗带；改后 19pt、底部暗带随圆角收窄（155pt 处已收窄到 200pt 宽）。两处 TEMP 已还原（`backgroundColor = .clear`、`expanded = false`），最终构建退出码 0。残留：模糊(14)仍大于外翻弧高度(8)，顶部两角在外受过白底的图上仍偏方，观感需用户目视确认；若仍嫌块状，下一档把远层半径降到 10 或直接去掉远层。
- 2026-11-04 「锁定不弹出」语义纠正（用户当面：「锁定不弹出的意思是灵动岛收缩后不再展开，和原来的锁功能不是一个功能」）：`IslandLock` 的 `isLocked` 改名 `blocksAutoExpand`，展开条件由 `pointerInside || locked` 改为 `pointerInside && !blocksAutoExpand`，删掉「锁定后鼠标移开仍保持展开」的保持语义；顶栏 `IslandTopBar` 入参同步改名 `autoExpandBlocked`（icon 仍 `lock.fill` / `lock.open` 表达，文案仍「锁定」/「解锁」），右键菜单文案与互斥置灰不变，仅日志改为「右键锁定不弹出 / 右键解除锁定不弹出」。锁定瞬间若是展开态，由 `onChange(of: lock.blocksAutoExpand)` → `syncExpansion(pointerInside && !blocked)` 就地收起。同步第 3.9 节条文。验证：`./build.sh` 退出码 0；`grep isLocked` 已无残留引用；`read_lints` 三个改动文件 0 诊断。**未实机验证**——锁定态只能由右键菜单或顶栏锁按钮触发，本机终端无辅助功能权限、`CGEvent` 投递不生效，需手动右键点「锁定不弹出」再悬停刘海确认不展开。
- 2026-11-04 产品化与开源改造（用户确认：源码分发、macOS 14+、私有 API 与播放器自动化默认关闭、GPL-3.0）：新增 `AppSettings`（三个能力开关默认关、天气城市、锁定状态、引导完成标记）、`AppWindows`（首启引导 + 设置窗）、`AppMenuBar`（菜单栏设置/锁定/退出）、`Assets/AppIcon.icns` 与 `tools/make-icon.swift`；`Info.plist` 的 `LSMinimumSystemVersion` 26.0→**14.0**、加 `CFBundleIconFile`、版本 0.2.0；`build.sh` 增加 `-target arm64-apple-macos14.0`（`MACOS_MIN` 可覆盖）与图标入包，新源文件已进 `SOURCES`；`MediaStore` 按开关决定是否走系统/代理/CDP 通道、是否带端口拉起与探端口，关掉读取时清空播放态；`NotchRootView` 按开关启停日历、跟随城市改天气；`IslandLock` 状态写入 `UserDefaults`；无刘海时改弹 `NSAlert` 后退出；右键菜单加「设置…」、退出项改名「退出 NotchIsland」。开源侧补 `LICENSE`(GPL-3.0)、`CONTRIBUTING`、`SECURITY`、`CHANGELOG`、issue/PR 模板与 `.github/workflows/build.yml`（tag 触发 zip + SHA256 Release），README 重写为中英双语。验证：`OUT=/tmp/ni-verify` 构建退出码 0，`otool` 确认 `minos 14.0`、图标已入包；用独立 bundle id 实跑 4s，日志出现 `[lifecycle] 菜单栏图标已安装` 与 `version=0.2.0 (2)`，`CGWindowList` 确认引导窗 520×520 与面板 600×194 同时存在、进程未崩。
