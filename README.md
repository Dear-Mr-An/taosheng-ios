## 0.8.3（build 43）：本地模型能直接下载了

原话与转写里的「本地」这一档，0.8.2 只能落到 iPhone 自带的系统识别——不能像 Android 原版那样把模型下到手机上。这一版补上同一条路。

### 一、接的是什么

- 模型还是原版那个 **SenseVoice**（`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17`，`model.int8.onnx`），字节数 **239 233 841**、SHA-256 `c71f0ce0…cd51`，与 Android 端 `LocalModels.cpu.modelBytes / modelHash` 完全一致：同一份模型，两端口径一样。
- 推理用官方的 `sherpa-onnx` Swift 包（2.0.1，iOS 静态 xcframework，`project.yml` 里锁 `exact: 2.0.1`）。
- 下载方式改了：Android 是下 `tar.bz2` 再解包，iOS 没有系统 tar/bz2，所以直接下 `model.int8.onnx` 与 `tokens.txt` 两个文件，少一层解包，校验的哈希不变。

### 二、下载与校验

- 目录：`Application Support/asr-models/sense-voice/`，两个文件 + 一个 `.verified` 标记。
- 先下 `tokens.txt`（315 894 B，只校验大小在 1 B…1 MB 之间，与原版一致），再下模型。
- 进度按已收字节实时算：「下载 42% · 68/239 MB」，与本机预留在 `LocalModelRules` 里，单测覆盖百分比向上取整、越界、`isComplete`、续传偏移、空间判断（模型 + 40 MB）。
- 下完先落 `.part` 临时文件，用 CryptoKit 每 1 MB 流式算 SHA-256，**校验通过才 move 进正式目录**；不通过就删掉临时文件并报「文件校验不通过，请重试」，旧模型不受影响。
- 直链顺序：HuggingFace（实测 200、长度对得上）在前，`hf-mirror` 在后兜底（它现在对这两个文件是 308 跳回原站，URLSession 会自己跟随）。

### 三、转写怎么用

- `TranscriberFactory` 的「本地」档：模型就绪 → `SenseVoiceTranscriber`（`AudioPCM.mono16k` 把 m4a/caf 转 16 kHz 单声道 Float32，再 `recognizer.decode(samples:sampleRate:)`），整段离网识别。
- 模型没下好 → 仍然回落到系统识别，设置页那句「没下载时，「本地」这一档先用系统识别」是真实行为，不是安慰话。
- 转写队列的联网门禁本来就把「本地」档当离线（上一轮的 `ASRRules.needsNetwork`），所以模型就绪后在飞行模式下也能排队转写。

### 四、界面

「原话与转写」→ 语音转写卡 → 选「本地」后多一块：

- 「SenseVoice 本地模型」+ 右侧「239 MB」；
- 状态行：还没下载 / 下载 42% · 68/239 MB / 校验文件… / 已就绪 · 离网也能转写 / 没下完：<原因>；
- 按钮：下载模型（未下载）、重试（失败）、取消（下载中）、删除模型（已就绪）；
- 说明：没下载时用系统识别；下载完成后自动换成这个模型。

### 五、验证

- CI：`build-ipa` 第 164 次（`25123fb`）通过，Swift 编译 0 warning，`swift test` **82** 项全过（新增 `LocalModelRulesTests` 6 例）。
- 产物：`dist/TaoSheng-v0.8.3.ipa`，11 711 791 字节，0.8.3（build 43），未签名；比 0.8.2 大 9.4 MB，多出来的是 SherpaOnnx + onnxruntime 两个 framework。

### 六、还没做到

1. 下载中途被杀进程不续传（只在本次运行内可取消/重试，重启后从头下）。
2. 没有做「边下边用」：必须整份校验通过才能开始转写。
3. 模型目录不参与 iCloud 备份排除清单以外的清理策略；「清空所有数据」不会删模型（删模型要点卡里的「删除模型」）。
4. 真机与真实网络未验证：模拟器上下载、校验、离网转写这三步都没有在真实设备上跑过，只做了规则层单测与代码核对。
## 0.8.2（build 42）：0.8.1 复核补正

第二轮源码复核发现并修掉的问题，只改调用链与文案，不改界面结构。

1. **专题参数**：「正在聆听」抽屉里的专题开始按钮，现在把类型、名字、结束时长一起交给 `ListenFlow.start(mode:topicName:endMinutes:)`；首页「◉ 专题」保持直连 `RsTopicSheet`。
2. **麦克风插拔**：`MicRules.uidAfterRouteChange` 只清掉已经不存在的具体设备；`auto` 是策略值，拔掉外接后仍保留。每次采集启动前重新 `MicRouter.applyPreferred()`，插入设备后不必手动重选。
   另：用户点过「停止」后，再点首页圆形按钮或从暂停恢复，会清掉 `rsUserStopped`，恢复后仍能正常自动聆听。
3. **坚果云通道**：账号写进 `channel.user` 列；密码只存钥匙串（`channelPass.<通道 id>`），不进 SQLite。删除通道和「清空所有数据」会一起清掉密码；保存坚果云通道必须填账号 + 应用密码；通道可单独启用/停用，设置首页只数启用的通道。
4. **备份范围**：快照/恢复从旧的 `item` / `digest` 表改为当前界面真正读的 `memory_event` / `memory_item`（事件、待办、关键原话）。旧格式备份仍可读，恢复时提示「旧格式」。
5. **回顾与提醒**：提醒列表支持左滑删除，删除同时取消系统通知；不再只有展示。
6. **原声保留**：`keepAudioDays` 现在由启动 / 回前台每天最多执行一次 `purgeOldAudioIfDue()`，不再只能手动点「现在就清掉过期的」。
7. **清空文案**：明确写清「模型密钥、识别密钥和备份设置保留」，与实际范围一致。

验证：本机（Windows）没有 Swift / Xcode，单测与 IPA 需由 CI 重新跑；`StopRules` 新增 1 例 `uidAfterRouteChange` 回归测试。

## 0.8.1（build 41）：设置里的功能按真实数据流修一遍

上一轮把设置页的控件都接上了，但静态核对发现有一批是「存了不用」「写死数字」「错报成功」。这一轮只修这些，不加新界面。

### 一、会出错的（P0）

1. **停止**：普通全天聆听点「停止」以前只把 `captureWanted` 置 false，采集线程没停，回到前台还会被自动拉起。现在：`StopRules` 区分「用户停止」与「会话结束」；用户停止 → `CaptureEngine.stop()` + `rsUserStopped=true`，前台 `onChange` 与 `onAppear` 都走 `StopRules.shouldAutoStart`（用户停过就不再自动开）；专题/会话结束 → 仍恢复一直聆听。
2. **麦克风**：`MicRules.choice` 把空 UID 明确翻成 `builtInMic`（`setPreferredInput(builtIn)`），不再只 `setPreferredInput(nil)` 让系统随便挑；`auto` 插拔保留偏好，重新 `applyPreferred()`；页面「正在用」读 `MicRouter.currentName()` 的真实路由。
3. **密钥**：只读写当前 provider 的键（豆包 → `doubaoApiKey`，自定义/本机 → `asrKey`），弹窗 `SecureField`、不预填，保存/清除只改当前 provider，不在界面上回显任何已保存的 Key。
4. **ASR 地址**：`ASRRules.endpoint(base:legacyFull:)` 以页面上的 `asrBaseURL` 为准，旧的 `asrFullURL` 只在没有新地址时兜底；改地址后队列与「测试」都请求新地址，不会再偷偷把音频和 Key 发到旧服务。
5. **2xx 但不是识别结果**：`ASRRules.parseReply` 只接受 JSON 里非空 `text`；`{"error":…}`、空 `text`、HTML、空响应都抛 `TranscribeError.badReply`，段保持 `failed` 可重试，不会把整段 HTML 当原话。
6. **本机识别离线**：`ASRRules.needsNetwork` 只有上传类 provider 为真，Apple Speech 在无网时也进自动队列（`tick` 与 `nextRunAt` 都放行）。
7. **导入录音**：复制成功且入库成功才算成功；去重键 = 相对路径 + 大小 + 修改时间（不再用文件名）；批量里失败的文件进失败清单、下次还能重试，界面上逐个报。
8. **转写完成后刷新**：页面订阅 `taoshengDataChanged`，新文字一落库就重读原话列表与待转写数。

### 二、专题与生命周期（P0）

9. 英雄卡「◉ 专题」独立打开专题面板（不再和「正在聆听」共用一个开关），开始按钮把类型、名字、结束时长一起交给 `ListenFlow.start(mode:topicName:endMinutes:)`。
10. 手动结束专题恢复普通聆听；设置页点「停止」保持停止（显式 `StopReason`，不再一律重启）。
11. 专题记录读全部会话（最多 100 条）并显示 `TopicStore` 里保存的命名；「预约专题 / 忘了点开始」这一版没做，入口已从面板移除，矩阵里标「未实现」。
   **平台限制**：iOS 进程被杀以后不能在后台按计划继续录音。进程内的定时结束与回前台补检保留；启动时发现 `recording` 会话按「进程中断」收尾并如实记录，不声称能跨进程续录。

### 三、模型与整理（P0）

12. 自定义服务商真正生效：`LLMRoute` 规范地址、判断是否官方 DeepSeek；`effectiveLLM` 不再把 base 重置成固定值、模型也不再强改成 deepseek-flash。余额查询只对官方接口可用，其他 provider 显示「余额查询只支持 DeepSeek 官方接口」，不会把 Key 发给 DeepSeek。
13. 整理间隔允许 5…720 分钟自定义，重启后不会变回 30（预设档位只决定界面怎么显示）。
14. 余额阈值被消费：刷新成功后低于阈值显示「低于提醒线 ¥N」；未配置 / 非官方 / 失败各有明确文案。
15. 「一直在说，最多等多久」不再只是文案：`DigestWindow.headCount` 按 `sessionCapMin` 决定一批整理多少条，30/60/120 三档结果不同；音频切段仍按 `CaptureMode.maxSegment`，两者分开。
16. 「停多久算说完了」变成真门禁：距最后一段结束不足 `sessionIdleMin` 或还有待转写段时，`afterTranscribeRound` 不整理；地点与环境音按段的 id / 时间区间挂，不再用 `rows.enumerated()` 的下标（插了话题分隔行会错位）。

### 四、不再显示假功能（P1）

17. 足迹读 `Store.places(day:)` 的真实停留，时间轴按真实记录渲染，三栏按真实停留算；没实现「路线」切换就删掉；高德 Key 入口（只存不用）已删除，页面写明只用系统地理服务。
18. 声纹页删掉「在原话里长按一句选这是谁」与「样本声音」这两处没有实现的入口，改成如实说明；「本地多人分段」默认值与 Kotlin `speakers-enabled` 一致。
19. 设置首页搜索框真的过滤（标题 / 详情 / 分组，命中为空时显示「没有找到」）；「语音输入时记上下文」没有任何消费者，开关与文案已删除。
20. 诊断页按日「件数」改读整理表（`memory_item`），导出用同一数据源；状态卡不再写「连续稳定 N 天 · 今天中断 M 次」，改成「状态检查未完成 · 还没有中断统计」。
21. 外观只提供浅色：`RsKit` 的颜色是按浅色写死的，没有深色令牌，所以不提供「深色 / 自动」，根视图锁定浅色，页面写明原因。
22. 环境音文案改成真实机制（转写后对已录片段做音量 / 过零率 / 高频占比的启发式判断，不下载 27 MB 模型，不上传）；版本更新页按数字段比较版本，差异时显示发布说明，失败给原因。

### 五、验证

