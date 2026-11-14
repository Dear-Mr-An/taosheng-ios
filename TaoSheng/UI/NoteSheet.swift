import SwiftUI

/// 速记的底部抽屉：从记忆页的卡片区点进来，铺满全屏高度看一份完整的会。
///
/// 排布照原版安卓的 `SkillCardSheet`：标题 + 灰色副标题、两个浅灰按钮、摘要框、分段要点、
/// 参与的人（点一下可以改名）、关键原话（点一下跳回原话）、底部重新生成 / 删除。
struct NoteSheet: View {
    let event: MemoryEvent
    let people: [(label: String, name: String, seconds: Double)]
    let onRename: (String, String) -> Void
    let onQuote: (EventQuote) -> Void
    let onRegenerate: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var renameItem: RenameTarget?
    @State private var confirmDelete = false
    @State private var copied = false

    private var tint: Color { event.scene == "培训" ? Theme.purple : Theme.accent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sp4) {
                header
                actions
                summaryBox
                sections
                if !people.isEmpty { peopleRow }
                if !event.quotes.isEmpty { quotesBlock }
                footer
            }
            .padding(.horizontal, Theme.sp4)
            .padding(.top, Theme.sp2)
            .padding(.bottom, Theme.sp6)
        }
        .background(Theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: $renameItem) { item in
            TextInputSheet(title: "这是谁",
                           fields: [TextInputField(label: "名字", placeholder: "例如 老王", text: item.name)],
                           confirmTitle: "保存",
                           message: "改名作用于这一整场，纪要和原话都会跟着变。") { values in
                let name = values.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty else { return }
                onRename(item.label, name)
            }
        }
        .confirmationDialog("删除这张速记？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { onDelete(); dismiss() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这一场的原话和录音不会被删，只是不再有这张速记。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: event.scene == "培训" ? "graduationcap.fill" : "person.2.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundColor(tint)
                Text(event.noteTitle)
                    .font(.system(size: Theme.fsCaption, weight: .medium))
                    .foregroundColor(tint)
                Spacer(minLength: 0)
                Text(event.durationText)
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundColor(Theme.dim)
            }
            Text(event.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: Theme.fsSmall))
                .foregroundColor(Theme.dim)
        }
    }

    private var subtitle: String {
        var parts = [Fmt.monthDay.string(from: event.startAt), event.timeRangeText]
        if !event.people.isEmpty { parts.append(event.people.joined(separator: "、")) }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: Theme.sp2) {
            Button {
                UIPasteboard.general.string = NoteRules.plainText(
                    mode: event.scene == "培训" ? "training" : "meeting",
                    title: event.title, timeRange: event.timeRangeText,
                    summary: event.summary, points: event.points,
                    people: event.people, quotes: event.quotes)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
            } label: {
                Text(copied ? "已复制" : "复制全部内容")
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.text2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(Theme.cardSoft))
            }
            .buttonStyle(.plain)

            ShareLink(item: NoteRules.plainText(
                mode: event.scene == "培训" ? "training" : "meeting",
                title: event.title, timeRange: event.timeRangeText,
                summary: event.summary, points: event.points,
                people: event.people, quotes: event.quotes)) {
                Text("选择部分内容")
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.text2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(Theme.cardSoft))
            }
            .buttonStyle(.plain)
        }
    }

    private var summaryBox: some View {
        Text(NoteRules.tidy(event.summary))
            .font(.system(size: Theme.fsBody))
            .foregroundColor(Theme.text)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.sp3)
            .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(Theme.cardSoft))
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: Theme.sp3) {
            ForEach(Array(event.noteSections.enumerated()), id: \.offset) { _, section in
                if !section.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.system(size: Theme.fsSmall, weight: .semibold))
                            .foregroundColor(section.title.contains("结论") || section.title == "核心要点" ? Theme.text : Theme.text2)
                        ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 7) {
                                Circle().fill(tint.opacity(0.55)).frame(width: 5, height: 5).padding(.top, 6)
                                Text(line)
                                    .font(.system(size: Theme.fsBody))
                                    .foregroundColor(Theme.text)
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var peopleRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("参与的人").font(.system(size: Theme.fsCaption, weight: .medium)).foregroundColor(Theme.dim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(people, id: \.label) { p in
                        Button {
                            renameItem = RenameTarget(label: p.label, name: p.name)
                        } label: {
                            HStack(spacing: 5) {
                                Text(String(p.name.prefix(1)))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Theme.personColor(p.name))
                                    .frame(width: 17, height: 17)
                                    .background(Circle().fill(Theme.personColor(p.name).opacity(0.16)))
                                Text(p.name)
                                    .font(.system(size: Theme.fsSmall))
                                    .foregroundColor(Theme.text)
                                Text(MemoryEvent.durationLabel(p.seconds))
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundColor(Theme.dim2)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.cardSoft))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var quotesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关键原话").font(.system(size: Theme.fsCaption, weight: .medium)).foregroundColor(Theme.dim)
            ForEach(Array(event.quotes.enumerated()), id: \.offset) { _, q in
                Button { onQuote(q) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Theme.blue.opacity(0.45))
                            .frame(width: 3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(q.speaker) · \(q.time)")
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

    private var footer: some View {
        HStack(spacing: Theme.sp2) {
            Button(action: onRegenerate) {
                Text("重新生成")
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(Theme.accentSoft))
            }
            .buttonStyle(.plain)
            Button { confirmDelete = true } label: {
                Text("删除这张卡")
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.bad)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(Theme.bad.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RenameTarget: Identifiable {
    let id = UUID()
    var label: String
    var name: String
}
