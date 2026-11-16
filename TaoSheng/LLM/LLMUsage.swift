import Foundation

/// 大模型用量统计：每次调用把接口返回的 usage 累加进本地，按天存。
/// 原来「用量」卡写死 10.5 万 token，现在没调用过就是 0。
enum LLMUsage {

    struct Bucket {
        var prompt = 0
        var completion = 0
        var calls = 0
        var total: Int { prompt + completion }
    }

    private static func key(_ day: String) -> String { "llmUsage.\(day)" }

    static func record(prompt: Int, completion: Int, at date: Date = Date()) {
        let d = UserDefaults.standard
        let day = DayKey.of(date)
        let k = key(day)
        let old = d.dictionary(forKey: k) as? [String: Int] ?? [:]
        d.set([
            "p": (old["p"] ?? 0) + max(0, prompt),
            "c": (old["c"] ?? 0) + max(0, completion),
            "n": (old["n"] ?? 0) + 1
        ], forKey: k)
    }

    static func bucket(day: String) -> Bucket {
        let raw = UserDefaults.standard.dictionary(forKey: key(day)) as? [String: Int] ?? [:]
        var b = Bucket()
        b.prompt = raw["p"] ?? 0
        b.completion = raw["c"] ?? 0
        b.calls = raw["n"] ?? 0
        return b
    }

    /// 从某天（含）到今天累加
    static func totals(since start: Date, now: Date = Date()) -> Bucket {
        var sum = Bucket()
        var cursor = Calendar.current.startOfDay(for: start)
        let end = Calendar.current.startOfDay(for: now)
        while cursor <= end {
            let b = bucket(day: DayKey.of(cursor))
            sum.prompt += b.prompt
            sum.completion += b.completion
            sum.calls += b.calls
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return sum
    }

    /// DeepSeek 的价格（元 / 百万 token），只用来估个大概
    static func cost(_ b: Bucket) -> Double {
        Double(b.prompt) / 1_000_000 * 2.0 + Double(b.completion) / 1_000_000 * 8.0
    }

    static func text(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1f 万", Double(n) / 10_000) }
        return "\(n)"
    }
}