- `build-ipa` 第 156 次（`fd733b3`）：Swift 0 warning，`swift test` 75 项全过。
- 新增/扩充单测：`StopRules`（用户停止、会话结束恢复、Mic 内置/自动、插拔保留偏好）、`LLMRoute`（官方判定、`api.deepseek.com.evil.com` 不算、模型不被替换）、`ASRRules`（provider 往返、地址优先级、离线门禁、200 HTML/`{error}`/空 text 解析）、`DigestWindow`（idle 未到不整理、cap 三档不同）、`ImportRules`（同上名不同内容、失败清单）、`LocationStats`（在家/外出/距离）。
- 产物：`dist/TaoSheng-v0.8.1.ipa`（2 273 963 字节，未签名，`0.8.1` / `41`）。
- 没测的：真机、真实密钥、真实网络、真实备份恢复与清空（本轮全部用假数据 / 不发真实请求；也没有回显或清空任何真实密钥）。

### 六、还没做到（如实）

1. 预约专题、忘了点开始：未实现，入口已移除。
2. 声纹：没有「在原话里指认说话人」的入口，只按已有分段统计。
3. 足迹：没有第三方地图，只用系统地理服务；没有「路线」视图。
4. 深色模式：没有配色。
5. 整理技能 / 推送通道 / 备份 / 回顾与提醒 / 隐私与数据这五页仍是 0.6.x 的旧页面，没有按原版逐项重做（矩阵里标「未逐项核对」）。
6. 进程被杀不能按计划继续录音（平台限制，见第 11 条）。

## 0.8.0（build 40）：设置里的功能逐项接通

这一版不做界面调整，只把「设置里看着能点、实际没接上」的地方接成真的：每个开关、输入框、按钮都落到 Settings / UserDefaults / Keychain / Store 上，并且有真实的消费者（转写队列、整理引擎、录音引擎、位置引擎、推送）。

### 一、暂停跨进程恢复（真实 bug）
原来 `RsQuiet` 启动时发现暂停时间已过，只把 `rsQuietUntil` 删掉，没有把 `captureWanted` 设回 true，也没有启动录音——暂停 15 分钟、杀掉 App、过期后重开，录音仍然是停的。

现在：
- 新增 `TaoSheng/Core/Policies/QuietRules.swift`：`onLaunch(savedUntil:heldByPause:now:)` 返回 `stillPaused / expiredResume / idle`；纯函数，可单测。
- `RsQuiet.init()` 按规则处理：`.expiredResume` 时清两个键、`captureWanted = true`、非截图模式且没在跑时 `CaptureEngine.start()`。
- `pause()` 记 `rsQuietHeldWanted = true`，只有「确实被暂停按住过」的才恢复，不会把用户手动停掉的录音又拉起来。
- `TaoShengApp` 启动时 `_ = RsQuiet.shared`（在 captureWanted 判断之前执行），回前台时 `checkNow()` 到点即恢复。
- 单测 `Tests/Policies/QuietRulesTests.swift` 5 例，含「正好到点算过期」。

### 二、原话与转写（全部接真实设置）
- 语音转写分段（豆包 / 本地 / 自定义）写 `settings.asrKind`；密钥按引擎写对字段——豆包写 `doubaoApiKey`，自定义写 `asrKey`（原来一律写 `asrKey`，豆包引擎根本读不到）。
- 自定义档补 `asrBaseURL` / `asrModel` 输入；「自定义请求头」真的编辑 `asrCustomHeaders`。
- 「多久转写一次」映射 `transcribeIntervalMin`（实时 1 / 15 / 30 / 自定义 5…240），`TranscribeQueue.nextRunAt` 读同一个值，重进页面保持。
- 「导入录音」走系统文件选择器，拷进 `Store.audioDir`、读真实时长、写 `Segment(state: .recorded)`、落库并立刻排队转写。
- 「开始培训专题」直接 `ListenFlow.start(mode: .training)`；「测试」用当前引擎对最近一段真实音频跑一次转写，显示成功片段或失败原因。
- 热词输入框接 `addHotword` / `deleteHotword`，并加「整理时用热词」开关（`hotwordEnabled`）。
- 「录音原话」按今天/昨天/前天查 `Store.segments(day:)`，不再是写死的行。

### 三、模型与整理时间（全部接真实设置与引擎）
- 三档整理时机写 `digestTiming`；间隔写 `digestIntervalMin`；时间点写 `digestHour`；`DigestSchedule` / `DigestEngine` 消费同一份配置。
- 新增 `sessionIdleMin`（停多久算说完了）与 `sessionCapMin`（一直在说最多等多久）：前者进入 `DigestEngine.buildLines` 的换话题分隔，后者在 `CaptureEngine` 里与模式上限取小值，真正决定切段。
- 服务商「编辑」写 `llmBaseURL / llmModel / llmKey`；「检测」用当前配置真发一次请求；「刷新余额」读 DeepSeek 官方余额接口，未配置显示「还没配置密钥」，失败显示原因；「添加服务商」写备用 `llm2*`（Keychain），「出问题时自动换备用」绑 `llmFailoverOn`，`LLMAuto.completeAny` 主服务商失败时真的切备用重跑。
- 用量卡接 `LLMUsage`（按天记 prompt/completion，`LLMClient` 解析 `usage` 时写入），今天/本周/30 天都算真实数字，没有调用就显示「这段时间还没有调用大模型」。
- 余额提醒阈值绑 `balanceAlertThreshold`。

### 四、专题闭环
- `TopicRules`：`endAt(start:minutes:)`、`shouldAutoFinish(endAt:now:isRecording:)`、`displayName(_:kind:)`，4 组单测。
- `RsTopicSheet` 开始专题时把名字与「什么时候结束」一起传进 `ListenFlow.start(mode:topicName:endMinutes:)`，`TopicStore` 按会话 id 存下来。
- 到点由主线程 `Timer` 自动 `stop()`；App 被杀重开后回前台会 `checkTopicDeadline()` 补一次（计划时间已过且还在录就当场收尾）。
- 专题名进入 `SessionDigest.run(topicName:)`：提示词里标明专题名，产出事件的标题直接用专题名，记录列表里能认出是哪一场。

### 五、录音与后台 / 声纹 / 足迹
- 录音输入两行真实绑 `preferredInputUID`（`""` 手机麦克风、`"auto"` 自动先外接）；`MicRouter.applyPreferred()` 新增 `auto`：有非 `builtInMic` 的输入就切过去，没有就用手机麦克风。点「外接设备」打开 `MicRouter.inputs()` 列表选取。
- 「＋ 添加文件夹」走系统目录选择器，写 `autoImportFolder` 并扫描一次（m4a/mp3/wav/aac/caf/aiff/aif/flac/mp4），去重后逐段导入并排队转写。
- 后台设置四项目前按真实状态算：麦克风权限（`AVAudioSession.recordPermission`）、通知权限（`UNUserNotificationCenter`）、后台音频（`UIBackgroundModes` 含 audio）、低电量模式（`isLowPowerModeEnabled` 取反）。完成数随真实状态变化，未完成项给「去设置」跳系统设置页。
- 声纹：「添加人物」「删除人物」接 `AppState`；「本地多人分段」绑 `speakerSplitOn`（不再是页面本地状态）。
- 足迹：开关 set 里立刻 `LocationEngine.syncWithSettings()`；日期行 ‹ › 真翻页（最多回看 30 天）；高德 Key 用 `@AppStorage` 持久化，写入/清除都有反馈。

### 六、通用组与诊断
- 「外观」：自动 / 浅色 / 深色写 `appearance`，`RsShell` 根上 `.preferredColorScheme` 真实生效。
- 「版本更新」：显示当前版本与 build，查 GitHub 最新 release 的 `tag_name` 做比对，失败给原因。
- 「高级与诊断 → 整理要求与诊断」：整理要求是多行文本，写进去会拼到整理提示词末尾（`用户额外要求`）；同一页还给按日统计（最近 7 天真实段数 / 件数）、守护记录（是否在收音、这次从什么时候开始、今天中断次数）、麦克风占用（当前输入名 / 采样率 / 声道 / 权限）、导出诊断文本（`ShareLink` 分享）。

### 七、验证
- `build-ipa`（提交 `aa68806`）：0 条 Swift warning，`swift test` **49 项全过**（新增 QuietRules 5、TopicRules 4、ASRRules/PushGate/WipeRules 共 4 组）。
- 交付 `dist/TaoSheng-v0.8.0.ipa`（未签名，`0.8.0` / `40` / `MinimumOSVersion 16.0`，无 `_CodeSignature`）。

### 八、还没闭环（如实列出）
1. 整理技能页、推送通道页、备份页、回顾与提醒页、隐私与数据页仍是 0.6.x 旧页：开关与表单在，但没有按这一轮的「保存位置—消费者—验证」标准逐项核对；`ChannelsView` 的坚果云账号在刷新后可能丢，`BackupView` 的恢复范围没写明。
2. 「高级与诊断」（整理要求、按日统计、守护记录、麦克风占用、导出）还没做。
3. 环境音识别只做了开关与持久化，没做模型下载进度与状态反馈。
4. 预约专题（到点自动开始）、忘了点开始（事后选一段时间）仍只有入口与说明。
5. 备份的自动策略、隐私的自动清理调度、「清空所有数据」是否包含 Keychain 项，都还没落到实现与文案一致。
# 涛声 iOS

