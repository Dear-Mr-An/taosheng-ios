# 涛声 iOS

按 [0xCoach/TaoSheng](https://github.com/0xCoach/TaoSheng)（Android / Kotlin + Compose）重写的 iOS 版：
**全天收音 → 人声切片 → 自动转写 → AI 整理成事件 / 待办 / 约定**。

原项目是纯原生 Android，没有 iOS 分支，所以这里是一个功能对齐的 SwiftUI 重写（iOS 16+，无第三方依赖）。
数据库用系统自带 SQLite3，录音用 AVAudioEngine，转写/整理走任意 OpenAI 兼容接口。

---

## 〇、ipa 已经出好了

**产物：`C:\项目分区\涛声app\dist\TaoSheng-v0.3.2.ipa`**（886 KB，未签名，arm64，iOS 16.0+，仅 iPhone）

已在 GitHub Actions（`macos-15` + Xcode 16.4）真实编译通过，可直接拿去签：

| 项 | 值 |
|---|---|
| Bundle ID | `app.taosheng.TaoSheng` |
| 显示名 | 涛声 |
| 版本 | 0.3.2 (6) |
| 可执行文件 | `Payload/TaoSheng.app/TaoSheng`（arm64，1.73 MB，MH_EXECUTE） |
| 最低系统 | iOS 16.0 |
| 签名状态 | 无 `_CodeSignature`、无 `embedded.mobileprovision`（纯未签名，签名工具会补） |
| Info.plist | 已转成 XML（不是二进制 bplist），国产签名工具能正常解析 |
| 后台模式 | `audio` + `fetch` |

仓库：<https://github.com/Dear-Mr-An/taosheng-ios>（public，改代码 push 后自动重出包，
Actions → `build-ipa` → Artifacts → `TaoSheng-unsigned-ipa`）。

### 0.3.2 做了什么：按原版逻辑重写

这一版不是加按钮，是把**数据模型和页面逻辑**整体换成原版那一套：

- **事件 / 提取项分开存**：`memory_event`（时间、场景、标题、摘要、要点、人物、地点、情绪、重要度、重点标记）+ `memory_item`（待办 / 约定 / 备忘 / 灵感 / 关键信息 / 决定 / 知识 七类，带状态：待确认 / 进行中 / 已完成 / 不用记）。
- **整理提示词换成原版 digest.md 全文**：事件按「场合」切分而不是按话题，停 10 分钟以上才切，半小时对话 1~2 个事件；待办要「以后要办且不办有后果」；对 AI 的即时指令、调试、提问、产品建议都不出提取项；媒体事件不出提取项；拿不准就不提。另有 `done_hints`——原话里说「发了 / 交了 / 弄完了」会自动把对应待办标完成。
- **技能卡**：`skill_cards` 表 + 每张卡按技能的 `fields` 定义产出字段（一句话 / 一段话 / 要点 / 清单 / 标签 / 原话），内容不足返回空卡并写原因。会议速记、收工打卡、每周回顾、情绪日记都带自己的字段。技能详情页可以改名字说明、改触发方式（说完自动识别 / 每天 / 每周 / 只手动）、看卡片字段、点「试一下」立刻生成一张。
- **寻物**：`thing` / `thing_fact` 表，整理时单独跑一遍「放置 / 借出 / 归还 / 带走」，记忆页的「寻物」能按东西名查「钥匙放哪了」「充电宝借给谁了」。
- **每日回顾换成原版 review.md**：一句话总结 + 要紧的 / 发生了什么 / 待办 / 值得留意 / 灵感 / 心力，每条带事件出处。
- **五个页面重排**：待办改成「待确认 / 进行中 / 已完成」三态 + 自然语言拆卡（写一句话让模型拆成多张待办卡）；记忆改成按天（日期条 + 当天回顾卡 + 时间线 + 技能卡）/ 按类（重点 / 寻物 / 灵感 / 关键信息 / 决定）；设置按原版分组（记录 / 智能 / 数据 / 外观 / 关于）。

**0.3.0 修的一批问题**：问问页键盘遮挡 / 收不回、点「现在整理」会误开关录音、导出按钮点了没反应、出错从不提示、声纹与技能与通道与提醒与回顾的数据表根本没建、中文检索查不到原话、录完不刷新、待办不按时间排、标了重点没处看。

功能对照（✅ 已做，◐ 简化版，✗ 这版没做）：
| 能力 | 状态 | 说明 |
|---|---|---|
| 手机麦克风 / 外接麦 / 蓝牙耳机 | ✅ | 设置→录音与后台里列设备，插拔自动切回，偏好不在线自动落回 |
| 全天后台收音 | ✅ | `UIBackgroundModes: audio`，被系统回收后回前台自动续上 |
| 只录人声（VAD） | ◐ | 本机 RMS 能量检测 + 停顿断句，不是 Silero 模型 |
| 外放时不转写 | ✅ | 开关在录音设置里 |
| 停录时段 | ✅ | 可设夜里 23:00–07:00 自动停 |
| 自动转写，间隔可调 | ✅ | 15–720 分钟，默认 30 |
| 云端转写 | ✅ | 豆包 / 任意 OpenAI 兼容 `/audio/transcriptions`，或填完整地址 |
| 苹果本机识别 | ✅ | `SFSpeechRecognizer`，支持设备端识别时走端上 |
| 本地离线大模型转写 | ✗ | SenseVoice / NPU 加速是 Android 侧能力 |
| 声纹认人 | ◐ | 本机 48 维 mel 特征 + 余弦相似度（阈值 0.82），长按原话「这是谁」教一次就记住 |
| 自动摘待办 / 约定 | ✅ | 整理时按提示词切事件、抽待办，`发了`这类完成语会标完成 |
| 每日回顾 / 每周回顾 | ✅ | 五节 + 四节，生成后可推送 |
| 整理技能（任务卡） | ✅ | 会议速记 / 收工打卡 / 每周回顾 / 情绪日记 + 「智能生成」新技能 |
| AI 问问 + 原话出处 | ✅ | 检索本机原话 → 模型回答 → 标注（1）（2）可点回原话 |
| 推送 10 种通道 | ✅ | Agent / 自定义接口 / 坚果云 / PushPlus / 企微 / 飞书 / Telegram / Bark / Server酱 / ntfy |
| 增量推送 | ◐ | 每次推当天全量，不是 diff |
| 云端备份 | ✅ | 坚果云 / WebDAV / S3（SigV4 手写签名），保留 3/7/30 份 |
| 换机恢复 | ✅ | 从云端拉 `latest.json` 回灌 |
| 模型随便换 + 余额 | ✅ | 10 家预置 + 自定义；余额查询未做 |
| 主模型故障切备用 | ✅ | 按顺序试，全失败才报错 |
| 热词纠错 | ✅ | 设置→录音与后台→热词表 |
| 导入录音文件 | ✅ | m4a/mp3/wav/aac/caf/amr/flac/ogg，导入后自动转写认人整理 |
| 时间轴回看 / 标星 / 删除 | ✅ | 记忆页按天回看，左滑标重点，长按删除 |
| 寻物 | ◐ | 「记忆→寻物」用关键词检索原话 |
| 闹钟式强提醒 | ✅ | `UNCalendarNotificationTrigger` + `.timeSensitive` |
| 录音回放 | ✅ | 每段可播放，倍速/字幕播放器未做 |
| 导出 Markdown | ✅ | 当天原话 + 整理结果 |
| 多段合成 M4A | ✗ | — |
| 语音输入记忆（输入法） | ✗ | 需要输入法扩展，iOS 不允许后台读别的 App 输入 |
| 环境音识别 | ✗ | — |
| 足迹 / 定位时间轴 | ✗ | 开关占位，未接 CoreLocation |
| 专题录音（会议/培训） | ✗ | — |
| 专用录音设备（Omi 等） | ✗ | 需要厂商 BLE 协议 |
| 重复灵感合并 | ✗ | — |
| App 内检查更新 | ✗ | 走签名工具更新即可 |
| 开箱向导 | ✗ | 首次进设置页手动填两个 Key |

---


## 一、最快拿到 IPA：GitHub Actions（不需要 Mac）

这个目录本身就是一个可推送的仓库根（`.github/workflows/ios-ipa.yml` 已在里面）。

```bash
# 1. 在 GitHub 网页新建一个空仓库（Private 就行，不要勾 README）
# 2. 在本目录执行（把 URL 换成你的仓库）
git remote add origin https://github.com/<你的账号>/<仓库名>.git
git branch -M main
git push -u origin main
```

推送后自动开始构建，约 4~6 分钟：

- 打开仓库 → **Actions** → 左侧 `build-ipa` → 最新一次运行
- 底部 **Artifacts** → 下载 `TaoSheng-unsigned-ipa`（zip，解开就是 `TaoSheng-unsigned.ipa`）
- 也可以在 Actions 页面点 **Run workflow** 手动重跑

产物是**未签名 IPA**（`CODE_SIGNING_ALLOWED=NO`），专门给你自己签。

---

## 二、自己签到自己手机

拿到 `TaoSheng-unsigned.ipa` 后，三选一：

### 1. Sideloadly（Windows / Mac，最省事）
1. 装 [Sideloadly](https://sideloadly.io/)，iPhone 用数据线连电脑
2. IPA 拖进去，Apple ID 填自己的（免费账号也行）
3. 点 Start，输入 Apple ID 密码 + 二次验证码
4. 手机上：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书

免费 Apple ID 签的 App **7 天过期**，到期重签一次；有 99 美元开发者账号则 1 年。

### 2. AltStore / SideStore（手机上续签）
适合长期用：装 AltServer，把 ipa 通过 AltStore 安装，7 天自动续签（手机和电脑同一 WiFi）。

### 3. ESign / TrollStore（已越狱或支持 TrollStore 的系统）
直接导入 ipa 签名安装，TrollStore 装的应用不过期。

### 用自己的证书（p12 + mobileprovision）
1. 用 [iReSign](https://github.com/maciekish/iReSign) 或 ESign：选 ipa → 选 p12 → 选 mobileprovision
2. **Bundle ID 必须和 provisioning profile 一致**。本工程默认 `app.taosheng.TaoSheng`：
   - 用通配符证书（`com.xxx.*`）可直接签
   - 用显式 App ID，就在 Apple Developer 后台建一个 `app.taosheng.TaoSheng`，或改 `project.yml` 里的 `PRODUCT_BUNDLE_IDENTIFIER` 重新出包
3. 签完装到手机即可

---

## 三、有 Mac 的话：本地出包

```bash
brew install xcodegen
cd ios
xcodegen generate          # 生成 TaoSheng.xcodeproj
open TaoSheng.xcodeproj    # 直接连手机 Run（会自动用你的证书签名）
```

命令行出未签名 ipa：

```bash
xcodebuild -project TaoSheng.xcodeproj -scheme TaoSheng \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath build/TaoSheng.xcarchive archive \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

mkdir -p build/Payload
cp -R build/TaoSheng.xcarchive/Products/Applications/TaoSheng.app build/Payload/
cd build && zip -qr TaoSheng-unsigned.ipa Payload
```

---

## 四、装上之后要做的两件事

设置里**只有两处要配**，别的地方都不用管：**转写服务** 和 **大模型**。

> 整理（总结事件/待办）、问问、整理技能、每日/每周回顾 —— **共用同一个大模型**，只配一次。
> 问问页顶部会显示当前用的模型名，没配会提示去哪儿配。

App 里 **设置 → 转写与大模型** 填两个接口，不填也能录音，只是不转写 / 不整理。

| 用途 | 填什么 | 例子 |
|---|---|---|
| 转写（豆包） | 火山引擎语音控制台的 **API Key** | 设置里选「豆包语音（火山引擎）」，只填 API Key 一项 |
| 转写（其它） | 任意 OpenAI 兼容的 `/audio/transcriptions` | `https://api.siliconflow.cn/v1` + `FunAudioLLM/SenseVoiceSmall` + `sk-...`；或 `https://api.openai.com/v1` + `whisper-1` |
| 大模型（整理/问问/技能/回顾共用） | 任意 OpenAI 兼容的 `/chat/completions` | 选「DeepSeek」→ `https://api.deepseek.com/v1` + `deepseek-chat` + `sk-...` |

大模型那一栏是**就地可改**的：服务商下拉选一家（会自动带出地址和模型名），填上 Key 就能用。
下面的「预设与备用」只是给别家预先存 Key 用的 —— 开了「主模型出问题自动换备用」，主模型断网或余额不足时会自动换下一家，整理不会中断。

### 豆包转写怎么填（重点）

豆包语音**不是** OpenAI 兼容协议，走的是自己的接口，所以 App 里单独做了一条通道：

- 端点（写死在代码里，不用填）：`https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash`
- 你只需要填 **API Key**：火山引擎控制台 → 语音技术 → [API Key 管理](https://console.volcengine.com/speech/new/)，生成一个 key 复制过来
- `Resource Id` 默认 `volc.bigasr.auc_turbo`（录音文件识别极速版），不用改
- 音频是 **base64 直传**，不需要公网地址、不需要对象存储
- 返回码看响应头 `X-Api-Status-Code`：`20000000` 成功，`20000003` 静音（当空文本处理）

老账号如果只有 App Key + Access Key（没有 x-api-key），点开「改用老版 App Key + Access Key」那栏填进去，代码会自动换用 `X-Api-App-Key` / `X-Api-Access-Key` 头。

不想用云端转写：把「转写方式」切成 **系统语音识别（本机）**，免费离线，准确率一般（要先在
设置 → 通用 → 键盘/语言 里下载中文听写包）。

然后回「今天」页点 **开始收音**，把手机放桌上就行。

### 后台收音说明
- `Info.plist` 已开 `UIBackgroundModes: audio`，用录音类后台模式常驻（和原 Android 版的前台服务同思路）
- 系统内存紧张时仍可能回收；回到 App 会自动续上（`captureWanted` 标记）
- 麦克风被电话/其它录音 App 抢占会中断，恢复后自动重启采集
- **只有检测到人声才写文件**，安静时不落盘，省电省空间

---

## 五、和 Android 原版的功能对照

| 原项目模块 | iOS 版 | 说明 |
|---|---|---|
| capture（全天收音 + VAD 切片） | ✅ | AVAudioEngine + RMS 能量 VAD，静音断句、最短/最长段约束 |
| transcribe（转写） | ✅ | OpenAI 兼容接口 + 系统 SFSpeechRecognizer 两条路 |
| digest（AI 整理成事件/待办） | ✅ | 按天聚合 → LLM → 事件 + 待办/约定/灵感/记忆，提示词精简自 `assets/prompts/digest.md` |
| review / diary（回顾、日记） | ✅ 部分 | 「记录」按天浏览 + 全文搜索 + Markdown 导出分享 |
| backup（备份） | ✅ 部分 | 文件共享（iTunes/Finder 可直接取 Documents）、Markdown 导出 |
| voiceprint（CAM++ 声纹分人） | ❌ | iOS 端未接；`Segment.speaker` 字段已预留，UI 已能显示「谁：内容」 |
| ask（对录音提问） | ❌ | 未实现 |
| skills / devices / location / envsound / push / update | ❌ | 依赖 Android 特有能力，iOS 版不做 |

---

## 六、工程结构

```
ios/
├── project.yml                     # XcodeGen 工程定义（改 bundle id / 版本在这里）
├── .github/workflows/ios-ipa.yml   # 云端出未签名 ipa
└── TaoSheng/
    ├── TaoShengApp.swift           # 入口，注入 5 个环境对象
    ├── Core/
    │   ├── Models.swift            # Segment / DigestItem / DigestRecord / DayKey
    │   ├── Store.swift             # SQLite3 直连封装（segment / item / digest 三张表）
    │   ├── Settings.swift          # UserDefaults 配置
    │   └── AppState.swift          # 界面数据聚合 + 导出
    ├── Audio/
    │   ├── CaptureEngine.swift     # 收音 + 能量 VAD + 切片落 wav
    │   └── SegmentPlayer.swift     # 片段回放
    ├── ASR/
    │   ├── Transcriber.swift       # OpenAI 兼容 / Apple Speech 两种实现
    │   └── TranscribeQueue.swift   # 20s 轮询队列，串行转写
    ├── LLM/
    │   ├── LLMClient.swift         # chat/completions + JSON 抽取
    │   ├── Prompts.swift           # 整理提示词
    │   └── DigestEngine.swift      # 按天整理 + 解析落库
    ├── UI/                         # Today / Recordings / Items / Settings + 主题
    └── Resources/
        ├── Info.plist              # 权限、后台模式、文件共享
        └── Assets.xcassets         # AppIcon / AccentColor
```

数据都在这台手机上：数据库 `Application Support/TaoSheng/taosheng.sqlite`，
音频 `Documents/Audio/*.wav`（开着「文件共享」，Finder 能直接拖出来）。
原话只发给你自己填的转写/整理服务，App 没有账号、没有中转服务器。
