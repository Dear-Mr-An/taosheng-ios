import Foundation
import Combine

enum ASRKind: String, CaseIterable, Identifiable {
    case doubao
    case openAICompatible
    case appleSpeech
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doubao: return "豆包语音（火山引擎）"
        case .openAICompatible: return "云端转写（OpenAI 兼容）"
        case .appleSpeech: return "系统语音识别（本机）"
        case .off: return "只录音，不转写"
        }
    }

    var hint: String {
        switch self {
        case .doubao: return "填火山引擎语音控制台拿到的 API Key（X-Api-Key）。走录音文件识别，音频直接 base64 上传，不用公网地址。"
        case .openAICompatible: return "Whisper / 硅基流动 / Groq / 自建服务走这个：POST {base}/audio/transcriptions。豆包语音不兼容这套，请选上面那个。"
        case .appleSpeech: return "免费、离线（需在系统设置里下载中文包），准确率一般"
        case .off: return "录音照常保存，随时可以在设置里打开转写再补"
        }
    }
}

/// 火山引擎语音识别的资源档位。账号开通了哪个，就必须传哪个，
/// 传错会返回 45000030「requested resource not granted」。
enum DoubaoResource {
    /// 豆包语音识别大模型（SeedASR）录音文件识别，控制台默认开通的就是这一档。
    static let seedASR = "volc.seedasr.auc"
    /// 大模型录音文件识别极速版，需要单独开通。
    static let turbo = "volc.bigasr.auc_turbo"
    /// 大模型录音文件识别闲时版。
    static let idle = "volc.bigasr.auc_idle"

    static let fallback = seedASR

    static let all: [(id: String, title: String, note: String)] = [
        (seedASR, "豆包语音识别大模型", "控制台「录音文件识别」默认档，识别准、支持标点与数字规整"),
        (turbo, "录音文件识别极速版", "需在控制台单独开通，速度更快"),
        (idle, "录音文件识别闲时版", "需单独开通，便宜但排队较久"),
    ]

    static func title(_ id: String) -> String {
        all.first(where: { $0.id == id })?.title ?? id
    }

    /// 分段控件用短标题：全称三档挤在一行会被截成「豆包语音…」
    static func shortTitle(_ id: String) -> String {
        switch id {
        case seedASR: return "大模型"
        case turbo: return "极速"
        case idle: return "闲时"
        default: return title(id)
        }
    }
}

// MARK: - 备份
enum BackupKind: String, CaseIterable, Identifiable {
    case none
    case webdav
    case nutstore
    case s3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "不备份"
        case .webdav: return "WebDAV（Nextcloud / 群晖）"
        case .nutstore: return "坚果云"
        case .s3: return "S3 兼容（阿里云 / 腾讯云 / R2）"
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()

    private let d = UserDefaults.standard

    // 转写
    @Published var asrKind: ASRKind { didSet { d.set(asrKind.rawValue, forKey: "asrKind") } }
    @Published var asrBaseURL: String { didSet { d.set(asrBaseURL, forKey: "asrBaseURL") } }
    @Published var asrModel: String { didSet { d.set(asrModel, forKey: "asrModel") } }
    @Published var asrKey: String { didSet { Secrets.set("asrKey", asrKey) } }
    @Published var asrLanguage: String { didSet { d.set(asrLanguage, forKey: "asrLanguage") } }
    @Published var asrFullURL: String { didSet { d.set(asrFullURL, forKey: "asrFullURL") } }
    @Published var transcribeIntervalMin: Int { didSet { d.set(transcribeIntervalMin, forKey: "transcribeIntervalMin") } }
    @Published var hotwordEnabled: Bool { didSet { d.set(hotwordEnabled, forKey: "hotwordEnabled") } }

    // 豆包语音（火山引擎）原生接口
    @Published var doubaoApiKey: String { didSet { Secrets.set("doubaoApiKey", doubaoApiKey) } }
    @Published var doubaoAppKey: String { didSet { d.set(doubaoAppKey, forKey: "doubaoAppKey") } }
    @Published var doubaoAccessKey: String { didSet { d.set(doubaoAccessKey, forKey: "doubaoAccessKey") } }
    @Published var doubaoResourceId: String { didSet { d.set(doubaoResourceId, forKey: "doubaoResourceId") } }

    // 大模型
    @Published var llmBaseURL: String { didSet { d.set(llmBaseURL, forKey: "llmBaseURL") } }
    @Published var llmModel: String { didSet { d.set(llmModel, forKey: "llmModel") } }
    @Published var llmKey: String { didSet { Secrets.set("llmKey", llmKey) } }
    // 只保留 DeepSeek 一套配置：底座地址固定，不给切换服务商的口子。

