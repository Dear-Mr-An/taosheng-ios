import SwiftUI
import UIKit

/// 一件事的详情。从时间线点进来时以「抽纸」的方式从底部抽出，
/// 看完往下滑即可收起，不打断时间线本身的位置。
struct EventDetailView: View {
    let event: MemoryEvent
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var lines: [Segment] = []
    /// 会话整理出来的分人原话：有就按人分行显示，没有才退回按段显示
    @State private var utterances: [Utterance] = []
    @State private var session: ListenSession?
    @State private var renameItem: RenamePayload?
    @State private var loadingLines = true
    @State private var shotOpened = false
    // 播放按钮要跟着播放器状态走，否则点了不变化
    @ObservedObject private var player = SegmentPlayer.shared
    @State private var editItem: EditPayload?
    @State private var draftTitle = ""
    @State private var draftSummary = ""
    @State private var toast: String?
    @State private var confirmDelete = false
    /// 速记的三段：0 速记 / 1 原话 / 2 发言（只有按场整理出来的事件才有）
    @State private var detailTab = 0
    @State private var shotTabbed = false

    private var current: MemoryEvent {
        app.todayEvents.first(where: { $0.id == event.id })
            ?? app.dayEvents.first(where: { $0.id == event.id })
            ?? event
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metaRow
                    Text(current.title)
                        .font(.system(size: Theme.fsHero, weight: .bold))
                        .foregroundColor(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if current.isNote {
                        Picker("", selection: $detailTab) {
                            Text("速记").tag(0)
                            Text("原话").tag(1)
                            Text("发言").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 2)

                        switch detailTab {
                        case 0: noteSection
                        case 1: rawSection
                        default: speakersSection
                        }
                    } else {
                        legacyContent
                    }

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
            }

            actionBar
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            if ShotMode.screen == "event-edit", !shotOpened {
                shotOpened = true
                editItem = EditPayload(title: current.title, summary: current.summary)
                return
            }
            draftTitle = event.title
            draftSummary = event.summary
            if !shotTabbed, let s = ShotMode.screen {
            shotTabbed = true
            if s == "event-raw" { detailTab = 1 }
            if s == "event-speakers" { detailTab = 2 }
        }
        if ShotMode.screen == "speaker-rename", renameItem == nil {
                renameItem = RenamePayload(label: "说话人2", name: session?.name("说话人2") ?? "周工")
            }
        }
        .task { await loadLines() }
        // 用 sheet(item:) 把初始值一起带进去：
        // 如果先改 draft 再置 isPresented，弹层会拿到改动前的旧值（标题、摘要都是空的）。
        .sheet(item: $editItem) { item in
            TextInputSheet(title: "编辑这件事",
                           fields: [
                               TextInputField(label: "标题", placeholder: "这件事叫什么", text: item.title),
                               TextInputField(label: "摘要", placeholder: "一两句话说明", kind: .multiline, text: item.summary)
                           ],
                           confirmTitle: "保存",
                           message: "改过之后，自动整理不会再覆盖你写的标题和摘要。") { values in
                draftTitle = values.first ?? ""
                draftSummary = values.count > 1 ? values[1] : ""
                saveEdit()
            }
        }
        // 点说话人标签改名字：一改就是整场，映射存在会话上，下次整理也用新名字
        .sheet(item: $renameItem) { item in
            TextInputSheet(title: "这是谁",
                           fields: [TextInputField(label: "名字", placeholder: "例如 老王", text: item.name)],
                           confirmTitle: "保存",
                           message: "改名作用于这一整场；已有人物可以直接填名字。") { values in
                let name = (values.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                ListenFlow.shared.renameSpeaker(item.label, to: name)
                Task { await loadLines() }
            }
        }
        .confirmationDialog("删除后这段原话对应的整理结果也会一起清掉", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除这件事", role: .destructive) { app.deleteEvent(event.id); dismiss() }
            Button("取消", role: .cancel) {}
        }
        .overlay(alignment: .top) {
            if let t = toast {
                Text(t)
                    .font(.system(size: 12.5))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
    }

    // MARK: 速记三段

    /// 「速记」页：摘要 + 四段要点（议题/结论先行/要点/决定 或 主题/核心要点/知识点/行动）+ 关键原话
    @ViewBuilder
    private var noteSection: some View {
        if !current.summary.isEmpty {
            Text(NoteRules.tidy(current.summary))
                .font(.system(size: 15.5))
                .foregroundColor(Theme.text2)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.sp3)
                .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(Theme.cardSoft))
        }

        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(current.noteSections.enumerated()), id: \.offset) { _, section in
                if !section.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(section.title)
                            .font(.system(size: Theme.fsSmall, weight: .semibold))
                            .foregroundColor(Theme.text2)
                        ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 8) {
                                Circle().fill(noteTint.opacity(0.6)).frame(width: 5, height: 5).padding(.top, 7)
                                Text(line)
                                    .font(.system(size: 15))
                                    .foregroundColor(Theme.text)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }

