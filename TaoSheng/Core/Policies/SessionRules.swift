import Foundation

/// 一场「聆听会话」的状态。
///
/// 董事长给的用法是：开会前点开始 → 边录边转写 → 点结束 → 分清说话人 → 立即整理 → 推送。
/// 这条链路每一步都要能被打断、能被恢复，所以状态是显式落库的：
/// 录音 → 收尾（拼音频 + 整场分人）→ 整理 → 完成；任何一步失败都停在 failed，界面给「重试」。
public enum SessionState: String, Codable, CaseIterable {
    case recording
    case finalizing
    case digesting
    case done
    case failed

    /// 已经不需要后台继续跑的终态。
    public var isSettled: Bool { self == .done || self == .failed }

    /// 界面上显示的中文。
    public var text: String {
        switch self {
        case .recording: return "正在聆听"
        case .finalizing: return "正在分辨说话人"
        case .digesting: return "正在整理"
        case .done: return "已整理并推送"
        case .failed: return "处理失败"
        }
    }

    /// App 被杀 / 闪退后重启时，正在进行中的会话不可能还在录，只能按已有段收尾。
    public static func recovered(_ raw: String?) -> SessionState? {
        guard let raw, let s = SessionState(rawValue: raw) else { return nil }
        switch s {
        case .recording, .finalizing: return .finalizing
        case .digesting: return .digesting
        case .done, .failed: return s
        }
    }
}

/// 允许的状态流转。写成表而不是散在各处 if 里，方便单测把非法流转全部钉死。
public enum SessionFlow {
    public static func canMove(from: SessionState, to: SessionState) -> Bool {
        switch (from, to) {
        case (.recording, .finalizing), (.recording, .failed):
            return true
        case (.finalizing, .digesting), (.finalizing, .failed), (.finalizing, .finalizing):
            return true
        case (.digesting, .done), (.digesting, .failed), (.digesting, .digesting):
            return true
        case (.failed, .finalizing), (.failed, .digesting):
            return true
        case (.done, .done):
            return true
        default:
            return false
        }
    }
}

/// 豆包返回的一条「话轮」。`start/end` 统一换算成秒（接口给的是毫秒）。
public struct UtteranceSpan: Equatable {
    public var speakerRaw: String?
    public var start: Double
    public var end: Double
    public var text: String

    public init(speakerRaw: String?, start: Double, end: Double, text: String) {
        self.speakerRaw = speakerRaw
        self.start = start
        self.end = end
        self.text = text
    }

    public var duration: Double { max(0, end - start) }
}

/// 喂给大模型的「一句话」：说话人已经换成中文编号，时间也换成了秒。
public struct LabeledSpan: Equatable {
    public var speaker: String
    public var start: Double
    public var end: Double
    public var text: String

    public init(speaker: String, start: Double, end: Double, text: String) {
        self.speaker = speaker
        self.start = start
        self.end = end
        self.text = text
    }
}

