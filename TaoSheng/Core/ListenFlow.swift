import Foundation
import Combine

/// 「开始聆听 → 边录边转写 → 结束 → 分清说话人 → 立即整理 → 推送」的总调度。
///
/// 一句话说明各步归谁管：录音归 CaptureEngine（段上带 session_id），转写归 TranscribeQueue
/// （会话中每段落盘就立刻转），分人与整理归这里。任何一步失败都落在会话上，界面给「重试」，
/// App 被杀之后重启也能凭库里的状态接着收尾。
@MainActor
final class ListenFlow: ObservableObject {
    static let shared = ListenFlow()

    /// 当前这一场（录音中或刚处理完）。没有会话时为 nil。
    @Published private(set) var current: ListenSession?
    /// 处理中的一句话提示：「正在分辨说话人…」「正在整理…」
    @Published private(set) var phaseText: String?
    /// 非致命提示，例如「未能分辨说话人」——如实告诉用户，不假装分开了。
    @Published private(set) var note: String?
    @Published private(set) var working = false
    @Published private(set) var lastError: String?

    private init() {
        current = Store.shared.latestSession()
    }

    var isRecording: Bool { current?.state == .recording }

    /// 重新读一次最新会话（启动、截图灌数据之后用）
    func reloadCurrent() {
        current = Store.shared.latestSession()
    }

    /// 英雄卡上显示的状态文字。
    var statusText: String {
        if let p = phaseText, !p.isEmpty { return p }
        guard let s = current else { return "点开始聆听，边录边转写" }
        switch s.state {
        case .recording: return "正在聆听"
        case .finalizing: return "正在分辨说话人"
        case .digesting: return "正在整理"
        case .done: return "已整理"
        case .failed: return "处理失败"
        }
    }

    var canRetry: Bool {
        guard let s = current else { return false }
        return s.state == .failed && !working
    }

    // MARK: - 开始 / 结束

    func start(mode: CaptureMode) {
        guard current?.state != .recording else { return }
        let s = ListenSession(
            id: shortID(),
            modeRaw: mode.rawValue,
            startedAt: Date(),
            endedAt: nil,
            stateRaw: SessionState.recording.rawValue,
            speakersJSON: "{}",
            eventId: nil,
            error: nil
        )
        Store.shared.insertSession(s)
        // 模式锁在会话上，设置里的当前模式跟着同步，界面显示才一致
        Settings.shared.captureMode = mode
        CaptureEngine.shared.bindSession(s.id, mode: mode)
        UserDefaults.standard.set(true, forKey: "captureWanted")
        current = s
        phaseText = nil
        note = nil
        lastError = nil
        CaptureEngine.shared.start()
    }

    func stop() {
        guard var s = current, s.state == .recording else { return }
        UserDefaults.standard.set(false, forKey: "captureWanted")
        CaptureEngine.shared.stop()
        CaptureEngine.shared.bindSession(nil, mode: nil)
        s.endedAt = Date()
        s.stateRaw = SessionState.finalizing.rawValue
        Store.shared.updateSessionState(id: s.id, state: .finalizing, endedAt: s.endedAt)
        current = s
        working = true
        Task { await finish(s, fromDigest: false) }
    }

    /// 失败后从失败那一步继续：还没分人就从分人开始，已经分好就直接重整理。
    func retry() {
        guard let s = current, !working else { return }
        working = true
        lastError = nil
        let hasUtterances = Store.shared.utteranceCount(sessionId: s.id) > 0
        Task { await finish(s, fromDigest: hasUtterances) }
    }

    /// 启动时接上次没处理完的会话（被杀、闪退、断电都算）。
    func resumeAfterLaunch() {
        let un = Store.shared.unfinishedSessions()
        guard !un.isEmpty else {
            current = Store.shared.latestSession()
            return
        }
        for var s in un {
            if s.state == .recording {
                // 进程都不在了当然没在录：按已有段收尾
                s.endedAt = s.endedAt ?? Date()
                s.stateRaw = SessionState.finalizing.rawValue
                Store.shared.updateSessionState(id: s.id, state: .finalizing, endedAt: s.endedAt)
            }
        }
        guard let last = Store.shared.unfinishedSessions().last else { return }
        current = last
        working = true
        let fromDigest = last.state == .digesting && Store.shared.utteranceCount(sessionId: last.id) > 0
        Task { await finish(last, fromDigest: fromDigest) }
    }

