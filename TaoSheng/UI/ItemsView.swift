import SwiftUI

struct ItemsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var digest: DigestEngine

    @State private var filter: ItemKind? = nil
    @State private var showDone = false
    @State private var items: [DigestItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    filterBar
                    if items.isEmpty {
                        EmptyHint(symbol: "checklist",
                                  title: showDone ? "还没有完成的事" : "还没有待办",
                                  detail: "等「今天」页整理过之后，答应别人的事、约好的时间会自动出现在这里。")
                            .card()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                ItemRow(item: item) {
                                    app.toggleItem(item)
                                    reload()
                                }
                                if item.id != items.last?.id { Divider().overlay(Theme.line) }
                            }
                        }
                        .card(padding: 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("整理")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        digest.digest(day: DayKey.of(Date()))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { reload() }
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .tint(Theme.accent)
                }
            }
            .onAppear { reload() }
            .onReceive(NotificationCenter.default.publisher(for: .taoshengDataChanged)) { _ in reload() }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", active: filter == nil) { filter = nil; reload() }
                ForEach(ItemKind.allCases, id: \.self) { k in
                    chip(k.title, active: filter == k) { filter = k; reload() }
                }
                chip(showDone ? "已完成" : "未完成", active: showDone) { showDone.toggle(); reload() }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? Theme.accent.opacity(0.18) : Theme.card)
                .foregroundStyle(active ? Theme.accent : Theme.dim)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func reload() {
        var list = Store.shared.items(openOnly: !showDone)
        if let f = filter { list = list.filter { $0.kind == f } }
        items = list
    }
}
