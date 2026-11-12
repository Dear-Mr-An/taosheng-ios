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
        case .doubao: return "填火山引擎语音控制台拿到的 API Key（x-api-key）。走录音文件识别极速版，音频直接 base64 上传，不用公网地址。"
        case .openAICompatible: return "Whisper / 硅基流动 / Groq / 自建服务走这个：POST {base}/audio/transcriptions。豆包语音不兼容这套，请选上面那个。"
        case .appleSpeech: return "免费、离线（需在系统设置里下载中文包），准确率一般"
        case .off: return "录音照常保存，随时可以在设置里打开转写再补"
        }
    }
}

// MARK: - 大模型服务商
struct LLMProvider: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var baseURL: String
    var model: String
    var key: String
    var note: String
    var builtin: Bool

    static let presets: [LLMProvider] = [
        LLMProvider(id: "deepseek", name: "DeepSeek", baseURL: DeepSeekConfiguration.baseURL,
                    model: DeepSeekConfiguration.models[0], key: "", note: "按量计费，同一密钥查询余额", builtin: true)
    ]
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
    @Published var asrKey: String { didSet { d.set(asrKey, forKey: "asrKey") } }
    @Published var asrLanguage: String { didSet { d.set(asrLanguage, forKey: "asrLanguage") } }
    @Published var asrFullURL: String { didSet { d.set(asrFullURL, forKey: "asrFullURL") } }
    @Published var transcribeIntervalMin: Int { didSet { d.set(transcribeIntervalMin, forKey: "transcribeIntervalMin") } }
    @Published var hotwordEnabled: Bool { didSet { d.set(hotwordEnabled, forKey: "hotwordEnabled") } }

    // 豆包语音（火山引擎）原生接口
    @Published var doubaoApiKey: String { didSet { d.set(doubaoApiKey, forKey: "doubaoApiKey") } }
    @Published var doubaoAppKey: String { didSet { d.set(doubaoAppKey, forKey: "doubaoAppKey") } }
    @Published var doubaoAccessKey: String { didSet { d.set(doubaoAccessKey, forKey: "doubaoAccessKey") } }
    @Published var doubaoResourceId: String { didSet { d.set(doubaoResourceId, forKey: "doubaoResourceId") } }

    // 大模型
    @Published var llmBaseURL: String { didSet { d.set(llmBaseURL, forKey: "llmBaseURL") } }
    @Published var llmModel: String { didSet { d.set(llmModel, forKey: "llmModel") } }
    @Published var llmKey: String { didSet { d.set(llmKey, forKey: "llmKey") } }
    @Published var llmProviderID: String { didSet { d.set(llmProviderID, forKey: "llmProviderID") } }
    @Published var llmFallback: Bool { didSet { d.set(llmFallback, forKey: "llmFallback") } }
    @Published var providersJSON: String { didSet { d.set(providersJSON, forKey: "providersJSON") } }
    @Published var deepThinking: Bool { didSet { d.set(deepThinking, forKey: "deepThinking") } }
    @Published var balanceAlertThreshold: Double { didSet { d.set(balanceAlertThreshold, forKey: "balanceAlertThreshold") } }

    // 自动化
    @Published var autoTranscribe: Bool { didSet { d.set(autoTranscribe, forKey: "autoTranscribe") } }
    @Published var autoDigest: Bool { didSet { d.set(autoDigest, forKey: "autoDigest") } }
    @Published var digestHour: Int { didSet { d.set(digestHour, forKey: "digestHour") } }
    /// 按间隔整理：多久整理一次（分钟）
    @Published var digestIntervalMin: Int { didSet { d.set(digestIntervalMin, forKey: "digestIntervalMin") } }
    /// true=按间隔，false=按时间点（digestHour）
    @Published var digestByInterval: Bool { didSet { d.set(digestByInterval, forKey: "digestByInterval") } }
    @Published var reviewHour: Int { didSet { d.set(reviewHour, forKey: "reviewHour") } }
    @Published var weeklyReviewWeekday: Int { didSet { d.set(weeklyReviewWeekday, forKey: "weeklyReviewWeekday") } }
    @Published var keepAudioDays: Int { didSet { d.set(keepAudioDays, forKey: "keepAudioDays") } }

    // 收音
    @Published var sensitivity: Double { didSet { d.set(sensitivity, forKey: "sensitivity") } }
    @Published var silenceGap: Double { didSet { d.set(silenceGap, forKey: "silenceGap") } }
    @Published var minSegment: Double { didSet { d.set(minSegment, forKey: "minSegment") } }
    @Published var maxSegment: Double { didSet { d.set(maxSegment, forKey: "maxSegment") } }
    @Published var captureModeRaw: String { didSet { d.set(captureModeRaw, forKey: "captureModeRaw") } }

    var captureMode: CaptureMode {
        get { CaptureMode(rawValue: captureModeRaw) ?? .daily }
        set { captureModeRaw = newValue.rawValue }
    }

    /// 当前模式下的收音参数（会议模式更敏感、少断句、允许更长的段）
    var modeSensitivity: Double { captureMode.sensitivity(sensitivity) }
    var modeSilenceGap: Double { captureMode.silenceGap }
    var modeMaxSegment: Double { captureMode.maxSegment }
    @Published var preferredInputUID: String { didSet { d.set(preferredInputUID, forKey: "preferredInputUID") } }
    @Published var skipWhenOutput: Bool { didSet { d.set(skipWhenOutput, forKey: "skipWhenOutput") } }
    @Published var silenceWindowOn: Bool { didSet { d.set(silenceWindowOn, forKey: "silenceWindowOn") } }
    @Published var silenceStartHour: Int { didSet { d.set(silenceStartHour, forKey: "silenceStartHour") } }
    @Published var silenceEndHour: Int { didSet { d.set(silenceEndHour, forKey: "silenceEndHour") } }

    // 备份
    @Published var backupKindRaw: String { didSet { d.set(backupKindRaw, forKey: "backupKind") } }
    @Published var backupURL: String { didSet { d.set(backupURL, forKey: "backupURL") } }
    @Published var backupUser: String { didSet { d.set(backupUser, forKey: "backupUser") } }
    @Published var backupPass: String { didSet { d.set(backupPass, forKey: "backupPass") } }
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

    private init() {
        asrKind = ASRKind(rawValue: d.string(forKey: "asrKind") ?? "") ?? .openAICompatible
        asrBaseURL = d.string(forKey: "asrBaseURL") ?? "https://api.openai.com/v1"
        asrModel = d.string(forKey: "asrModel") ?? "whisper-1"
        asrKey = d.string(forKey: "asrKey") ?? ""
        asrLanguage = d.string(forKey: "asrLanguage") ?? "zh"
        asrFullURL = d.string(forKey: "asrFullURL") ?? ""
        transcribeIntervalMin = d.object(forKey: "transcribeIntervalMin") as? Int ?? 30
        hotwordEnabled = d.object(forKey: "hotwordEnabled") as? Bool ?? true

        doubaoApiKey = d.string(forKey: "doubaoApiKey") ?? ""
        doubaoAppKey = d.string(forKey: "doubaoAppKey") ?? ""
        doubaoAccessKey = d.string(forKey: "doubaoAccessKey") ?? ""
        doubaoResourceId = d.string(forKey: "doubaoResourceId") ?? "volc.bigasr.auc_turbo"

        let migrated = DeepSeekConfiguration.migrated(
            baseURL: d.string(forKey: "llmBaseURL") ?? DeepSeekConfiguration.baseURL,
            model: d.string(forKey: "llmModel") ?? "",
            key: d.string(forKey: "llmKey") ?? "",
            providersJSON: d.string(forKey: "providersJSON") ?? "",
            allowLegacyProviders: !d.bool(forKey: "deepSeekConfigurationSaved"))
        llmBaseURL = DeepSeekConfiguration.baseURL
        llmModel = migrated.model
        llmKey = migrated.key
        llmProviderID = "deepseek"
        llmFallback = false
        providersJSON = d.string(forKey: "providersJSON") ?? ""
        deepThinking = d.bool(forKey: "deepThinking")
        balanceAlertThreshold = d.object(forKey: "balanceAlertThreshold") as? Double ?? 10

        autoTranscribe = d.object(forKey: "autoTranscribe") as? Bool ?? true
        autoDigest = d.object(forKey: "autoDigest") as? Bool ?? true
        digestHour = d.object(forKey: "digestHour") as? Int ?? 21
        let savedInterval = d.object(forKey: "digestIntervalMin") as? Int ?? 30
        digestIntervalMin = [15, 30, 60, 120, 240, 720].contains(savedInterval) ? savedInterval : 30
        digestByInterval = d.object(forKey: "digestByInterval") as? Bool ?? true
        reviewHour = d.object(forKey: "reviewHour") as? Int ?? 22
        weeklyReviewWeekday = d.object(forKey: "weeklyReviewWeekday") as? Int ?? 1
        keepAudioDays = d.object(forKey: "keepAudioDays") as? Int ?? 3

        sensitivity = d.object(forKey: "sensitivity") as? Double ?? 0.020
        captureModeRaw = CaptureMode.restored(d.string(forKey: "captureModeRaw") ?? "").rawValue
        silenceGap = d.object(forKey: "silenceGap") as? Double ?? 1.5
        minSegment = d.object(forKey: "minSegment") as? Double ?? 2.0
        maxSegment = d.object(forKey: "maxSegment") as? Double ?? 180.0
        preferredInputUID = d.string(forKey: "preferredInputUID") ?? ""
        skipWhenOutput = d.object(forKey: "skipWhenOutput") as? Bool ?? true
        silenceWindowOn = d.object(forKey: "silenceWindowOn") as? Bool ?? false
        silenceStartHour = d.object(forKey: "silenceStartHour") as? Int ?? 23
        silenceEndHour = d.object(forKey: "silenceEndHour") as? Int ?? 7

        backupKindRaw = d.string(forKey: "backupKind") ?? BackupKind.none.rawValue
        backupURL = d.string(forKey: "backupURL") ?? ""
        backupUser = d.string(forKey: "backupUser") ?? ""
        backupPass = d.string(forKey: "backupPass") ?? ""
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

        // 初始化赋值不触发 didSet，显式保存规范化配置；旧服务商记录保留但不再参与请求。
        d.set(llmBaseURL, forKey: "llmBaseURL")
        d.set(llmModel, forKey: "llmModel")
        d.set(llmKey, forKey: "llmKey")
        d.set("deepseek", forKey: "llmProviderID")
        d.set(false, forKey: "llmFallback")
        d.set(captureModeRaw, forKey: "captureModeRaw")
    }

    // MARK: - 派生

    var asrReady: Bool {
        // 填了豆包 Key 就直接算就绪，不用再去挑「方式」
        if !doubaoApiKey.isEmpty { return true }
        if !doubaoAppKey.isEmpty && !doubaoAccessKey.isEmpty { return true }
        switch asrKind {
        case .off: return false
        case .appleSpeech: return true
        case .doubao: return false
        case .openAICompatible: return !asrKey.isEmpty && (!asrBaseURL.isEmpty || !asrFullURL.isEmpty) && !asrModel.isEmpty
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
        llmProviderID = "deepseek"
        llmFallback = false
        // 只停用旧配置，不删除历史密钥；显式保存后不再从旧列表恢复空密钥。
        d.set(true, forKey: "deepSeekConfigurationSaved")
    }

    var effectiveLLM: (base: String, model: String, key: String) {
        (DeepSeekConfiguration.baseURL, DeepSeekConfiguration.normalizedModel(llmModel),
         llmKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
