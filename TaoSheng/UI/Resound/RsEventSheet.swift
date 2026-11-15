import SwiftUI
import UIKit

/// 事件详情（照原版 Sheets.kt / EventSheet 的结构）：
/// 顶部一行时间 · 场景 · 时长 + 存待办 / 编辑；标题；摘要；原话（播放这件事 / 导出）；
/// 分人原话卡片；重点 / 复制 / 问问 / 删除；最后一条「设为专题」。
struct RsEventSheet: View {
    let event: MemoryEvent
    var onClose: () -> Void = {}
    @EnvironmentObject private var app: AppState
    private func dismiss() { onClose() }

    @State private var lines: [Segment] = []
    @State private var utterances: [Utterance] = []
    @State private var loaded = false

    private var current: MemoryEvent {
        app.todayEvents.first(where: { $0.id == event.id })
            ?? app.dayEvents.first(where: { $0.id == event.id })
            ?? event
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerRow
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
                transcriptBlock
                actionRow
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Text("设为专题（可连带前后几件事合成一件）")
                            .font(.system(size: 13, weight: .medium))
                        Text("›").font(.system(size: 13))
                    }
                    .foregroundStyle(Rs.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
        .task { await load() }
    }

    // MARK: 顶部

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(metaLine)
                .font(.system(size: 13))
                .foregroundStyle(Rs.text3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Button {
                app.addItems([(content: current.title, category: "待办", due: nil)])
            } label: {
                Text("存待办")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Rs.accent)
            }
            .buttonStyle(.plain)
            Button {
                UIPasteboard.general.string = current.title + "\n" + current.summary
            } label: {
                Text("编辑")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Rs.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var metaLine: String {
        var parts: [String] = ["今天"]
        let from = current.timeText
        let to = current.endAt.map { Fmt.hm.string(from: $0) } ?? from
        parts.append(from + " – " + to)
        if !current.scene.isEmpty { parts.append(current.scene) }
        let secs = Int((current.endAt ?? current.startAt).timeIntervalSince(current.startAt))
        parts.append(secs < 60 ? "不到 1 分钟" : "\(max(1, secs / 60)) 分钟")
        return parts.joined(separator: " · ")
    }

    // MARK: 原话

    private var transcriptBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("原话")
                    .font(.system(size: 13))
                    .foregroundStyle(Rs.text3)
                Spacer(minLength: 0)
                compactPill("▶ 播放这件事") { playAll() }
                compactPill("导出") {
                    UIPasteboard.general.string = lines.map { $0.transcript }.joined(separator: "\n")
                }
            }
            if rows.isEmpty {
                Text("这段没有可用的原话。")
                    .font(.system(size: 13))
                    .foregroundStyle(Rs.text3)
            } else {
                RsCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                            HStack(alignment: .top, spacing: 8) {
                                ZStack {
                                    Circle().fill(Rs.accentSoft).frame(width: 24, height: 24)
                                    Text("\(i + 1)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Rs.accent)
                                }
                                .padding(.top, 1)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(row.who)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Rs.accent)
                                        Text(row.time)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Rs.text3)
                                        Button {
                                            playRow(i)
                                        } label: {
                                            Text("▶").font(.system(size: 12))
                                                .foregroundStyle(Rs.accent)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    Text(row.text)
                                        .font(.system(size: 15))
                                        .lineSpacing(4)
                                        .foregroundStyle(Rs.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private struct Row { let who: String; let time: String; let text: String }

    private var rows: [Row] {
        if !utterances.isEmpty {
            return utterances.map { u in
                Row(who: u.speaker.isEmpty ? "说话人 1" : u.speaker,
                    time: u.timeText,
                    text: u.text)
            }
        }
        return lines.filter { !$0.transcript.isEmpty }.map { s in
            Row(who: s.speaker.isEmpty ? "说话人 1" : "说话人 \(s.speaker)",
                time: Fmt.hm.string(from: s.startedAt),
                text: s.transcript)
        }
    }

    private func playAll() {
        guard !lines.isEmpty else { return }
        SegmentPlayer.shared.playAll(lines)
    }

    private func playRow(_ index: Int) {
        guard index < lines.count else { return }
        SegmentPlayer.shared.toggle(segment: lines[index])
    }

    // MARK: 操作

    private var actionRow: some View {
        HStack(spacing: 10) {
            pill(current.starred ? "★ 重点" : "☆ 重点", filled: current.starred) {
                app.starEvent(current.id, starred: !current.starred)
            }
            pill("复制", filled: false) {
                UIPasteboard.general.string = current.title + "\n" + current.summary
            }
            pill("问问", filled: false) { dismiss() }
            pill("删除", filled: false, danger: true) {
                app.deleteEvent(current.id)
                dismiss()
            }
        }
        .padding(.top, 6)
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

    private func pill(_ text: String, filled: Bool, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(danger ? Rs.critical : (filled ? Rs.accent : Rs.text))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    Capsule(style: .continuous)
                        .fill(danger ? Rs.critical.opacity(0.10) : (filled ? Rs.accentSoft : Rs.card))
                )
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        guard !loaded else { return }
        loaded = true
        let ev = current
        let segs = Store.shared.segments(day: ev.day, limit: 400)
        lines = segs
        if let sid = ev.sessionId, let s = Store.shared.session(id: sid) {
            utterances = Store.shared.utterances(sessionId: s.id)
        }
    }
}
