import Foundation
import Combine

enum ASRKind: String, CaseIterable, Identifiable {
    case openAICompatible
    case appleSpeech
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAICompatible: return "云端转写（OpenAI 兼容）"
        case .appleSpeech: return "系统语音识别（本机）"
        case .off: return "只录音，不转写"
        }
    }

    var hint: String {
        switch self {
        case .openAICompatible: return "豆包 / Whisper / 自建服务都走这个接口：POST {base}/audio/transcriptions"
        case .appleSpeech: return "免费、离线（需在系统设置里下载中文包），准确率一般"
        case .off: return "录音照常保存，随时可以在设置里打开转写再补"
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()

    private let d = UserDefaults.standard

    @Published var asrKind: ASRKind { didSet { d.set(asrKind.rawValue, forKey: "asrKind") } }
    @Published var asrBaseURL: String { didSet { d.set(asrBaseURL, forKey: "asrBaseURL") } }
    @Published var asrModel: String { didSet { d.set(asrModel, forKey: "asrModel") } }
    @Published var asrKey: String { didSet { d.set(asrKey, forKey: "asrKey") } }
    @Published var asrLanguage: String { didSet { d.set(asrLanguage, forKey: "asrLanguage") } }

    @Published var llmBaseURL: String { didSet { d.set(llmBaseURL, forKey: "llmBaseURL") } }
    @Published var llmModel: String { didSet { d.set(llmModel, forKey: "llmModel") } }
    @Published var llmKey: String { didSet { d.set(llmKey, forKey: "llmKey") } }

    @Published var autoTranscribe: Bool { didSet { d.set(autoTranscribe, forKey: "autoTranscribe") } }
    @Published var autoDigest: Bool { didSet { d.set(autoDigest, forKey: "autoDigest") } }
    @Published var digestHour: Int { didSet { d.set(digestHour, forKey: "digestHour") } }
    @Published var keepAudioDays: Int { didSet { d.set(keepAudioDays, forKey: "keepAudioDays") } }

    @Published var sensitivity: Double { didSet { d.set(sensitivity, forKey: "sensitivity") } }
    @Published var silenceGap: Double { didSet { d.set(silenceGap, forKey: "silenceGap") } }
    @Published var minSegment: Double { didSet { d.set(minSegment, forKey: "minSegment") } }
    @Published var maxSegment: Double { didSet { d.set(maxSegment, forKey: "maxSegment") } }

    private init() {
        asrKind = ASRKind(rawValue: d.string(forKey: "asrKind") ?? "") ?? .openAICompatible
        asrBaseURL = d.string(forKey: "asrBaseURL") ?? "https://api.openai.com/v1"
        asrModel = d.string(forKey: "asrModel") ?? "whisper-1"
        asrKey = d.string(forKey: "asrKey") ?? ""
        asrLanguage = d.string(forKey: "asrLanguage") ?? "zh"

        llmBaseURL = d.string(forKey: "llmBaseURL") ?? "https://api.deepseek.com/v1"
        llmModel = d.string(forKey: "llmModel") ?? "deepseek-chat"
        llmKey = d.string(forKey: "llmKey") ?? ""

        autoTranscribe = d.object(forKey: "autoTranscribe") as? Bool ?? true
        autoDigest = d.object(forKey: "autoDigest") as? Bool ?? true
        digestHour = d.object(forKey: "digestHour") as? Int ?? 21
        keepAudioDays = d.object(forKey: "keepAudioDays") as? Int ?? 3

        sensitivity = d.object(forKey: "sensitivity") as? Double ?? 0.020
        silenceGap = d.object(forKey: "silenceGap") as? Double ?? 1.5
        minSegment = d.object(forKey: "minSegment") as? Double ?? 2.0
        maxSegment = d.object(forKey: "maxSegment") as? Double ?? 180.0
    }

    var asrReady: Bool {
        switch asrKind {
        case .off: return false
        case .appleSpeech: return true
        case .openAICompatible: return !asrKey.isEmpty && !asrBaseURL.isEmpty && !asrModel.isEmpty
        }
    }

    var llmReady: Bool { !llmKey.isEmpty && !llmBaseURL.isEmpty && !llmModel.isEmpty }
}
