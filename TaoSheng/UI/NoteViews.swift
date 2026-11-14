import SwiftUI

/// 速记相关的一组小控件：右侧小时时间轴、时间线上的速记行、今天页的「刚结束」卡、底部抽屉。
///
/// 这些界面是照原版安卓涛声（0xCoach/TaoSheng，MIT）的排布做的：右侧窄条列小时、点一下跳到
/// 那个小时的第一件事；速记在时间线上单独一种样式，不和普通事件混在一起。

// MARK: - 右侧小时时间轴

/// 一条时间轴上的小时槽
struct RailEntry: Identifiable, Hashable {
    let id: String
    let hour: Int
    var title: String = ""
}

struct HourRail: View {
    let slots: [RailSlot]
    let autoHeight: CGFloat
    /// 当前滚动到顶部的那一条的 id，用来画橙色气泡
    let activeKey: String?
    let onJump: (String) -> Void

    @State private var dragging = false
    @State private var dragY: CGFloat?

    private var heights: [CGFloat] {
        RailRules.heights(counts: slots.map { $0.count }, total: Double(slots.reduce(0) { $0 + $1.count }))
            .map { CGFloat($0) }
    }
    private var tops: [CGFloat] { RailRules.tops(heights.map { Double($0) }).map { CGFloat($0) } }

    private var activeIndex: Int? {
        guard let activeKey else { return nil }
        return slots.firstIndex { $0.firstKey == activeKey }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(slots.enumerated()), id: \.element.hour) { i, slot in
                Text("\(slot.hour)")
                    .font(.system(size: 10.5, weight: i == activeIndex ? .semibold : .regular, design: .rounded))
                    .foregroundColor(i == activeIndex ? .white : Theme.dim)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle().fill(i == activeIndex ? Theme.accent : Color.clear)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: heights.indices.contains(i) ? max(heights[i], 18) : 18)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 30)
        .frame(height: autoHeight, alignment: .top)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Theme.card.opacity(dragging ? 0.96 : 0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Theme.line.opacity(0.7), lineWidth: 0.6)
        )
        .overlay(alignment: .topLeading) { bubble }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    dragging = true
                    dragY = g.location.y
                    jumpIfNeeded(at: g.location.y)
                }
                .onEnded { _ in
                    dragging = false
                    dragY = nil
                    UISelectionFeedbackGenerator().selectionChanged()
                }
        )
        .accessibilityLabel("小时时间轴")
    }

    @ViewBuilder
    private var bubble: some View {
        if dragging, let y = dragY, let i = index(at: y) {
            Text("\(slots[i].hour):00")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.accent))
                .offset(x: -46, y: max(0, y - 10))
                .allowsHitTesting(false)
        }
    }

    private func index(at y: CGFloat) -> Int? {
        guard !slots.isEmpty else { return nil }
        let ys = tops
        guard ys.count == slots.count else { return nil }
        var best = 0
        for (i, top) in ys.enumerated() where y >= top - 6 {
            best = i
        }
        return best
    }

    private func jumpIfNeeded(at y: CGFloat) {
        guard let i = index(at: y), slots.indices.contains(i) else { return }
        onJump(slots[i].firstKey)
    }
}

/// 让 ScrollView 里的行把「自己在滚动容器里的纵坐标」报上来。
/// 用于算当前顶部是哪一个小时、以及时间轴的橙色气泡停在哪。
struct RailOffsetKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { a, _ in a }
    }
}

extension View {
    /// 标记这一行要参与时间轴定位
    func railTrack(_ key: String, space: String = "railScroll") -> some View {
        background(
            GeometryReader { g in
                Color.clear.preference(key: RailOffsetKey.self,
                                       value: [key: g.frame(in: .named(space)).minY])
            }
        )
    }
}

// MARK: - 时间线上的速记行

/// 时间线上的一场会/一场培训：左边模式图标 + 起止时间，右边标题 + 两行结论 + 标签。
struct NoteTimelineLine: View {
    let event: MemoryEvent
    let itemCount: Int
    let onTap: () -> Void

