import SwiftUI

/// 原版安卓涛声（app.resound 0.4.0）的设计系统，逐项对照 ui/theme/Theme.kt 与 ui/AppShell.kt。
/// 颜色、字号、圆角、间距都按原版取值，iOS 侧只做单位换算（dp → pt）。
enum Rs {
    // MARK: - 颜色（LightRs）
    static let bg = Color(hex: "F4F2EF")
    static let card = Color.white
    static let cardPressed = Color(hex: "F7F4F0")
    static let text = Color(hex: "1D1B19")
    static let text2 = Color(hex: "7D7770")
    static let text3 = Color(hex: "8A847C")
    static let separator = Color(hex: "ECE8E3")
    static let accent = Color(hex: "F07B2E")
    static let accentSoft = Color(hex: "FDEBDD")
    static let good = Color(hex: "34A853")
    static let warning = Color(hex: "E6A23C")
    static let critical = Color(hex: "E5484D")
    static let fill = Color(hex: "F4F2EF")
    static let track = Color(hex: "ECE8E3")
    static let shadow = Color(hex: "583A1C").opacity(0.08)
    static let hairline = Color.black.opacity(0.04)

    // MARK: - 字号（RsType）
    static let largeTitle = Font.system(size: 32, weight: .bold)
    static let title = Font.system(size: 20, weight: .semibold)
    static let headline = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 15, weight: .regular)
    static let subhead = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 12, weight: .regular)
    static let section = Font.system(size: 13, weight: .medium)
    static let number = Font.system(size: 26, weight: .semibold).monospacedDigit()

    // MARK: - 卡片圆角与内容宽度
    static let cardRadius: CGFloat = 22
    static let heroRadius: CGFloat = 26
    static let maxContent: CGFloat = 640
    static let shellBottom: CGFloat = 76

    /// 分类颜色，对照 TodayScreen.kt categoryColor()
    static func categoryColor(_ category: String) -> Color {
        switch category {
        case "待办": return accent
        case "约定": return Color(hex: "2E9C93")
        case "备忘": return Color(hex: "4F86C6")
        case "灵感": return Color(hex: "7E68C2")
        case "关键信息": return Color(hex: "CC5E82")
        case "决定": return good
        default: return Color(hex: "A9803C")
        }
    }
}

// MARK: - 卡片

/// 白色圆角卡片，淡阴影分层（Components.kt RsCard）
struct RsCard<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
    var fill: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous)
                    .fill(fill ?? Rs.card)
                    .shadow(color: Rs.shadow, radius: 10, x: 0, y: 4)
            )
    }
}

/// 一组带标题的分节（Components.kt Section）
struct RsSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Rs.section)
                    .foregroundStyle(Rs.text2)
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 10)
            content()
        }
    }
}

extension RsSection where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - 胶囊

/// 首页主卡上的胶囊：实心为白底橙字（ink.primary = 白）
struct RsHeroPill: View {
    let text: String
    var filled: Bool = false
    var danger: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(danger ? Color.white : (filled ? Color(hex: "D2511F") : Color.white))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(danger ? Rs.critical : (filled ? Color.white : Color.white.opacity(0.2)))
                )
        }
        .buttonStyle(RsSpringButtonStyle())
    }
}

/// 分区里的小胶囊（待办页顶部筛选、卡片按钮）
struct RsChip: View {
    let text: String
    var count: Int? = nil
    var on: Bool = false
    var dot: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let d = dot {
                    Circle().fill(on ? Color.white.opacity(0.8) : d).frame(width: 7, height: 7)
                }
                Text(text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(on ? Color.white : Rs.text2)
                if let n = count {
                    Text("\(n)")
                        .font(Rs.caption)
                        .foregroundStyle(on ? Color.white.opacity(0.85) : Rs.text3)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .background(Capsule(style: .continuous).fill(on ? Rs.accent : Rs.card))
        }
        .buttonStyle(RsSpringButtonStyle())
    }
}

/// 分类小标签（TodayScreen.kt CategoryChip）
struct RsCategoryChip: View {
    let category: String
    var kind: String? = nil

    var body: some View {
        let color = Rs.categoryColor(category)
        Text(kind != nil && category == "待办" ? "待办 · \(kind!)" : category)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(color.opacity(0.13)))
    }
}

/// 选中态描边胶囊（TopicUi.kt ChoicePill）
struct RsChoicePill: View {
    let text: String
    var on: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? Rs.text : Rs.text2)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(on ? Rs.accentSoft : Rs.fill)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(on ? Rs.accent : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(RsSpringButtonStyle())
    }
}

/// 大号主按钮（verify ActionButton）
struct RsActionButton: View {
    let title: String
    var kind: Kind = .primary
    var enabled: Bool = true
    let action: () -> Void

    enum Kind { case primary, plain, danger }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(kind == .primary ? Color.white : (kind == .danger ? Color.white : Rs.text2))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(kind == .primary ? Rs.accent : (kind == .danger ? Rs.critical : Rs.fill))
                )
        }
        .buttonStyle(RsSpringButtonStyle())
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}

// MARK: - 日期切换

/// 今天 / 昨天 / 前天（VerifyScreen.kt DaySwitcher）
struct RsDaySwitcher: View {
    @Binding var selected: Int
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(["今天", "昨天", "前天"].enumerated()), id: \.offset) { i, label in
                let on = i == selected
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selected = i }
                } label: {
                    Text(label)
                        .font(compact ? Rs.caption : Rs.subhead)
                        .foregroundStyle(on ? Rs.text : Rs.text2)
                        .padding(.horizontal, compact ? 12 : 18)
                        .padding(.vertical, compact ? 4 : 7)
                        .background(Capsule(style: .continuous).fill(on ? Rs.card : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(Rs.track))
    }
}