界面与功能参考 Android 原版 [0xCoach/TaoSheng](https://github.com/0xCoach/TaoSheng) 0.4.0（FSL-1.1-MIT，仅供个人使用）的 SwiftUI 重写，iOS 16+，无第三方运行依赖。
全天收音 → 人声切片 → 转写 → DeepSeek 整理事件、待办和记忆。数据使用本机 SQLite。


## 0.7.5

这一版只修两件事：验收图本身要对（截图路由、滚动定位、截图数据），以及上一轮复核里确认的几处界面差异。界面结构不动。

### 一、验收图与截图路由

- 滚动图不再按百分比猜位置。`RsSubPage` 改成 `ScrollViewReader` + 锚点：每个滚动画面在页面里对应一个 `.id()`，截图前滚到那个锚点（滚两次，等布局算完）。
  - `rs-recording-b` → `rec-input`（录音输入）、`rs-recording-c` → `rec-backend`（后台设置）
  - `rs-transcript-b` → `tr-speech`（语音转写）、`rs-transcript-c` → `tr-raw`（录音原话）
  - `rs-llm-b` → `llm-timing`（什么时候整理）、`rs-llm-c` → `llm-idle`（停多久算说完了）
  - `rs-location-b` → `loc-day`（这一天）、`rs-voice-b` → `vp-samples`（样本声音）
  - `rs-settings-b` → `row-transcript`（原话与转写那一行，在 `RsShell` 里滚）
- 新增画面 `rs-memory-all`：记忆页按天，滚到回顾卡在顶端——就是原版 `.tmp/ref/15-memory-all.png` 那一屏（回顾卡 + 「卡片 2 张」+「时间线 42 件事」）。`17-all` 用它跟原版对齐，`18-memory-cards` 用 `rs-memory-cards`（卡片区对齐）。
- 角标版本号照 `ios/project.yml` 的 `MARKETING_VERSION` 读（`iOS 0.7.5  402pt`）。

### 二、截图数据对齐原版

截图模式（`ShotMode`）里的数字改成跟参照图一致，免得数量、换行、卡高都对不上：

- 今天英雄卡：28 分钟 / 42 件 / 4 条待确认；待确认卡片 4 张（第 2 条「我答应别人」改成待确认，凑到 4）。
- 时间线「媒体 42」、记忆页「时间线 42 件事」。
- 设置首页状态卡第二行固定「连续稳定 0 天 · 今天中断 2 次」。
- 原话与转写：「都转完了」「上次 今天 15:43 · 约 9 分钟后下一轮」「今天 29 分 · 近 30 天 314 分 · 约 ¥4.2」「已填写」。
- 录音与后台：「安静中 · 已持续 4小时32分」。
- 设置首页：模型「DeepSeek · ¥12.84」、整理技能「开了 3 个」。

### 三、界面

1. 设置首页行图标颜色照 `SettingsHome.kt` 的 `Tints`：模型与整理时间 `7C5CC4`（紫）、整理技能 `5B5BD6`、推送通道 `3B82C4`、外接设备 `F2994A`、原话与转写 `E0A030`、声纹与人物 `E06A50`、环境音识别 `D4A017`、足迹 `C9643A`。
2. 设置首页「已暂停」红点：截图模式一律「正在聆听」、无警示点；真机走 `CaptureEngine.isRunning`。
3. 录音与后台：子页改成原版间距——列表段间 22dp、段内小标题与白卡之间 7dp，卡外灰说明贴近所属卡片；页面顶部内边距 8dp。这样「停录时段 / 录音输入 / 语音输入 / 自动导入文件夹 / 后台设置」各段的上下留白跟原版一致，不再整体往下挤。
4. 模型与整理时间：「多久整理一次」保持白色滑块分段控件；「按间隔 / 按时间点」「停多久算说完了」「一直在说，最多等多久」才是实心橙胶囊。
5. 足迹：日期行 `‹` 贴边、日期居中加粗、`›` 贴边；「这一天」加粗；空态卡 260pt，三栏数字贴卡底、无分隔线。
6. 记忆卡片：36pt 类型色图标方块、彩色首行（技能名 + 时间）、15pt 粗体标题、13pt 灰摘要两行，每周回顾整行浅紫 `E7E4F8`，卡片按时间正序，「卡片」后灰色「2 张」。

### 四、版本与验证

- 0.7.5（build 39）。
- `build-ipa` 第 141 次运行（`3016590`）通过：Swift 编译 0 warning，`swift test` 36 项全过，SQL 回归 8 项通过；产物 `dist/TaoSheng-v0.7.5.ipa`（2 141 820 字节，未签名；Info.plist 0.7.5 / 39，`MinimumOSVersion 16.0`，包里没有 `_CodeSignature`）。
- `shots` 第 84 次运行（`3016590`）出 75 张，其中 iPhone 16 的 `rs-*` 28 张；拼图 `.tmp/compare-0.7.5/` 28 张，逐张看过。

### 五、还没做到 / 没验证

- 后台设置仍是 iOS 能做的四项（麦克风权限、通知权限、锁屏继续录音、低电量模式）；原版的「忽略电池优化」「最近任务锁定」在 iOS 没有对应能力。
- 记忆页按类下的「卡片」分类与第二排小胶囊（回顾 / 每周回顾 / 会议速记）没做；卡片区在按天页。
- 设置「通用」组缺「外观」（自动 / 浅色 / 深色）与「版本更新」两行。
- 抽屉与事件详情仍是自绘覆盖面板，不是系统 modal。
- 时间线行数来自演示数据（11 件），只有标题里的 42 是参照图数字。
- 小屏（iPhone SE）没拍 `rs-*`；真机与真实密钥未验证。

## 0.7.4

这一版只做上一轮（0.7.3）核对图里没对上的九处细节，界面结构不动。

### 一、对比图本身

- 0.7.3 的四张滚动图（`09-recording-b`、`10-transcript-b`、`13-location-b`、`14-llm-b`）右边全是今天页：截图模式只认画面名，不认后缀。这版加了 `ShotMode.baseShot()`，把 `-b` / `-c` / `-d` 去掉再找 tab 与子页，滚动位置由 `RsScrollFrac`（`UIViewRepresentable`，挂上 0.9 秒后把 `UIScrollView` 的 `contentOffset.y` 设成 `maxY × 0.38 / 0.68 / 1.0`）负责。
- 角标版本号从 `ios/project.yml` 的 `MARKETING_VERSION` 读，不再写死。
- `05-settings-b` 左图改成原版设置页真正上滑后的那一屏；`17-all` 两边都对齐到「卡片 / 时间线 43 件事」这一块，iOS 用新加的 `rs-memory-cards` 画面滚到卡片区。
- Android 那边模拟器已经是 11/16 且没有当天数据，带数据的滚动参照只能沿用 11/15 那批图，这版没有再重截那些。

### 二、界面

1. 通用值行 `RsValueRow`：左边标题用正文黑色，右边值右对齐 + `›`。「外接设备 未连接」和「余额提醒 低于 ¥10 时提醒」两处都换掉（原话与转写里那三行仍是左标签式的 `RsInfoRow`，原版就是那个样式）。
2. 自动导入文件夹：小标题挪到卡外，卡里只剩一行「＋ 添加文件夹」（加号在浅橙圆里、文字橙色），两段说明改卡外灰字，删掉多出来的「录音笔、录音机存的文件夹」。
3. 后台设置：标题挪到卡外、右边橙色「3 / 4 已完成」；每项左边浅绿圆角方块里的勾，未完成的是数字方块，「我已设置」挂在未完成那一行右侧。iOS 做不到的两项（忽略电池优化、最近任务锁定）换成「锁屏继续录音」「低电量模式」，没有留假勾。
4. 模型与整理时间：「多久整理一次」按原版换成白色滑块的分段控件；「按间隔 / 按时间点」「停多久算说完了」「一直在说，最多等多久」仍是实心橙胶囊 —— 原版就是这两种样式混着用。
5. 足迹：`‹` 贴左、日期居中加粗、`›` 贴右；「这一天」加粗；空状态卡 260pt 高、三栏数字贴卡底、去掉分隔线。
6. 声纹与人物：「本地多人分段」默认开（原版偏好 `speakers-enabled` 默认 true）。
7. 记忆页卡片照 `SkillVisuals.kt` 的 `SkillCardRow` 重做：36pt 类型色图标方块 + 彩色「会议纪要 · 今天 15:41–15:43」+ 粗体标题 + 灰摘要，行间分隔线左缩进 64；每周回顾整行浅紫（`E7E4F8`）；「卡片」后面跟灰色「2 张」。截图模式造了一张会议纪要卡（今天 15:41–15:43）和一张每周回顾卡（今天 21:00）。
8. 设置首页右侧状态：截图模式下统一显示「正在聆听」，不再因为模拟器没开录音而显示「已暂停」红点；真机正常聆听时走 `CaptureEngine.isRunning`，与之前一致。

### 三、版本与验证

- 0.7.4（build 38）。
- `build-ipa` 第 137 次运行（`b310eef`）通过：Swift 编译 0 warning，`swift test` 36 项全过，SQL 回归 8 项通过；产物 `dist/TaoSheng-v0.7.4.ipa`（2 129 974 字节，未签名，0.7.4 / 38）。
- 中间 `build-ipa` 第 135 次失败过一次（`ShotMode.swift` 里新写的 `seedCardsIfNeeded()` 与文件末尾同名旧函数冲突），删掉旧函数后第 136 次通过。
- `shots` 第 80 次运行（`b310eef`）出 74 张，其中 iPhone 16 的 `rs-*` 27 张；拼图 `.tmp/compare-0.7.4/` 共 27 张，已逐张对照。

### 四、还没做到 / 没验证

- 事件详情、专题抽屉、搜索抽屉仍是自绘面板（覆盖在页面上），不是系统 modal。
- 记忆卡片区在按天页排在「回顾」之后；原版按天页顺序是 回顾 → 卡片 → 时间线，这一版一致，但原版还有按类下的「卡片」分类第二排小胶囊（回顾 / 每周回顾 / 会议速记），iOS 没做。
- 后台设置只列了 iOS 能做的四项；电池优化、最近任务锁定在 iOS 没有对应能力，按上文替换。
- 小屏（iPhone SE）这轮没有拍 `rs-*`。
- 真机与真实密钥未验证（模拟器没有麦克风，英雄卡状态靠截图模式 override）。

## 0.7.3（第十六轮）

这一轮没有新功能，全是对照原版（Android 0.4.0）修细节，外加把对比图本身修对。

### 对比方法的两处错

- 四张滚动图（`09-recording-b`、`10-transcript-b`、`13-location-b`、`14-llm-b`）右边截到的都是今天页：`ShotMode` 只认 `rs-recording` 这样的名字，带 `-b` 后缀的没进路由。现在 `RsShell.baseShot(_:)` 会先去掉末尾的 `-b` / `-c`，再用名字找 tab 与子页，滚动由 `RsSubPage` 里的 `RsScrollFrac` 负责——`-b` 停在内容 55% 处，`-c` 滚到最底。
- `17-all` 左边原来用的是记忆页顶部，右边是时间线，两边不是同一画面。原版用 adb 重截了滚到「时间线 43 件事」那一屏（`.tmp/ref/15-memory-all.png`），现在两边都停在时间线。
- 对比图角标改成从 `ios/project.yml` 读 `MARKETING_VERSION`，以后改版本不用再动脚本。

### 界面

- 事件详情：从系统 pageSheet 换成自绘 `RsBottomSheet`（白底圆角 28、背景压暗、下拉关闭），不再有顶部黑条和后面露出的卡片；面板打开时同样把内容层提到 TabBar 之上。
- 录音与后台：整页按原版重排——状态卡右上角「手机麦克风」、中间橙色点状波形；「停录时段」改卡外小标题 + 右侧「未开启」，卡内「睡眠 23:00 – 次日 07:00 · 每天」+ 开关 + 分隔线 +「+ 添加时段」（加号在浅橙小方块里），卡外灰字说明；「录音输入」卡外小标题，卡内两行单选（左圆形头像「手」「自」，右单选圈），卡外「● 正在用：手机麦克风」+ 灰说明；「外接设备 未连接 ›」单独一张卡；「语音输入」卡外小标题、开关默认关。
- 声纹与人物：「在原话里长按一句，选「这是谁」…」移到人物卡外；「试用」紧跟「本地多人分段」。
- 足迹：日期行改成普通 ‹ › 加粗日期，去掉白色圆按钮；「这一天」空态上下留白加大，三栏数字贴到卡底。
- 原话与转写：「语音转写」分段控件改成内容宽度（原本撑满整行）。
- 模型与整理时间：「检测」「刷新余额」改浅橙底橙字，「编辑」橙色；「按间隔 / 按时间点」「多久整理一次」「每天整理」「停多久算说完了」「一直在说，最多等多久」都换成独立的实心橙胶囊（选中实心橙底白字）。
- 小字号：14、17 这类不在原版字号表里的值收进 Kotlin 档位（caption 12 / subhead 13 / body 15 / headline 16 / title 20 / largeTitle 32），设置子页灰说明与「已填写」行的字号一起改。

### 版本与验证

- `0.7.3`（build 37）。
- `build-ipa` 第 134 次运行（`4399666`）通过：Swift 编译 0 warning、`swift test` 36 项全过、SQL 回归通过。
- `shots` 第 77 次运行（`4399666`）产出 73 张截图，对比图在 `.tmp/compare-0.7.3/`：上一轮 21 张 + 新增 `-c` 三张（录音、原话与转写、模型）+ `-b` 两张（声纹、设置）+ 修正后的 `17-all`，共 26 张。
- 产物：`dist/TaoSheng-v0.7.3.ipa`（2 112 157 字节，未签名，0.7.3 / 37）。

### 还没做到

- 对比图里的滚动位置是按比例算的，和原版手滑停的位置不完全一致，个别图上下会差半屏。
- 原版「预约专题 / 忘了点开始」两个入口仍只提示「这版还没做」。
- 记忆「按类」的分类仍来自我们自己的整理结果，原版另有的「重点 / 寻物 / 知识 / 卡片」没有对应数据源。
- 设置子页里「自动导入文件夹」「后台设置」的权限检测只做了展示，没有真的去查系统权限。
- 真机与真实密钥仍未验证（模拟器没有麦克风，英雄卡状态靠截图模式覆盖）。

## 0.7.2

这一版只做一件事：把设置里的六个子页、专题抽屉的次要入口、记忆的「按类」、待确认卡片这些和原版（Android 0.4.0）还差着的地方，逐页照着 Kotlin 源码和原版截图重做了一遍。

### 一、设置六个子页照原版重做

原版每个子页的骨架是 `SettingsScreen.kt` 的 `SubPageBar`（左上「‹ 设置」+ 居中标题）加一叠白卡。这次六个页面都按原版的顺序和文案重排：

- **录音与后台**：状态卡（正在聆听 / 安静中 · 已持续多久 / 声波点线 / 暂停 1 小时 · 停止）→ 停录时段（睡眠 23:00–次日 07:00 · 每天、添加时段）→ 录音输入（手机麦克风 / 自动先外接、正在用：手机麦克风、外接设备 未连接）→ 语音输入 → 自动导入文件夹 → 后台设置（3 / 4 已完成、麦克风权限、通知权限、忽略电池优化、最近任务锁定、我已设置）。
- **原话与转写**：状态卡（都转完了 / 上次今天 15:43 · 约 10 分钟后下一轮 / 现在转写、导入录音 / 云端转写、原声、录音包三行）→ 语音转写（豆包 / 本地 / 自定义、自定义请求头、豆包语音密钥、已填写 · 更换 · 清除）→ 多久转写一次（实时 / 15 分钟 / 30 分钟 / 自定义）→ 只在 WiFi 下转写、外放声音时不转写、区分说话人与认人 → 培训专题入口 → 测试一下 → 热词 → 录音原话。
- **声纹与人物**：人物列表（头像 + 名字 + 还没有声音 + ›）加「添加人物」；本地多人分段（带「试用」小标）；样本声音；底部「还有 N 段等着匹配声音」。
- **环境音识别**：只有一段说明加一张开关卡，没有分组标题（原版就是这样）。
- **足迹**：记录全天位置开关卡；日期切换（‹ 11月15日 周日 · 今天 ›）；「这一天」卡（时间轴 / 路线、空态文案、在家 / 外出 / 移动距离三栏）；显示地名加高德 Key。
- **模型与整理时间**：整理用的大模型（服务商单选行、余额 ¥12.88 · 含赠送 ¥0.00、检测 / 刷新余额、出问题时自动换备用、添加服务商、余额提醒、密钥说明）→ 什么时候整理（按间隔 / 按时间点、多久整理一次、整理要等转写完成、停多久算说完了、整理前先思考、整理时参考地点和环境音、用量）。原版没有「转写完就整理」，这一版也删掉了。

选项行统一改成原版那种「浅灰轨道 + 白色滑块」的分段控件（`RsSegControl`），不再是自己画的一排浅橙胶囊。

### 二、专题抽屉的次要入口

「预约专题」「忘了点开始」照原版 `SideEntry`：没有左侧图标，粗体标题加灰色副标题，右侧一个 ›；两张卡横排并排。两个入口点下去仍然只提示「这版还没做」，原版那套预约与补选的流程这一版没做。

### 三、今天页

- 待确认小卡不再固定 176 高（原来下面空出约 80pt，把时间线往下推），现在高度跟内容走，按钮紧贴文字。
- 英雄卡的数字行、分隔线、整理状态行各收 2pt，整卡比上一版矮一截。
- 设置首页「一切正常」卡改成状态圈 28、对勾 13、主行 16 加粗、说明 13，上下留白 11，和原版的 52dp 高度对上。

### 四、记忆页按类

- 「按类」时右上角不再有「导出」。
- 分类胶囊从「重点」开始，去掉了「全部」：重点 / 寻物 / 灵感 / 关键信息 / 决定，后面再补我们数据里真出现的类别。
- 空态照原版：「在时间线上把一件事往左滑，就能标成重点。标过的事会集中放在这里，问问能查，每日和每周回顾也会跟进」；其他分类给一句对应的说明。
- 时间线每一行支持左滑，滑出 84 宽的「标重点 / 取消重点」，点一下就落库。

### 五、事件详情照原版重做

新增 `RsEventSheet`，结构照原版事件详情：一行「今天 07:00 – 07:10 · 会议 · 10 分钟」加右侧「存待办 / 编辑」；大标题；摘要；「原话」配「▶ 播放这件事」「导出」；白卡里按说话人分行（编号圆点 + 说话人 + 时间 + 播放 + 正文）；底部「★ 重点 / 复制 / 问问 / 删除」；最后一条「设为专题（可连带前后几件事合成一件）›」。原来那套「速记 / 原话 / 发言」三档切换的旧详情页不再用于 Resound 页面。

### 六、小号文字按 Kotlin 的 sp 全部调小

`RsType` 在 Kotlin 里是 largeTitle 32/38 Bold、title 20/26 SemiBold、headline 16/22 SemiBold、body 15/21、subhead 13/18、caption 12/16、number 26/30 SemiBold、section 13/18 Medium。iOS 这边原来整体大 1–2pt（34 / 21 / 17 / 16 / 14 / 12.5 / 13.5 / 28），这一版全部改成和 Kotlin 一致。

### 七、截图与验证

- `build-ipa` 第 127 次（`192e2f4`）修完编译错误后通过；第 130 次（`4c1e35d`）为最终通过的一次：Swift 编译 0 warning（日志里只有 Node 的 punycode 弃用提示），`swift test` 36 项全过，SQL 回归 8 项通过，产物 `dist/TaoSheng-v0.7.2.ipa`（2 110 375 字节，未签名，`CFBundleShortVersionString 0.7.2` / `CFBundleVersion 36` / `MinimumOSVersion 16.0`）。
- `shots` 第 73 次（`4c1e35d`）出 68 张，其中 iPhone 16 的 `rs-*` 画面 21 个：上一版的 15 个，加上 `rs-recording-b`、`rs-transcript-b`、`rs-llm-b`、`rs-location-b`（子页滚到底的第二屏）、`rs-event`（事件详情）、`rs-all`（时间线全部）。
- 对比图在 `.tmp/compare-0.7.2/`，按安卓 1440px ÷4 = 360dp、iOS 1206px ÷3 = 402pt 换算，统一 1 逻辑单位 = 1.5px、顶部对齐，共 16 张：上一版 15 张里除 `03-memory` 与 `15-memory-class` 之外的 13 张，加 `09-recording-b`、`10-transcript-b`、`13-location-b`、`14-llm-b`、`16-event`、`17-all`。

### 还没做到

1. 预约专题、忘了点开始：只有入口，点了提示「这版还没做」。
2. 记忆「按类」的分类名来自我们自己的整理结果，原版的「重点 / 寻物 / 知识 / 卡片」里只有「重点」有对应数据。
3. 设置子页里有些原版能力 iOS 没有对应实现：外接设备只显示当前输入、不能枚举设备；后台设置的权限项只能显示状态，点了不会跳到系统设置里的具体页。
4. 抽屉面板是自绘的覆盖层，不是系统 modal，状态栏区域仍是页面本身。
5. 小屏（iPhone SE）这一版没有重拍 `rs-*` 画面。
6. 真机与真实密钥仍未验证；模拟器没有麦克风，状态卡里的「正在聆听」是截图模式下的显示。

0.7.1 第十四轮（照原版细节对齐，2026-11-15）

这一轮不改功能，只把界面细节逐条对齐 Android 原版 0.4.0（`src` v0.4.0，包名 `app.resound`）。对比方法也修了：旧拼图把两边缩成相近像素宽，导致 iOS 被多缩 25%，看起来什么都偏小；新版按「安卓 1440px ÷4 = 360dp、iOS 1206px ÷3 = 402pt」换算，统一 1 逻辑单位 = 1.5px、顶端对齐、不裁剪，所以下面的结论都是拿同一个尺子量出来的。

一、对比方法（对应打回第 0 条）
- 新增 `.tmp/compare3.ps1`：左侧原版按 ÷4、右侧 iOS 按 ÷3，统一 1 逻辑单位 = 1.5px，顶部对齐、不裁剪，标注两侧逻辑宽度。
- 尺寸一律以 Kotlin 的 dp/sp 为准（1dp = 1pt），不再目测。

二、三个抽屉（第 1、2、5 条）
- 新增通用底部面板 `RsBottomSheet`（`TaoSheng/UI/Resound/RsSheetKit.swift`）：背景压暗 32%、白色面板、顶部圆角 28、36×5 拖动条、下拉超过 110 关闭，内容区按 `RsSheet` 内边距（左右 20、底 28、段间距 12）。
- 正在聆听 / 专题 / 搜索三个抽屉都改用这个面板，不再露出状态栏和后层卡片。
- 「暂停多久」「删掉哪段时间」的选中态改成实心橙底白字（`ListenSheet.kt` 的 `Choice`），未选是浅灰底。
- 搜索记录输入框去掉放大镜（原版没有）。

三、专题五格与次要入口（第 3、4 条）
- 新增 `RsIcons.swift`：照 `SkillVisuals.kt` 的 TINTS 表做浅色底 + 深色线条的图标方块（会议浅蓝、培训浅绿、通话浅绿、口播稿浅黄、普通浅棕），图形分别是两个人、灯泡、对话气泡、麦克风、列表，对应 `kindIcon` = meeting/bulb/chat/mic/timeline。
- 五格现在是「浅色圆角方块 30 + 类型名」，选中格浅橙底 + 1.5 描边（`TopicKindChoice`）。
- 「预约专题 / 忘了点开始」改成原版的 `SideEntry`：没有左图标，只有粗体标题 + 灰说明 + ›。

四、问问页建议问题（第 6 条）
- 用 `Layout` 协议写了 `RsFlowLayout`，建议胶囊流式排布（一行能放两个），字号 15、内边距 h17/v11，跟原版一致。

五、记忆页（第 7、11 条）
- 「按天 / 按类」选中态改成浅橙底 + 橙字（`ModeSwitch`），未选白底灰字。
- 「卡片」「时间线」改成 20 号粗体标题 + 灰色数量（`卡片 · N 张` / `时间线 · N 件事`），右侧「↓ 早的在上」白胶囊。
- 新增「按类」视图：顶部是类别胶囊（全部 + 出现过的类别），下面是按类别分组的白卡，每条显示标题、类别胶囊、截止时间和状态。

六、今天页待确认小卡（第 8 条）
- 卡片高度跟内容走（两行正文预留固定高度），按钮紧贴正文，去掉中间那块空白。

七、设置（第 9、11 条）
- 分组重排成原版四组：记录（录音与后台 / 外接设备 / 原话与转写 / 声纹与人物 / 环境音识别 / 足迹）、整理（模型与整理时间 / 整理技能 / 推送通道）、数据（数据备份）、通用（回顾与提醒 / 关于涛声），末尾单独一张「高级与诊断」（热词识别 / 隐私与数据）。
- 行样式照 `SettingsHome.kt`：28×28 圆角图标方块 + 标题 + 右侧详情 + ›，行高 50、分隔线左侧缩进 54。
- 「声纹与人物」样本不足时右侧圆点和文字都是橙色；「外接设备」图标换成手机外框。
- 六个子页照原版 `SubPageBar` 重写（`RsSettingsPages.swift`）：录音与后台、原话与转写、声纹与人物、环境音识别、足迹、模型与整理时间。

八、TabBar（第 10 条）
- 按新对比图核对后保持原版参数：胶囊容器 padding 5、每项 h13/v10、字 16 SemiBold、选中浅橙底橙字。

九、版本与验证
- 版本 0.7.1（build 35）；`build-ipa` 第 125 次运行（`823c328`）通过，Swift 编译 0 warning、`swift test` 36 项全过、SQL 回归 8 项通过；产物 `dist/TaoSheng-v0.7.1.ipa`（2 020 990 字节，未签名）。中间还修了 5 次编译错误（#117–#121）与两轮截图反馈（#122、#123）。
- 截图：`shots` 第 67 次运行（`823c328`）出 62 张，iPhone 16 侧新增 15 张 `rs-*`；拼图在 `.tmp/compare-0.7.1/` 共 15 张（上一轮 8 张 + 设置子页 6 张 + 记忆按类），逐张与原版对照过。

十、还没做到 / 没验证
- 预约专题、忘了点开始：面板里有入口，点了只提示「这版还没做」，原版是完整流程。
- 记忆页「按类」的类别名来自我们自己的整理结果（待办/约定/灵感…），原版还有「重点 / 寻物 / 知识 / 卡片」这几类，我们没有对应数据来源。
- 设置子页只对齐了分组与行样式，里面的开关项按 iOS 能力裁剪（外接设备只显示当前音频输入，不能枚举设备）。
- 抽屉顶部仍然保留 iOS 系统状态栏区域（自定义面板已从底部升起并压暗背景，但页面本身不是全屏 modal）。
- 小屏（iPhone SE）这轮没有拍 `rs-*` 画面。
- 真机与真实密钥仍未验证（模拟器无麦克风，英雄卡状态用截图模式的 override 展示「正在聆听」）。

0.7.0 第十三轮（照原版 Android 0.4.0 重做界面，2026-11-15）

这一版不再按自己的审美改，唯一标准是 `C:\项目分区\涛声app\src`（v0.4.0，ddd3306，包名 app.resound）：
原版没有的入口一律去掉，原版有而 iOS 没有的补上。参照图用 MuMu 模拟器装原版 0.4.0 逐屏截，
iOS 侧每张参照图都有对应截图，左右拼图放在 `.tmp/compare-0.7.0/`，画面清单与差异写在 `.tmp/ref/INDEX.md`。

一、界面：从 0.6.x 的「自己设计」换成照抄原版
- 新写一套 Resound 界面（`TaoSheng/UI/Resound/`）：`RsKit.swift` 复刻 `ui/theme/Theme.kt` 的颜色与字号
  （背景 F4F2EF、卡白、正文 1D1B19、次要 7D7770、分隔线 ECE8E3、主色 F07B2E、浅橙 FDEBDD），
  圆角 22 / 英雄卡 26、内容宽上限 640、底部留 76。
- TabBar 换成原版的悬浮白胶囊 + 五个纯文字（今天/问问/记忆/待办/设置），选中项浅橙底橙字，
  每项左右 13 上下 10，文字 16 semibold（`RsShell.swift` 的 `RsTabBar`）。
- 今天页（`RsToday.swift`）照 `ui/today/TodayScreen.kt`：头部「今天 · 星期日 / 11月15日」+ 放大镜 + 日夜半月，
  英雄卡（状态行 › 声波 ◉ 专题 暂停键、三个大数字、0.5pt 分隔线、「现在整理」+ 模型胶囊），
  待确认一屏两张卡（忽略 / 记下·接受），时间线「今天|昨天|前天」+「全部 / ● 媒体」+ 凌晨上午下午晚上分组、
  时间列 58pt、行间 0.5pt 细分隔线。
- 问问页（`RsAskScreen`）照 `ui/ask/AskScreen.kt`：大标题 + 右上历史时钟 + 「想问点什么？」+ 建议胶囊 + 底部输入。
- 记忆页（`RsMemoryScreen`）照 `ui/memory/MemoryScreen.kt`：导出胶囊、按天/按类分段、日历卡（有数据的日期带橙点）、
  回顾卡、速记卡区、「+ 生成」、时间线正序（早的在上）。
- 待办页（`RsTodoScreen`）照 `ui/todo/TodoScreen.kt`：待确认/进行中/已完成三档（带条数）、全部接受/全部忽略、
  「今天 · N 条」分组、卡片内多行 + 细分隔线、右下橙色 FAB。
- 设置页（`RsSettingsScreen`）照 `ui/settings/SettingsScreen.kt`：搜索框、状态卡（一切正常）、分组行（44pt 彩色圆角图标 + 详情 + ›）。
- 三个抽屉：正在聆听（`RsListenSheet`，暂停四选 + 专题区 + 删除时间段）、专题（`RsTopicSheet`，五格类型 + 名字 + 结束时机 + 两个次要入口）、搜索记录（`RsRecordSearchSheet`）。三个面板都由 `RsSheetKit.swift` 的 `RsBottomSheet` 承担：背景压暗、白底圆角 28、下拉关闭；面板打开时把内容层提到 TabBar 之上，不会被胶囊挡住。

二、专题：回到原版的五种
`CaptureMode` 从两种扩成五种，场景与产物由代码写死（`SceneRules` / `NoteRules`）：

| 模式 | 场景 | 产物 | 分说话人 |
|---|---|---|---|
| 会议 | 会议 | 会议速记（议题/结论先行/要点/决定） | 分 |
| 培训 | 培训 | 培训笔记（主题/核心要点/知识点/行动） | 不分 |
| 通话·访谈 | 通话 | 通话记录（聊了什么/结论/待办） | 分 |
| 口播稿 | 口播稿 | 整理版 + 原话版（稿子/要点/怎么说） | 不分 |
| 普通 | 普通 | 合成一条记录（这件事/要点） | 不分 |

老库里的 daily / 未知值仍然按会议处理，不会丢事件。

三、录音行为：默认一直在听
- 首次启动就把 `captureWanted` 置 true，之后只在用户暂停时停；`CaptureEngine` 只在检测到人声时才落段，
  静音段照样丢（原版「只在有人说话时录音」）。
- 暂停用原版的四档（15/30/60/120 分钟，默认 30），到点自动恢复；暂停期间英雄卡显示「<名称>中 · HH:mm 恢复」。
- 0.6.x 那套「开始聆听/结束聆听」大按钮、会议/培训两个切换键、刚结束卡、小时时间轴都从新界面里去掉了；
  底层能力（会话、分人、整理、推送）保留，只是入口换回原版的样子。

四、仍然复用 0.6.x 的底层
会话与收尾（分说话人 → 整理 → 推送）、后台转写节奏、「转写完就整理」的整理时机、闹钟与提醒、
备份、声纹、环境音这些没有重写，新界面只是换了皮和入口。

五、版本与验证
- 版本 0.7.0（build 34）。
- CI：`build-ipa`（run 43691615499，提交 `baa35f1`）成功，`.swift:行:列:` 里 warning 与 error 计数 0，`swift test` 36 项全过，SQL 回归 8 项全过。
- 截图：`shots` 工作流（artifact `shots-070`）拍 iPhone 16 与 SE 各一套，落在 `.tmp/shots-0.7.0/`；
  与原版左右拼图在 `.tmp/compare-0.7.0/`，文件名与参照图一一对应。

六、这一版没做到 / 没验证的
1. **真机与真实密钥没验证**：截图全部来自模拟器 + 演示数据，实际的录音、分人、整理、推送链路只在代码层成立。
2. **记忆页「按类」视图**只做了分段切换，内容仍是按天；按类的聚合留到下一轮。
3. **设置子页**（录音与后台、原话与转写、声纹与人物、环境音、足迹）还是 0.6.x 的页面，只是入口行照原版排；
   逐个子页对齐留到下一轮。
4. **外接设备 / 系统音频**：iOS 没有对应能力（无法枚举并锁定输入设备、无法后台录其它 App 的音频），
   设置里保留入口但点开只说明现状，不留死入口。
5. **待办「已完成」档**的勾选与划线、**记忆页卡片区**的媒体缩略图等细节没有逐像素对齐。
6. **旧界面没有删掉**：`legacyShell` 只是从正常入口摘掉，还留着给 CI 拍旧截图；
   下一轮确认新界面稳定后整段删除。

0.6.6 第十二轮（文案对齐：录音中不再暗示「会议进行中就出纪要」，2026-11-15）

0.6.5 功能都对，但文案自相矛盾：录音中的英雄卡一边写「转出文字就自动整理」，一边写「结束后统一分人，再整理成纪要」；「什么时候整理」里「转写完就整理」的说明还写着「会议中也能马上看到纪要」。实际行为是：会话里的段只在点「结束」后整场整理（`DigestEngine.performDigest` 里的 `session_id` 过滤），「转写完就整理」只作用于零散段。

1. 英雄卡删掉「转出文字就自动整理」那一行。录音中只剩三样：状态行「正在聆听 · 会议/培训」、已录时长 + 「已录 N 段，后台每 X 分钟转写一次」、底部「结束后统一分人，再整理成纪要」，不再提「边录边整理」。
2. `DigestTiming.afterTranscribe` 的说明改成「转出新文字就整理；开会和培训的录音在点结束后统一整理成速记」。
3. 全仓按同一口径扫了一遍：`ListenFlow.statusText` 默认文案「点开始聆听，边录边转写」→「点开始聆听开始录音」；今天页空态「点「开始聆听」边说边转写，结束就出纪要」→「点「开始聆听」开始录音，点结束分人出纪要」；`SessionProgress.liveLines`（已经没人读的字段）删掉；`ListenFlow` / `SessionRules` 的文档注释补上「后台转写只攒文字，这一场的纪要要等点结束」。
4. README：0.6.0 章节里描述实时转写区的两处、`shots-060` 里「today-live 带实时转写行」一处，都加了「0.6.5 起已改」的标注；0.6.5 章节开头那句「转出文字就整理」也补明只管零散段。

版本与验证：

- `project.yml`：`MARKETING_VERSION 0.6.6` / `CURRENT_PROJECT_VERSION 33`。
- CI `build-ipa #106`（提交 `2c64723`）success：warning count 0，`swift test` 36 个用例 0 失败。`dist/TaoSheng-v0.6.6.ipa` 未签名、1 681 143 字节，`Info.plist` 为 XML，`CFBundleShortVersionString 0.6.6`、`CFBundleVersion 33`。
- `shots #48`（提交 `2c64723`）success，截图 `.tmp/shots-0.6.6/`：`iphone16-today-live`（录音中的英雄卡：时长、段数、结束按钮，没有「转出文字就自动整理」）、`iphone16-llm`（「什么时候整理」三档，第一档说明改成新口径）。

没做到 / 没验证：

- 本轮只改文案、删了一个没人读的字段，没动逻辑；真机与真实密钥仍没验证（同上一条）。


0.6.5 第十一轮（真机反馈：点「开始聆听」一直等网络，改成点开就录、后台转、转出字就整理，2026-11-15）

真机上装 0.6.4 后，点「开始聆听」英雄卡一直显示「等网络后转写」，录音转不出文字，等于用不了。

原因有三处，都在代码里核过：

- 设置里 `wifiOnlyTranscribe` 默认是 `true`，蜂窝网络下 `NetWatcher.canUpload` 永远是 `false`，`TranscribeQueue` 的每一轮都被这句 guard 挡回去。
- `NetWatcher` 不是 `ObservableObject`，界面拿不到链路变化，网络恢复了界面也不知道。
- 会话里的切段被单独提速到「停顿 0.8 秒 / 最长 20 秒」，而且每落一段就 `tick(live: true)` 催一次转写；段又碎又多，配合上面那条「等 WiFi」，英雄卡就一直停在「等网络」。

董事长要的其实很简单：点聆听就开始录，后台按设置里的「多久转写一次」转文字；攒下来的零散段转出字就整理，开会和培训这类录音要等点「结束」才整场分人、出速记。实时转写这一套不要了。这一版按这个改：

1. 去掉实时转写。英雄卡录音中只显示「正在聆听 · 会议/培训」、已录时长（每秒走）、「已录 N 段，后台每 X 分钟转写一次」，以及「结束」按钮；`liveTranscript`、「转写中…」「等网络后转写」全部删掉，界面上不再出现任何网络等待字样。
2. 会话里的段不再特殊。`CaptureEngine` 删掉 0.8 秒 / 20 秒的实时阈值，切段按这一场锁定的模式走（会议 2.5 秒静音断句、单段上限 300 秒），最短时长也用设置里的值；段落地不再调 `tick(live:)`。`TranscribeQueue` 的 `live` 参数、`CaptureMode.liveSilenceGap` / `liveMaxSegment` 一起删掉。
3. `wifiOnlyTranscribe` 默认改成 `false`：蜂窝也照转。开关保留，文案写清「打开后，用流量时不转写，连上 WiFi 再补」。
4. 点「结束」后的收尾（整场分说话人 → 整理 → 推送）保留，而且不受「只在 WiFi 下转写」限制——收尾走的是 `SessionTranscriber`，不看 `NetWatcher`。真没网时英雄卡显示「没有网络，联网后自动继续」：`NetWatcher` 加了 `.taoshengNetworkRestored` 通知（只在「断→通」那一刻发），`ListenFlow` 订阅后自动接着做失败的那一步，用户不用回来点重试。
5. 「什么时候整理」多了一档「转写完就整理」，放在第一个并作为默认（新增 `TaoSheng/Core/Policies/DigestTiming.swift`，纯逻辑好单测）。选它时 `TranscribeQueue` 每轮转完，只要真转出了新文字，就调 `DigestEngine.afterTranscribeRound` 立刻整理零散段；会话里的段仍然留到点「结束」时整场整理（`performDigest` 里那句 `session_id` 过滤没动）。另外两档（按间隔、按时间点）行为和 0.6.4 完全一样。第一档不跑定时器，所以另外加了开机补一次（`catchUpAfterLaunch`），上次没整理完的零散段不会漏。
6. 老数据迁移：0.6.4 之前只存了 `digestByInterval`。`true` 是老版本的默认值（等于没选过），升级后落到「转写完就整理」；`false` 说明用户主动切过「按时间点」，保留。全新安装直接就是「转写完就整理」。
7. 「转写与原话」页的状态行也改了：按设置现在不能上传时写「当前网络按设置不转，连上 WiFi 自动继续」，能转时照旧写「约 N 分钟后下一轮」。`NetWatcher` 变成 `ObservableObject` 后这页会跟着网络变化刷新。

回归检查：

- 卡在 `recording` 的老会话：启动时 `ListenFlow.resumeAfterLaunch()` 会把它改成 `finalizing` 并按已有段收尾；收尾失败会落到 `failed`，英雄卡给「重试」，网络恢复也会自动重试，不会一直卡在「正在聆听」。
- 「转写与原话」页的待转写数量来自 `Store.pendingSegments`，下一轮时间来自 `lastRunAt + transcribeIntervalMin`，没有待转写或现在传不出去时给 `nil`，不会写出「约 0 分钟后」这种不会发生的时刻。

版本与验证：

- `project.yml`：`MARKETING_VERSION 0.6.5` / `CURRENT_PROJECT_VERSION 32`。
- 新增单测 `Tests/Policies/DigestTimingTests.swift` 五组：默认落到「转写完就整理」、老键迁移（nil / true / false）、`usesTimer`、`DigestTrigger` 四个条件缺一不可、第一档定时器永不触发、间隔与时间点两档行为与 0.6.4 一致。
- CI `build-ipa #105`（提交 `2215b2f`）success：warning count 0，`swift test` 执行 36 个用例 0 失败。`dist/TaoSheng-v0.6.5.ipa` 未签名、1 681 578 字节，`Info.plist` 为 XML、3495 字节，`CFBundleShortVersionString 0.6.5`、`CFBundleVersion 32`、`CFBundleIdentifier app.taosheng.TaoSheng`、`MinimumOSVersion 16.0`。
- `shots #47`（提交 `4106141`）success：47 张（iPhone 16 32 张、iPhone SE 15 张）。截图 `.tmp/shots-0.6.5/`：`iphone16-today-live` / `iphonese-today-live` 拍新的录音中英雄卡（有已录时长与段数，没有转写行、没有网络字样），`iphone16-llm` / `iphonese-llm` 拍「什么时候整理」三档（第一档「转写完就整理」为默认选中）。

没做到 / 没验证：

- 没上真机跑过：本轮只在模拟器上验证界面与流程，真机上的后台音频、蜂窝网络切换、锁屏后的转写节奏都没实测。董事长真机上的复验是下一步。
- 没有真实的豆包 / DeepSeek 密钥，所以「转出文字立刻整理」在真实接口下的延迟、费用没测；逻辑与单测覆盖的是触发条件，不是真实时延。
- 打开「只在 WiFi 下转写」后从蜂窝切到 WiFi 的自动补转，靠的是 30 秒定时器轮询 `canUpload`，不是链路一恢复就立刻转，最多晚半分钟。


0.6.4 第十轮（时间轴高亮跟着列表顶部走，2026-11-15）

第九轮 5 处都通过了，这一轮只剩一个真 bug：右侧小时轴高亮的小时永远是最后一格。

问题
「全部」页的时间线加了小时轴之后，高亮的永远是最后那个小时——列表停在 08:00–17:00，轴上亮的却是 21:00。

原因
三处时间线各自写了一遍「取顶部那一行」的算法，其中两处（今天页、记忆页）先做了过滤：

```swift
let visible = map.filter { $0.value <= 4 && $0.value > -260 }
let key = visible.max(by: { $0.value < $1.value })?.key
```

`TimelineFullView` 里漏了过滤，直接 `prefs.max(by: { $0.value < $1.value })`：

```swift
.onPreferenceChange(RailOffsetKey.self) { prefs in
    guard let key = prefs.max(by: { $0.value < $1.value })?.key else { return }
    ...
}
```

每行上报的是自己相对滚动容器顶部的 minY：滚到中间以后，顶部那几行是负数（已经滚出屏幕上方），下面的行是越来越大的正数。全表取最大值，命中的必然是列表最底下那一行，于是高亮永远是最后几个小时。

修法
把算法抽成 `RailRules` 里的纯函数，三处共用：

```swift
/// 列表顶部那一行：在 down...up 区间里取 minY 最大的一条。
public static func activeKey(_ offsets: [String: Double],
                             up: Double = 4,
                             down: Double = -260) -> String? {
    offsets
        .filter { $0.value <= up && $0.value > down }
        .max(by: { $0.value < $1.value })?
        .key
}
```

- `TodayView` 今天页卡片、`TodayView` 的 `TimelineFullView`、`MemoryView` 记忆页时间线三处都改成 `RailRules.activeKey(map.mapValues { Double($0) })`。
- 截图时橙色气泡的强制位置也从「固定第二格」改成「跟着高亮的那一格」，这样图里「列表顶部那条事件」和「气泡上的小时」是同一个时刻，不会再出现列表停在 10:00、气泡写 8:00 的情况。

单测
`Tests/Policies/RailRulesTests.swift` 六组用例：

1. 一排 minY（-600 / -180 / -40 / 900）应选中 -40 那条（越过顶部且离顶部最近）。
2. 窗口里一行都没有时（列表整体从更下方开始）退回最靠上的那一行——记忆页时间线从分组标题下面起步，正好是这种情况，以前会一个都不亮。
3. 全部滚出顶部太远（-900 / -400）时返回 nil（上面也没有可见行）。
4. 略高于顶部（-3）算它，越过 down 边界（-261）不算。
5. 回归用例：12 行从 -300 到 +1350，旧算法返回 `row-11`，新算法必须返回 `row-2`。

版本与验证
- 版本 0.6.4（build 31），`CFBundleShortVersionString = 0.6.4`、`CFBundleVersion = 31`。
- CI：`build-ipa` 0 error 0 warning；`swift test` 31 项通过（原 25 + 本次 6）；`node --test Tests/segment-sql.test.mjs` 8 项通过；产物 `../dist/TaoSheng-v0.6.4.ipa`（未签名）。
- 截图：../.tmp/shots-0.6.4/，重点看 iphone16-timeline-rail（高亮小时 = 列表顶部那条的时间）与 iphone16-memory-timeline-rail。iphone16-timeline-rail 停在列表开头：演示数据只有十来条，内容总高刚过一屏，滚到中段会被夹在最大偏移上，顶部那行只剩半截、看不出高亮对的是哪一条。

没验证
- 真机未验证；小时轴的点击跳转只在模拟器里点过。

0.6.3 第九轮（全部页时间轴、气泡单行、记忆页正序、关于页致谢，2026-11-15）

第八轮 9 条里 8 条通过，剩下 5 处在这一轮补齐。都是小改，但每一条都能在截图里指出来。

1. 「全部」时间线页补上固定的小时时间轴
   上一轮报告说「全部页滚到中段」，但那张图里其实没有时间轴——全仓只有今天页的卡片和记忆页调了 `HourRail`，`TimelineFullView` 根本没接。
   现在 `TimelineFullView` 的 `ScrollView` 加了 `.coordinateSpace(name: "railScroll")` 与 `.onPreferenceChange(RailOffsetKey.self)`，每行 `.railTrack(e.id)` 上报自己的位置；`HourRail` 通过 `.overlay(alignment: .trailing)` 盖在 `ScrollView` 外面（不是塞进滚动内容），所以它固定在屏幕右边不跟着滚。点一下或拖动都能跳到对应小时（`proxy.scrollTo("tl-<id>", anchor: .top)`）。事件超过 6 条才出现，右侧同时给内容让出 26pt，长标题不会钻到轴底下。

2. 小时轴的气泡不再折成「20 / :0 / 0」
   气泡是 `overlay(alignment: .topLeading)` 里的 `Text`，父容器只有 30pt 宽，文字被压缩就换行了——真机拖动时同样会这样，不只是截图问题。给气泡的 `Text` 加 `.fixedSize()`，保持单行「20:00」。

3. 记忆页时间线改成整段正序
   以前分组顺序跟着输入顺序走（输入是倒序），于是出现「晚上→下午→上午」分组、组内条目却是正序的错位，右侧时间轴从上到下是 21→7。
   现在 `partGroups(_:)` 先按 `startAt` 正序排，再按固定顺序 `["凌晨","上午","下午","晚上"]` 输出；`railSlots(_:)` 也先排序再算，时间轴从上到下是 7→21，和今天页、「全部」页完全一致。

4. 关于页补 MIT 署名
   原版是 MIT 协议，必须注明。`AboutView` 新增一段「致谢」：

   > 界面与文案参考 Android 原版 0xCoach/TaoSheng（MIT License）。
   > github.com/0xCoach/TaoSheng

   链接用 `Link` 打开 `https://github.com/0xCoach/TaoSheng`。截图入口加 `about`（`ShotMode.tab(for:)` 走设置 Tab，`RootView` 直接渲染 `NavigationStack { AboutView() }`）。

5. 「刚结束」卡的空格
   原来时长和说话人数是两个 `Text`，`HStack(spacing: 10)` 中间还带一个「· 」，肉眼看是两个空格。改成一个 `Text`：`"\(durationText) · \(speakerCount) 位说话人"`。

版本与验证
- 版本 0.6.3（build 30），`CFBundleShortVersionString = 0.6.3`、`CFBundleVersion = 30`。
- CI：`build-ipa` 0 error 0 warning，`swift test` 25 项通过，`node --test Tests/segment-sql.test.mjs` 8 项通过；产物 `../dist/TaoSheng-v0.6.3.ipa`（未签名）。
- 截图：`../.tmp/shots-0.6.3/`，必拍四张 `iphone16-timeline-rail`、`iphone16-memory-timeline-rail`、`iphone16-about`、`iphone16-today-justended`，以及其余常规画面（iPhone 16 与 iPhone SE 各一遍）。

没验证
- 真机与真实密钥仍未验证；说话人分离的真实返回字段与延迟只能按官方 schema 推断。
- 小时轴的点击/拖动跳转只在模拟器里点过，没有在真机上用手指拖过。
0.6.2 第八轮（按验收打回的 9 条改，2026-11-15）

这一轮不动架构，只修 0.6.1 里被逐张截图挑出来的问题。每条都配了截图，截图里的画面就是改完之后的实际样子。

1. 速记抽屉补上「关键原话」，抽屉里终于有内容可滚
   以前抽屉里只有摘要和分段，`card-sheet-bottom.png` 和 `card-sheet-top.png` 一模一样，因为根本没东西能往下滚——原因有两层：整理时虽然要求模型给出 quotes，但演示数据（`ShotMode.seedTimelineIfNeeded`）里那条 20:00 的会议没有 quotes；截图脚本又恰好挑了它，于是抽屉空着。
   现在：演示数据那条会议补了 3 条真实原话（说话人1 "0:12"、说话人2 "1:36"、说话人3 "2:48"）；截图脚本优先挑「有原话」的那一场；`NoteSheet.quotesBlock` 保持 plan 4.6 b) 的样子——浅灰圆角卡（`Theme.cardSoft`）、左侧一条蓝色竖线、上面一行「说话人 · 时间」、下面带引号的原话，点一下跳到那一段原话并播放。
   另外两处排版：`议题` 不再是圆点列表项，改成粗体正文；摘要框底色从 `Theme.cardSoft` 改成浅蓝灰（`Theme.blue.opacity(0.08)`）。
   抽屉本身也加了滚动锚点 `id("quotes")`，截图模式会先滚到「关键原话」再拍，所以 `card-sheet-bottom.png` 与 top 一定不同。

