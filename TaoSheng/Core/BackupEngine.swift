import Foundation
import CryptoKit

/// 备份：WebDAV（坚果云 / Nextcloud / 群晖）与 S3 兼容存储，增量按天
final class BackupEngine {
    static let shared = BackupEngine()

    private let store = Store.shared

    // MARK: - 快照

    func snapshot(day: String) -> String {
        let segs = store.segments(day: day, limit: 2000).sorted { $0.startedAt < $1.startedAt }
        let items = store.items(day: day, openOnly: false)
        let dig = store.digest(day: day)
        var obj: [String: Any] = [
            "day": day,
            "generated_at": ISO8601DateFormatter().string(from: Date()),
            "summary": dig?.summary ?? "",
            "segments": segs.map { s -> [String: Any] in
                [
                    "id": s.id,
                    "start": s.startedAt.timeIntervalSince1970,
                    "duration": s.duration,
                    "speaker": s.speaker,
                    "text": s.transcript
                ]
            },
            "items": items.map { i -> [String: Any] in
                [
                    "id": i.id,
                    "kind": i.kind.rawValue,
                    "title": i.title,
                    "detail": i.detail,
                    "due": i.due,
                    "status": i.status.rawValue
                ]
            }
        ]
        let s = Settings.shared
        obj["settings"] = [
            "asrKind": s.asrKind.rawValue,
            "llmModel": s.llmModel,
            "digestHour": s.digestHour,
            "keepAudioDays": s.keepAudioDays
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - 备份

    func backupNow(day: String? = nil) async -> String {
        let s = Settings.shared
        guard s.backupKind != .none else { return "还没选备份位置" }
        let target = day ?? DayKey.of(Date())
        let text = snapshot(day: target)
        let bytes = text.utf8.count
        do {
            try await putText(path: "taosheng/\(target).json", text: text)
            try await putText(path: "taosheng/latest.json", text: text)
            return "已备份 \(target) · \(bytes / 1024) KB"
        } catch {
            return "备份失败：\(error.localizedDescription)"
        }
    }

    func restoreLatest() async -> String {
        let s = Settings.shared
        guard s.backupKind != .none else { return "还没选备份位置" }
        do {
            let text = try await getText(path: "taosheng/latest.json")
            guard let data = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "云端文件读不出来"
            }
            let day = (obj["day"] as? String) ?? DayKey.of(Date())
            if let summary = obj["summary"] as? String, !summary.isEmpty {
                store.saveDigest(day: day, summary: summary)
            }
            if let items = obj["items"] as? [[String: Any]] {
                var list: [DigestItem] = []
                for i in items {
                    list.append(DigestItem(
                        id: (i["id"] as? String) ?? shortID(),
                        day: day,
                        kind: ItemKind(rawValue: (i["kind"] as? String) ?? "event") ?? .event,
                        title: (i["title"] as? String) ?? "",
                        detail: (i["detail"] as? String) ?? "",
                        due: (i["due"] as? String) ?? "",
                        status: ItemStatus(rawValue: (i["status"] as? String) ?? "open") ?? .open,
                        createdAt: Date()
                    ))
                }
                store.replaceItems(day: day, items: list)
            }
            NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
            return "已从云端恢复 \(day)（原话录音不回传）"
        } catch {
            return "恢复失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 读写抽象

    func putText(path: String, text: String) async throws {
        let s = Settings.shared
        switch s.backupKind {
        case .none:
            throw TranscribeError.http(0, "没选备份位置")
        case .webdav, .nutstore:
            var base = s.backupURL
            if s.backupKind == .nutstore && base.isEmpty {
                base = "https://dav.jianguoyun.com/dav/"
            }
            if !base.hasSuffix("/") { base += "/" }
            guard let url = URL(string: base + path) else { throw TranscribeError.http(0, "备份地址不对") }
            var req = URLRequest(url: url)
            req.httpMethod = "PUT"
            req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
            let auth = Data("\(s.backupUser):\(s.backupPass)".utf8).base64EncodedString()
            req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 60
            req.httpBody = text.data(using: .utf8)
            try await fire(req)
        case .s3:
            try await s3Put(path: path, body: text.data(using: .utf8) ?? Data())
        }
    }

    func getText(path: String) async throws -> String {
        let s = Settings.shared
        switch s.backupKind {
        case .none:
            throw TranscribeError.http(0, "没选备份位置")
        case .webdav, .nutstore:
            var base = s.backupURL
            if s.backupKind == .nutstore && base.isEmpty {
                base = "https://dav.jianguoyun.com/dav/"
            }
            if !base.hasSuffix("/") { base += "/" }
            guard let url = URL(string: base + path) else { throw TranscribeError.http(0, "备份地址不对") }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            let auth = Data("\(s.backupUser):\(s.backupPass)".utf8).base64EncodedString()
            req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 60
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw TranscribeError.http((resp as? HTTPURLResponse)?.statusCode ?? 0, "读取失败")
            }
            return String(data: data, encoding: .utf8) ?? ""
        case .s3:
            return try await s3Get(path: path)
        }
    }

    private func fire(_ req: URLRequest) async throws {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TranscribeError.http((resp as? HTTPURLResponse)?.statusCode ?? 0, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - S3（SigV4）

    private func s3Host() -> String {
        let s = Settings.shared
        var host = s.backupURL
        host = host.replacingOccurrences(of: "https://", with: "")
        host = host.replacingOccurrences(of: "http://", with: "")
        if host.hasSuffix("/") { host.removeLast() }
        return host
    }

    private func s3Request(path: String, method: String, body: Data) -> URLRequest? {
        let s = Settings.shared
        let host = s3Host()
        let key = "\(s.backupBucket)/\(path)"
        var scheme = "https"
        if s.backupURL.hasPrefix("http://") { scheme = "http" }
        guard let url = URL(string: "\(scheme)://\(host)/\(key)") else { return nil }

        let now = Date()
        let amzDate = BackupEngine.amzFormatter.string(from: now)
        let dateStamp = String(amzDate.prefix(8))
        let region = s.backupRegion.isEmpty ? "auto" : s.backupRegion
        let service = "s3"
        let payloadHash = BackupEngine.sha256Hex(body)

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(host, forHTTPHeaderField: "Host")
        req.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        req.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        req.timeoutInterval = 60
        if method == "PUT" { req.httpBody = body }

        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = "host:\(host)\n" + "x-amz-content-sha256:\(payloadHash)\n" + "x-amz-date:\(amzDate)\n"
        let canonicalRequest = [
            method,
            "/\(key)",
            "",
            canonicalHeaders,
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            BackupEngine.sha256Hex(Data(canonicalRequest.utf8))
        ].joined(separator: "\n")

        let kDate = BackupEngine.hmac(key: Data("AWS4\(s.backupPass)".utf8), data: Data(dateStamp.utf8))
        let kRegion = BackupEngine.hmac(key: kDate, data: Data(region.utf8))
        let kService = BackupEngine.hmac(key: kRegion, data: Data(service.utf8))
        let kSigning = BackupEngine.hmac(key: kService, data: Data("aws4_request".utf8))
        let signature = BackupEngine.hmac(key: kSigning, data: Data(stringToSign.utf8)).map { String(format: "%02x", $0) }.joined()

        let auth = "AWS4-HMAC-SHA256 Credential=\(s.backupUser)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        return req
    }

    private func s3Put(path: String, body: Data) async throws {
        guard let req = s3Request(path: path, method: "PUT", body: body) else {
            throw TranscribeError.http(0, "S3 地址不对")
        }
        try await fire(req)
    }

    private func s3Get(path: String) async throws -> String {
        guard let req = s3Request(path: path, method: "GET", body: Data()) else {
            throw TranscribeError.http(0, "S3 地址不对")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TranscribeError.http((resp as? HTTPURLResponse)?.statusCode ?? 0, "读取失败")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - 加密助手

    static let amzFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }()

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hmac(key: Data, data: Data) -> Data {
        let k = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: k)
        return Data(mac)
    }
}
