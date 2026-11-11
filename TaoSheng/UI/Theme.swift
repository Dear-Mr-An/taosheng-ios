import SwiftUI

/// 深色暖调：墨黑底 + 琥珀强调色，跟 Android 版的气质对齐
enum Theme {
    static let bg = Color(red: 0.055, green: 0.067, blue: 0.086)        // #0E1116
    static let card = Color(red: 0.098, green: 0.110, blue: 0.133)      // #191C22
    static let cardHi = Color(red: 0.137, green: 0.153, blue: 0.184)    // #232730
    static let accent = Color(red: 1.0, green: 0.541, blue: 0.259)      // #FF8A42
    static let accentSoft = Color(red: 1.0, green: 0.541, blue: 0.259).opacity(0.16)
    static let text = Color(red: 0.949, green: 0.933, blue: 0.910)      // #F2EEE8
    static let dim = Color(red: 0.576, green: 0.596, blue: 0.639)       // #9398A3
    static let line = Color.white.opacity(0.08)
    static let ok = Color(red: 0.239, green: 0.796, blue: 0.478)
    static let warn = Color(red: 0.976, green: 0.663, blue: 0.290)
    static let bad = Color(red: 0.949, green: 0.380, blue: 0.290)

    static let radius: CGFloat = 16
}

struct CardBG: ViewModifier {
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View { modifier(CardBG(padding: padding)) }
}

struct SectionTitle: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.dim)
            Spacer()
            if let t = trailing {
                Text(t).font(.system(size: 12)).foregroundStyle(Theme.dim.opacity(0.8))
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
            .background(color.opacity(0.16))
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
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(Theme.dim.opacity(0.6))
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}