2. 记忆页速记卡：不露字段名，也不再混进别的技能卡
   以前摘要直接拼 `points`/`summary` 两个字段，屏幕上会出现「结论先行：…。；要点：…」这种句子。现在 `noteSummary(_:)` 只取结论那一句（`NoteRules.conclusion`），空则用 `NoteRules.tidy` 清一遍，并把「；」换成「，」、「。。」换成「。」。
   卡片区数据源从「技能卡（`dayCards`）」换成「速记事件（`dayEvents.filter(\.isNote)`）」，所以「项目快讯」「今日复盘」这类与会议无关的卡不再出现在这里；标题也从「卡片」改成「速记 / N 场」。
   卡片左侧图标底色改成浅蓝灰（`Theme.blue.opacity(0.10)`），和原版安卓一致。

3. 截图改为真的滚到位
   上一轮 `memory-timeline-rail.png` 与 `memory-cards.png` 是同一张图，`timeline-rail.png` 拍的是今天页本身——不是界面坏了，是截图脚本没滚。现在：
   - 记忆页加锚点 `id("memo-timeline")`，截图模式滚到时间线标题，小时轴与橙色气泡一起入镜；
   - 今天页 `timeline-rail` 先用 `.onAppear` 打开「全部」页（`TimelineFullView`），再由 `ScrollViewReader` 滚到列表中段，小时轴完整显示；
   - `TimelineFullView` 的 `lineRow` 补了 `.id(e.id)`，滚动才有目标。

