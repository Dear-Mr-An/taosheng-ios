import Foundation

struct DeepSeekConfiguration {
    static let baseURL = "https://api.deepseek.com"
    static let models = ["deepseek-flash", "deepseek-v4-pro"]
    static let keyURL = URL(string: "https://platform.deepseek.com/api_keys")!
    static let topUpURL = URL(string: "https://platform.deepseek.com/top_up")!

    let model: String
    let key: String

    static func migrated(baseURL: String, model: String, key: String, providersJSON: String,
                         allowLegacyProviders: Bool = true) -> Self {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !allowLegacyProviders {
            return Self(model: normalizedModel(model), key: isOfficial(baseURL) ? cleanKey : "")
        }
        if isOfficial(baseURL), !cleanKey.isEmpty {
            return Self(model: normalizedModel(model), key: cleanKey)
        }
        if let data = providersJSON.data(using: .utf8),
           let providers = try? JSONDecoder().decode([LegacyProvider].self, from: data),
           let saved = providers.first(where: { isOfficial($0.baseURL) && !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return Self(model: normalizedModel(saved.model), key: saved.key.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Self(model: models[0], key: "")
    }

    static func normalizedModel(_ model: String) -> String {
        models.contains(model) ? model : models[0]
    }

    private static func isOfficial(_ base: String) -> Bool {
        guard let url = URL(string: base.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme == "https" && url.host?.lowercased() == "api.deepseek.com"
            && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
            && (url.port == nil || url.port == 443)
            && ["", "/", "/v1", "/v1/"].contains(url.path)
    }

    private struct LegacyProvider: Decodable {
        let baseURL: String
        let model: String
        let key: String
    }
}

struct DeepSeekBalance {
    let total: Decimal
    let granted: Decimal?
    let toppedUp: Decimal?
    let currency: String
    let available: Bool

    static func parse(_ data: Data) throws -> Self {
        guard data.count <= 65_536,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let infos = root["balance_infos"] as? [[String: Any]],
              let info = infos.first(where: { ($0["currency"] as? String) == "CNY" }) ?? infos.first,
              let total = amount(info["total_balance"]),
              let currency = info["currency"] as? String, !currency.isEmpty else {
            throw BalanceError.invalidReply
        }
        return Self(total: total, granted: amount(info["granted_balance"]),
                    toppedUp: amount(info["topped_up_balance"]), currency: currency,
                    available: root["is_available"] as? Bool ?? true)
    }

    func isLow(threshold: Double) -> Bool {
        currency == "CNY" && threshold > 0 && (!available || total < Decimal(threshold))
    }

    var totalText: String { formatted(total) }
    var grantedText: String? { granted.map(formatted) }

    private func formatted(_ amount: Decimal) -> String {
        let prefix = currency == "CNY" ? "¥" : (currency == "USD" ? "$" : "\(currency) ")
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        return prefix + (formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "—")
    }

    private static func amount(_ value: Any?) -> Decimal? {
        let string: String
        if let value = value as? String { string = value }
        else if let value = value as? NSNumber { string = value.stringValue }
        else { return nil }
        guard string.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil,
              let result = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")),
              !result.isNaN else { return nil }
        return result
    }

    enum BalanceError: LocalizedError {
        case invalidReply
        var errorDescription: String? { "余额返回格式不正确，请稍后刷新" }
    }
}
