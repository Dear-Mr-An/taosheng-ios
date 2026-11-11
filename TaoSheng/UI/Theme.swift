import SwiftUI

/// 浅色暖调：米白画布 + 白卡 + 琥珀橙强调，对齐原版 Android 的观感
enum Theme {
    static let bg = Color(red: 0.965, green: 0.949, blue: 0.925)        // #F6F2EC
    static let bgDeep = Color(red: 0.945, green: 0.925, blue: 0.898)    // #F1ECE5
    static let card = Color.white
    static let cardSoft = Color(red: 0.984, green: 0.973, blue: 0.957)  // #FBF8F4
    static let accent = Color(red: 0.941, green: 0.514, blue: 0.243)    // #F0833E
    static let accentHi = Color(red: 0.965, green: 0.627, blue: 0.373)  // #F6A05F
    static let accentSoft = Color(red: 0.941, green: 0.514, blue: 0.243).opacity(0.12)
    static let text = Color(red: 0.114, green: 0.098, blue: 0.086)      // #1D1916
    static let text2 = Color(red: 0.290, green: 0.259, blue: 0.231)     // #4A423B
    static let dim = Color(red: 0.545, green: 0.510, blue: 0.475)       // #8B8279
    static let dim2 = Color(red: 0.678, green: 0.647, blue: 0.612)      // #ADA59C
    static let line = Color(red: 0.898, green: 0.878, blue: 0.851)      // #E5E0D9
    static let lineSoft = Color(red: 0.937, green: 0.922, blue: 0.902)
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
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(Theme.dim2)
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
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