4. 今天页英雄卡按原版 `TodayScreen.kt` 重做
   对着 `src/app/src/main/java/app/resound/ui/today/TodayScreen.kt:472-585` 一行行对：
   - 第一行：8pt 状态点 + 状态文字（19pt，semibold）+「›」+ 右侧点状波形（`HeroWave`，16 根 2.6pt 胶囊，`TimelineView` 0.14s 刷新，录音时亮、暂停时淡）；
   - 第二行：三个大数字（21pt rounded，`录到人声 / 件事 / 待确认`），等宽分布；
   - 一条 0.5pt 白 0.3 分隔线；
   - 末行：左边一行说明（正在转写 / N 段录音待转写 / 正在整理 / 整理状态），右边两颗胶囊——「现在整理」白底橙字，「收起 / 展开」白 0.2 底；
   - 外框圆角 26、渐变 `#FFAE6A → #F07B2E → #E8582A`、内边距 18/18/14/12；
   - 会议/培训按钮与「开始聆听」保留，但只在展开时显示，间距从 12/10 收到 10/8，整卡比 0.6.1 矮了三分之一以上。

5. 待确认横卡一屏两张
   卡片宽度从 `屏幕宽 × 0.62` 改成 `(屏幕宽 − 40) / 2`（40 = 左右 16 边距 + 卡片间 8 间距），一屏正好两张，第三张起横向滑。

