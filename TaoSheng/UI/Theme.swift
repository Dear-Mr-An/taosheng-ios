import SwiftUI
import UIKit

/// 暖调：米白画布 + 白卡 + 琥珀橙强调；深色下自动换成炭黑底。
enum Theme {
    /// 浅色 / 深色成对定义，跟随系统外观
    private static func dyn(_ l: (Double, Double, Double), _ d: (Double, Double, Double)) -> Color {
        Color(UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? d : l
            return UIColor(red: CGFloat(c.0), green: CGFloat(c.1), blue: CGFloat(c.2), alpha: 1)
        })
    }

    static let bg = dyn((0.965, 0.949, 0.925), (0.078, 0.067, 0.059))        // #F6F2EC / #14110F
    static let bgDeep = dyn((0.945, 0.925, 0.898), (0.106, 0.090, 0.078))    // #F1ECE5 / #1B1714
    static let card = dyn((1.0, 1.0, 1.0), (0.118, 0.102, 0.090))            // #FFFFFF / #1E1A17
    static let cardSoft = dyn((0.984, 0.973, 0.957), (0.141, 0.125, 0.098))  // #FBF8F4 / #242019
    static let accent = Color(red: 0.941, green: 0.514, blue: 0.243)    // #F0833E
    static let accentHi = Color(red: 0.965, green: 0.627, blue: 0.373)  // #F6A05F
    static let accentSoft = Color(red: 0.941, green: 0.514, blue: 0.243).opacity(0.14)
    static let text = dyn((0.114, 0.098, 0.086), (0.949, 0.929, 0.906))      // #1D1916 / #F2EDE7
    static let text2 = dyn((0.290, 0.259, 0.231), (0.812, 0.776, 0.737))     // #4A423B / #CFC6BC
    static let dim = dyn((0.545, 0.510, 0.475), (0.604, 0.565, 0.525))       // #8B8279 / #9A9086
    static let dim2 = dyn((0.678, 0.647, 0.612), (0.478, 0.443, 0.408))      // #ADA59C / #7A7168
    static let line = dyn((0.898, 0.878, 0.851), (0.180, 0.157, 0.137))      // #E5E0D9 / #2E2823
    static let lineSoft = dyn((0.937, 0.922, 0.902), (0.149, 0.125, 0.106))
    static let ok = Color(red: 0.204, green: 0.651, blue: 0.412)        // #34A669
    static let warn = Color(red: 0.898, green: 0.588, blue: 0.176)      // #E5962D
    static let bad = Color(red: 0.851, green: 0.310, blue: 0.243)       // #D94F3E
    static let blue = Color(red: 0.271, green: 0.478, blue: 0.878)      // #457ACF
    static let purple = Color(red: 0.545, green: 0.435, blue: 0.816)

    // MARK: 间距令牌（4 的倍数，全局统一，避免各页 10/12/14/16 混用）
    static let sp1: CGFloat = 4
    static let sp2: CGFloat = 8
    static let sp3: CGFloat = 12
    static let sp4: CGFloat = 16
    static let sp5: CGFloat = 20
    static let sp6: CGFloat = 28

    // MARK: 字号令牌（收敛为 6 档）
    static let fsCaption: CGFloat = 11
    static let fsSmall: CGFloat = 12.5
    static let fsBody: CGFloat = 14
    static let fsTitle: CGFloat = 17
    static let fsCardTitle: CGFloat = 20
    static let fsHero: CGFloat = 26

    // MARK: 圆角令牌
    static let radiusSmall: CGFloat = 12
    static let radius: CGFloat = 16
    static let radiusLarge: CGFloat = 22

    static let heroGradient = LinearGradient(
        colors: [accent, accentHi],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 稳定取模：String.hashValue 每次启动都会变，说话人颜色会因此跳变。
    /// 用 FNV-1a 自己算，跨启动、跨设备一致。
    static func stableIndex(_ text: String, modulo m: Int) -> Int {
        guard m > 0 else { return 0 }
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in text.utf8 {
            h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01b3
        }
        return Int(h % UInt64(m))
    }

    /// 人物/说话人统一取色（与 store 里的人名无关，纯展示）
    static func personColor(_ name: String) -> Color {
        if name.isEmpty { return dim2 }
        if name == "我" { return accent }
        let idx = stableIndex(name, modulo: personPalette.count)
        let rgb = hexToRGB(personPalette[idx])
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}

struct CardBG: ViewModifier {
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .shadow(color: Color.black.opacity(0.045), radius: 10, x: 0, y: 3)
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View { modifier(CardBG(padding: padding)) }

    func softCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Theme.cardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.dim)
            Spacer()
            if let t = trailing {
                Text(t).font(.system(size: 12)).foregroundStyle(Theme.dim2)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.accent
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.13))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct EmptyHint: View {
    let symbol: String
    let title: String
    let detail: String

    init(symbol: String, title: String, detail: String = "") {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }

    /// 只有一句话的用法
    init(text: String) {
        self.symbol = "waveform"
        self.title = ""
        self.detail = text
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(Theme.dim2)
            if !title.isEmpty {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            }
            Text(detail).font(.system(size: 12.5)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 8)
    }
}

/// 加载态：骨架屏（列表首屏、整理中都用它，避免白屏）
struct LoadingHint: View {
    var rows: Int = 3
    var text: String? = nil

    @State private var animate = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sp3) {
            if let text {
                HStack(spacing: Theme.sp2) {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                    Text(text)
                        .font(.system(size: Theme.fsSmall))
                        .foregroundStyle(Theme.dim)
                }
            }
            ForEach(0..<max(1, rows), id: \.self) { i in
                VStack(alignment: .leading, spacing: Theme.sp2) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.lineSoft)
                        .frame(height: 12)
                        .frame(maxWidth: i % 2 == 0 ? .infinity : 190, alignment: .leading)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Theme.lineSoft)
                        .frame(height: 10)
                        .frame(maxWidth: 140, alignment: .leading)
                }
                .padding(Theme.sp3)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
        }
        .opacity(animate ? 0.55 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("正在载入")
    }
}

/// 头像圆点：首字 + 柔和底色，用于人物列表
struct AvatarDot: View {
    let name: String
    var color: Color = Theme.accent
    var size: CGFloat = 34
    var body: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.13))
            .clipShape(Circle())
    }
}
