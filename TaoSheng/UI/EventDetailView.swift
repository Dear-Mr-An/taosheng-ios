import SwiftUI
import UIKit

/// 一件事的详情。从时间线点进来时以「抽纸」的方式从底部抽出，
/// 看完往下滑即可收起，不打断时间线本身的位置。
struct EventDetailView: View {
    let event: MemoryEvent
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var lines: [Segment] = []
    @State private var showEdit = false
    @State private var draftTitle = ""
    @State private var draftSummary = ""
    @State private var toast: String?
    @State private var confirmDelete = false

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
                                    Circle().fill(Theme.accent)
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 7)
                                    Text(p)
                                        .font(.system(size: 15))
                                        .foregroundColor(Theme.text)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Text("原话")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.dim)
                        Spacer(minLength: 0)
                        pill("播放这件事", symbol: "play.fill", tint: Theme.accent) { playAll() }
                        pill("导出", symbol: nil, tint: Theme.accent) { exportText() }
                    }
                    .padding(.top, 4)

                    if lines.isEmpty {
                        EmptyHint(text: "这件事没有对应的原话片段")
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(lines) { seg in
                                lineRow(seg)
                            }
                        }
                        .padding(16)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
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
            draftTitle = event.title
            draftSummary = event.summary
        }
        .task { await loadLines() }
        .alert("编辑这件事", isPresented: $showEdit) {
            TextField("标题", text: $draftTitle)
            TextField("摘要", text: $draftSummary)
            Button("保存") { saveEdit() }
            Button("取消", role: .cancel) {}
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
                showEdit = true
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
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // MARK: 原话行

    private func lineRow(_ seg: Segment) -> some View {
        let no = speakerNo(seg.speaker)
        let name = seg.speaker.isEmpty ? "说话人\(no)" : seg.speaker
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
                        Image(systemName: SegmentPlayer.shared.isPlaying(seg.id) ? "pause.fill" : "play.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                Text(seg.transcript)
                    .font(.system(size: 15.5))
                    .foregroundColor(Theme.text)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func speakerNo(_ speaker: String) -> Int {
        let digits = speaker.filter { $0.isNumber }
        if let n = Int(digits), n > 0 { return n }
        return 1
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
    }

    private func playAll() {
        guard let first = lines.first else { return }
        SegmentPlayer.shared.toggle(segment: first)
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
        if !lines.isEmpty {
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
