# 涛声 iOS

按 [0xCoach/TaoSheng](https://github.com/0xCoach/TaoSheng)（Android / Kotlin + Compose）重写的 iOS 版：
**全天收音 → 人声切片 → 自动转写 → AI 整理成事件 / 待办 / 约定**。

原项目是纯原生 Android，没有 iOS 分支，所以这里是一个功能对齐的 SwiftUI 重写（iOS 16+，无第三方依赖）。
数据库用系统自带 SQLite3，录音用 AVAudioEngine，转写/整理走任意 OpenAI 兼容接口。

---

## 〇、ipa 已经出好了

**产物：`C:\项目分区\涛声app\dist\TaoSheng-unsigned.ipa`**（388 KB，未签名，arm64，iOS 16.0+，仅 iPhone）

已在 GitHub Actions（`macos-15` + Xcode 最新版）真实编译通过，可直接拿去签：

| 项 | 值 |
|---|---|
| Bundle ID | `app.taosheng.TaoSheng` |
| 显示名 | 涛声 |
| 版本 | 0.1.0 (1) |
| 可执行文件 | `Payload/TaoSheng.app/TaoSheng`（arm64，MH_EXECUTE） |
| 最低系统 | iOS 16.0 |
| 签名状态 | 无 `_CodeSignature`、无 `embedded.mobileprovision`（纯未签名，签名工具会补） |
| 后台模式 | `audio` + `fetch` |

仓库：<https://github.com/Dear-Mr-An/taosheng-ios>（public，改代码 push 后自动重出包，
Actions → `build-ipa` → Artifacts → `TaoSheng-unsigned-ipa`）。

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

App 里 **设置** 页填两个接口，不填也能录音，只是不转写 / 不整理。

| 用途 | 填什么 | 例子 |
|---|---|---|
| 转写 | 任意 OpenAI 兼容的 `/audio/transcriptions` | `https://api.openai.com/v1` + `whisper-1` + `sk-...`；豆包/硅基流动/自建 whisper 同理 |
| 整理 | 任意 OpenAI 兼容的 `/chat/completions` | `https://api.deepseek.com/v1` + `deepseek-chat` + `sk-...` |

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
