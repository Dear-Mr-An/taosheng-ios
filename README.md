# 涛声 iOS

Android 原版 [0xCoach/TaoSheng](https://github.com/0xCoach/TaoSheng) 的 SwiftUI 重写，iOS 16+，无第三方运行依赖。
全天收音 → 人声切片 → 转写 → DeepSeek 整理事件、待办和记忆。数据使用本机 SQLite。

当前源码调整（2026-11-12）

- 收音模式依次为日常、会议、培训、通话；移除口播稿入口和新口播卡生成，历史卡片不删除。
- 待办右下角 +：轻点打字，长按说话，松手停止收音；短暂等待尾字后填入编辑框，由用户确认保存。旁边文字只提示，不接收长按。
- 整理模型只有 DeepSeek，分为「整理用的大模型」「什么时候整理」「服务商」三张卡：主服务商固定 DeepSeek，可再添加任意 OpenAI 兼容服务商当备用，打开「出问题时自动换备用」后主服务商报错会依次试备用；不显示 token 用量，只显示余额。
- 原话与转写页补齐：顶部状态卡（转写已就绪 / 尚未就绪）、豆包 Key、主要识别语言（自动 / 普通话 / 粤语 / 英语 / 中英混合，「自动」不传 language 字段）、原声保留天数与录音包导出（本机 wav 打 zip 分享，最多 200 段）、热词入口。
- 余额查询显示真实金额、赠送额度、更新时间和失败提示；优先人民币，成功结果缓存一小时，可手动刷新。低额提醒只在设置页展示，不是后台通知。
- 自动整理遵守开关、间隔或每日整点设置，包含历史积压并分批处理；手动整理不占用定时任务的成功记录。深度思考仅用于整理请求。定时任务依赖 App 实际运行，不能保证 iOS 挂起时准点执行。

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

1. 设置 → 原话与转写：填写豆包语音 API Key；其他转写服务和系统识别在折叠区配置。
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

- 已在 GitHub Actions（`macos-15` + Xcode 16.4）真实编译通过：run 43179200132 success（commit 0988265）。
- 产物：`../dist/TaoSheng-v0.4.2.ipa`（958 KB，arm64 可执行文件 1.90 MB，0.4.2 (9)，Info.plist 已转 XML，无 `_CodeSignature`、无 `embedded.mobileprovision`）。
- `node --test Tests/segment-sql.test.mjs`：5 项通过，使用内存 SQLite 执行应用 SQL，覆盖旧数据保留、模式读写、历史积压查询、未完成事项编号及忽略状态保护。SQL 检查不验证整理循环、推送调用等 Swift 集成行为。
- `swift test`：本机 Windows 未安装 Swift，8 项纯逻辑测试未执行；编译正确性由 CI 的 xcodebuild 保证，不等于运行期行为正确。
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

工程配置在 `project.yml`，Bundle ID 为 `app.taosheng.TaoSheng`，版本仍为 0.4.1 (8)。签名安装需自行配置匹配的证书。
仓库已有 `.github/workflows/ios-ipa.yml`；推送默认分支或手动运行会构建并发布 GitHub Release，必须经授权再操作。

本次变更和验证边界见 `docs/2026-11-12-交互与DeepSeek调整.md`。