    /// 整理要求：用户自己写的偏好，会拼进整理提示词（成就「高级与诊断」里的可编辑项）
    @Published var digestRequirement: String {
        didSet { d.set(digestRequirement, forKey: "digestRequirement") }
    }
    @Published var deepThinking: Bool { didSet { d.set(deepThinking, forKey: "deepThinking") } }
    @Published var balanceAlertThreshold: Double { didSet { d.set(balanceAlertThreshold, forKey: "balanceAlertThreshold") } }

    // 自动化
    @Published var autoTranscribe: Bool { didSet { d.set(autoTranscribe, forKey: "autoTranscribe") } }
    @Published var autoDigest: Bool { didSet { d.set(autoDigest, forKey: "autoDigest") } }
    @Published var digestHour: Int { didSet { d.set(digestHour, forKey: "digestHour") } }
    /// 按间隔整理：多久整理一次（分钟）
    /// 可选的整理间隔（分钟）。5 分钟给短会、720 给一整天只整理一次的人
    static let digestIntervalOptions = [5, 10, 15, 30, 60, 120, 240, 720]

    @Published var digestIntervalMin: Int { didSet { d.set(digestIntervalMin, forKey: "digestIntervalMin") } }
    /// 什么时候整理：转写完就整理（默认）/ 按间隔 / 按时间点。规则在 DigestTiming 里。
    @Published var digestTimingRaw: String {
        didSet {
            d.set(digestTimingRaw, forKey: "digestTimingRaw")
            // 老键继续跟着写，降级回 0.6.4 时至少还是「按间隔」或「按时间点」
            d.set(digestTiming == .interval, forKey: "digestByInterval")
        }
    }
    var digestTiming: DigestTiming {
        get { DigestTiming.restored(digestTimingRaw) }
        set { digestTimingRaw = newValue.rawValue }
    }
    /// 兼容旧读法：true=按间隔
    var digestByInterval: Bool { digestTiming == .interval }
    @Published var reviewHour: Int { didSet { d.set(reviewHour, forKey: "reviewHour") } }
    @Published var weeklyReviewWeekday: Int { didSet { d.set(weeklyReviewWeekday, forKey: "weeklyReviewWeekday") } }
    @Published var keepAudioDays: Int { didSet { d.set(keepAudioDays, forKey: "keepAudioDays") } }

    // 收音
    @Published var sensitivity: Double { didSet { d.set(sensitivity, forKey: "sensitivity") } }
    @Published var minSegment: Double { didSet { d.set(minSegment, forKey: "minSegment") } }
    @Published var captureModeRaw: String { didSet { d.set(captureModeRaw, forKey: "captureModeRaw") } }

    var captureMode: CaptureMode {
        get { CaptureMode(rawValue: captureModeRaw) ?? .meeting }
        set { captureModeRaw = newValue.rawValue }
    }

    /// 当前模式下的收音灵敏度（会议模式更敏感）
    /// 静音断句 / 单段上限由 CaptureMode 决定，界面上不暴露可调项，避免出现「改了不生效」的假开关
    var modeSensitivity: Double { captureMode.sensitivity(sensitivity) }
    @Published var preferredInputUID: String { didSet { d.set(preferredInputUID, forKey: "preferredInputUID") } }
    @Published var skipWhenOutput: Bool { didSet { d.set(skipWhenOutput, forKey: "skipWhenOutput") } }
    /// 只在 WiFi 下转写：默认关（蜂窝也传）。打开后流量下不转，连上 WiFi 再补。
    @Published var wifiOnlyTranscribe: Bool { didSet { d.set(wifiOnlyTranscribe, forKey: "wifiOnlyTranscribe") } }
    /// 自定义转写请求头，一行一个 "Key: Value"
    @Published var asrCustomHeaders: String { didSet { d.set(asrCustomHeaders, forKey: "asrCustomHeaders") } }
    /// 区分说话人与认人
    @Published var speakerSplitOn: Bool { didSet { d.set(speakerSplitOn, forKey: "speakerSplitOn") } }
    @Published var silenceWindowOn: Bool { didSet { d.set(silenceWindowOn, forKey: "silenceWindowOn") } }
    @Published var silenceStartHour: Int { didSet { d.set(silenceStartHour, forKey: "silenceStartHour") } }
    @Published var silenceEndHour: Int { didSet { d.set(silenceEndHour, forKey: "silenceEndHour") } }

