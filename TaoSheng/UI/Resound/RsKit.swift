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

/// 卡片上的小按钮：主要操作实心；次要操作白底橙字（OverviewCard.kt CardPill / SmallPill）
struct RsPillButton: View {
    let text: String
    var filled: Bool = false
    var danger: Bool = false
    var minHeight: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(danger ? Color.white : (filled ? Rs.accent : Rs.accent))
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(danger ? Rs.critical : (filled ? Rs.accent : Rs.card))
                )
        }
        .buttonStyle(RsSpringButtonStyle())
        .frame(minHeight: minHeight)
    }
}

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
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
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
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 9)
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

enum RsThemeMode { case system, light, dark }

struct RsThemeModePill: View {
    @Binding var mode: RsThemeMode

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                mode = mode == .system ? .light : (mode == .light ? .dark : .system)
            }
        } label: {
            ZStack {
                Circle().fill(Rs.accentSoft)
                icon.foregroundStyle(Rs.accent)
                    .frame(width: 20, height: 20)
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(RsSpringButtonStyle())
    }

    @ViewBuilder private var icon: some View {
        switch mode {
        case .light: sun
        case .dark: moon
        case .system: half
        }
    }

    private var sun: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.42, y: c.y - r * 0.42, width: r * 0.84, height: r * 0.84)),
                     with: .color(Rs.accent))
            for i in 0..<8 {
                let a = Double(i) * 45 * .pi / 180
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * r * 0.66, y: c.y + sin(a) * r * 0.66))
                p.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.95, y: c.y + sin(a) * r * 0.95))
                ctx.stroke(p, with: .color(Rs.accent), style: StrokeStyle(lineWidth: r * 0.16, lineCap: .round))
            }
        }
    }

    private var moon: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let full = Path(ellipseIn: CGRect(x: c.x - r * 0.85, y: c.y - r * 0.85, width: r * 1.7, height: r * 1.7))
            ctx.fill(full, with: .color(Rs.accent))
            let bite = Path(ellipseIn: CGRect(x: c.x + r * 0.42 - r * 0.72, y: c.y - r * 0.32 - r * 0.72,
                                              width: r * 1.44, height: r * 1.44))
            ctx.blendMode = .destinationOut
            ctx.fill(bite, with: .color(.black))
        }
    }

    private var half: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let ring = Path(ellipseIn: CGRect(x: c.x - r * 0.78, y: c.y - r * 0.78, width: r * 1.56, height: r * 1.56))
            ctx.stroke(ring, with: .color(Rs.accent), lineWidth: r * 0.16)
            var half = Path()
            half.addArc(center: c, radius: r * 0.78, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            half.closeSubpath()
            ctx.fill(half, with: .color(Rs.accent))
        }
    }
}

// MARK: - 声波

/// 实时声波：44 根柱子按 60ms 滚动，最右边是此刻（Components.kt BreathingWave）
struct RsBreathingWave: View {
    var level: Double
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
            guard recording else {
                // 说完后再滚约 2 秒让柱子退出画面
                history[head] = 0
                head = (head + 1) % bars
                return
            }
            history[head] = loudness(level)
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

// MARK: - 底部抽屉

/// 原版 RsSheet：顶部圆角、抓手、大标题 + 一句说明，内容自己滚
struct RsSheetBody<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Rs.track)
                .frame(width: 54, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Rs.text)
                    if let s = subtitle, !s.isEmpty {
                        Text(s)
                            .font(.system(size: 15))
                            .foregroundStyle(Rs.text2)
                    }
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .background(Rs.card)
        .presentationDragIndicator(.hidden)
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
