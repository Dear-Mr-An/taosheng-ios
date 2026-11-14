# 涛声 iOS

Android 原版 [0xCoach/TaoSheng](https://github.com/0xCoach/TaoSheng) 的 SwiftUI 重写，iOS 16+，无第三方运行依赖。
全天收音 → 人声切片 → 转写 → DeepSeek 整理事件、待办和记忆。数据使用本机 SQLite。

0.5.4 第五轮修复（把「转写」和「整理」拆成两页，2026-11-14）

版本号 0.5.4 (26)。0.5.1 删服务商入口时，把「整理用的大模型」和「什么时候整理」两张卡塞进了原话页；原话一多，整理设置就被顶到很远。本轮把这一页拆成两个入口，并修掉小屏上看到的截断与截图种子重复。

一、拆成两个入口

「设置 → 记录」现在是：录音与后台 / 转写与原话 / 大模型与整理 / 环境音识别 / 足迹。

- **转写与原话**：新文件 `TaoSheng/UI/TranscribeOverviewView.swift`（由原 `ModelSettingsView` 改名），只留「转写状态卡」和「今天的原话」。状态点看 `settings.asrReady` 与待转写数量，副标题是「都转完了 / 待转写 N 段 / 正在转写 / 转写未就绪」。
- **大模型与整理**：新文件 `TaoSheng/UI/LLMSettingsView.swift`，只放「整理用的大模型」卡（余额、检测连接、余额提醒、编辑弹层）和「什么时候整理」卡（自动整理、按间隔或时间点、整理前先思考、参考地点和环境音）。状态点看 `settings.llmReady`，副标题显示模型名或「未填密钥」。同样带 `.tabBarClearance()`，最后一行不会被悬浮 TabBar 挡住。
- 代码侧：`SettingsSub.swift` 里整段删掉 `ModelSettingsView`（561 行）与 `private struct DeepSeekEditorSheet`（37 行），两者各自独立成文件，`DeepSeekEditorSheet` 跟着搬到 `LLMSettingsView.swift`。`SettingsView.swift` 的「记录」组改成两行 `nav(...)`，各自读自己的就绪状态。

二、原话卡只留 3 段

- `previewLimit = 3`，`ForEach(Array(todaySegments.prefix(3).enumerated()), id: \.element.id)`；`Store.segments(day:)` 本来就是 `ORDER BY started_at DESC`，所以最新的三段落在上。
- 超过 3 段时底部是「看全部 N 段 ›」进 `RawLinesView`；3 段以内显示「打开原话页」；一段都没有时仍是原来那句提示。

三、标题与按钮

- `TranscribeSettingsSheet` 的导航标题、`// MARK` 注释都改回「转写设置」；转写状态卡右上角的按钮文字也是「转写设置」——它现在只弹转写相关设置，不再指向整理。

四、文案对齐

- `LLM/LLMAuto.swift`、`UI/AskView.swift`、`UI/SettingsSub.swift` 里所有「模型与整理」改成「大模型与整理」；`SettingsSub.swift` 的两处说明文字分别指向「大模型与整理」和「转写与原话」。
- 全仓 grep「模型与整理」为 0，只剩「大模型与整理」。

五、小屏截断（截图时发现）

- `iphonese-transcribe.png` 第一版里「云端转写」和「原声」两行的值被截成 `约 ¥...`、`占用...`。统计行改成两行可回绕 + `minimumScaleFactor(0.85)`，标签列 62 → 58，文案也缩短（「近 30 天」→「30 天」、「约 ¥」→「≈¥」、「把手机里的原始录音打包导出」→「打包导出原始录音」）。

六、截图种子重复（截图时发现）

- 第一版 `iphone16-transcribe.png` 显示「64 段」，三行原文还一模一样：截图模式每启动一次就插 8 段，而判重写的是 `segments(day:limit: 1).count >= 8`（limit 只限行数，恒为 1）。改成按固定 id `shot-seg-1…8` 判重并跳过已存在的，一台设备连续启动 15 次也只会有 8 段。

七、截图

- `ShotMode` 新增两个画面：`transcribe` → 直接渲染「转写与原话」（先灌 8 段今天的原话，用来证明只列 3 段 + 「看全部 8 段」）；`llm` → 直接渲染「大模型与整理」并用 `ShotBottomAnchor` 贴到页面底部，验证最后一行不被 TabBar 挡住。
- `ios-shots.yml`：iPhone 16 Pro 与 iPhone SE (3rd) 各加 `transcribe`、`llm`；建完设备就按 UDID 往 `device.plist` 写 `ConnectHardwareKeyboard=false`（必须在 `simctl boot` 之前），小屏的「新的人物」这次能看到软键盘。另外修掉 `mk()` 把提示语写进 stdout 的 bug（`DEV=$(mk)` 会把两行都捕获，导致 `Invalid device: 已关闭硬件键盘: …`、一张图都拍不出来）。
- 截图目录 `../.tmp/shots-0.5.4/`，共 15 张：大屏 9 张（todo / today / ask / memory / recording-bottom / person-add / event-edit / transcribe / llm），小屏 6 张（todo / today / recording-bottom / person-add / transcribe / llm）。

八、验证

- CI `build-ipa`（run 43567418231）：success，`.swift` 层 0 error 0 warning。
- CI `shots`（run 43567418201）：success，15 张。
- 产物 `../dist/TaoSheng-v0.5.4.ipa`：`CFBundleShortVersionString = 0.5.4`、`CFBundleVersion = 26`、`CFBundleIdentifier = app.taosheng.TaoSheng`、Info.plist 为 XML。

九、本轮仍未做

- 声纹算法、备份结构（只覆盖 legacy 表）、S3 key 编码：与上一轮结论相同，留后续版本。

0.5.3 第四轮修复（验收打回，2026-11-14）

版本号 0.5.3 (25)。上一轮交付被逐张截图打回 9 条，本轮全部处理；其中第 2 条（小屏截到桌面）先查清原因再修，截图流程本身也加了自检。

一、事件编辑弹层初始值丢了（第 1 条）

- 现象：`iphone16-event-edit.png` 里标题和摘要都是空的，保存按钮因此一直是灰的；事件本身有标题和摘要。
- 原因：`.sheet(isPresented:)` 的 content 闭包在同一次状态更新里被求值，`draftTitle/draftSummary` 还是旧值（空串），弹层拿到的是改动前的草稿。
- 修法：两处弹层全部改成 `.sheet(item:)`，初始值放进 item 传进去：
  - `EventDetailView` 用 `@State private var editItem: EditPayload?`，`EditPayload { title, summary }`；截图模式与「编辑」按钮都改为 `editItem = EditPayload(title: current.title, summary: current.summary)`。
  - `PersonsView` 用 `@State private var addItem: AddPerson?`，新建人物没有初始值，但同样走 item，避免以后再加默认值时重复踩坑。
- 对应截图：`iphone16-event-edit.png`（标题「和周工确认交付时间」、摘要都在，保存按钮高亮）、`iphone16-person-add.png`。

二、小屏截到的其实是模拟器桌面（第 2 条）

- 先查日志：`logs/iphone16-todo-fail1-app.log` 里是 `installcoordinationd` 的 `IXSCoordinatedAppInstall` 停在 `IXCoordinationPlaceholderPromiseNotSet`，`installd` 还在装占位包（`type Placeholder`）；同一时刻 `simctl launch` 报 App not found，截图就拍到了 SpringBoard。`DiagnosticReports` 里没有崩溃报告，`launchctl list` 也没有该进程——**不是 App 崩了，是安装还没落地就去启动**。
- 修法（截图脚本）：
  - `wait_installed()`：install 之后用 `xcrun simctl get_app_container "$DEV" "$BID" app` 轮询（30 × 2s）确认 bundle 真装好，再 `sleep 2`。
  - `launch_and_wait()`：`simctl launch` 最多三试，成功后还轮询 `launchctl list` 确认进程在（15 × 1s）。
  - 截图后再验一次：`app_running` 为假就删掉这张、重新启动重拍。
  - 函数内变量全部加 `local`（上一版 `dump_diag` 的 `NAME="$2"` 覆写过调用方变量，产出过 `iphone16-todo-fail1-todo-fail2-todo.png` 这种文件名）。
- 小屏从 1 张扩到 4 张：`todo / today / recording-bottom / person-add`，每张都过了「安装完成 + App 在运行 + 截图后仍在前台」三道检查。
- 对应截图：`iphonese-todo.png`、`iphonese-today.png`、`iphonese-recording-bottom.png`、`iphonese-person-add.png`。

三、键盘引导页盖住输入框（第 3 条）

- 修法：每次启动设备后先关掉系统引导页——`simctl spawn <dev> defaults write com.apple.Preferences DidShowContinuousPathIntroduction / DidShowGestureKeyboardIntroduction / DidShowContinuousPathIntroductionV2 -bool true`（同时对 `com.apple.keyboard.preferences` 写一遍），并把语言/区域固定成 `zh-Hans` / `zh_CN`，避免首次启动的引导层。
- 对应截图：`iphone16-person-add.png`、`iphonese-person-add.png`（输入框与软键盘同时可见，没有「滑动输入」引导）。

四、事件详情「问问」的预填还是丢（第 4 条）

- 原因：`RootView` 收到 `taoshengAskPrefill` 只切 tab；`app.askPending` 只在 `AskView` 自己的监听里赋值，而发通知时 `AskView` 还没被创建，问题就整条丢了。
- 修法：`RootView` 的监听里直接 `AppState.shared.askPending = q` 再切 tab；`AskView` 删掉通知监听，改成 `.onAppear` 消费一次 + `.onChange(of: app.askPending)` 消费后到的值（已经停在问问页时也能落进输入框）。

五、`wipeAll` 仍然漏表（第 5 条）

- `Store+Ext.swift` 的清空清单补上 `voice_cluster`；现在共 20 张表全部清掉（含 memory_* / skill_* / thing* / env_tag / voice_cluster），随后删除 `Documents/Audio` 下的音频文件。

六、旧入口名残留（第 6 条）

- `AskView.swift`：「去设置 → 转写与大模型」→「去设置 → 模型与整理」。
- `LLMAuto.swift`：「去 设置 → 整理模型 → 编辑」→「去 设置 → 模型与整理 → 编辑」。
- `SettingsSub.swift`：「模型和转写设置」（sheet 标题、导航标题、`// MARK`）→「模型与整理」。
- 全仓再搜一遍「整理模型 / 转写与大模型 / 模型和转写」，只剩一处代码注释与一处描述性文案（"模型和转写服务都用你自己填的密钥"），语义正确，保留。

七、今天页英雄卡（第 7 条）

- 三列统计之间的竖线原来紧贴数字，看起来像「|1」「|2」：给 `heroDivider` 加 `.padding(.horizontal, 12)`。
- 模式按钮原来用自适应网格（`GridItem(.adaptive(minimum: 88))`），窄屏折成 3+1：改成 `HStack(spacing: 6)` + 每个按钮 `.frame(maxWidth: .infinity)`，一行四个等宽；文字加了 `minimumScaleFactor(0.8)`，小屏也不会挤成两行。
- 对应截图：`iphone16-today.png`、`iphonese-today.png`。

八、点击区（第 8 条）

- 新增 `View.tapTarget(_ pad:)`：`padding(pad).contentShape(Rectangle()).padding(-pad)`——点击区外扩、布局尺寸不变。逐处套上：
  - 待办勾选圈（`TodosView`）、时间线事件行星标（`EventRow`，顺带把星标做成可点：未标时是淡色空心星，点了就标重点）、原话行播放键（`SegmentRow`）、今天页「收起/展开」、「全部 >」、记忆页「查看完整回顾」、热词删除（`HotwordView`）、详情页播放键（32pt 再外扩 6pt）。
- 星标从「只能长按菜单」变成「直接点图标」，这条也顺手把 `EventRow` 的交互补全了。

九、主键长度（第 9 条）

- `Models.swift` 的 `shortID()` 从「UUID 前 8 位」改成「完整 UUID（小写）」。所有拿它当主键的表（待办、人物、提醒、问答、热词、通道、技能卡、技能运行）都不会再因为 8 位前缀撞车被 `INSERT OR REPLACE` 静默覆盖。老数据不迁移。

十、截图里自己修掉的一个回归（顺带）

- 上一轮为了在小屏上把表单滚到底，在「录音与后台」末尾加了一个 `if ShotMode.active { Section { Color.clear.frame(height: 1) } }` 当滚动锚点；`Form` 会给每个 Section 画一张卡片，于是截图底部多出一张空白卡片（真机不受影响，只在截图模式出现）。
- 修法：删掉这个空 Section，把 `.id("row-window")` 挂到「夜里自动停录」开关、`.id("row-end")` 挂到「到 X:00 结束」那一行，按 `silenceWindowOn` 选锚点再 `scrollTo`。
- 对应截图：`iphone16-recording-bottom.png`、`iphonese-recording-bottom.png`（「停录时段 / 夜里自动停录」完整露在悬浮 TabBar 之上，底部没有空白卡片）。

十一、验证

- CI `build-ipa` #67（9968b59）：success，`.swift` 层 0 error 0 warning。
- CI `shots` #11（9968b59）：success，11 张（7 张大屏 + 4 张小屏），文件名干净、无 `logs/`（首启即成功，说明「等安装落地」生效），逐张确认都是 App 画面。
- 产物 `../dist/TaoSheng-v0.5.3.ipa`：1352637 B，`CFBundleShortVersionString = 0.5.3`、`CFBundleVersion = 25`、`CFBundleIdentifier = app.taosheng.TaoSheng`、Info.plist 为 XML。
- 截图目录 `../.tmp/shots-0.5.3/`：`iphone16-todo / today / ask / memory / recording-bottom / person-add / event-edit`、`iphonese-todo / today / recording-bottom / person-add`。

十二、本轮仍未做

- 声纹算法、备份结构、S3 key 编码：与上一轮结论相同，属于要单独一轮的改动。
- 44×44 的完整点击区规整：本轮只覆盖验收点名的 8 类控件，其余按钮已随 `tapTarget` 一起处理或本身够大。
0.5.2 第三轮修复（审查清单驱动，2026-11-14）

版本号 0.5.2 (24)。按 `.tmp/plan-0.5.2.md` 的 P0 → P1 → P2 顺序逐条修，每条都对着源码核过。功能不变，只修错、修一致、修数据安全。

一、P0 三个显性问题

1. 待办页 FAB 与 TabBar 撞在一起：`TodosView` 原来把 `.tabBarClearance()` 加在整屏 ZStack 上、又给 FAB 加了 `.floatingTabBarPadding`，两处叠加；改成一屏一份（clearance 只挂 ScrollView，FAB 只留 floating），占位从写死的 120 改成「FAB 56 + 16」。
2. 添加人物弹窗的输入框只露一半：`.alert` 里塞 TextField 在 iOS 上会被裁。新增通用 `TaoSheng/UI/TextInputSheet.swift`（sheet + presentationDetents + 自动聚焦 + 去空白后为空则禁用确定），替换「新的人物」「编辑这件事」两处 alert。现在全仓 `.alert` 里没有输入框。
3. 键盘弹出时底部仍留 66pt：`tabBarClearance` / `floatingTabBarPadding` 改成读 `KeyboardObserver.isVisible`，键盘可见时高度归零，带 0.18s 动画。

二、P1 录音与转写

- CaptureEngine 加 `AVAudioEngineConfigurationChange` 监听 + 5 秒看门狗：引擎还在跑但 5 秒没收到 buffer，或引擎已被系统停掉，自动重建（原来换蓝牙、来电、共享音频后可能静默停录，界面还显示在录）。
- 媒体服务重置的守卫写反了（`!isRunning` 才处理），改为无条件拆 tap、停引擎、收尾当前段、重建后重启。
- 录音写入加背压（最多 16 块待写），写盘跟不上时丢块而不是无限堆积。
- 转写队列改 `@MainActor`，一次 tick 跑到队列清空（最多 40 轮 × 8 段），缺文件的段直接进终态不再反复重试。
- 段 id 改完整 UUID + 纯 INSERT + 冲突换 id 重试；`insert` 返回 Bool，写库失败不再谎报「已保存」。
- NetWatcher 提前初始化，首次 path 到达前 `canUpload = false`，避免冷启动把「还没检测到网络」当成「有网」。
- SegmentPlayer 在听筒输出时临时切扬声器，停或播完还原；新增连播队列，详情页「播放这件事」按时间连播全部原话。
- Voiceprint 只分析前 60 秒（10 分钟的段原来要整段解码，约 38MB 峰值）；向量含 NaN/Inf 直接丢弃（否则写入声纹时 JSONSerialization 抛不可捕获异常，闪退）。
- 指认说话人的声纹计算挪到后台线程 + 进度态。

三、P1 整理、技能、回顾

- 整理失败按天记次数 + 指数退避（300 秒起翻倍，上限 1 小时），连续 5 次停自动重试并在整理卡提示；模型输出被截断时批次对半重跑。
- `markDigested` 挪到写库之后，中途失败不会把没整理的段标成已整理。
- 已删除的事件不再被重新整理复活（`upsertEvent` 查旧行不再过滤 deleted）。
- 技能「没有内容」不再锁死当天；同一天同技能覆盖写同一张卡。
- 回顾的时间窗按「被生成的那一天」算，不再用 `Date()`（补生成历史天时窗口会错位）。

四、P1 提醒、推送、备份

- 完成/忽略/删除待办、清空数据时同步撤销对应本地提醒；启动时补排还没到点的 pending/accepted 待办；过期的一次性提醒不再排队。
- 推送按通道解析响应体（企微 errcode、PushPlus code、Server酱 code、飞书 code、Telegram ok、Bark code），业务失败不再显示成「已推送」；正文按各通道上限截断。
- ntfy 频道地址不再拼成 `/topic/topic`；只填 host 时不再往公共频道推。
- 坚果云通道用自己的账号密码走 WebDAV，目录不存在先 MKCOL。
- 备份改为「上次备份日 → 昨天」逐日补齐 + 今天按 6 小时间隔，空天跳过，防重入。

五、P1 数据层

- `ensureColumn` 的 skill.fields 缺 `ALTER TABLE` 前缀，老库永远加不上这一列（已修）。
- `wipeAll` 补 voice_cluster；`purgeDerived` 补 item/digest/skill_run/voice_cluster；删段顺带删 env_tag。
- 过期清理改后台 + SQL 筛选（未标星、早于截止时间），只删音频文件并清空文件名，保留转写与整理结果，清完提示删了几段。
- 豆包资源档位迁移改成只跑一次。

六、P1 设置页

- 豆包密钥输入框「打一个字就消失」：改成独立草稿 + 显式保存。
- 四个密钥（转写 Key、豆包 Key、整理 Key、备份密码）从 UserDefaults 搬进钥匙串，启动时把旧明文迁进钥匙串并抹掉。
- 技能详情的全局「生成后推送」删除；技能可左滑删除；保存校验名字非空；周计划补上「周几 / 小时 / 分钟」。
- 识别档位改短名（大模型 / 极速 / 闲时），不再被截断。
- 录音包与 Markdown 导出改后台 + 进度 + 禁用按钮。
- 「从云端恢复」加二次确认。

七、P1 页面

- 问问：发送中/错误状态挪进 AppState（切页不再丢），回车发送，详情页「问问」的预填不再丢。
- 记忆：切分类先清空、勾选后图标立刻变、重点列表点得开详情、周条能翻上一周/下一周、生成回顾有进行中状态、删除原话前确认并停止播放。
- 今天：切模式的重试会看用户是否已经手动停录，时间线标星走统一的 AppState，时间线 sheet 数据改后台查。
- 详情：播放按钮订阅播放器、点击区 32pt、加载中显示骨架而不是「没有原话」、未识别说话人显示中性「未识别」。
- 待办：拆分失败的错误提示从 toast 改成弹窗内联（原来被 sheet 盖住看不见）。

八、P2 UI 统一

- 字号收敛到 `Theme.fsHero / fsCardTitle / fsTitle / fsBody / fsSmall / fsCaption`（全仓 44 处改用令牌），圆角统一到 `radiusSmall 12 / radius 16 / radiusLarge 22`。
- 空状态全部带图标 + 说明；列表加载中显示 `LoadingHint` 骨架（今天时间线、记忆分类、详情原话）。
- 分段控件选中态改 `accentSoft` 底 + accent 字；页面标题统一 `fsHero`。
- 删掉 `ThingsView`（无入口）、`scheduleDaily`（无调用）、`pendingCountImmediate` 等死代码。

九、新增文件

- `TaoSheng/UI/TextInputSheet.swift`：通用文本输入弹层。
- `TaoSheng/Core/Secrets.swift`：钥匙串读写与明文迁移。
- `TaoSheng/Core/Formatters.swift`：共享 DateFormatter 与安全文件名。
- `TaoSheng/Core/Policies/PushRules.swift`：推送地址拼接、响应判定、截断、周名、退避、LIKE 转义（纯逻辑，带单测）。
- `TaoSheng/UI/ShotMode.swift`：截图模式（`-TSShot <screen>`）的跳转与演示数据。
- `Tests/Policies/PushRulesTests.swift`：上面这些纯逻辑的 8 组用例。

十、模拟器截图（本轮新增的验收手段）

- 新增独立工作流 `.github/workflows/ios-shots.yml`：在 macos-15 上建 iPhone 16 Pro 与 iPhone SE (3rd generation) 模拟器，用启动参数 `-TSShot <screen>` 直接跳到指定画面、灌少量演示数据，截 8 张图上传 artifact `shots-052`。
- 截图只是证据，失败不影响 IPA 打包（所以拆成独立 workflow，避免连带取消）。
- 截图步骤全程包超时（macOS runner 没有 GNU timeout，用 coreutils 的 gtimeout），设备只启动一次，避免 simctl 卡死把 job 拖到上限。

十一、验证

- CI `build-ipa` #65（9f0a2ba）：success，编译 0 error / 0 warning；`swift test` 8 项、`node --test Tests/segment-sql.test.mjs` 8 项全过。
- CI `shots` #7（9f0a2ba）：success，8 张截图上传。
- 产物 `../dist/TaoSheng-v0.5.2.ipa`：包内 `Payload/TaoSheng.app/Info.plist` 为 XML，`CFBundleShortVersionString = 0.5.2`、`CFBundleVersion = 24`、`CFBundleIdentifier = app.taosheng.TaoSheng`、`CFBundleSupportedPlatforms` 单条 `iPhoneOS`。
- 截图落在 `../.tmp/shots-0.5.2/`：`iphone16-todo.png`（FAB 与 TabBar 间距）、`iphone16-recording-bottom.png`（设置子页滚到底，停录时段完整露出）、`iphone16-person-add.png`（弹层输入框 + 键盘）、`iphone16-event-edit.png`（编辑弹层）、`iphone16-today.png`、`iphone16-ask.png`、`iphone16-memory.png`、`iphonese-todo.png`（小屏）。

十二、本轮未修与理由

- 声纹算法本身（24 维 mel 均值 + 方差）不动：换算法是产品改动，要重做阈值与聚类验证，不属于「修 bug」。
- BackupEngine 的备份结构仍是 0.4.x 的「段 + 待办 + 日报」，没扩到 memory_event / memory_item / skill_card / thing：改格式要做版本迁移与向下兼容，单独一轮更稳。
- S3 备份的路径仍按原样拼 key（含中文或空格会失败）：要同时改 SigV4 的 canonical URI，风险高于收益，记为已知限制。
- 点击区统一到 44×44 没做全：本轮只把详情页播放键从 12pt 提到 32pt；星标、勾选圈这些小控件的点击区要逐页对着真机校准，留到下一轮和截图一起调，避免盲改把行高撑开。
- `.onChange(of:)` 仍是 iOS 16 的单参闭包：本工程 deployment target 16.0，双参 API 要 17+，现阶段不产生警告（CI 实测 0 warning）。

0.5.1 第二轮修复（真机反馈，2026-11-13）

版本号 0.5.1 (23)。真机装上 0.5.0 后暴露两类问题：底部悬浮 TabBar 盖住内容、设置里「整理模型 / 服务商」是多余入口。本轮按此修，功能不变。

一、底部让位（根因）

TabBar 是 `ZStack(alignment: .bottom)` 里的浮层，不占布局空间。0.5.0 上一轮把各页写死的底部留白从 78/100 压到 16–24，而 RootView 里那层 62pt 的 `safeAreaInset` 同时被删掉，于是所有页面都少了这一层——Tab 页末行紧贴 TabBar，`NavigationStack` 推入的设置子页（`safeAreaInset` 不透传给推入页）直接被盖住，待办页 FAB 也一样。

修法：在 `TaoSheng/UI/RootView.swift` 末尾新增两个修饰符，页面自己声明，推入页同样生效。

- `tabBarClearance(_ extra: CGFloat = 12)`：`safeAreaInset(edge: .bottom)` 补 `TabBar.reservedHeight + extra`，给滚动内容用；
- `floatingTabBarPadding(_ extra: CGFloat = 8)`：`padding(.bottom, TabBar.reservedHeight + extra)`，给悬浮控件用；
- `TabBar.reservedHeight` 62 → 66（按 8 + 22 + 3 + 13 + 5 + 5 + 2 + 2 + 4 实测内容高度，原值低估 4pt）。

逐页结果（均已加占位，最后一行/悬浮控件完整露在 TabBar 上方）：

| 页面 | 处理 |
| --- | --- |
| 今天 `TodayView` | `.tabBarClearance()`；原 `frame(height: 78)` 占位改 16（避免与占位叠加） |
| 问问 `AskView` | 输入条 `.padding(.bottom, kb.isVisible ? 8 : TabBar.reservedHeight + 12)`；内容由 `safeAreaInset` 抬到输入条之上 |
| 记忆 `MemoryView` | `.tabBarClearance()`；原 78 占位改 16 |
| 记忆 → 原话 `RawLinesView` | `.tabBarClearance()`（推入页，原来完全被盖） |
| 记忆 → 寻物 `ThingsView` | `.tabBarClearance()` |
| 待办 `TodosView` | `.tabBarClearance()`；FAB 区 `.padding(.bottom, 20)` → `.floatingTabBarPadding(12)` |
| 设置 `SettingsView` | `.tabBarClearance()`；删掉旧的 `.padding(.bottom, 110)` |
| 设置 → 录音与后台 | `.tabBarClearance()`（本轮上报的「停录时段」被挡） |
| 设置 → 热词 / 声纹与人物 / 整理技能 / 技能详情 / 推送通道 / 数据备份 / 模型与整理 / 回顾与提醒 / 隐私与数据 / 导入录音 / 关于涛声 | 同上，各 `.tabBarClearance()` |
| 设置 → 环境音识别 / 足迹 | 同上 |
| 各处弹窗（`sheet`：时间线、回顾、历史、这是谁、新通道、原声、模型和转写） | 不动：弹窗盖住整个屏幕，没有 TabBar |

二、删除「整理用的大模型 / 服务商」

整理本来就只有 DeepSeek 一条路（`Settings.init` 每次都把 `llmProviderID` 写回 `deepseek`、`llmFallback` 写回 `false`），服务商列表和自动换备用是改不动的死配置，界面上却给了两个入口。

- 删除 `TaoSheng/UI/DeepSeekSettingsView.swift`（整理模型页 + 添加服务商页）；
- `SettingsView` 的「智能 → 整理模型」入口删除；「记录 → 原话与转写」改名为「模型与整理」（`ModelSettingsView`），页内新增 `llmCard`（密钥、模型、检测连接、余额与余额提醒）与 `timingCard`（自动整理、按间隔/时间点、整理前先思考、参考地点与环境音），原「什么时候整理」不再单独挂在一个不可达的页里；
- `Settings.swift` 删除 `llmProviderID` / `llmFallback` / `providersJSON` 三个字段与 `providers` / `saveProviders` / `upsertProvider` / `deleteProvider` / `backupProviders`，以及 `LLMProvider` 结构；旧 `providersJSON` 仍作为**只读**历史值传给 `DeepSeekConfiguration.migrated` 做一次性密钥迁移，迁移后不再写入；
- `LLMAuto.completeAny` 去掉备用服务商轮询，失败直接抛错（整理失败照旧保留原话、300s 后重试）。

自动整理不受影响：`DigestEngine` 走 `Settings.effectiveLLM`（固定 `https://api.deepseek.com` + 规范化模型 + `llmKey`），本次没有改动这条链路。

三、验证

- CI（macos-15）`xcodegen` + `xcodebuild archive` 零错误，警告清单 0 条；
- `swift test`（策略包 8 项）与 `node --test Tests/segment-sql.test.mjs`（SQL 回归 8 项）全通过；
- 产物：`../dist/TaoSheng-v0.5.1.ipa`（未签名，1251515 B，`CFBundleShortVersionString` 0.5.1 / `CFBundleVersion` 23，`Info.plist` 为 XML、`CFBundleSupportedPlatforms` 恰好一条 `iPhoneOS`）；
- 底部让位只在模拟器与真机手工核对，自动化测不到浮层遮挡，仍需装机复看一遍。

0.5.0 全量质量提升（2026-11-13）

本版做了一轮完整审查 + 修复 + UI 统一，目标是把「能用」推到「不崩、不卡、不歪、不像半成品」。版本号 0.5.0 (22)。

修复清单（已修复，file:line 为改动前定位）

崩溃与数据丢失

- `Core/AudioExport.swift`：导出录音包会把最多 200 段 wav 全部 `Data(contentsOf:)` 读进内存（峰值接近 2 GB），必然被系统杀进程。改为边读边写 zip（FileHandle + 256 KB 分块 CRC32 + 流式拷贝），内存占用与段数无关。
- `Audio/CaptureEngine.swift:handle()`：每个音频 buffer 都无条件 `queue.async` 一份拷贝，写盘跟不上时任务无限堆积。加了 16 个槽位的背压（`reserveSlot`/`releaseSlot`），超额直接丢块而不是涨内存；同时把断句/上限/灵敏度改成实时读，录音中改模式立即生效（原来要重开录音）。
- `Core/Store+Memory.swift:upsertEvent`：`INSERT OR REPLACE` 的列清单不含 `edited`，重新整理会把手改过的标题、摘要和 edited 标记一起重置。改为先查旧行，`edited=1` 时保留原标题/摘要并把标记写回。
- `Core/Store+Memory.swift:thing(named:)`：`name` 为空时 `name.contains($0.name)` 恒真，会返回第一条寻物记录。加了空串守卫，模糊匹配改为小写比较。

网络与并发

- `Core/NetWatcher.swift`：三个状态量由 `NWPathMonitor` 的后台队列写、主线程读，属真实数据竞争。改为 NSLock 保护的私有字段 + 只读计算属性。
- `Core/PushEngine.swift:104`：Bark 用 `.urlPathAllowed` 编码标题和正文，该字符集包含 `/`，正文带斜杠会把 URL 拆成多段路径直接 404。改为剔除 `/ ? # %` 的字符集。
- `Core/PushEngine.swift:broadcast`：每发一个通道就 post 一次 `.taoshengDataChanged`，多通道时触发 N 次全量刷新。改为一个 Task + TaskGroup 并发发送，结束后只通知一次。
- `LLM/SkillEngine.swift:84`：`fire()` 里的 `Task {}` 继承 MainActor，1200 行原话查询跑在主线程。改为 `Task.detached`。

主线程 IO（滚动掉帧的直接原因）

- `UI/TodayView.swift:377`：`digestAgo` 在 body 里同步查 `reviews(limit:1)`；`:427` `TimelineFullView.raw` 每次重绘同步查 800 行事件。都改成 `.task` + 后台查询 + 本地缓存。
- `UI/MemoryView.swift:255`：分类列表在计算属性里同步查 200 行；`:440` 原话列表点星标后不刷新。改为缓存 + 异步加载 + 写库后 reload。
- `UI/AskView.swift:399`：历史问答每敲一个字就重查 600 行（关键词本来只在本地过滤）。删除该 onChange。
- `UI/EventDetailView.swift:290`：详情页 onAppear 在主线程查 3000 行原话。改为异步。
- `UI/SettingsSub.swift:773`：模型页每 5 秒在主线程跑 6 次查询。改为一次性后台快照 + 回主线程赋值。
- `ASR/TranscribeQueue.swift:refreshPending()`：在调用线程查 999 行待转写。改为 utility 队列。

正确性与逻辑

- `UI/EventDetailView.swift:211`：`speakerNo` 只认数字说话人，实名说话人（「老王」）会全部显示成 ①。改为首字头像 + 稳定配色。
- `UI/EventDetailView.swift:329`：导出文件名直接用标题前 12 字，标题含 `/` 时写盘失败却仍弹分享面板。改为文件名清洗 + 失败提示。
- `UI/SettingsSub.swift:384`：`Toggle` 放在 `NavigationLink` 的 label 里，点开关会同时跳页。拆成并排两行。
- `UI/SettingsSub.swift:1277`：关于页版本号写死「0.2.0 · iOS」，与工程版本无关。改为读 `CFBundleShortVersionString`/`CFBundleVersion`。
- `Core/Settings.swift:134/136/146/147`：`silenceGap`、`maxSegment`、`modeSilenceGap`、`modeMaxSegment` 全项目无人读取（断句和上限由 `CaptureMode` 固定），属改了不生效的假开关，删除。
- `ASR/TranscribeQueue.swift:identifySpeaker`：簇匹配初值 `bestScore = 0.0`，相似度全负时永远开新簇，编号会一路涨。改为 -1.0。
- `Audio/MicRouter.swift:39`：设备排序比较器不是严格弱序（`a.id == current` 直接 return true），排序结果不稳定。改为标准三段比较。
- `Core/LocationEngine.swift:39`：`Timer.scheduledTimer` 之后又 `RunLoop.main.add`，定时器被重复投递。改为只 add 一次。
- `UI/Components.swift:62`：`SpeakerDot` 用 `name.hashValue` 取色，`hashValue` 每次启动都变，同一个人换一次 App 换一次颜色。改为 FNV-1a 稳定索引。
- `Core/Models.swift:27` / `Core/Models3.swift:26`：`timeText` 每次调用新建 `DateFormatter`，时间线每行每帧都在建。新增 `Core/Formatters.swift` 统一缓存格式化器。
- `Core/Store+Ext.swift:662`：`queue.sync { exec(...) }` 的返回值未使用，是本版唯一一条编译警告，改为显式丢弃。

布局

- 六处底部留白与 `RootView` 的 `safeAreaInset` 叠加：今天页 78、记忆页 78、问问页 76、待办页 92、设置页 100、模型页 100，实际底部空白最多到 158pt。统一收到 16～24，改由 `TabBar.reservedHeight` 一处负责。
- `UI/RootView.swift:22`：给 TabBar 预留的 `Color.clear.frame(height: 58)` 与 TabBar 真实高度（62）不一致，末行会被压住。改为引用 `TabBar.reservedHeight`。
- 外观设置在两个地方用同一个 `appearance` 键但语义不同（设置页写 `auto`、`TodayView` 默认 `system`），首次进入时段选器没有任何高亮。统一为 `light`/`dark`/`auto`。

UI 改动清单

- 设计令牌：新增间距 `sp1…sp6`（4/8/12/16/20/28）、字号 6 档（11/12.5/14/17/20/26）、圆角三档（12/16/22，原来是 12/14/18/20/24 混用）。问问页、事件详情页、设置页的硬编码字号与圆角全部换成令牌。
- 暗色模式：TabBar 选中态从「只变色」改为 `accentSoft` 胶囊底 + 选中色文字 + 未选中项 `line` 描边，暗色下不再糊成一片；图标 18→19pt、文字 10→10.5pt，加了无障碍标签。
- 空状态：记忆页（时间线/重点/分类/寻物/回顾/原话）、待办页（待确认/进行中/已完成）、时间线全屏页，全部从「一句话」改成「图标 + 标题 + 一句怎么产生内容」的说明。
- 加载状态：新增 `LoadingHint` 骨架屏（3 行占位 + 呼吸动画 + 可选文案），用于记忆分类列表与时间线首屏，避免切日期时白屏。
- 交互一致性：待办页顶部三个胶囊改成与 TabBar 同一套选中样式（淡橙底 + 橙字 + 细描边），未选中的计数不再用白字。
- 说话人颜色：同一个名字跨启动、跨设备颜色固定（「我」固定橙色），声纹聚类的人不再是每人一个随机色。
- 关于页版本号与外观选择器反映真实状态（见上）。

本轮未修与理由

- `Core/BackupEngine.swift`：备份快照仍只覆盖旧 `item`/`digest`/`segment`，不写 `memory_event`/`memory_item`/`skill_card`/`thing`；S3 分支的 key 未做百分号编码且不按份数清理。原因是改备份格式涉及恢复路径的数据迁移，没有真机与真实 WebDAV/S3 账号可回归，贸然改会让老备份不可恢复。
- `LLM/ReviewEngine.swift:34`：每日回顾要求 `hour >= reviewHour`，App 那天 22 点前后没运行就不补，第二天也不会补前一天。这属于产品语义（要不要补跑历史回顾），需要产品确认后再动。
- `Core/Store+Speaker.swift:renameSpeaker`：改说话人名只更新 `segment`，不回写事件里的 `people`。事件里的人是整理当时的快照，回写会让历史记录与当时不一致。
- `UI/SettingsSub.swift:288`：技能详情页里放了全局开关「生成后推送」。位置不合理，但移动它会改变现有交互路径，本轮不动。
- `UI/EventDetailView.swift` 编辑仍用 alert 里的两个 TextField，长摘要体验一般。改成 sheet 牵扯到草稿状态与键盘处理，属于交互改版而非修 bug，本轮不动。
- `LLM/PromptsAsk.swift` 仍是带 tool calling / DSML 说明的提示词，而当前 `AskEngine` 并没有工具调用。属遗留文本，删改有回归风险。
- 8 处 `.onChange(of:)` 仍是单参数闭包：双参数版本要求 iOS 17，而本工程 deployment target 是 16.0；本版编译 0 警告，保留兼容写法。
- 真机行为（按住说话手势、后台收音、通知投递时机、豆包/DeepSeek 真实密钥联调）没有设备可验，仍未验证。

0.5.0 源码调整（时间线、说话人、详情页）

- 时间线按原版重做：标题行「时间线 · N 件事」+ 右上白胶囊分段（今天 / 昨天 / 前天）；第二行橙色「全部」胶囊与「● 媒体 N」；按凌晨 / 上午 / 下午 / 晚上分组，白色大卡内每行左侧橙色时刻、右侧标题与两行摘要，行间细线。
- 点进一件事改为「抽纸式」详情页：从底部抽出，下滑即收起。内容为状态行（今天 13:20 – 13:22 · 闲聊 · 1 分钟 · 地点）、大标题、摘要、要点、原话（可逐句播放 / 导出 / 复制），底部固定「重点 / 复制 / 问问 / 删除」；「存待办」把首条要点存成待办，「编辑」可改标题与摘要（手改后标记 edited，自动整理不再覆盖）。
- 说话人：声纹认不出的人不再留空，而是按当天声音相似度聚成「说话人 1 / 2 / 3 …」，新声音自动开新簇，命中后簇心滑动平均；已建人物卡的人仍显示人名。今日节律的「我说了 / 别人说了 / 人聊过」按这套编号统计，没建过「我」时把「说话人1」视作机主。
- 今日节律改真实数据：24 根柱子按每小时说话时长归一，不再是一根装饰波形。
- 从事件详情点「问问」会切到问问页并预填问题。

既有能力（2026-11-12 起）

- 收音模式依次为日常、会议、培训、通话；移除口播稿入口和新口播卡生成，历史卡片不删除。
- 待办右下角 +：轻点打字，长按说话，松手停止收音；短暂等待尾字后填入编辑框，由用户确认保存。旁边文字只提示，不接收长按。
- 整理模型只有 DeepSeek，分为「整理用的大模型」「什么时候整理」「服务商」三张卡：主服务商固定 DeepSeek，可再添加任意 OpenAI 兼容服务商当备用，打开「出问题时自动换备用」后主服务商报错会依次试备用；不显示 token 用量，只显示余额。
- 原话与转写页补齐：顶部状态卡（转写已就绪 / 尚未就绪）、豆包 Key、主要识别语言（自动 / 普通话 / 粤语 / 英语 / 中英混合，「自动」不传 language 字段）、原声保留天数与录音包导出（本机 wav 打 zip 分享，最多 200 段）、热词入口。
- 余额查询显示真实金额、赠送额度、更新时间和失败提示；优先人民币，成功结果缓存一小时，可手动刷新。低额提醒只在设置页展示，不是后台通知。
- 自动整理遵守开关、间隔或每日整点设置，包含历史积压并分批处理；手动整理不占用定时任务的成功记录。深度思考仅用于整理请求。定时任务依赖 App 实际运行，不能保证 iOS 挂起时准点执行。

0.4.12 复审修复（2026-11-12）

- 录音：首个有声 buffer 在打开新录音段后正确记作人声，避免短语音落盘又被误删；转写队列先跳过已失败三次的记录，再取后续 8 段，避免队头堵塞。
- 记忆：重新整理保留原有事件标星；清空数据覆盖事件、事项、技能卡、寻物与环境标签；近期原话先按时间筛选再截取。
- 备份：WebDAV 地址已有百分号编码时避免二次编码，目录列表由 XML 解析并核对路径，建目录失败会明确报错。
- 回顾与技能：每日和每周回顾可同日触发，运行中去重并对失败退避，空白周报不落库；技能字段不符时不再把原始 JSON 当成正文。
- 界面：切换日期与后台刷新不再互相覆盖，历史问答搜索先完整配对再按关键词筛选；云端转写费用说明能实际弹出。
- 本版回归：`node --test Tests/segment-sql.test.mjs` 8 项通过；iOS 编译结果以本次 GitHub Actions 为准。
- 待完善：备份恢复仍仅恢复旧摘要/事项，未覆盖全部记忆和配置；S3 尚未实现按保留份数清理。

0.4.11 全量 bug 审查修复

- 提醒：重排待办提醒时不再把整理自动排的提醒一起清掉；重启后按未完成待办补排一次；只有日期的截止统一落到当天 09:00，过期不再补响。
- 整理：「重新整理」不再把同一件事重复插一遍（按 entity_id 复用旧行并保留标星）；某天没有可整理内容时不再把该天永久卡在未整理；done_hints 单条格式不合格不再整组丢弃。
- 回顾：每日回顾按事件 / 条目 / 时间窗的完整结构送模型，解析失败不写空白；周回顾真正按「哪一天 + 几点」触发，且取最近的内容而不是最早的。
- 技能：模型没返回 JSON 时直接报错让用户重试，不再把半截 JSON 当正文写库并推送。
- 问问：答案出处只保留模型真正标注的那几条；历史对话取最新 300 条（原来超过 300 条后只看得到最早的）；只命中答案的消息不再被丢掉；清空和删除后主页面同步刷新。
- 转写：手动「现在转写」不受自动开关和间隔限制，并会重试之前失败三次的段；Apple 语音识别加超时兜底，不会永久挂住队列；填完整地址带尾斜杠不再重复拼路径。
- 音频：全零检测阈值按实际采样率计算（原来 48 kHz 下 6.7 秒就误判被别的 App 占用）；第二段起「是否录到人声」判断恢复正常；短语音松手后等尾字从 1.5 秒放宽到 2.2 秒。
- 备份：WebDAV 首次自动建目录（原来 409 后不自愈）；地址做百分号编码，坚果云中文目录可用；按「保留 3 / 7 / 30 份」清理云端旧日备份。
- 性能：AppState 的 20 多次查询移到后台队列，转写完成、勾选待办不再卡住界面。

收音模式

| 模式 | 静音断句 | 单段上限 | 声纹分人 |
|---|---|---|---|
| 日常 | 1.5 秒 | 3 分钟 | 是 |
| 会议 | 2.5 秒 | 5 分钟 | 是 |
| 培训 | 3 秒 | 10 分钟 | 否 |
| 通话 | 1.8 秒 | 4 分钟 | 是 |

新录音保存自己的模式，后续切换不会改变历史段的转写、整理规则。旧录音无法还原当时模式，统一按日常兼容。
「通话」是整理规则，不代表 iOS 支持直接录制系统电话通道。

首次配置

1. 设置 → 原话与转写：填写豆包语音 API Key，并选对「识别档位」（默认 `volc.seedasr.auc`，即豆包语音识别大模型）；其他转写服务和系统识别在折叠区配置。

豆包语音转写怎么填（2026-11-13 实测）

- 端点固定 `https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash`，音频 base64 直传，不需要公网地址。
- 请求头：`X-Api-Key`（控制台 API Key）、`X-Api-Resource-Id`（识别档位）、`X-Api-Request-Id`、`X-Api-Sequence: -1`。
- **识别档位必须和账号开通的一致**，否则返回 `45000030 requested resource not granted`，这就是之前转写失败的根因：
  - `volc.seedasr.auc` 豆包语音识别大模型（默认，实测可用）
  - `volc.bigasr.auc_turbo` 录音文件识别极速版（需单独开通）
  - `volc.bigasr.auc_idle` 录音文件识别闲时版
- 状态码在响应头：`20000000` 成功、`20000003` 静音（按空结果处理）、其余失败；失败原因会翻成人话显示在原话与转写页。
- 旧版本默认写的是 `volc.bigasr.auc_turbo`，升级后会自动迁移成 `volc.seedasr.auc`，不用手动改。
2. 设置 → 整理模型 → 编辑：填写 DeepSeek API Key，选择 Flash 或 V4 Pro。整理、问问、回顾、技能共用这一份配置。
3. 回到今天页，选择模式并点「开始聆听」。

DeepSeek 固定使用 `https://api.deepseek.com`，余额为 `GET /user/balance`。
升级时只迁移确认为官方 DeepSeek 地址的密钥，不把其他服务商密钥改发给 DeepSeek；没有可迁移密钥时需要重新填写。旧服务商列表停用但保留；明确保存或清空 DeepSeek 后，不再从旧列表恢复密钥。
「检测」实际验证连接和 JSON 回复，不包含 Android 原版的工具调用、流式检测。检测会产生一次小额模型调用。

数据与权限

- 数据库：`Application Support/TaoSheng/taosheng.sqlite`；录音：`Documents/Audio/`。
- 云转写发送录音给所选转写服务；整理、问问等发送相关文字给 DeepSeek。没有自建中转服务器。
- 地点默认只存本机；开启「整理时参考地点和环境音」后，相关内容会随原话发送给 DeepSeek。
- 模型密钥沿用本机 UserDefaults 保存，编辑框遮蔽显示；尚未迁移到 Keychain，不应视为加密保险箱。
- 短语音需要麦克风和语音识别权限；支持设备端识别时优先使用，否则可能使用 Apple 语音服务。首次权限弹窗可能取消本次长按，授权后重新按住 + 即可。
- 短语音会暂时暂停全天收音，结束或取消后按原收音开关恢复。iOS 系统电话、后台回收和音频路由变化仍需真机验证。

本次验证

- 0.5.0 源码由 GitHub Actions（`macos-15`）构建通过：run 43414690508 success（commit ae48d73），编译 **0 error / 0 warning**（工作流新增「编译警告清单」步骤，`grep -c "warning:"` 输出 0；上一版遗留的 `Store+Ext.swift:662` 未使用返回值警告已修）。
- 产物：`../dist/TaoSheng-v0.5.0.ipa`（1274207 B，iOS 16+ arm64，版本 0.5.0 (22)，`CFBundleIdentifier` 为 `app.taosheng.TaoSheng`，无签名文件与描述文件）。
- `node --test Tests/segment-sql.test.mjs`：8 项通过，使用内存 SQLite 执行应用 SQL，覆盖迁移、积压查询、事件标星、手改保护的 `edited` 回写、清空表以及最近原话截取。本版起该测试也在 CI 里跑（macos-15 + Node 24），不再只靠本机。SQL 检查不验证设备录音和云服务行为。
- `swift test`：本版起由 CI 的「策略单元测试」步骤真正执行（本机 Windows 无 Swift），8 项纯逻辑测试全部通过：`CaptureMode.restored`、`DeepSeekConfiguration.migrated` ×3、`DeepSeekBalance.parse` ×2、`VoiceSessionState`、`DigestSchedule.shouldRun` 全分支。
- 尚未在 iPhone 上验证手势、后台收音、真实密钥余额联调与通知投递时机。

构建与测试

在有 Swift 5.9+ 的机器上运行纯逻辑测试：

```bash
swift test
```

在 Node.js 24+ 上运行 SQL 回归：

```bash
node --test Tests/segment-sql.test.mjs
```

在 Mac 上安装 Xcode 和 XcodeGen 后：

```bash
xcodegen generate
open TaoSheng.xcodeproj
```

命令行构建未签名归档：

```bash
xcodebuild -project TaoSheng.xcodeproj -scheme TaoSheng \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath build/TaoSheng.xcarchive archive \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

工程配置在 `project.yml`，Bundle ID 为 `app.taosheng.TaoSheng`，版本 `0.5.0`（build 22）。签名安装需自行配置匹配的证书。
仓库已有 `.github/workflows/ios-ipa.yml`；推送默认分支或手动运行会构建并发布 GitHub Release，必须经授权再操作。

本次变更和验证边界见上面「0.5.0 全量质量提升」章节与 `docs/2026-11-12-交互与DeepSeek调整.md`。
