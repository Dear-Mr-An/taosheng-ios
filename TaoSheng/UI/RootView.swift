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

    /// 悬浮 TabBar 实际占用的高度：内边距 8+2+4 + 胶囊（图标 22 + 间距 3 + 文字 13 + 上下 5+5）
    static let reservedHeight: CGFloat = 66

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

extension View {
    /// 悬浮 TabBar 的占位：凡是会被 TabBar 盖住的滚动页面都要自己声明一次，
    /// 这样最后一行才能完整滚到 TabBar 上方。底部安全区（Home 指示条）
    /// 由 ScrollView / List 自身处理，这里只补 TabBar 实际占用的高度。
    func tabBarClearance(_ extra: CGFloat = 12) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: TabBar.reservedHeight + extra)
        }
    }

    /// 悬浮按钮（FAB、输入条）用的底部内边距：直接让控件本身越过 TabBar
    func floatingTabBarPadding(_ extra: CGFloat = 8) -> some View {
        padding(.bottom, TabBar.reservedHeight + extra)
    }
}