/// 豆包「录音文件识别」响应的解析。
///
/// 依据：BytePlus 的同源文档给出的 JSON schema
/// （ASRUtterance: text / start_time / end_time / words / additions，并注明
/// speaker labels arrive in `additions` when `enable_speaker_info` is set）与
/// 社区的字段表（`enable_speaker_info` 需配合 `show_utterances`，说话人标签在 `additions`）。
/// 真实返回字段没有密钥，未能在真机验证，所以这里对三种写法都做兼容。
public enum DoubaoResultParser {
    /// 从 `result` 对象里取话轮；拿不到就退回整段 `text`。
    public static func utterances(fromResult result: Any?) -> [UtteranceSpan] {
        guard let dict = result as? [String: Any] else { return [] }
        let rawList = (dict["utterances"] as? [[String: Any]]) ?? []
        var out: [UtteranceSpan] = []
        for item in rawList {
            let text = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty { continue }
            out.append(UtteranceSpan(
                speakerRaw: speakerLabel(in: item),
                start: seconds(item["start_time"] ?? item["start"] ?? item["startTime"]),
                end: seconds(item["end_time"] ?? item["end"] ?? item["endTime"]),
                text: text
            ))
        }
        if !out.isEmpty { return out }

        // 没有话轮就当成一条，时间未知。别丢字。
        if let text = (dict["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return [UtteranceSpan(speakerRaw: nil, start: 0, end: 0, text: text)]
        }
        return []
    }

    /// 说话人标签在哪：`additions.speaker`（官方 schema）→ `speaker` → `speaker_id`。
    public static func speakerLabel(in item: [String: Any]) -> String? {
        if let additions = item["additions"] as? [String: Any] {
            for key in ["speaker", "speaker_id", "spk", "speakerId"] {
                if let v = stringify(additions[key]), !v.isEmpty { return v }
            }
        }
        for key in ["speaker", "speaker_id", "spk", "speakerId"] {
            if let v = stringify(item[key]), !v.isEmpty { return v }
        }
        return nil
    }

    /// 毫秒 → 秒。接口若已经给了秒（小于 1000 且带小数），按原值处理。
    public static func seconds(_ any: Any?) -> Double {
        guard let v = number(any) else { return 0 }
        if v > 1000 { return v / 1000 }
        return v
    }

    private static func stringify(_ any: Any?) -> String? {
        if let s = any as? String { return s.trimmingCharacters(in: .whitespaces) }
        if let n = any as? Int { return String(n) }
        if let n = any as? Double { return String(Int(n)) }
        return nil
    }

    private static func number(_ any: Any?) -> Double? {
        if let n = any as? Double { return n }
        if let n = any as? Int { return Double(n) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }
}

/// 说话人编号：按「第一次出现的顺序」映射成 说话人1、说话人2…
///
/// 豆包给的是任务内的临时标签（可能是 "1"/"2"，也可能是 "speaker_1"），
/// 不能直接拿去显示，也不能跨场复用，所以每场都重新编号。
public enum SpeakerRules {
    public static func display(_ index: Int) -> String { "说话人\(index)" }

    /// 把原始标签按首现顺序编号；没有标签的统一归到编号 1（后续会被声纹兜底覆盖）。
    public static func numbering(_ spans: [UtteranceSpan]) -> [String: Int] {
        var map: [String: Int] = [:]
        var next = 1
        for s in spans {
            guard let raw = s.speakerRaw, !raw.isEmpty else { continue }
            if map[raw] == nil {
                map[raw] = next
                next += 1
            }
        }
        return map
    }

    /// 把话轮换成带中文说话人的列表。没有标签的按 1 号处理。
    public static func label(_ spans: [UtteranceSpan]) -> [LabeledSpan] {
        let map = numbering(spans)
        return spans.map { s in
            let idx = s.speakerRaw.flatMap { map[$0] } ?? 1
            return LabeledSpan(speaker: display(idx), start: s.start, end: s.end, text: s.text)
        }
    }

    /// 同一个说话人是否被拆成了两段相邻话轮——用于判断「分人是否可信」。
    public static func distinctSpeakers(_ spans: [UtteranceSpan]) -> Int {
        numbering(spans).count
    }

    /// 每人累计发言时长（秒），按编号从小到大。
    public static func durations(_ spans: [LabeledSpan]) -> [(name: String, seconds: Double)] {
        var acc: [String: Double] = [:]
        for s in spans { acc[s.speaker, default: 0] += max(0, s.end - s.start) }
        return acc.sorted { a, b in
            let na = Int(a.key.replacingOccurrences(of: "说话人", with: "")) ?? 99
            let nb = Int(b.key.replacingOccurrences(of: "说话人", with: "")) ?? 99
            return na < nb
        }.map { (name: $0.key, seconds: $0.value) }
    }
}

/// 事件场景由代码写死，不再让大模型猜——它以前会把会议写成「日常」，节律统计就全错了。
public enum SceneRules {
    public static let meeting = "会议"
    public static let training = "培训"
    public static let call = "通话"

    public static func scene(forMode raw: String?) -> String {
        switch raw ?? "" {
        case "training": return training
        default: return meeting
        }
    }
}