// MARK: - 图标（原版是 Canvas 画的，不引入系统图标以免画风不一致）

struct RsMagnifier: View {
    var ink: Color = Rs.accent
    var body: some View {
        Canvas { ctx, size in
            let stroke = size.width * 0.13
            let r = size.width * 0.33
            let c = CGPoint(x: r + stroke, y: r + stroke)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(ink), lineWidth: stroke)
            var p = Path()
            let d = r * 0.72
            p.move(to: CGPoint(x: c.x + d, y: c.y + d))
            p.addLine(to: CGPoint(x: size.width - stroke / 2, y: size.height - stroke / 2))
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
        }
    }
}

// MARK: - 声波

/// 实时声波：44 根柱子按 60ms 滚动，最右边是此刻（Components.kt BreathingWave）
struct RsBreathingWave: View {
    /// 读取此刻电平。必须是闭包：计时器抓住的是创建那一刻的视图副本，
    /// 传数值进来的话柱子会一直停在开始录音时的那个高度。
    var level: () -> Double = { CaptureEngine.shared.level }
    var active: Bool
    var recording: Bool
    var tint: Color = .white

    @State private var history = [Double](repeating: 0, count: 44)
    @State private var head = 0
    @State private var ticker: Timer?

    private var bars: Int { history.count }
    private var color: Color {
        if recording { return tint }
        if active { return tint.opacity(0.75) }
        return tint.opacity(0.5)
    }

    var body: some View {
        Canvas { ctx, size in
            let gap = size.width / CGFloat(bars - 1)
            let w = gap * 0.46
            for i in 0..<bars {
                let v = history[(head + i) % bars]
                let x = CGFloat(i) * gap
                let edge = min(max(min(x, size.width - x) / (gap * 4), 0.15), 1)
                let h = max(size.height * (0.06 + 0.94 * v), w)
                let rect = CGRect(x: x - w / 2, y: (size.height - h) / 2, width: w, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: w / 2),
                         with: .color(color.opacity(0.35 + 0.65 * edge)))
            }
        }
        .onAppear { start() }
        .onDisappear { ticker?.invalidate(); ticker = nil }
        .onChange(of: recording) { _ in start() }
    }

    private func start() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.06, repeats: true) { _ in
            if recording {
                history[head] = loudness(level())
                head = (head + 1) % bars
                return
            }
            // 说完后再滚约 2 秒让柱子退出画面；全落回 0 以后不再改状态，空闲时就不重绘
            guard history.contains(where: { $0 > 0 }) else { return }
            history[head] = 0
            head = (head + 1) % bars
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func loudness(_ l: Double) -> Double {
        guard l > 0 else { return 0 }
        let db = (20 * log10(l) + 60) / 60
        return pow(min(max(db, 0), 1), 1.4)
    }
}

/// 实心选择胶囊（ListenSheet.kt Choice：选中橙底白字，未选浅底灰字）
struct RsSolidPill: View {
    let text: String
    var on: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(on ? Color.white : Rs.text2)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(on ? Rs.accent : Rs.fill)
                )
        }
        .buttonStyle(RsSpringButtonStyle())
    }
}

/// 抽屉底部的次要入口（TopicUi.kt SideEntry：没有图标，只有标题 + 说明 + ›）
struct RsSideEntry: View {
    let title: String
    let note: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Rs.text)
                        .lineLimit(1)
                    Text(note)
                        .font(Rs.caption)
                        .foregroundStyle(Rs.text3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("›")
                    .font(.system(size: 16))
                    .foregroundStyle(Rs.text3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Rs.fill)
            )
        }
        .buttonStyle(RsSpringButtonStyle())
    }
}

// MARK: - 底部抽屉

/// 抽屉里的内容区（原版 RsSheet：标题 20/26 SemiBold、副标题 13 灰、段间 12、内边距 20/28）
struct RsSheetBody<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Rs.text)
            if let s = subtitle, !s.isEmpty {
                Text(s)
                    .font(Rs.subhead)
                    .foregroundStyle(Rs.text2)
            }
            Color.clear.frame(height: 2)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }
}
/// 小号灰色标签（TopicUi.kt Label / ListenSheet.kt Label）
struct RsLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Rs.text3)
    }
}

// MARK: - 动效

/// 按下缩到 0.96（Components.kt springClick）
struct RsSpringButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// 原版状态卡里那条点线（安静时暗，说话时亮）
struct RsDotLine: View {
    var active: Bool
    var body: some View {
        GeometryReader { geo in
            let n = max(12, Int(geo.size.width / 9))
            HStack(spacing: 6) {
                ForEach(0..<n, id: \.self) { _ in
                    Circle()
                        .fill(Rs.accent.opacity(active ? 0.85 : 0.35))
                        .frame(width: 3, height: 3)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
        }
    }
}

/// 时间线一行左滑标重点（ItemsScreens.kt 里 star 手势）：右滑出 84 宽的动作区
struct RsStarSwipe<Content: View>: View {
    var starred: Bool = false
    let onStar: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var dx: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { dx = 0 }
                onStar()
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: starred ? "star.slash" : "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(starred ? "取消重点" : "标重点")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Rs.accent)
                .frame(width: 84)
                .frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .background(Rs.accentSoft)

            content()
                .background(Rs.card)
                .offset(x: dx)
                .gesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { g in
                            if g.translation.width < 0 { dx = max(-84, g.translation.width) }
                        }
                        .onEnded { g in
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                dx = g.translation.width < -44 ? -84 : 0
                            }
                        }
                )
        }
        .clipped()
    }
}