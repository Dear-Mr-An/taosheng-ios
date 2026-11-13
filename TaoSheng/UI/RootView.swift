import SwiftUI

struct RootView: View {
    @State private var tab: Int = 0
    @StateObject private var kb = KeyboardObserver.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()

            Group {
                switch tab {
                case 0: NavigationStack { TodayView() }
                case 1: NavigationStack { AskView() }
                case 2: NavigationStack { MemoryView() }
                case 3: NavigationStack { TodosView() }
                default: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // 与 TabBar 实际占用高度共用同一个常量，避免列表最后一行被压住
                Color.clear.frame(height: kb.isVisible ? 0 : TabBar.reservedHeight)
            }

            if !kb.isVisible {
                TabBar(selected: $tab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: kb.isVisible)
        .onReceive(NotificationCenter.default.publisher(for: .taoshengAskPrefill)) { _ in
            withAnimation(.easeOut(duration: 0.16)) { tab = 1 }
        }
    }
}

struct TabBar: View {
    @Binding var selected: Int

    /// 悬浮 TabBar 实际占用的高度：上 8 + 胶囊 44 + 下 4 + 底部留白 6
    static let reservedHeight: CGFloat = 62

    private let items: [(icon: String, iconOn: String, title: String)] = [
        ("sun.max", "sun.max.fill", "今天"),
        ("bubble.left.and.text.bubble.right", "bubble.left.and.text.bubble.right.fill", "问问"),
        ("book.closed", "book.closed.fill", "记忆"),
        ("checkmark.circle", "checkmark.circle.fill", "待办"),
        ("slider.horizontal.3", "slider.horizontal.3", "设置")
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<items.count, id: \.self) { i in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selected = i }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selected == i ? items[i].iconOn : items[i].icon)
                            .font(.system(size: 19, weight: selected == i ? .semibold : .regular))
                            .frame(height: 22)
                        Text(items[i].title)
                            .font(.system(size: 10.5, weight: selected == i ? .semibold : .regular))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selected == i ? Theme.accent : Theme.dim2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                            .fill(selected == i ? Theme.accentSoft : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(items[i].title)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Theme.card
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .stroke(Theme.line, lineWidth: 0.6)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }
}