6. 待办页
   - 组标题带条数：「今天 · 3 条」「昨天 · 1 条」；
   - 有截止日的条目，元信息那行（「今晚 8 点」）用主色 `Theme.accent` + medium 字重，不再是灰的。

7. 周历条改成原版的「年 月 ∨」
   顶部标题从「本周」改成 `2026年11月 ⌄`，点一下弹月份列表（最近 12 个月，`.medium` 高度），选中后整条周历跳到那个月；左右箭头仍然按周翻。`monthAnchor` 单独存，翻周不再依赖「今天」。

8. 说话人数统一从会话算
   「刚结束」卡以前用 `event.people.count`，而 `people` 是整理时模型给的参与人，常和实际话轮对不上，于是出现「1 位说话人」但抽屉里 3 个人。现在 `AppState.refresh()` 后台把每场会话的 utterance 按 speaker 去重算成 `speakerCountBySession`，新增 `app.speakerCount(event)`：有会话就用会话的数，没有才退回 `people.count`。今天页「刚结束」和一切显示人数的地方都走它。

9. 整理间隔一眼看全
   原来是一个 `Picker`，收起状态只看得到「30 分钟」。现在换成自适应网格的分段按钮（`LazyVGrid` + Capsule），5 分 / 10 分 / 15 分 / 30 分 / 1 小时 / 2 小时 / 4 小时 / 12 小时 一次全部可见，选中项橙底白字。