    private var symbol: String { event.scene == "培训" ? "graduationcap.fill" : "person.2.wave.2.fill" }
    private var tint: Color { event.scene == "培训" ? Theme.purple : Theme.accent }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 5) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(tint)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.13)))
                    Text(event.timeText)
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundColor(Theme.dim)
                }
                .frame(width: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(event.title)
                            .font(.system(size: Theme.fsBody, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                        Pill(text: event.noteTag, color: tint)
                        Spacer(minLength: 0)
                    }
                    Text(event.conclusion)
                        .font(.system(size: Theme.fsSmall))
                        .foregroundColor(Theme.text2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        if itemCount > 0 {
                            Text("\(itemCount) 条待办")
                                .font(.system(size: 10.5))
                                .foregroundColor(Theme.dim)
                        }
                        if event.starred {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundColor(Theme.warn)
                        }
                        Spacer(minLength: 0)
                        Text(event.durationText)
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundColor(Theme.dim2)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 今天页的「刚结束」

/// 刚结束的这一场：标题、时长、几个人、结论第一句、「看速记 ›」。
struct JustEndedCard: View {
    let event: MemoryEvent
    let speakerCount: Int
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.ok)
                    Text("刚结束 · \(event.noteTitle)")
                        .font(.system(size: Theme.fsCaption, weight: .medium))
                        .foregroundColor(Theme.text2)
                    Spacer(minLength: 0)
                    Text(event.timeText)
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundColor(Theme.dim)
                }
                Text(event.title)
                    .font(.system(size: Theme.fsTitle, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(event.conclusion)
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.text2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 10) {
                    Text(event.durationText)
                    if speakerCount > 0 { Text("· \(speakerCount) 位说话人") }
                    Spacer(minLength: 0)
                    Text("看速记 ›").foregroundColor(Theme.accent)
                }
                .font(.system(size: 11))
                .foregroundColor(Theme.dim)
            }
            .padding(Theme.sp3 + 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(Theme.line.opacity(0.8), lineWidth: 0.6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("刚结束的\(event.noteTitle)：\(event.title)")
    }
}

// MARK: - 发言时长条

/// 事件详情「发言」页：每人一条，按总时长倒序。
struct SpeakerBars: View {
    let rows: [(label: String, name: String, seconds: Double)]
    let onRename: (String, String) -> Void

    private var maxSeconds: Double { max(rows.map(\.seconds).max() ?? 1, 1) }

    var body: some View {
        VStack(spacing: Theme.sp2 + 2) {
            ForEach(rows, id: \.label) { row in
                Button {
                    onRename(row.label, row.name)
                } label: {
                    HStack(spacing: 10) {
                        Text(String(row.name.prefix(1)))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.personColor(row.name))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Theme.personColor(row.name).opacity(0.14)))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.name)
                                    .font(.system(size: Theme.fsSmall, weight: .medium))
                                    .foregroundColor(Theme.text)
                                Spacer(minLength: 0)
                                Text(MemoryEvent.durationLabel(row.seconds))
                                    .font(.system(size: 10.5, design: .rounded))
                                    .foregroundColor(Theme.dim)
                            }
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.lineSoft)
                                    Capsule()
                                        .fill(Theme.personColor(row.name).opacity(0.75))
                                        .frame(width: max(4, g.size.width * row.seconds / maxSeconds))
                                }
                            }
                            .frame(height: 7)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 左滑露出「完成 / 接受」，右滑直接进删除确认（原版待办页的手势）
struct SwipeRow<Content: View>: View {
    let onDone: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0

    private let actionWidth: CGFloat = 84

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { offset = 0 }
                    onDone()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                        Text("完成").font(.system(size: 10))
                    }
                    .foregroundColor(.white)
                    .frame(width: actionWidth)
                    .frame(maxHeight: .infinity)
                    .background(Theme.ok)
                }
                .buttonStyle(.plain)
                .opacity(offset < -8 ? 1 : 0)
            }

            content
                .background(Theme.card)
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { v in
                            offset = max(-actionWidth, min(120, v.translation.width))
                        }
                        .onEnded { v in
                            if v.translation.width > 72 {
                                offset = 0
                                onDelete()
                            } else if v.translation.width < -44 {
                                withAnimation(.easeOut(duration: 0.16)) { offset = -actionWidth }
                            } else {
                                withAnimation(.easeOut(duration: 0.16)) { offset = 0 }
                            }
                        }
                )
        }
        .clipped()
    }
}
