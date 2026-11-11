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
        LLMProvider(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat", key: "", note: "便宜、中文稳，默认", builtin: true),
        LLMProvider(id: "doubao", name: "豆包 / 火山方舟", baseURL: "https://ark.cn-beijing.volces.com/api/v3", model: "doubao-pro-32k", key: "", note: "国内直连快", builtin: true),
        LLMProvider(id: "qwen", name: "通义千问", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus", key: "", note: "阿里云百炼", builtin: true),
        LLMProvider(id: "kimi", name: "Kimi", baseURL: "https://api.moonshot.cn/v1", model: "moonshot-v1-8k", key: "", note: "长文本强", builtin: true),
        LLMProvider(id: "zhipu", name: "智谱 GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4-flash", key: "", note: "有免费额度", builtin: true),
        LLMProvider(id: "siliconflow", name: "硅基流动", baseURL: "https://api.siliconflow.cn/v1", model: "Qwen/Qwen2.5-7B-Instruct", key: "", note: "聚合多家开源模型", builtin: true),
        LLMProvider(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini", key: "", note: "需网络", builtin: true),
        LLMProvider(id: "ollama", name: "局域网自建（Ollama / vLLM）", baseURL: "http://192.168.1.10:11434/v1", model: "qwen2.5", key: "", note: "完全不出设备", builtin: true),
        LLMProvider(id: "custom", name: "自定义 OpenAI 兼容接口", baseURL: "", model: "", key: "", note: "可填自定义请求头", builtin: true)
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

    // 自动化
    @Published var autoTranscribe: Bool { didSet { d.set(autoTranscribe, forKey: "autoTranscribe") } }
    @Published var autoDigest: Bool { didSet { d.set(autoDigest, forKey: "autoDigest") } }
    @Published var digestHour: Int { didSet { d.set(digestHour, forKey: "digestHour") } }
    @Published var reviewHour: Int { didSet { d.set(reviewHour, forKey: "reviewHour") } }
    @Published var weeklyReviewWeekday: Int { didSet { d.set(weeklyReviewWeekday, forKey: "weeklyReviewWeekday") } }
    @Published var keepAudioDays: Int { didSet { d.set(keepAudioDays, forKey: "keepAudioDays") } }

    // 收音
    @Published var sensitivity: Double { didSet { d.set(sensitivity, forKey: "sensitivity") } }
    @Published var silenceGap: Double { didSet { d.set(silenceGap, forKey: "silenceGap") } }
    @Published var minSegment: Double { didSet { d.set(minSegment, forKey: "minSegment") } }
    @Published var maxSegment: Double { didSet { d.set(maxSegment, forKey: "maxSegment") } }
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

        llmBaseURL = d.string(forKey: "llmBaseURL") ?? "https://api.deepseek.com/v1"
        llmModel = d.string(forKey: "llmModel") ?? "deepseek-chat"
        llmKey = d.string(forKey: "llmKey") ?? ""
        llmProviderID = d.string(forKey: "llmProviderID") ?? "deepseek"
        llmFallback = d.object(forKey: "llmFallback") as? Bool ?? true
        providersJSON = d.string(forKey: "providersJSON") ?? ""

        autoTranscribe = d.object(forKey: "autoTranscribe") as? Bool ?? true
        autoDigest = d.object(forKey: "autoDigest") as? Bool ?? true
        digestHour = d.object(forKey: "digestHour") as? Int ?? 21
        reviewHour = d.object(forKey: "reviewHour") as? Int ?? 22
        weeklyReviewWeekday = d.object(forKey: "weeklyReviewWeekday") as? Int ?? 1
        keepAudioDays = d.object(forKey: "keepAudioDays") as? Int ?? 3

        sensitivity = d.object(forKey: "sensitivity") as? Double ?? 0.020
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
    }

    // MARK: - 派生

    var asrReady: Bool {
        switch asrKind {
        case .off: return false
        case .appleSpeech: return true
        case .doubao: return !doubaoApiKey.isEmpty || (!doubaoAppKey.isEmpty && !doubaoAccessKey.isEmpty)
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

    // MARK: - 多模型

    var providers: [LLMProvider] {
        var list = LLMProvider.presets
        if let data = providersJSON.data(using: .utf8),
           let saved = try? JSONDecoder().decode([LLMProvider].self, from: data) {
            for s in saved {
                if let i = list.firstIndex(where: { $0.id == s.id }) {
                    list[i].key = s.key
                    list[i].baseURL = s.baseURL.isEmpty ? list[i].baseURL : s.baseURL
                    list[i].model = s.model.isEmpty ? list[i].model : s.model
                    if !s.note.isEmpty { list[i].note = s.note }
                } else {
                    list.append(s)
                }
            }
        }
        return list
    }

    func saveProviders(_ list: [LLMProvider]) {
        if let data = try? JSONEncoder().encode(list),
           let s = String(data: data, encoding: .utf8) {
            providersJSON = s
        }
    }

    func updateProvider(_ p: LLMProvider) {
        var list = providers
        if let i = list.firstIndex(where: { $0.id == p.id }) {
            list[i] = p
        } else {
            list.append(p)
        }
        saveProviders(list)
    }

    /// 主模型 + 备用（有 key 的）
    var activeProviders: [LLMProvider] {
        let all = providers.filter { !$0.key.isEmpty && !$0.baseURL.isEmpty && !$0.model.isEmpty }
        guard !all.isEmpty else { return [] }
        var ordered: [LLMProvider] = []
        if let main = all.first(where: { $0.id == llmProviderID }) {
            ordered.append(main)
        }
        if llmFallback {
            for p in all where p.id != llmProviderID {
                ordered.append(p)
            }
        }
        return ordered
    }

    /// 当前主服务商的 key 为空时，用已填的任意一家
    var effectiveLLM: (base: String, model: String, key: String) {
        if llmReady { return (llmBaseURL, llmModel, llmKey) }
        if let p = activeProviders.first { return (p.baseURL, p.model, p.key) }
        return (llmBaseURL, llmModel, llmKey)
    }
}
