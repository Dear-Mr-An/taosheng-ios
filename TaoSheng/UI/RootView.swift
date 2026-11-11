import SwiftUI

struct RootView: View {
    @State private var tab: Int = 0

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

            TabBar(selected: $tab)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

struct TabBar: View {
    @Binding var selected: Int

    private let items: [(icon: String, iconOn: String, title: String)] = [
        ("sun.max", "sun.max.fill", "今天"),
        ("bubble.left.and.text.bubble.right", "bubble.left.and.text.bubble.right.fill", "问问"),
        ("book.closed", "book.closed.fill", "记忆"),
        ("checkmark.circle", "checkmark.circle.fill", "待办"),
        ("slider.horizontal.3", "slider.horizontal.3", "设置")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<items.count, id: \.self) { i in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selected = i }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selected == i ? items[i].iconOn : items[i].icon)
                            .font(.system(size: 18, weight: selected == i ? .semibold : .regular))
                        Text(items[i].title)
                            .font(.system(size: 10, weight: selected == i ? .semibold : .regular))
                    }
                    .foregroundStyle(selected == i ? Theme.accent : Theme.dim2)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .padding(.horizontal, 6)
        .background(
            Theme.card
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 4)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }
}