版本与验证
- 版本 0.6.2（build 29），`CFBundleShortVersionString = 0.6.2`、`CFBundleVersion = 29`。
- CI：`build-ipa` 0 error 0 warning，`swift test` 25 项通过，`node --test Tests/segment-sql.test.mjs` 8 项通过；产物 `../dist/TaoSheng-v0.6.2.ipa`（未签名）。
- 截图：iOS 模拟器 iPhone 16 与 iPhone SE（第 3 代）各跑一遍，全部落在 `../.tmp/shots-0.6.2/`。本轮报告里点到的每张图都按文件名核对过内容。

没做到 / 没验证
- 真机仍未验证（手边没有可用设备与真实豆包/DeepSeek 密钥），说话人分离的真实返回字段与延迟依旧只能按官方 schema 推断。
- 周历只做到「按周翻 + 按月份跳」，没做整月网格；待办没做原版的三栏滑动切换。
- 深色模式只做了静态检查，没有逐页截图对比。
0.6.1 第七轮（按原版安卓对齐界面，速记独立成卡，2026-11-14）

截图复核后补修的 6 处（提交 1dcc503、515df1a、a46cc07）

- 英雄卡右下写「还没整理过」而右上写「已整理」：两处状态不同源。改成先看这一场会话的状态——已整理显示「HH:mm 整理完」，失败显示「这一场没整理成，可重试」，整理中显示「正在整理这一场…」。
- 时间线右侧小时轴被挤出屏幕，只剩半个数字：列表改为占满宽度、刻度条固定 30pt 宽叠在右上角，列表右侧留 36pt；`TodayView` 与 `MemoryView` 两处同改。
- 记忆页速记卡把 `points` / `summary` 当字段名显示：改成「图标 + 模式名·时间 / 粗体标题 / 两行摘要」。
- `event-summary`、`event-raw`、`event-speakers` 三张截图拍到的是今天页：`RootView` 的截图分派补上这三个画面。
- 待办行把类型写了两遍：合并成「待办 · 我要做」一颗胶囊，后面只跟截止和人物。
- 关键原话里的说话人按整场映射显示（改过名就写名字）；截图演示数据补了分段要点与三条关键原话。

版本号 0.6.1 (28)。这一轮按董事长的用法继续收紧：只留会议和培训两套流程、每场结束立刻出速记、长会议不再整场失败，今天页与记忆页照原版安卓重做。新增 `TaoSheng/Core/Policies/ChunkRules.swift`、`NoteRules.swift`、`RailRules.swift`、`TaoSheng/UI/NoteViews.swift`、`TaoSheng/UI/NoteSheet.swift`。

一、长会议不再整场失败

- 豆包极速版单次上限按官方文档取 2 小时 / 100MB（`ChunkRules.flashMaxSeconds`、`flashMaxBytes`），运行时不贴着上限用，按 80%（`safeRatio`）判断。
- 超过上限就按段切成若干块，一块一块识别（`ASR/SessionTranscriber.swift` 的 `ChunkRules.chunks`），每块各自分说话人。
- 合并跨块的说话人：每块里同一个人累计语音满 15 秒才取样，取其语音片段的声纹（`speakerVector`），按余弦相似度与已有说话人比对（阈值 0.75），配得上算同一个人，配不上开新的；最后整场按首次出现顺序统一编号。
- 分人阶段英雄卡显示「正在分辨说话人（2/3）…」。
- 如实说明：2 小时 / 100MB 是文档口径，没有真机跑过这么长的会；跨块配音阈值 0.75 是经验值，多人会议如果串人可调。

二、只留会议和培训

- `CaptureMode` 只剩 `.meeting` / `.training`，默认会议；旧数据的 call / daily / script 一律映射成会议（`CaptureMode.restored`），导入录音记会议。
- 删掉 `Prompts.callModeExtra` 与全部通话文案；模式按钮一行两个等宽。

三、每场结束就出速记

- 一场会/培训就是一个事件，标题固定「会议速记 / 培训笔记」，结构由代码按模式选：
  - 会议：议题 / 结论先行 / 要点（分点）/ 决定 / 待办（负责人写说话人名）
  - 培训：主题 / 核心要点 / 知识点 / 行动（负责人是我）
- 新增「关键原话」3–5 条（`EventQuote`，存 `memory_event.quotes_json`）。
- 推送内容改成「标题 + 结论 + 待办」（`PushEngine.pushSession`）。
- 内置技能「会议速记」下线：新装不再预置，老用户启动时自动置为关闭，旧卡片仍可在记忆页查到。
- 原定时整理保留，但会跳过属于某一场的段，同一场不会出两个事件。

四、速记摆在哪儿

- 今天页英雄卡下面「刚结束」卡：标题、结论第一句、时长与说话人数，点「看速记」进详情。
- 时间线里会议/培训单独一行：左边模式图标与起止时间，右边标题、两行结论、速记/笔记标签。
- 事件详情三段「速记 | 原话 | 发言」：速记是分段纪要加关键原话；原话按人分行带颜色点；发言是每人时长条，点名字可改名（改名作用于整场，原话页跟着变）。
- 记忆页顶部「全部 / 会议 / 培训」筛选，时间线变成本类事件；回顾卡里列出当天几场会，点进去就是速记。

五、今天页与时间轴

- 「今日节律」整块删除（连带 Space 里那套时段统计一起清掉）。
- 时间线改正序：凌晨 → 上午 → 下午 → 晚上，当天事件全部显示；超过 8 条时右侧出现小时轴（`UI/NoteViews.swift` 的 `HourRail`）。小时轴只列有事件的小时，间距按条数有比例但有最小高度；点或按住拖动跳到那一小时的第一条，带轻触反馈；滚动时当前小时用橙色气泡标出并跟着走。
- 整理间隔新增 5 分钟和 10 分钟（`Settings.digestIntervalOptions = [5, 10, 15, 30, 60, 120, 240, 720]`）。

六、界面按原版重做

- 今天页：英雄卡下面加「待确认」横卡（一屏两张、卡宽约屏宽六成、留出右侧下一张；iOS 17 上整卡吸附翻页，iOS 16 退化成普通横滑）。
- 待办页：三条筛选带数量、全部接受/全部忽略（忽略要点两次）、按天一张大卡、细分隔线从文字起画、标题固定两行、左滑完成右滑删除。
- 记忆页：速记卡区是一张白色大卡，条间分隔线从文字起画，左边浅色方块放模式图标；点卡片从底部弹出抽屉（`UI/NoteSheet.swift`），里面有复制全部内容、选择部分内容、摘要框、字段分段、参与人胶囊（点一下改名）、关键原话（点一下跳到原话并播放）、重新生成与删除。
- 配色、圆角、字号继续走 `UI/Theme.swift` 的令牌。

七、截图（模拟器，`.tmp/shots-0.6.1/`）

iPhone 16 与 iPhone SE（第三代）各截一遍，重点画面：

- `iphone16-today-hero.png`、`iphonese-today-hero.png`
- `iphone16-today-justended.png`
- `iphone16-today-timeline-asc.png`、`iphonese-today-timeline-asc.png`
- `iphone16-timeline-rail.png`
- `iphone16-timeline-meeting.png`
- `iphone16-today-timeline-parts.png`
- `iphone16-event-summary.png`、`iphone16-event-raw.png`、`iphone16-event-speakers.png`
- `iphone16-memory-filter-meeting.png`
- `iphone16-memory-cards.png`、`iphonese-memory-cards.png`
- `iphone16-memory-week.png`、`iphone16-memory-timeline-rail.png`
- `iphone16-card-sheet-top.png`、`iphone16-card-sheet-bottom.png`、`iphonese-card-sheet-top.png`
- `iphone16-review-meetings.png`
- `iphone16-todo-pending.png`、`iphonese-todo-pending.png`
- `iphone16-llm-interval.png`

