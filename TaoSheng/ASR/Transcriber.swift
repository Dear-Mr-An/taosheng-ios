import Foundation
import Speech
import AVFoundation

enum TranscribeError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case empty
    case speechUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "转写服务还没配置（设置 → 转写）"
        case .http(let code, let body): return "转写接口返回 \(code)：\(body.prefix(180))"
        case .empty: return "这段没有识别出文字"
        case .speechUnavailable(let m): return "系统语音识别不可用：\(m)"
        }
    }
}

protocol Transcriber {
    func transcribe(fileURL: URL) async throws -> String
}

// MARK: - OpenAI 兼容（豆包 / Whisper / 自建）
struct OpenAICompatibleTranscriber: Transcriber {
    let baseURL: String
    let apiKey: String
    let model: String
    let language: String

    static func mimeType(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "mp4": return "audio/mp4"
        case "aac": return "audio/aac"
        case "caf": return "audio/x-caf"
        case "amr": return "audio/amr"
        case "flac": return "audio/flac"
        case "ogg": return "audio/ogg"
        case "opus": return "audio/opus"
        default: return "audio/wav"
        }
    }

    static func customHeaders() -> [(String, String)] {
        let raw = Settings.shared.asrCustomHeaders
        guard !raw.isEmpty else { return [] }
        var out: [(String, String)] = []
        for line in raw.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let s = String(line)
            guard let i = s.firstIndex(of: ":") else { continue }
            let k = String(s[s.startIndex..<i]).trimmingCharacters(in: .whitespaces)
            let v = String(s[s.index(after: i)...]).trimmingCharacters(in: .whitespaces)
            if !k.isEmpty && !v.isEmpty { out.append((k, v)) }
        }
        return out
    }

    func transcribe(fileURL: URL) async throws -> String {
        guard var base = URL(string: baseURL) else { throw TranscribeError.notConfigured }
        if !base.absoluteString.hasSuffix("/audio/transcriptions") {
            base = base.appendingPathComponent("audio/transcriptions")
        }

        let boundary = "----TaoSheng\(UUID().uuidString)"
        var body = Data()
        func add(_ s: String) { body.append(s.data(using: .utf8)!) }

        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"model\"\r\n\r\n\(model)\r\n")
        // 「自动识别」不传 language，交给服务自己判断
        if !language.isEmpty && language != "auto" {
            add("--\(boundary)\r\n")
            add("Content-Disposition: form-data; name=\"language\"\r\n\r\n\(language)\r\n")
        }
        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n")
        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        add("Content-Type: \(OpenAICompatibleTranscriber.mimeType(fileURL))\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        add("\r\n--\(boundary)--\r\n")

        var req = URLRequest(url: base)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (k, v) in Self.customHeaders() {
            req.setValue(v, forHTTPHeaderField: k)
        }
        req.timeoutInterval = 180
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw TranscribeError.empty }
        guard (200..<300).contains(http.statusCode) else {
            throw TranscribeError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = obj["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let text = String(data: data, encoding: .utf8) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw TranscribeError.empty
    }
}

// MARK: - 豆包语音（火山引擎 · 录音文件识别极速版）
/// 官方文档：https://www.volcengine.com/docs/6561/1354868
/// 极速版同步返回，音频走 base64，不需要公网 URL。
struct DoubaoTranscriber: Transcriber {
    let apiKey: String
    let appKey: String
    let accessKey: String
    let resourceId: String

    static let endpoint = "https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash"

    private static func audioFormat(_ ext: String) -> String {
        switch ext.lowercased() {
        case "m4a", "mp4": return "m4a"
        case "mp3": return "mp3"
        case "ogg", "opus": return "ogg"
        case "flac": return "flac"
        case "aac": return "aac"
        default: return "wav"
        }
    }

