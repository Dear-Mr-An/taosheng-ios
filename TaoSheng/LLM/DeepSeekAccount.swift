import Foundation
import Combine

/// 余额只查 DeepSeek 官方接口，不使用可编辑地址，也不记录密钥或响应正文。
@MainActor
final class DeepSeekAccount: ObservableObject {
    @Published private(set) var balance: DeepSeekBalance?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var updatedAt: Date?

    private var currentKey = ""
    private var generation: UInt64 = 0

    func reset() {
        generation &+= 1
        currentKey = ""
        balance = nil
        updatedAt = nil
        error = nil
        loading = false
    }

    func refresh(key: String, force: Bool = false) async {
        guard !Task.isCancelled else { return }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentKey != key {
            reset()
            currentKey = key
        }
        guard !key.isEmpty, !loading else { return }
        if !force, error == nil, let updatedAt, Date().timeIntervalSince(updatedAt) < 3600 { return }
        generation &+= 1
        let token = generation
        loading = true
        error = nil
        defer { if token == generation { loading = false } }

        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard token == generation else { return }
            guard let http = response as? HTTPURLResponse else {
                error = "余额查询失败，请检查网络"
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                error = http.statusCode == 401 ? "密钥无效，请重新编辑" : "余额查询失败，请稍后刷新"
                return
            }
            balance = try DeepSeekBalance.parse(data)
            updatedAt = Date()
        } catch is CancellationError {
            return
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            self.error = "余额查询失败，请检查密钥和网络"
        }
    }
}
