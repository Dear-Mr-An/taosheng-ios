import Foundation
import AVFoundation

/// 整场识别 + 分说话人。
///
/// 用的接口：豆包「录音文件识别」极速版
/// `POST https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash`，
/// 请求里 `show_utterances: true` + `enable_speaker_info: true`（不传 language）。
/// 说话人标签读 `utterances[].additions.speaker`（官方 schema 里的 `additions`，「Extra
/// per-utterance annotations; speaker labels arrive here when enable_speaker_info is set」），
/// 兼容 `speaker` / `speaker_id` 两种写法。字段依据与未验证项见 README 的 0.6.0 / 0.6.1 章节。
///
/// **长会议必须切块**：官方文档写明单次音频不超过 2 小时、100MB（`ChunkRules.flashMaxSeconds`
/// 等），董事长一场会经常一个多小时，再加上重采样后的体量，整场一次送上去会直接失败。
/// 这里的做法是：超过上限 80% 就按段顺序切块，逐块拼接识别；每块里每个说话人取 ≥30 秒的
/// 话轮算一个声纹均值，再跨块按余弦相似度把同一个人并到一簇，最后整场统一编号。
///
/// 拿不到标签（没配豆包、服务返回里没有 additions、或者模式是培训不区分人）就退回
/// 「逐段转写 + 声纹编号」，并在会话上留一句「未能分辨说话人」，界面如实显示。
enum SessionTranscriber {
    struct Output {
        var utterances: [Utterance]
        var note: String?
        /// 这次识别切了几块；英雄卡拿它显示「正在分辨说话人（2/3）…」
        var chunkCount: Int
    }

    /// 一段话轮要多少秒才拿得动当声纹参考；太短的样本噪声比人声大
    private static let minSampleSeconds: Double = 30