    // MARK: - 收尾

    private func finish(_ session: ListenSession, fromDigest: Bool) async {
        var s = Store.shared.session(id: session.id) ?? session
        do {
            var utterances = Store.shared.utterances(sessionId: s.id)

            if !fromDigest || utterances.isEmpty {
                phaseText = "正在分辨说话人…"
                s.stateRaw = SessionState.finalizing.rawValue
                Store.shared.updateSessionState(id: s.id, state: .finalizing)
                current = s

                let segs = Store.shared.sessionSegments(sessionId: s.id)
                if segs.isEmpty { throw LLMError.badReply("这场没有录到内容") }
                let out = try await SessionTranscriber.run(session: s, segments: segs) { [weak self] done, total in
                    guard total > 1 else { return }
                    // 回调在后台线程：进度文字要回主线程改
                    Task { @MainActor in self?.phaseText = "正在分辨说话人（\(done)/\(total)）…" }
                }
                utterances = out.utterances
                Store.shared.replaceUtterances(sessionId: s.id, out.utterances)
                writeSpeakersBack(utterances, segments: segs)
                note = out.note
            }

            phaseText = "正在整理…"
            s.stateRaw = SessionState.digesting.rawValue
            Store.shared.updateSessionState(id: s.id, state: .digesting)
            current = s

            let digest = try await SessionDigest.run(session: s, utterances: utterances)
            Store.shared.updateSessionState(id: s.id, state: .done, eventId: digest.eventId)
            PushEngine.shared.pushSession(session: s, title: digest.title,
                                          conclusion: NoteRules.conclusion(digest.summary),
                                          items: digest.items)

            s.stateRaw = SessionState.done.rawValue
            s.eventId = digest.eventId
            current = s
            phaseText = Settings.shared.pushOnDigest ? "已整理并推送" : "已整理"
            lastError = nil
        } catch {
            phaseText = nil
            lastError = error.localizedDescription
            Store.shared.updateSessionState(id: s.id, state: .failed, error: error.localizedDescription)
            s.stateRaw = SessionState.failed.rawValue
            s.error = error.localizedDescription
            current = s
            NSLog("涛声: 会话收尾失败 \(error)")
        }
        working = false
        AppState.shared.refresh()
        NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
    }

    /// 把整场分好的说话人写回每一段：原话页、时间线里那些按段显示的地方
    /// 也就能看到「周工」而不是「说话人2」。按时间重叠最多的那条话轮算。
    private func writeSpeakersBack(_ utterances: [Utterance], segments: [Segment]) {
        guard !utterances.isEmpty else { return }
        // 拼接时是按时间顺序首尾相接的，所以每段在整场音频里的起点 = 前面所有段时长之和，
        // 和 SessionMerger 记的 offsets 一致，不用再单独传进来。
        var cursor = 0.0
        for seg in segments {
            let start = cursor
            let end = cursor + max(seg.duration, 0.1)
            cursor = end
            var best: Utterance?
            var bestOverlap = 0.0
            for u in utterances {
                let overlap = min(end, u.end) - max(start, u.start)
                if overlap > bestOverlap { bestOverlap = overlap; best = u }
            }
            if let best, !best.speaker.isEmpty {
                Store.shared.setSpeaker(id: seg.id, speaker: best.speaker)
            }
        }
    }

    /// 改说话人名：作用在整场（utterance + 会话映射），事件详情上的标签立刻跟着变。
    func renameSpeaker(_ label: String, to name: String) {
        guard var s = current ?? Store.shared.latestSession() else { return }
        var map = s.speakers
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            map.removeValue(forKey: label)
        } else {
            map[label] = trimmed
        }
        Store.shared.updateSessionSpeakers(id: s.id, speakers: map)
        s.speakersJSON = JSONList.encodeMap(map)
        current = s
        NotificationCenter.default.post(name: .taoshengDataChanged, object: nil)
    }
}
