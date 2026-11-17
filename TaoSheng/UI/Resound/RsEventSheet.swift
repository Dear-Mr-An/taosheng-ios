import SwiftUI
import UIKit

/// 事件详情面板的全局开关：任意一页点某件事，都从这里打开同一张面板。
/// 面板挂在 RsShell 最外层，才能盖住 TabBar，也不会被列表行的边界裁掉。
final class RsEventPanel: ObservableObject {
    static let shared = RsEventPanel()
    @Published var event: MemoryEvent?
    private init() {}
    func open(_ e: MemoryEvent) { event = e }
    func close() { event = nil }
}

/// 事件详情（照原版 Sheets.kt / EventSheet 的结构）：
/// 顶部一行日期 · 时间 · 场景 · 时长 + 存待办 / 编辑；标题；摘要；原话（播放这件事 / 导出）；
/// 分人原话卡片；重点 / 复制 / 问问 / 删除。
/// 外层 RsBottomSheet 已经包了 ScrollView，这里不要再套一层。
struct RsEventSheet: View {
    let event: MemoryEvent
    var onClose: () -> Void = {}
    @EnvironmentObject private var app: AppState
    @ObservedObject private var player = SegmentPlayer.shared
    private func dismiss() { onClose() }

    /// 这件事自己的录音段：按场记录的取整场的段，其余按 lineFrom/lineTo 从当天原话里切出来。
    /// 不能拿当天全部录音：那样详情里会堆满别的事的原话，「播放这件事」也会把一整天播一遍。
    @State private var lines: [Segment] = []
    @State private var utterances: [Utterance] = []
    @State private var session: ListenSession?
    @State private var loaded = false
    @State private var loading = true

    @State private var editing = false
    @State private var draftTitle = ""
    @State private var draftSummary = ""
    @FocusState private var titleFocused: Bool
    /// 从搜索打开的往日事件不在 app 的列表里，刷新后也拿不到新值，靠这两个让面板立刻显示改动
    @State private var edited: (title: String, summary: String)?
    @State private var starOverride: Bool?
    @State private var savedTodo = false
    @State private var confirmDelete = false