    func transcribe(fileURL: URL) async throws -> String {
        guard let url = URL(string: Self.endpoint) else { throw TranscribeError.notConfigured }
        let raw = try Data(contentsOf: fileURL)
        if raw.isEmpty { throw TranscribeError.empty }

        let uid = apiKey.isEmpty ? (appKey.isEmpty ? UUID().uuidString : appKey) : apiKey
        let audioPart: [String: Any] = [
            "format": Self.audioFormat(fileURL.pathExtension),
            "data": raw.base64EncodedString()
        ]
        let requestPart: [String: Any] = [
            "model_name": "bigmodel",
            "show_utterances": true,
            "enable_itn": true,
            "enable_punc": true,
            "enable_speaker_info": true
        ]
        let body: [String: Any] = [
            "user": ["uid": uid] as [String: Any],
            "audio": audioPart,
            "request": requestPart
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        } else {
            req.setValue(appKey, forHTTPHeaderField: "X-Api-App-Key")
            req.setValue(accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        }
        req.setValue(resourceId.isEmpty ? "volc.bigasr.auc_turbo" : resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        req.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Request-Id")
        req.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        req.timeoutInterval = 300
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw TranscribeError.empty }

        let code = http.value(forHTTPHeaderField: "X-Api-Status-Code") ?? ""
        let message = http.value(forHTTPHeaderField: "X-Api-Message") ?? ""

        // 20000003 = 静音，不算错误
        if code == "20000003" { return "" }
        if code != "20000000" {
            let hint = message.isEmpty ? (String(data: data, encoding: .utf8) ?? "") : message
            throw TranscribeError.http(http.statusCode, "[\(code.isEmpty ? "无状态码" : code)] \(hint.prefix(200))")
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? [String: Any] else { throw TranscribeError.empty }

        if let utts = result["utterances"] as? [[String: Any]], !utts.isEmpty {
            let lines = utts.compactMap { $0["text"] as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty { return lines.joined(separator: "\n") }
        }
        if let text = result["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw TranscribeError.empty
    }
}

// MARK: - 系统语音识别（本机 / 免费）
final class AppleSpeechTranscriber: Transcriber {
    private let locale: Locale

    init(language: String) {
        locale = Locale(identifier: (language.isEmpty || language == "auto") ? "zh-CN" : (language == "zh" ? "zh-CN" : language))
    }

    func transcribe(fileURL: URL) async throws -> String {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { _ in c.resume() }
            }
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscribeError.speechUnavailable("没有语音识别权限")
        }
        guard let rec = SFSpeechRecognizer(locale: locale), rec.isAvailable else {
            throw TranscribeError.speechUnavailable("当前语言包不可用")
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let req = SFSpeechURLRecognitionRequest(url: fileURL)
            req.shouldReportPartialResults = false
            req.requiresOnDeviceRecognition = rec.supportsOnDeviceRecognition
            var finished = false
            rec.recognitionTask(with: req) { result, error in
                if finished { return }
                if let error {
                    finished = true
                    cont.resume(throwing: TranscribeError.speechUnavailable(error.localizedDescription))
                    return
                }
                if let result, result.isFinal {
                    finished = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }
}

// MARK: - 工厂
enum TranscriberFactory {
    static func make() -> Transcriber? {
        let s = Settings.shared
        // 填了豆包 Key 就优先用豆包，不用管「方式」选的什么
        if !s.doubaoApiKey.isEmpty || (!s.doubaoAppKey.isEmpty && !s.doubaoAccessKey.isEmpty) {
            if s.asrKind != .off {
                return DoubaoTranscriber(apiKey: s.doubaoApiKey,
                                         appKey: s.doubaoAppKey,
                                         accessKey: s.doubaoAccessKey,
                                         resourceId: s.doubaoResourceId)
            }
        }
        switch s.asrKind {
        case .off:
            return nil
        case .appleSpeech:
            return AppleSpeechTranscriber(language: s.asrLanguage)
        case .doubao:
            guard s.asrReady else { return nil }
            return DoubaoTranscriber(apiKey: s.doubaoApiKey,
                                     appKey: s.doubaoAppKey,
                                     accessKey: s.doubaoAccessKey,
                                     resourceId: s.doubaoResourceId)
        case .openAICompatible:
            guard s.asrReady else { return nil }
            let base = s.asrFullURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return OpenAICompatibleTranscriber(baseURL: base.isEmpty ? s.asrBaseURL : base,
                                               apiKey: s.asrKey, model: s.asrModel, language: s.asrLanguage)
        }
    }
}
