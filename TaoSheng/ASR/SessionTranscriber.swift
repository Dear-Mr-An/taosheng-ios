import Foundation

/// 整场识别 + 分说话人。
///
/// 用的接口：豆包「录音文件识别」极速版
/// `POST https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash`，
/// 请求里 `show_utterances: true` + `enable_speaker_info: true`（不传 language）。
/// 说话人标签读 `utterances[].additions.speaker`（官方 schema 里的 `additions`，「Extra
/// per-utterance annotations; speaker labels arrive here when enable_speaker_info is set」），
/// 兼容 `speaker` / `speaker_id` 两种写法。字段依据与未验证项见 README 的 0.6.0 章节。
///
/// 拿不到标签（没配豆包、服务返回里没有 additions、或者模式是培训不区分人）就退回
/// 「逐段转写 + 声纹编号」，并在会话上留一句「未能分辨说话人」，界面如实显示。
enum SessionTranscriber {
    struct Output {
        var utterances: [Utterance]
        var note: String?
    }

    static func run(session: ListenSession, segments: [Segment]) async throws -> Output {
        guard !segments.isEmpty else { throw TranscribeError.empty }

        let merged: SessionMerger.Result
        do {
            merged = try await SessionMerger.merge(segments: segments)
        } catch {
            // 拼不起来就退到逐段结果，至少别把这一场弄丢
            let fallback = fallbackUtterances(segments: segments, offsets: [:])
            if fallback.isEmpty { throw error }
            return Output(utterances: fallback, note: "音频拼接失败，按每段自己认的人显示")
        }
        defer { try? FileManager.default.removeItem(at: merged.url) }

        if session.mode.separateSpeakers, let transcriber = TranscriberFactory.make() {
            do {
                let res = try await transcriber.transcribe(fileURL: merged.url)
                let spans = res.spans
                let distinct = SpeakerRules.distinctSpeakers(spans)
                if !spans.isEmpty, distinct >= 2 || spans.contains(where: { ($0.speakerRaw ?? "").isEmpty == false }) {
                    let labeled = SpeakerRules.label(spans)
                    let list = labeled.enumerated().map { i, s in
                        Utterance(id: shortID(), sessionId: session.id, speaker: s.speaker,
                                  start: s.start, end: s.end, text: s.text, orderIndex: i)
                    }
                    let note = distinct <= 1 ? "接口只返回了一个说话人，可能是单人讲述" : nil
                    return Output(utterances: list, note: note)
                }
            } catch {
                NSLog("涛声: 整场识别失败，退回逐段结果 — \(error.localizedDescription)")
            }
        }

        let fallback = fallbackUtterances(segments: segments, offsets: merged.offsets)
        if fallback.isEmpty { throw TranscribeError.empty }
        return Output(utterances: fallback, note: "未能分辨说话人，按每段自己认的人显示")
    }

    /// 逐段兜底：用段上已有的转写和声纹说话人，时间用拼接时的偏移。
    static func fallbackUtterances(segments: [Segment], offsets: [String: Double]) -> [Utterance] {
        let sorted = segments.sorted { $0.startedAt < $1.startedAt }
        var out: [Utterance] = []
        var cursor = 0.0
        for seg in sorted {
            let start = offsets[seg.id] ?? cursor
            let text = seg.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            cursor = start + max(seg.duration, 0)
            guard !text.isEmpty else { continue }
            let speaker = seg.speaker.isEmpty ? "说话人1" : seg.speaker
            out.append(Utterance(id: shortID(), sessionId: seg.sessionId ?? "", speaker: speaker,
                                 start: start, end: start + max(seg.duration, 0), text: text,
                                 orderIndex: out.count))
        }
        return out
    }
}