    // 备份
    @Published var backupKindRaw: String { didSet { d.set(backupKindRaw, forKey: "backupKind") } }
    @Published var backupURL: String { didSet { d.set(backupURL, forKey: "backupURL") } }
    @Published var backupUser: String { didSet { d.set(backupUser, forKey: "backupUser") } }
    @Published var backupPass: String { didSet { Secrets.set("backupPass", backupPass) } }
    @Published var backupBucket: String { didSet { d.set(backupBucket, forKey: "backupBucket") } }
    @Published var backupRegion: String { didSet { d.set(backupRegion, forKey: "backupRegion") } }
    @Published var backupAuto: Bool { didSet { d.set(backupAuto, forKey: "backupAuto") } }
    @Published var backupKeepVersions: Int { didSet { d.set(backupKeepVersions, forKey: "backupKeepVersions") } }
    @Published var backupEncryptPass: String { didSet { d.set(backupEncryptPass, forKey: "backupEncryptPass") } }

    // 推送
    @Published var pushOnDigest: Bool { didSet { d.set(pushOnDigest, forKey: "pushOnDigest") } }
    @Published var pushOnReview: Bool { didSet { d.set(pushOnReview, forKey: "pushOnReview") } }
    @Published var pushOnTodo: Bool { didSet { d.set(pushOnTodo, forKey: "pushOnTodo") } }

    // 其它
    @Published var autoImportFolder: String { didSet { d.set(autoImportFolder, forKey: "autoImportFolder") } }
    @Published var onboarded: Bool { didSet { d.set(onboarded, forKey: "onboarded") } }
    @Published var envSoundOn: Bool { didSet { d.set(envSoundOn, forKey: "envSoundOn") } }
    @Published var locationOn: Bool { didSet { d.set(locationOn, forKey: "locationOn") } }
    @Published var usePlaceInDigest: Bool { didSet { d.set(usePlaceInDigest, forKey: "usePlaceInDigest") } }

    // MARK: 0.8.0 新增：会话切分与备用服务商

    /// 两段对话之间停多久就算「前面那段说完了」（分钟）。整理时按它标出话题边界。
    @Published var sessionIdleMin: Int { didSet { d.set(sessionIdleMin, forKey: "sessionIdleMin") } }
    /// 一直有人在说话时最多等多久先切一段（分钟）。
    @Published var sessionCapMin: Int { didSet { d.set(sessionCapMin, forKey: "sessionCapMin") } }
    /// 主服务商失败时自动换备用
    @Published var llmFailoverOn: Bool { didSet { d.set(llmFailoverOn, forKey: "llmFailoverOn") } }
    @Published var llm2BaseURL: String { didSet { d.set(llm2BaseURL, forKey: "llm2BaseURL") } }
    @Published var llm2Model: String { didSet { d.set(llm2Model, forKey: "llm2Model") } }
    @Published var llm2Key: String { didSet { Secrets.set("llm2Key", llm2Key) } }

    var llm2Ready: Bool { !llm2Key.isEmpty && !llm2BaseURL.isEmpty && !llm2Model.isEmpty }

