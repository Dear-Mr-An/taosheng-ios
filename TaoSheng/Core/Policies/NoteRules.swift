import Foundation

/// 速记的结构（纯逻辑，可单测）。
///
/// 董事长要的是「开完会马上出的一张纸」：会议是议题/结论/要点/决定/待办，培训是主题/要点/方法/行动。
/// 结构由代码按模式写死，不让大模型自由发挥——同一个 App 里两种东西长得不一样，用户才分得清。
public struct NoteSection: Equatable {
    public var title: String
    public var lines: [String]

    public init(title: String, lines: [String]) {
        self.title = title
        self.lines = lines
    }

    public var isEmpty: Bool { lines.isEmpty }
}

public enum NoteRules {
    /// 会议速记 / 培训笔记
    public static func noteTitle(forMode raw: String?) -> String {
        (raw ?? "") == "training" ? "培训笔记" : "会议速记"
    }

    /// 时间线上用的小标签：速记 / 笔记
    public static func tag(forScene scene: String) -> String {
        scene == "培训" ? "笔记" : "速记"
    }

    public static func tag(forMode raw: String?) -> String {
        (raw ?? "") == "training" ? "笔记" : "速记"
    }

    /// 场景写死：会议 / 培训
    public static func scene(forMode raw: String?) -> String {
        SceneRules.scene(forMode: raw)
    }

    /// 分段名（顺序即展示顺序）
    public static func sectionTitles(forMode raw: String?) -> [String] {
        if (raw ?? "") == "training" {
            return ["主题", "核心要点", "知识点", "行动"]
        }
        return ["议题", "结论先行", "要点", "决定"]
    }

    /// 大模型返回的字段名 → 展示用的分段名
    private static func prefixes(forMode raw: String?) -> [String] {
        if (raw ?? "") == "training" {
            return ["主题：", "核心要点：", "知识点：", "行动："]
        }
        return ["议题：", "结论先行：", "要点：", "决定："]
    }

    /// 把「字段：内容」格式的要点重新分拣成分段；没带前缀的落到第三个分段（要点/知识点）。
    /// 老数据（0.6.0 及以前，points 是裸句子）也走这里：全部落到要点段，不会丢。
    public static func sections(forMode raw: String?, points: [String]) -> [NoteSection] {
        let titles = sectionTitles(forMode: raw)
        let marks = prefixes(forMode: raw)
        var bag = [[String]](repeating: [], count: titles.count)
        let fallback = titles.count > 2 ? 2 : max(0, titles.count - 1)
        for raw in points {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            var placed = false
            for (i, mark) in marks.enumerated() where line.hasPrefix(mark) {
                let body = String(line.dropFirst(mark.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty { bag[i].append(body) }
                placed = true
                break
            }
            if !placed { bag[fallback].append(line) }
        }
        return zip(titles, bag).map { NoteSection(title: $0, lines: $1) }
    }

    /// 结论第一句：给「刚结束」卡和推送用，一行就能读完。
    public static func conclusion(_ summary: String) -> String {
        let text = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        for sep in ["。", "！", "？", "\n", "；", ";"] {
            if let r = text.range(of: sep), text.distance(from: text.startIndex, to: r.lowerBound) >= 4 {
                return String(text[text.startIndex...r.lowerBound])
            }
        }
        return String(text.prefix(60))
    }

    /// 摘要盒子里的正文：去掉首尾空白、合并多余空行
    public static func tidy(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    /// 复制全部内容用的纯文本
    public static func plainText(mode raw: String?, title: String, timeRange: String,
                                 summary: String, points: [String],
                                 people: [String], quotes: [EventQuote]) -> String {
        var out = "\(noteTitle(forMode: raw))·\(title)\n\(timeRange)\n\n"
        if !summary.isEmpty { out += summary + "\n\n" }
        for s in sections(forMode: raw, points: points) where !s.isEmpty {
            out += s.title + "\n"
            for l in s.lines { out += "- \(l)\n" }
            out += "\n"
        }
        if !people.isEmpty { out += "参与的人：" + people.joined(separator: "、") + "\n\n" }
        if !quotes.isEmpty {
            out += "关键原话\n"
            for q in quotes { out += "\(q.speaker) · \(q.time)：\(q.text)\n" }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
