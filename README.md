# 涛声 iOS

Android 原版 [0xCoach/TaoSheng](https://github.com/0xCoach/TaoSheng) 的 SwiftUI 重写，iOS 16+，无第三方运行依赖。
全天收音 → 人声切片 → 转写 → DeepSeek 整理事件、待办和记忆。数据使用本机 SQLite。

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
- `node --test Tests/segment-sql.test.mjs`：8 项通过，使用内存 SQLite 执行应用 SQL，覆盖迁移、积压查询、事件标星、清空表以及最近原话截取。SQL 检查不验证设备录音和云服务行为。
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