    /// - Parameter progress: 每块识别完回调一次 (已完成块数, 总块数)，在主线程调用
    static func run(session: ListenSession,
                    segments: [Segment],
                    progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> Output {
        guard !segments.isEmpty else { throw TranscribeError.empty }
        let ordered = segments
            .filter { !$0.fileName.isEmpty }
            .sorted { $0.startedAt < $1.startedAt }
        guard !ordered.isEmpty else { throw TranscribeError.empty }

        // 培训是一个人讲，不需要分人，也就没必要整场重识别一遍
        guard session.mode.separateSpeakers, let transcriber = TranscriberFactory.make() else {
            let merged = try? await SessionMerger.merge(segments: ordered)
            if let url = merged?.url { try? FileManager.default.removeItem(at: url) }
            let list = fallbackUtterances(segments: ordered, offsets: merged?.offsets ?? [:])
            guard !list.isEmpty else { throw TranscribeError.empty }
            let note = session.mode.separateSpeakers ? "没有可用的转写服务，按每段自己认的人显示" : nil
            return Output(utterances: list, note: note, chunkCount: 1)
        }

        let groups = ChunkRules.chunks(segmentDurations: ordered.map { max($0.duration, 0) })
        guard !groups.isEmpty else { throw TranscribeError.empty }

        var chunkSpans: [[UtteranceSpan]] = []
        var chunkOffsets: [Double] = []
        var refs: [ChunkRules.SpeakerRef] = []
        var mergedOffsets: [String: Double] = [:]
        var cursor = 0.0
        var recognized = 0

        for (index, indexes) in groups.enumerated() {
            let part = indexes.compactMap { $0 < ordered.count ? ordered[$0] : nil }
            guard !part.isEmpty else { continue }
            let merged: SessionMerger.Result
            do {
                merged = try await SessionMerger.merge(segments: part)
            } catch {
                NSLog("涛声: 第 \(index + 1) 块拼接失败 — \(error.localizedDescription)")
                continue
            }
            defer { try? FileManager.default.removeItem(at: merged.url) }
            // 段的起点换算到整场：前面各块已经识别过的时长之和
            for (segID, local) in merged.offsets {
                mergedOffsets[segID] = cursor + local
            }
            let spans: [UtteranceSpan]
            do {
                spans = try await transcriber.transcribe(fileURL: merged.url).spans
            } catch {
                NSLog("涛声: 第 \(index + 1) 块识别失败 — \(error.localizedDescription)")
                cursor += merged.duration
                chunkSpans.append([])
                chunkOffsets.append(cursor)
                continue
            }
            chunkSpans.append(spans)
            chunkOffsets.append(cursor)
            // 每块每个说话人取样本，供跨块对号
            for label in labelOrder(spans) {
                let ranges = speechRanges(spans, label: label)
                let seconds = ranges.reduce(0.0) { $0 + $1.duration.seconds }
                guard seconds >= minSampleSeconds / 2 else { continue }
                if let vec = await speakerVector(file: merged.url, ranges: ranges) {
                    refs.append(ChunkRules.SpeakerRef(chunk: index, label: label, vector: vec))
                }
            }
            recognized += 1
            let done = recognized
            let total = groups.count
            progress?(done, total)
            cursor += merged.duration
        }

        // 只有一块时不用跨块对号，直接用接口给的标签顺序编号
        var mapping: [String: String] = [:]
        if let first = chunkSpans.first, groups.count == 1 {
            for (i, label) in labelOrder(first).enumerated() {
                mapping["0|\(label)"] = SpeakerRules.display(i)
            }
        } else if !refs.isEmpty {
            mapping = ChunkRules.mergeSpeakers(refs)
        }

        var out: [Utterance] = []
        for (index, spans) in chunkSpans.enumerated() where !spans.isEmpty {
            let base = chunkOffsets.indices.contains(index) ? chunkOffsets[index] : 0
            let ordered = labelOrder(spans)
            for span in spans {
                let text = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let label = span.speakerRaw ?? ordered.first ?? "1"
                let mapped = mapping["\(index)|\(label)"]
                    ?? mapping["\(index)|\(label.trimmingCharacters(in: .whitespaces))"]
                let speaker = mapped ?? SpeakerRules.display(ordered.firstIndex(of: label) ?? 0)
                out.append(Utterance(id: shortID(), sessionId: session.id, speaker: speaker,
                                     start: base + span.start, end: base + max(span.end, span.start),
                                     text: text, orderIndex: out.count))
            }
        }

        if out.isEmpty {
            let list = fallbackUtterances(segments: ordered, offsets: mergedOffsets)
            guard !list.isEmpty else { throw TranscribeError.empty }
            return Output(utterances: list, note: "识别没有返回可用的话轮，按每段自己认的人显示",
                          chunkCount: groups.count)
        }

        let distinct = Set(out.map(\.speaker)).count
        var note: String? = distinct <= 1 ? "接口只返回了一个说话人，可能是单人讲述" : nil
        if groups.count > 1, mapping.isEmpty, note == nil {
            note = "这场分了 \(groups.count) 段识别，说话人是按声音对上的，可能有偏差"
        }
        return Output(utterances: out, note: note, chunkCount: groups.count)
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

    // MARK: - 内部

    /// 这一块里说话人标签首次出现的顺序（接口给的编号在各块之间不保证一致，先记顺序再对号）
    private static func labelOrder(_ spans: [UtteranceSpan]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in spans {
            let label = (s.speakerRaw ?? "").trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            if seen.insert(label).inserted { out.append(label) }
        }
        return out
    }

    private static func speechRanges(_ spans: [UtteranceSpan], label: String) -> [CMTimeRange] {
        spans.compactMap { span in
            guard (span.speakerRaw ?? "") == label else { return nil }
            let dur = max(span.end - span.start, 0)
            guard dur > 0.2 else { return nil }
            return CMTimeRange(start: CMTime(seconds: span.start, preferredTimescale: 600),
                               duration: CMTime(seconds: dur, preferredTimescale: 600))
        }
    }

    /// 把某个人的话轮从这一块里切出来算声纹均值；切不出来就返回 nil（不参与对号）
    private static func speakerVector(file: URL, ranges: [CMTimeRange]) async -> [Double]? {
        guard !ranges.isEmpty else { return nil }
        guard let slice = try? await SessionMerger.export(from: file, ranges: ranges) else { return nil }
        defer { try? FileManager.default.removeItem(at: slice) }
        return await Task.detached(priority: .utility) { Voiceprint.vector(from: slice) }.value
    }
}