    private var current: MemoryEvent {
        var e = app.todayEvents.first(where: { $0.id == event.id })
            ?? app.dayEvents.first(where: { $0.id == event.id })
            ?? event
        if let edited {
            e.title = edited.title
            e.summary = edited.summary
        }
        if let starOverride { e.starred = starOverride }
        return e
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            if editing {
                editor
            } else {
                Text(current.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Rs.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !current.summary.isEmpty {
                    Text(current.summary)
                        .font(.system(size: 15))
                        .lineSpacing(5)
                        .foregroundStyle(Rs.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            transcriptBlock
            if !editing { actionRow }
            Color.clear.frame(height: 24)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .task { await load() }
        .confirmationDialog("删除后这件事会从时间线里清掉，录音和原话不受影响",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除这件事", role: .destructive) { deleteEvent() }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: 顶部

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(metaLine)
                .font(.system(size: 13))
                .foregroundStyle(Rs.text3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if !editing {
                linkButton(savedTodo ? "已存待办" : "存待办", enabled: !savedTodo) { toTodo() }
                linkButton("编辑") { startEdit() }
            }
        }
    }

    private var metaLine: String {
        var parts: [String] = [dayLabel, timeRange]
        if !current.scene.isEmpty { parts.append(current.scene) }
        let secs = Int((current.endAt ?? current.startAt).timeIntervalSince(current.startAt))
        if secs < 60 {
            parts.append("不到 1 分钟")
        } else if secs < 3600 {
            parts.append("\(secs / 60) 分钟")
        } else {
            parts.append("\(secs / 3600) 小时 \(secs % 3600 / 60) 分")
        }
        return parts.joined(separator: " · ")
    }

    private var dayLabel: String {
        guard let d = DayKey.date(from: current.day) else { return current.day }
        if Calendar.current.isDateInToday(d) { return "今天" }
        if Calendar.current.isDateInYesterday(d) { return "昨天" }
        return Fmt.monthDay.string(from: d)
    }

    private var timeRange: String {
        let from = current.timeText
        let to = current.endAt.map { Fmt.hm.string(from: $0) } ?? from
        return from == to ? from : from + " – " + to
    }

    // MARK: 编辑

    private var trimmedTitle: String { draftTitle.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("标题", text: $draftTitle, axis: .vertical)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Rs.text)
                .lineLimit(1...3)
                .focused($titleFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Rs.fill))
            TextField("摘要（可不填）", text: $draftSummary, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(Rs.text)
                .lineLimit(2...8)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Rs.fill))
            HStack(spacing: 10) {
                pill("取消", filled: false) { cancelEdit() }
                pill("保存", filled: true) { saveEdit() }
                    .disabled(trimmedTitle.isEmpty)
                    .opacity(trimmedTitle.isEmpty ? 0.5 : 1)
            }
        }
    }

    private func startEdit() {
        draftTitle = current.title
        draftSummary = current.summary
        editing = true
        // 输入框这一帧才插进视图树，立刻设焦点会被忽略
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { titleFocused = true }
    }

    private func cancelEdit() {
        titleFocused = false
        editing = false
    }

    private func saveEdit() {
        let title = trimmedTitle
        guard !title.isEmpty else { return }
        let summary = draftSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        Store.shared.updateEventTitle(id: current.id, title: title, summary: summary)
        edited = (title: title, summary: summary)
        titleFocused = false
        editing = false
        app.refresh()
        RsToast.shared.show("已保存")
    }

    // MARK: 原话

    private var transcriptBlock: some View {
        let rows = self.rows
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("原话")
                    .font(.system(size: 13))
                    .foregroundStyle(Rs.text3)
                Spacer(minLength: 0)
                if !lines.isEmpty {
                    compactPill(playingThis ? "■ 停止" : "▶ 播放这件事") { playAll() }
                }
                if !rows.isEmpty {
                    compactPill("导出") { exportText() }
                }
            }
            if loading {
                Text("正在读原话…")
                    .font(.system(size: 13))
                    .foregroundStyle(Rs.text3)
            } else if rows.isEmpty {
                Text("这段没有可用的原话。")
                    .font(.system(size: 13))
                    .foregroundStyle(Rs.text3)
            } else {
                RsCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                            rowView(index: i, row: row)
                        }
                    }
                }
            }
        }
    }

    private func rowView(index: Int, row: Row) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle().fill(Rs.accentSoft).frame(width: 24, height: 24)
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Rs.accent)
            }
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.who)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Rs.accent)
                        .lineLimit(1)
                    Text(row.time)
                        .font(.system(size: 12))
                        .foregroundStyle(Rs.text3)
                    if let seg = row.segment {
                        let on = player.isPlaying(seg.id)
                        Button {
                            player.toggle(segment: seg)
                        } label: {
                            Image(systemName: on ? "pause.fill" : "play.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Rs.accent)
                                .frame(width: 28, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(on ? "暂停这段" : "播放这段")
                    }
                }
                Text(row.text)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .foregroundStyle(Rs.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// segment 为空的是按人切开的句子：一句话没有自己的音频文件，不给单句播放
    private struct Row {
        let who: String
        let time: String
        let text: String
        let segment: Segment?
    }

    private var rows: [Row] {
        if !utterances.isEmpty {
            return utterances.map { u in
                Row(who: session?.name(u.speaker) ?? u.speaker, time: utteranceTime(u), text: u.text, segment: nil)
            }
        }
        return lines.filter { !$0.transcript.isEmpty }.map { s in
            Row(who: speakerName(s.speaker), time: Fmt.hm.string(from: s.startedAt), text: s.transcript, segment: s)
        }
    }

    private func utteranceTime(_ u: Utterance) -> String {
        guard let s = session else { return u.timeText }
        return Fmt.hm.string(from: s.startedAt.addingTimeInterval(u.start))
    }

    /// 段上的 speaker 可能已经是人名（声纹认出来的），只有空和纯编号才补「说话人」
    private func speakerName(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "说话人" }
        return t.allSatisfy(\.isNumber) ? "说话人\(t)" : t
    }

    private var playingThis: Bool { lines.contains { player.isPlaying($0.id) } }

    private func playAll() {
        guard !lines.isEmpty else { return }
        if playingThis {
            player.stop()
        } else {
            player.playAll(lines)
        }
    }

    // MARK: 操作

    private var actionRow: some View {
        HStack(spacing: 10) {
            pill(current.starred ? "★ 重点" : "☆ 重点", filled: current.starred) { toggleStar() }
            pill("复制", filled: false) { copyText() }
            pill("问问", filled: false) { askAbout() }
            pill("删除", filled: false, danger: true) { confirmDelete = true }
        }
        .padding(.top, 6)
    }

    private func toggleStar() {
        let next = !current.starred
        starOverride = next
        app.starEvent(current.id, starred: next)
    }

    private func toTodo() {
        guard !savedTodo else { return }
        app.addItems([(content: current.title, category: "待办", due: nil)])
        savedTodo = true
        RsToast.shared.show("已存为待办")
    }

    private func copyText() {
        UIPasteboard.general.string = plainText
        RsToast.shared.show("已复制")
    }

    /// 问题交给 RsShell：它会关掉这张面板、切到「问问」并把问题填进输入框
    private func askAbout() {
        NotificationCenter.default.post(name: .taoshengAskPrefill, object: nil,
                                        userInfo: ["q": "关于「\(current.title)」，帮我回顾一下要点和待办"])
        dismiss()
    }

    private func deleteEvent() {
        if playingThis { player.stop() }
        app.deleteEvent(current.id)
        dismiss()
        RsToast.shared.show("已删除")
    }

    /// 复制和导出用绝对日期：文件传出去以后「今天」就对不上了
    private var plainText: String {
        var meta = "\(current.day) \(timeRange)"
        if !current.scene.isEmpty { meta += " · \(current.scene)" }
        var out = "\(meta)\n\(current.title)\n"
        if !current.summary.isEmpty { out += "\(current.summary)\n" }
        if !current.points.isEmpty {
            out += "要点\n" + current.points.map { "· \($0)" }.joined(separator: "\n") + "\n"
        }
        let rs = rows
        if !rs.isEmpty {
            out += "原话\n" + rs.map { "\($0.who) \($0.time) \($0.text)" }.joined(separator: "\n") + "\n"
        }
        return out
    }

    private func exportText() {
        // 标题里的「/」「:」等字符会让路径非法，写入静默失败却照样弹分享面板
        let raw = "\(current.day)-\(current.timeText.replacingOccurrences(of: ":", with: ""))-\(current.title)"
        let name = Fmt.safeFileName(raw, fallback: "涛声-\(current.day)") + ".txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try plainText.write(to: url, atomically: true, encoding: .utf8)
            ShareSheet.present(items: [url])
        } catch {
            RsToast.shared.show("导出失败，请重试")
        }
    }

    private func linkButton(_ text: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(enabled ? Rs.accent : Rs.text3)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func compactPill(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Rs.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(Rs.accentSoft))
        }
        .buttonStyle(.plain)
    }

    /// 未选中的按钮用浅灰底：面板本身是白的，白底按钮看上去只是一行字，不像能点
    private func pill(_ text: String, filled: Bool, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(danger ? Rs.critical : (filled ? Rs.accent : Rs.text))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    Capsule(style: .continuous)
                        .fill(danger ? Rs.critical.opacity(0.10) : (filled ? Rs.accentSoft : Rs.fill))
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        guard !loaded else { return }
        loaded = true
        let ev = event
        let result = await Task.detached(priority: .userInitiated) { () -> ([Segment], ListenSession?, [Utterance]) in
            if let sid = ev.sessionId, !sid.isEmpty {
                let segs = Store.shared.sessionSegments(sessionId: sid)
                let utts = Store.shared.utterances(sessionId: sid)
                if !segs.isEmpty || !utts.isEmpty {
                    return (segs, Store.shared.session(id: sid), utts)
                }
            }
            let rows = Store.shared.transcriptRows(day: ev.day, limit: 3000)
            let from = max(1, ev.lineFrom) - 1
            let to = min(rows.count, max(ev.lineTo, ev.lineFrom))
            if from < to {
                return (Array(rows[from..<to]), nil, [])
            }
            // 行号对不上（重新整理过）时按时间重叠兜底
            let end = ev.endAt ?? ev.startAt.addingTimeInterval(60)
            let hit = rows.filter {
                $0.startedAt >= ev.startAt.addingTimeInterval(-1) && $0.startedAt <= end.addingTimeInterval(1)
            }
            return (hit, nil, [])
        }.value
        lines = result.0
        session = result.1
        utterances = result.2
        loading = false
    }
}