    private init() {
        // 老版本把密钥明文写在 UserDefaults 里，启动时顺手搬进钥匙串并抹掉明文
        Secrets.migrateFromDefaults(d)

        asrKind = ASRKind(rawValue: d.string(forKey: "asrKind") ?? "") ?? .doubao
        asrBaseURL = d.string(forKey: "asrBaseURL") ?? "https://api.openai.com/v1"
        asrModel = d.string(forKey: "asrModel") ?? "whisper-1"
        asrKey = Secrets.get("asrKey") ?? ""
        asrLanguage = d.string(forKey: "asrLanguage") ?? "zh"
        asrFullURL = d.string(forKey: "asrFullURL") ?? ""
        transcribeIntervalMin = d.object(forKey: "transcribeIntervalMin") as? Int ?? 30
        hotwordEnabled = d.object(forKey: "hotwordEnabled") as? Bool ?? true

        doubaoApiKey = Secrets.get("doubaoApiKey") ?? ""
        doubaoAppKey = d.string(forKey: "doubaoAppKey") ?? ""
        doubaoAccessKey = d.string(forKey: "doubaoAccessKey") ?? ""
        // 旧版本默认写的是极速版资源（volc.bigasr.auc_turbo），多数账号只开通了
        // 豆包语音识别大模型的 volc.seedasr.auc，命中旧默认值时自动迁移。
        let savedResource = d.string(forKey: "doubaoResourceId") ?? ""
        // 只迁移一次：用户后来手动选回 turbo（账号真开通了）不该每次启动被改回去
        let migrated = d.bool(forKey: "ts.resourceMigrated")
        if !migrated && (savedResource.isEmpty || savedResource == "volc.bigasr.auc_turbo") {
            doubaoResourceId = DoubaoResource.fallback
            d.set(DoubaoResource.fallback, forKey: "doubaoResourceId")
            d.set(true, forKey: "ts.resourceMigrated")
        } else {
            doubaoResourceId = savedResource
        }

        // 页面允许改任意服务商，所以这里必须尊重用户存的地址与模型；
        // 只有「老库里没有保存过地址」时才走 DeepSeek 迁移（把旧 providersJSON 里的官方配置捡回来）。
        let savedBase = LLMRoute.normalize(d.string(forKey: "llmBaseURL") ?? "")
        let savedModel = d.string(forKey: "llmModel") ?? ""
        let savedKey = Secrets.get("llmKey") ?? ""
        if savedBase.isEmpty {
            let migrated = DeepSeekConfiguration.migrated(
                baseURL: DeepSeekConfiguration.baseURL,
                model: savedModel,
                key: savedKey,
                providersJSON: d.string(forKey: "providersJSON") ?? "",
                allowLegacyProviders: !d.bool(forKey: "deepSeekConfigurationSaved"))
            llmBaseURL = LLMRoute.deepSeekBase
            llmModel = migrated.model
            llmKey = migrated.key
        } else {
            llmBaseURL = savedBase
            llmModel = savedModel
            llmKey = savedKey
        }

        digestRequirement = d.string(forKey: "digestRequirement") ?? ""
        deepThinking = d.bool(forKey: "deepThinking")
        balanceAlertThreshold = d.object(forKey: "balanceAlertThreshold") as? Double ?? 10

        autoTranscribe = d.object(forKey: "autoTranscribe") as? Bool ?? true
        autoDigest = d.object(forKey: "autoDigest") as? Bool ?? true
        digestHour = d.object(forKey: "digestHour") as? Int ?? 21
        let savedInterval = d.object(forKey: "digestIntervalMin") as? Int ?? 30
        // 自定义间隔（35/45/90…）也要活着：预设只决定显示哪一档，不限制存下来的值
        digestIntervalMin = (5...720).contains(savedInterval) ? savedInterval : 30
        // 0.6.5 之前只有 digestByInterval；没有 digestTimingRaw 的老库按旧值推出「按间隔 / 按时间点」，
        // 全新安装（两个键都没有）默认「转写完就整理」——董事长的用法就是转出字就整理。
        if let savedTiming = d.string(forKey: "digestTimingRaw") {
            digestTimingRaw = DigestTiming.restored(savedTiming).rawValue
        } else {
            digestTimingRaw = DigestTiming.migrated(
                byInterval: d.object(forKey: "digestByInterval") as? Bool).rawValue
        }
        reviewHour = d.object(forKey: "reviewHour") as? Int ?? 22
        weeklyReviewWeekday = d.object(forKey: "weeklyReviewWeekday") as? Int ?? 1
        keepAudioDays = d.object(forKey: "keepAudioDays") as? Int ?? 3

        sensitivity = d.object(forKey: "sensitivity") as? Double ?? 0.020
        captureModeRaw = CaptureMode.restored(d.string(forKey: "captureModeRaw") ?? "").rawValue
        minSegment = d.object(forKey: "minSegment") as? Double ?? 2.0
        preferredInputUID = d.string(forKey: "preferredInputUID") ?? ""
        skipWhenOutput = d.object(forKey: "skipWhenOutput") as? Bool ?? true
        // 默认不算流量：真机上第一次用就被「等网络」卡住，压根录不出东西
        wifiOnlyTranscribe = d.object(forKey: "wifiOnlyTranscribe") as? Bool ?? false
        asrCustomHeaders = d.string(forKey: "asrCustomHeaders") ?? ""
        speakerSplitOn = d.object(forKey: "speakerSplitOn") as? Bool ?? true
        silenceWindowOn = d.object(forKey: "silenceWindowOn") as? Bool ?? false
        silenceStartHour = d.object(forKey: "silenceStartHour") as? Int ?? 23
        silenceEndHour = d.object(forKey: "silenceEndHour") as? Int ?? 7

        backupKindRaw = d.string(forKey: "backupKind") ?? BackupKind.none.rawValue
        backupURL = d.string(forKey: "backupURL") ?? ""
        backupUser = d.string(forKey: "backupUser") ?? ""
        backupPass = Secrets.get("backupPass") ?? ""
        backupBucket = d.string(forKey: "backupBucket") ?? ""
        backupRegion = d.string(forKey: "backupRegion") ?? "auto"
        backupAuto = d.object(forKey: "backupAuto") as? Bool ?? false
        backupKeepVersions = d.object(forKey: "backupKeepVersions") as? Int ?? 7
        backupEncryptPass = d.string(forKey: "backupEncryptPass") ?? ""

        pushOnDigest = d.object(forKey: "pushOnDigest") as? Bool ?? true
        pushOnReview = d.object(forKey: "pushOnReview") as? Bool ?? true
        pushOnTodo = d.object(forKey: "pushOnTodo") as? Bool ?? false

        autoImportFolder = d.string(forKey: "autoImportFolder") ?? ""
        onboarded = d.object(forKey: "onboarded") as? Bool ?? false
        envSoundOn = d.object(forKey: "envSoundOn") as? Bool ?? false
        locationOn = d.object(forKey: "locationOn") as? Bool ?? false
        usePlaceInDigest = d.object(forKey: "usePlaceInDigest") as? Bool ?? false
        sessionIdleMin = d.object(forKey: "sessionIdleMin") as? Int ?? 10
        sessionCapMin = d.object(forKey: "sessionCapMin") as? Int ?? 60
        llmFailoverOn = d.object(forKey: "llmFailoverOn") as? Bool ?? false
        llm2BaseURL = d.string(forKey: "llm2BaseURL") ?? ""
        llm2Model = d.string(forKey: "llm2Model") ?? ""
        llm2Key = Secrets.get("llm2Key") ?? ""

        // 初始化赋值不触发 didSet，显式保存规范化配置；旧服务商记录保留但不再参与请求。
        d.set(llmBaseURL, forKey: "llmBaseURL")
        d.set(llmModel, forKey: "llmModel")
        Secrets.set("llmKey", llmKey)

        d.set(captureModeRaw, forKey: "captureModeRaw")
    }

