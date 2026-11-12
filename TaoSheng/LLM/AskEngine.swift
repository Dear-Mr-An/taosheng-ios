import Foundation

/// 问问：先检索原话，再让模型只基于原话回答，答案带出处
final class AskEngine {
    static let shared = AskEngine()

    private let store = Store.shared

    struct Answer {
        var text: String
        var citations: [Segment]
    }

    func ask(_ question: String) async throws -> Answer {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { throw TranscribeError.empty }

        // 1) 检索：关键词命中 + 最近原话兜底
        var hits = store.searchForAsk(q, limit: 10)
        if hits.isEmpty {
            hits = store.recentTranscripts(days: 14, limit: 40)
        }
        let picked = Array(hits.prefix(10))

        // 2) 拼上下文
        var context = ""
        for (i, s) in picked.enumerated() {
            let who = s.speaker.isEmpty ? "" : "\(s.speaker)："
            context += "[\(i + 1)] \(s.day) \(s.timeText) \(who)\(s.transcript)\n"
        }
        if context.isEmpty {
            context = "（还没有任何转写记录）"
        }

        let system = """
        你是用户的私人记忆助手「涛声」。你只能依据下面提供的原话片段回答，不许编造。
        回答要求：
        1. 先给直接结论，一到三句话说清楚；
        2. 需要列点时用「1. 2. 3.」，每条后面用（1）（2）标注依据的片段编号；
        3. 如果原话里没有相关信息，直接说「没找到相关记录」，并给出最接近的线索；
        4. 不要复述问题，不要说「根据提供的内容」这类套话。
        """

        let user = """
        原话片段：
        \(context)

        问题：\(q)
        """

        let text = try await LLMClient.completeAny(system: system, user: user, temperature: 0.2)

        // 3) 引用：回答里出现过的编号
        var cited: [Segment] = []
        for (i, s) in picked.enumerated() {
            let tag = "（\(i + 1)）"
            let tag2 = "(\(i + 1))"
            let tag3 = "[\(i + 1)]"
            if text.contains(tag) || text.contains(tag2) || text.contains(tag3) {
                cited.append(s)
            }
        }
        // 没标编号就是没依据（比如「没找到相关记录」），别硬塞前 3 条，
        // 否则点进去的内容和答案对不上，出处等于假的。
        return Answer(text: text.trimmingCharacters(in: .whitespacesAndNewlines), citations: cited)
    }

    func record(question: String, answer: Answer) {
        let q = AskMessage(id: shortID(), role: .me, text: question, citations: [], createdAt: Date())
        store.insertAsk(q)
        let a = AskMessage(
            id: shortID(),
            role: .ai,
            text: answer.text,
            citations: answer.citations.map { $0.id },
            createdAt: Date()
        )
        store.insertAsk(a)
    }
}
