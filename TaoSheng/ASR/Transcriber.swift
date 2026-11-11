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
        if !language.isEmpty {
            add("--\(boundary)\r\n")
            add("Content-Disposition: form-data; name=\"language\"\r\n\r\n\(language)\r\n")
        }
        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n")
        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        add("Content-Type: audio/wav\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        add("\r\n--\(boundary)--\r\n")

        var req = URLRequest(url: base)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

// MARK: - 系统语音识别（本机 / 免费）
final class AppleSpeechTranscriber: Transcriber {
    private let locale: Locale

    init(language: String) {
        locale = Locale(identifier: language.isEmpty ? "zh-CN" : (language == "zh" ? "zh-CN" : language))
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
        switch s.asrKind {
        case .off:
            return nil
        case .appleSpeech:
            return AppleSpeechTranscriber(language: s.asrLanguage)
        case .openAICompatible:
            guard s.asrReady else { return nil }
            return OpenAICompatibleTranscriber(baseURL: s.asrBaseURL, apiKey: s.asrKey, model: s.asrModel, language: s.asrLanguage)
        }
    }
}