八、验证

- CI `build-ipa` 成功，`.swift` 层 0 error 0 warning；`swift test` 25 项通过（含 0.6.1 新加的会话规则、模式映射、场景、推送规则、时间轴规则用例）；`node --test Tests/segment-sql.test.mjs` 8 项通过。
- 产物 `../dist/TaoSheng-v0.6.1.ipa`，1645283 B，`CFBundleShortVersionString 0.6.1`、`CFBundleVersion 28`、`CFBundleIdentifier app.taosheng.TaoSheng`，Info.plist 为 XML（来自 `build-ipa #91`，sha `a46cc07`）。
- 截图由 `shots #34`（sha `a46cc07`）产出，46 张，两台机各 23 张，已下载到 `../.tmp/shots-0.6.1/`；逐张看过：英雄卡右下与顶部状态同源、「刚结束」卡可进速记、时间线正序并按上午/下午/晚上分组、右侧小时轴完整露在屏内、速记卡是「图标 + 模式名·时间 + 标题 + 两行摘要」、三张事件详情分别停在速记/原话/发言、共 3 名说话人显示 46 秒/32 秒/18 秒、改名弹层预填「周工」、待办只写一次「待办 · 我要做」、回顾里「今天开了 5 场会」可点开、小屏同样正常。
- 整理间隔的 5 分钟 / 10 分钟在代码里（`Settings.digestIntervalOptions = [5, 10, 15, 30, 60, 120, 240, 720]`，`Settings.swift:119`），截图 `iphone16-llm-interval.png` 只能看到折叠下拉的当前值「30 分钟」，展开后的选项没有截到。

九、没做到 / 没验证的

- 真机没跑：录音、分人、切块都只在模拟器与代码层验证；2 小时上限、`additions.speaker` 的真实返回字段与延迟仍未在真实密钥下确认。
- 记忆页周历条仍是「本周 / N 周前」按周翻页，原版的「点月份展开整月网格」没有做。
- 原版待办页三栏可左右滑动切换，这里仍是顶部胶囊切换。
- 深色模式没有逐页截图核对。

十、界面参考

- 界面结构与文案参考 0xCoach/TaoSheng（MIT）。

0.6.0 第六轮修复（按会议流程重做录音主链路，2026-11-14）

版本号 0.6.0 (27)。这一版按董事长的实际用法重排：「开会前点开始聆听 → 边录边转写 → 点结束 → 分清说话人 1/2/3 → 立即整理 → 推送」。改动集中在 `TaoSheng/Core/ListenFlow.swift`（新增，一场会的生命周期）、`TaoSheng/ASR/SessionTranscriber.swift`（新增，整场分人）、`TaoSheng/Audio/SessionMerger.swift`（新增，整场拼音频）、`TaoSheng/LLM/SessionDigest.swift`（新增，单场纪要）。

一、聆听会话（A）

- 新表 `listen_session(id, mode, started_at, ended_at, state, speakers_json, event_id, error, created_at)`，状态 `recording / finalizing / digesting / done / failed`，状态流转规则在 `TaoSheng/Core/Policies/SessionRules.swift` 的 `SessionFlow.canMove(from:to:)`。`segment` 新增 `session_id`，`memory_event` 也加 `session_id`（整理出的事件能反查那一场）。
- 点「开始聆听」建会话，模式写在会话上：`ListenFlow.start(mode:)` 先写会话再 `CaptureEngine.bindSession`，所以录音中换模式不会再出现「音频按旧模式切、界面显示新模式」。录音中模式按钮置灰，提示「录音中不能换模式，结束这一场再换」。
- 设置里的培训入口改走 `ListenFlow.start(mode: .training)`（原来只切 `settings.captureMode` 再 `capture.start()`，消息发不进同一套流程）。
- App 被杀或闪退：`TaoShengApp.onAppear` 调 `ListenFlow.resumeAfterLaunch()`，把 `recording` 状态的会话改成 `finalizing` 并用已有段收尾，不会留下永远「正在聆听」的会话。

二、边录边转写（B）（0.6.5 起已改：只后台转写，不再边录边出字；这一场的纪要仍等点「结束」）

（0.6.5 已删）会话中段在停顿 0.8 秒或长度 20 秒时切开（`CaptureMode.liveSilenceGap` / `liveMaxSegment`），切完立刻调 `TranscribeQueue.tick(live: true)`，不等 60 秒定时器；非会话录音仍是原来的 2.5–3 秒 / 300–600 秒。
（0.6.5 已删）今天页英雄卡在录音时显示实时转写区：最近 6 行、带 `HH:mm`，还没出字的行显示「转写中…」；不允许联网时提示「等网络后转写」。实时行不标说话人——跨段编号在结束时统一分，先标会标错。

三、结束 → 整场分说话人（C）

- 点「结束聆听」：`SessionMerger.merge` 用 `AVMutableComposition` 把本场所有段按时间拼成一个 m4a（记下每段在整场里的起点），一次送豆包，只请求一次，说话人编号才稳定。
- 接口用的是豆包极速版 `POST https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash`，请求体带 `show_utterances: true`、`enable_speaker_info: true`（且不传 language，官方字段表要求 `enable_speaker_info` 依赖 `show_utterances` 且语言留空或 zh-CN）。
- 文档：极速版音频文件识别 https://docs.byteplus.com/en/docs/byteplusvoice/asraudiofile-flash ；响应结构（含 `ASRUtterance.text / start_time / end_time / additions`）https://modelschemas.com/schemas/byteplus/audio/auc/bigmodel/recognize/flash?kind=output ；说话人分离最佳实践 https://docs.volcengine.com/docs/doubao-voice/speaker-separation?lang=zh
- 解析在 `TaoSheng/Core/Policies/SessionRules.swift` 的 `DoubaoResultParser`：说话人标签先读 `utterances[].additions.speaker`，兼容 `additions.speaker_id / spk / speakerId` 与顶层同名键；时间戳 `start_time/end_time`（毫秒）自动换算成秒。编号按首次出现顺序映射成「说话人1、说话人2…」（`SpeakerRules.numbering`）。
- 拿不到标签（或整场只有 1 个标签）时如实降级：退回逐段声纹（`SpeakerRules` + 段上已有的 `speaker`），会话备注写「未能分辨说话人，按每段自己认的人显示」；只有一个标签时写「接口只返回了一个说话人，可能是单人讲述」。界面照实显示，不假装分开了。
- 结果落 `utterance(id, session_id, speaker, start_sec, end_sec, text, order_index)`。事件详情里按人分行显示，每个人一颗胶囊带本场发言时长（`MemoryEvent.durationLabel`），点胶囊可以改名（已有人物、「我」或新名字），映射写回 `listen_session.speakers_json`，整场一起改。

四、立即整理并推送（D）

- 分完人直接整理这一场：`SessionDigest.run` 只喂本会话的话轮，一场只产出一个事件（标题 / 摘要 / 要点 + 决定 / 待办），`scene` 由代码按会话模式写死（会议 / 培训 / 通话，`SceneRules.scene(forMode:)`），不再让模型自由发挥；事件带 `session_id`。
- 整理完立刻推送：本机通知（`PushEngine.notifyLocal`，需要通知权限）+ 已配置通道（`PushEngine.pushSession`）。
- 英雄卡依次显示「正在分辨说话人…」→「正在整理…」→「已整理并推送」；失败显示原因和「重试」，重试会从失败的那一步继续（已有话轮就不重复分人）。
- 没填大模型密钥时：转写和分人照常做，整理那一步给出「去『设置 → 大模型与整理』填好，再点重试」。
- 原来的定时整理保留，只兜底没有会话的零散段（`DigestEngine.performDigest` 过滤掉带 `session_id` 的段），不会和单场整理重复出事件。

五、去掉「日常」模式（E）

- `CaptureMode` 只剩 `meeting / training / call`，默认会议；`CaptureMode.restored` 把 `daily`、`script` 和未知值都映射成 `meeting`，老库里的 `capture_mode='daily'` 读出来就是会议。导入的录音记会议。
- `SkillSchedule.daily`、`ReviewKind.daily` 是别的枚举，没动。

六、今日节律重做（F）

- 四格改成「场会议 / 开会时长 / 条待办 / 位说话人」，数字全部来自会话：会议场次 = 今天 `mode=meeting` 的会话数，时长 = 今天所有会话时长和，待办 = 今天会话产出的事件下挂的待办数，说话人 = 今天各场会议去重后的人数（`AppState.meetingCount / sessionSeconds / sessionTodoCount / peopleCount`）。不再依赖段级说话人标签，也不再靠模型写的 scene 字符串。
- 下面那条空白虚线换成 0–24 点时间条：每场会一块色块（会议橙、培训紫、通话蓝），带 6/12/18 点刻度。

七、新增与改动的文件

- 新增：`Core/Policies/SessionRules.swift`、`Core/Models4.swift`、`Core/Store+Session.swift`、`Core/ListenFlow.swift`、`Audio/SessionMerger.swift`、`ASR/SessionTranscriber.swift`、`LLM/SessionDigest.swift`、`Tests/Policies/SessionRulesTests.swift`。
- 改动：`ASR/Transcriber.swift`（协议改为返回 `TranscriptResult{text, spans}`）、`Audio/CaptureEngine.swift`（会话绑定、0.8s/20s 切片、切完触发转写）、`ASR/TranscribeQueue.swift`（`tick(live:)`）、`Core/Store.swift`（`session_id` 列）、`Core/Store+Memory.swift`（事件 `session_id`）、`Core/AppState.swift`（会话统计）、`UI/TodayView.swift`（英雄卡 + 节律）、`UI/EventDetailView.swift`（分人原话 + 改名 + 时长）、`Core/PushEngine.swift`（`pushSession` / `notifyLocal`）、`UI/ShotMode.swift`（四个新画面）、`Core/Policies/CaptureMode.swift`（删 daily）、`UI/SettingsSub.swift`（培训入口）、`Core/ImportEngine.swift`。

八、模拟器截图

`ios-shots.yml` 的产物 `shots-060`，两台机各 11 张，新的四张：`today-live`（0.6.5 起改拍「已录时长 + 段数」，不再有实时转写行）、`today-done`（已整理 + 节律会话语块）、`event-meeting`（按人分行 + 每人发言时长）、`speaker-rename`（改说话人名字的弹层）。截图种子在 `ShotDemo.seedSessionsIfNeeded()`：一场三名说话人的已结束会议（其中「说话人2」已改名「周工」）+ 一场录音中的会话。

九、验证

- CI `build-ipa`：编译 0 error、`.swift` 层 0 warning；`swift test` 全绿（新增 `SessionRulesTests`：带 `additions.speaker` 的豆包样例解析、编号按首现顺序、`daily/script/未知 → meeting`、会话状态流转与恢复、`scene` 由模式写死）；`node --test Tests/segment-sql.test.mjs` 8 项全过（含 `session_id` 列、去掉 daily 后的索引位移）。
- 产物：`../dist/TaoSheng-v0.6.0.ipa`（未签名，`Info.plist` 为 XML，0.6.0 / 27）。

十、这一版没有验证到的地方（如实写）

- 没有真实豆包密钥，没有在真机跑过一次真实会议。以下都只能按官方 schema 与字段表实现，没有实测：`utterances[].additions.speaker` 的真实返回形态、长会议（>30 分钟）一次性送整场的耗时与超时、说话人编号在长音频里是否稳定、整场 m4a 拼接后的大小与内存占用。
- 极速版接口本身有音频时长/大小限制，超过限制时会抛 `http(45000000…)`；本轮没有实现「超长自动切片再合并编号」的兜底，超长会议可能整场失败（失败会在英雄卡显示原因并提供重试）。
- 声纹降级路径（拿不到标签时）沿用原来的阈值，多人会议仍可能并成一两个人，这是已知限制。

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