        if !current.quotes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("关键原话")
                    .font(.system(size: Theme.fsCaption, weight: .medium))
                    .foregroundColor(Theme.dim)
                ForEach(Array(current.quotes.enumerated()), id: \.offset) { _, q in
                    Button { jumpToQuote(q) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 1.5).fill(noteTint.opacity(0.5)).frame(width: 3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text((session?.name(q.speaker) ?? q.speaker) + " · " + q.time)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(Theme.dim)
                                Text("「\(q.text)」")
                                    .font(.system(size: Theme.fsSmall))
                                    .foregroundColor(Theme.text2)
                                    .lineSpacing(3)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(Theme.card))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var noteTint: Color { current.scene == "培训" ? Theme.purple : Theme.accent }

    /// 「发言」页：每人一条时长条，点名字改名（作用在整场）
    @ViewBuilder
    private var speakersSection: some View {
        if speakerRows.isEmpty {
            EmptyHint(symbol: "person.2", title: "还没有分人结果", detail: "这场会没录到可以分辨的说话人")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("这一场共 \(speakerRows.count) 位说话人")
                    .font(.system(size: Theme.fsCaption))
                    .foregroundColor(Theme.dim)
                SpeakerBars(rows: speakerRows) { label, name in
                    renameItem = RenamePayload(label: label, name: name)
                }
            }
            .padding(Theme.sp3)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.card))
        }
    }

    private var speakerRows: [(label: String, name: String, seconds: Double)] {
        var sums: [String: Double] = [:]
        for u in utterances { sums[u.speaker, default: 0] += u.duration }
        return sums
            .map { (label: $0.key, name: session?.name($0.key) ?? $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    /// 「原话」页：按人分行（有分人结果），否则退回按段
    @ViewBuilder
    private var rawSection: some View {
        HStack(spacing: 8) {
            Text(utterances.isEmpty ? "原话" : "原话 · 按说话人")
                .font(.system(size: Theme.fsCaption, weight: .medium))
                .foregroundColor(Theme.dim)
            Spacer(minLength: 0)
            pill("播放这件事", symbol: "play.fill", tint: Theme.accent) { playAll() }
            pill("导出", symbol: nil, tint: Theme.accent) { exportText() }
        }

        if !utterances.isEmpty { speakerChips }

        if loadingLines && lines.isEmpty && utterances.isEmpty {
            LoadingHint(rows: 2, text: "正在找这段原话…")
        } else if !utterances.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(utterances) { u in utteranceRow(u) }
            }
            .padding(16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        } else if lines.isEmpty {
            EmptyHint(symbol: "text.magnifyingglass", title: "没有对应的原话片段",
                      detail: "这件事可能是从别的内容里整理出来的")
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(lines) { seg in lineRow(seg) }
            }
            .padding(16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
    }

    /// 普通事件的旧版内容：摘要、要点、原话（散段整理出来的没有分人结果）
    @ViewBuilder
    private var legacyContent: some View {
        if !current.summary.isEmpty {
            Text(current.summary)
                .font(.system(size: 15.5))
                .foregroundColor(Theme.text2)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !current.points.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("要点")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.dim)
                    .padding(.top, 2)
                ForEach(Array(current.points.enumerated()), id: \.offset) { _, p in
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(.top, 7)
                        Text(p)
                            .font(.system(size: 15))
                            .foregroundColor(Theme.text)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        rawSection
    }

    /// 点关键原话：跳到「原话」页，并从头播放这一场（找不到精确那一段时至少先听到声音）
    private func jumpToQuote(_ q: EventQuote) {
        withAnimation(.easeInOut(duration: 0.18)) { detailTab = 1 }
        guard let target = utterances.first(where: { $0.text.contains(String(q.text.prefix(8))) }) else {
            playAll()
            return
        }
        let segs = app.todaySegments
        if let seg = segs.first(where: { seg in
            let start = seg.startedAt.timeIntervalSince(current.startAt)
            return start <= target.start + 1 && start + seg.duration >= target.start
        }) {
            player.playAll([seg])
        } else {
            playAll()
        }
    }

    // MARK: 顶部信息行

    private var metaRow: some View {
        HStack(spacing: 6) {
            Text(metaText)
                .font(.system(size: 12.5))
                .foregroundColor(Theme.dim)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                toTodo()
            } label: {
                Text("存待办")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.accent)
            }
            .buttonStyle(.plain)
            Button {
                // 每次打开都用最新的 current 重置草稿，取消不会残留上一次的输入
                editItem = EditPayload(title: current.title, summary: current.summary)
            } label: {
                Text("编辑")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var metaText: String {
        var parts: [String] = []
        let day = DayKey.of(current.startAt)
        parts.append(day == DayKey.of(Date()) ? "今天" : day)
        if let end = current.endAt {
            parts.append("\(current.timeText) – \(timeText(end))")
        } else {
            parts.append(current.timeText)
        }
        if !current.scene.isEmpty { parts.append(current.scene) }
        if !current.durationText.isEmpty { parts.append(current.durationText) }
        if let p = current.place, !p.isEmpty { parts.append(p) }
        return parts.joined(separator: " · ")
    }

    private func timeText(_ d: Date) -> String {
        Fmt.hm.string(from: d)
    }

    // MARK: 原话行

    private func lineRow(_ seg: Segment) -> some View {
        let name = seg.speaker.trimmingCharacters(in: .whitespaces).isEmpty ? "未识别" : seg.speaker
        let tint = Theme.personColor(name)
        return HStack(alignment: .top, spacing: 10) {
            Text(avatarText(name))
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundColor(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(tint)
                    Text(seg.timeText)
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundColor(Theme.dim2)
                    Button {
                        SegmentPlayer.shared.toggle(segment: seg)
                    } label: {
                        Image(systemName: player.isPlaying(seg.id) ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.accent)
                            .frame(width: 32, height: 32)
                    .tapTarget(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(player.isPlaying(seg.id) ? "暂停这段" : "播放这段")
                }
                Text(seg.transcript)
                    .font(.system(size: 15.5))
                    .foregroundColor(Theme.text)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 头像文字：实名说话人取首字（以前不论叫什么都显示 ①）
    private func avatarText(_ name: String) -> String {
        if let n = Int(name.filter { $0.isNumber }), n > 0 { return "\(n)" }
        return name.isEmpty ? "·" : String(name.prefix(1))
    }

    private func speakerTint(_ no: Int) -> Color {
        let palette: [Color] = [Theme.accent, Theme.blue, Theme.purple, Theme.ok, Theme.warn, Theme.bad]
        return no > 0 ? palette[(no - 1) % palette.count] : Theme.accent
    }

    /// 每个人说了多久，一眼看出谁主导。点一下能改名，改的是整场。
    private var speakerChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(speakerTotals, id: \.0) { item in
                    Button {
                        renameItem = RenamePayload(label: item.0,
                                                    name: session?.name(item.0) ?? item.0)
                    } label: {
                        HStack(spacing: 5) {
                            Text(avatarText(item.0))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(tint(for: item.0))
                            Text(session?.name(item.0) ?? item.0)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(tint(for: item.0))
                            Text(MemoryEvent.durationLabel(item.1))
                                .font(.system(size: 11.5))
                                .foregroundColor(Theme.dim)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(tint(for: item.0).opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(session?.name(item.0) ?? item.0)，发言 \(MemoryEvent.durationLabel(item.1))，点一下改名")
                }
            }
        }
    }

    /// 按说话人聚合的发言秒数，多的排前面
    private var speakerTotals: [(String, Double)] {
        var map: [String: Double] = [:]
        for u in utterances { map[u.speaker, default: 0] += u.duration }
        return map.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private func tint(for label: String) -> Color {
        Theme.personColor(session?.name(label) ?? label)
    }

    private func utteranceRow(_ u: Utterance) -> some View {
        let display = session?.name(u.speaker) ?? u.speaker
        let color = tint(for: u.speaker)
        return HStack(alignment: .top, spacing: 10) {
            Text(avatarText(display))
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundColor(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(display)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(color)
                    Text(u.timeText)
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundColor(Theme.dim2)
                }
                Text(u.text)
                    .font(.system(size: 15.5))
                    .foregroundColor(Theme.text)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func pill(_ title: String, symbol: String?, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let s = symbol {
                    Image(systemName: s).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(.system(size: 12.5, weight: .medium))
            }
            .foregroundColor(tint)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Theme.accentSoft)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 底部操作

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                app.starEvent(event.id, starred: !current.starred)
                flash(current.starred ? "已取消重点" : "已标为重点")
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: current.starred ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .semibold))
                    Text("重点").font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(current.starred ? .white : Theme.accent)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(current.starred ? Theme.accent : Theme.accentSoft)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button { copyText() } label: {
                Text("复制").font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.text)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Theme.card).clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button { askAbout() } label: {
                Text("问问").font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.text)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Theme.card).clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button { confirmDelete = true } label: {
                Text("删除").font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.bad)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Theme.bad.opacity(0.10)).clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.bg)
    }

    // MARK: 动作实现

    private func loadLines() async {
        // 3000 行查询以前在 onAppear 里同步跑，进详情页必顿一下
        let ev = event
        let result = await Task.detached(priority: .userInitiated) { () -> [Segment] in
            let rows = Store.shared.transcriptRows(day: ev.day, limit: 3000)
            let from = max(1, ev.lineFrom) - 1
            let to = min(rows.count, max(ev.lineTo, ev.lineFrom))
            if from < to {
                return Array(rows[from..<to])
            }
            // 行号对不上（重新整理过）时按时间重叠兜底
            let end = ev.endAt ?? ev.startAt.addingTimeInterval(60)
            return rows.filter { $0.startedAt >= ev.startAt.addingTimeInterval(-1) && $0.startedAt <= end.addingTimeInterval(1) }
        }.value
        lines = result
        let sid = ev.sessionId
        let extra = await Task.detached(priority: .userInitiated) { () -> (ListenSession?, [Utterance]) in
            guard let sid, !sid.isEmpty else { return (nil, []) }
            return (Store.shared.session(id: sid), Store.shared.utterances(sessionId: sid))
        }.value
        session = extra.0
        utterances = extra.1
        loadingLines = false
    }

    private func playAll() {
        guard !lines.isEmpty else { return }
        if player.isPlayingAny {
            player.stop()
        } else {
            player.playAll(lines)
        }
    }

    private func copyText() {
        UIPasteboard.general.string = plainText
        flash("已复制")
    }

    private var plainText: String {
        var out = "\(metaText)\n\(current.title)\n"
        if !current.summary.isEmpty { out += "\(current.summary)\n" }
        if !current.points.isEmpty {
            out += "要点\n" + current.points.map { "· \($0)" }.joined(separator: "\n") + "\n"
        }
        if !utterances.isEmpty {
            out += "原话\n"
            for u in utterances {
                out += "\(session?.name(u.speaker) ?? u.speaker) \(u.timeText) \(u.text)\n"
            }
        } else if !lines.isEmpty {
            out += "原话\n"
            for s in lines {
                out += "\(s.speaker.isEmpty ? "说话人" : s.speaker) \(s.timeText) \(s.transcript)\n"
            }
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
            flash("导出失败，请重试")
        }
    }

    private func toTodo() {
        let content = current.points.first ?? current.title
        app.addItems([(content: content, category: "待办", due: nil)])
        flash("已存为待办")
    }

    private func askAbout() {
        NotificationCenter.default.post(name: .taoshengAskPrefill, object: nil,
                                        userInfo: ["q": "关于「\(current.title)」，帮我回顾一下要点和待办"])
        dismiss()
    }

    private func saveEdit() {
        let t = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Store.shared.updateEventTitle(id: event.id, title: t,
                                      summary: draftSummary.trimmingCharacters(in: .whitespacesAndNewlines))
        app.refresh()
        flash("已保存")
    }

    private func flash(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { toast = nil }
        }
    }
}

extension Notification.Name {
    /// 从别处点「问问」时，把问题预填进问问页
    static let taoshengAskPrefill = Notification.Name("taoshengAskPrefill")
}

/// 编辑弹层的初始值。跟着 item 一起传进 sheet，避免读到上一次的草稿。
private struct EditPayload: Identifiable {
    let id = UUID()
    var title: String
    var summary: String
}

/// 改说话人名时的原始标签与当前名字
private struct RenamePayload: Identifiable {
    let id = UUID()
    var label: String
    var name: String
}
