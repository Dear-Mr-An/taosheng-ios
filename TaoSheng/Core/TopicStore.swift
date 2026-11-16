import Foundation

/// 专题计划：名字 + 什么时候自动结束。跟着会话 id 存，App 被杀再回来也还认得出这一场。
enum TopicStore {
    private static let nameKey = "rsTopicName."
    private static let endKey = "rsTopicEnd."
    private static let d = UserDefaults.standard

    static func save(sessionId: String, name: String, endAt: Date?) {
        d.set(name, forKey: nameKey + sessionId)
        if let endAt { d.set(endAt, forKey: endKey + sessionId) } else { d.removeObject(forKey: endKey + sessionId) }
    }

    static func name(sessionId: String) -> String? {
        let v = (d.string(forKey: nameKey + sessionId) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    static func endAt(sessionId: String) -> Date? { d.object(forKey: endKey + sessionId) as? Date }

    static func clear(sessionId: String) {
        d.removeObject(forKey: nameKey + sessionId)
        d.removeObject(forKey: endKey + sessionId)
    }
}