    // MARK: - 派生

    var asrReady: Bool {
        // 先看用户选的「方式」：选了自定义/本地/关闭，就不能因为残留着豆包 Key 而判成就绪，
        // 否则选引擎这项设置永远不生效。
        switch asrKind {
        case .off: return false
        case .appleSpeech: return true
        case .doubao: return !doubaoApiKey.isEmpty || (!doubaoAppKey.isEmpty && !doubaoAccessKey.isEmpty)
        case .openAICompatible:
            return !asrKey.isEmpty && (!asrBaseURL.isEmpty || !asrFullURL.isEmpty) && !asrModel.isEmpty
        }
    }

    var asrReadyHint: String {
        if asrReady { return "已配置" }
        switch asrKind {
        case .doubao: return "还没填火山引擎 API Key"
        case .openAICompatible: return "还没填地址和 Key"
        case .appleSpeech: return "本机识别，不用配"
        case .off: return "已关闭转写"
        }
    }

    var llmReady: Bool { !llmKey.isEmpty && !llmBaseURL.isEmpty && !llmModel.isEmpty }

    var backupKind: BackupKind {
        get { BackupKind(rawValue: backupKindRaw) ?? .none }
        set { backupKindRaw = newValue.rawValue }
    }

    // MARK: - DeepSeek（整理、问问、技能、回顾共用）

    func saveDeepSeek(key: String, model: String) {
        llmBaseURL = DeepSeekConfiguration.baseURL
        llmModel = DeepSeekConfiguration.normalizedModel(model)
        llmKey = key.trimmingCharacters(in: .whitespacesAndNewlines)

        // 只停用旧配置，不删除历史密钥；显式保存后不再从旧列表恢复空密钥。
        d.set(true, forKey: "deepSeekConfigurationSaved")
    }

    /// 执行时真正用的配置：页面存什么就用什么，不再固定成官方地址与 deepseek-flash。
    var effectiveLLM: (base: String, model: String, key: String) {
        let base = LLMRoute.resolveBase(stored: llmBaseURL)
        let official = LLMRoute.isOfficialDeepSeek(base)
        return (base,
                LLMRoute.resolveModel(stored: llmModel, official: official),
                llmKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 当前服务商是不是 DeepSeek 官方（决定能不能查余额、能不能用官方 Key）
    var llmIsOfficial: Bool { LLMRoute.isOfficialDeepSeek(LLMRoute.resolveBase(stored: llmBaseURL)) }
}
