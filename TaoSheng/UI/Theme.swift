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

    static let radius: CGFloat = 18
    static let radiusSmall: CGFloat = 14

    static let heroGradient = LinearGradient(
        colors: [accent, accentHi],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
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
