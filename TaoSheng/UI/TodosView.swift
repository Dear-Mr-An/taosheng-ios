import SwiftUI

struct TodosView: View {
    @EnvironmentObject var app: AppState

    @State private var all: [DigestItem] = []
    @State private var showAdd = false
    @State private var draft = ""
    @State private var dueDate = Date().addingTimeInterval(3600)
    @State private var hasDue = false
    @State private var withAlarm = true

    private var timed: [DigestItem] {
        all.filter { $0.status == .open && !$0.due.isEmpty }
            .sorted { $0.dueSortKey < $1.dueSortKey }
    }

    private var anytime: [DigestItem] {
        all.filter { $0.status == .open && $0.due.isEmpty }
    }

    private var done: [DigestItem] {
        Array(all.filter { $0.status == .done }.prefix(5))
    }

    private var nextReminder: Reminder? {
        app.reminders.filter { $0.enabled && $0.fireAt > Date() }.min { $0.fireAt < $1.fireAt }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let r = nextReminder { reminderCard(r) }
                if !timed.isEmpty { group("有时间 · \(timed.count)", items: timed) }
                if !anytime.isEmpty { group("随时做的 · \(anytime.count)", items: anytime) }
                if !done.isEmpty { group("已经做完 · \(done.count)", items: done) }
                if timed.isEmpty && anytime.isEmpty && done.isEmpty {
                    EmptyHint(text: "还没有待办。整理之后，你说过要办的事会自动出现在这里；也可以点右上角手动加。")
                        .padding(.top, 30)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 110)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { load() }
        .onReceive(NotificationCenter.default.publisher(for: .taoshengDataChanged)) { _ in load() }
        .sheet(isPresented: $showAdd) { addSheet }
    }

    // MARK: - 头部
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("涛声")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("\(timed.count + anytime.count) 件还没做")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            Button { showAdd = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 提醒卡
    private func reminderCard(_ r: Reminder) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "alarm.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(alarmText(r.fireAt) + (r.repeatDaily ? " · 每天" : ""))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            Button {
                ReminderEngine.shared.cancel(r.id)
                Store.shared.deleteReminder(id: r.id)
                app.refresh()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.dim2)
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private func alarmText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }

    // MARK: - 分组
    private func group(_ title: String, items: [DigestItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .padding(.leading, 2)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    todoRow(item)
                    if idx < items.count - 1 {
                        Divider().overlay(Theme.lineSoft).padding(.leading, 34)
                    }
                }
            }
            .card(padding: 4)
        }
    }

    private func todoRow(_ item: DigestItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                Store.shared.setItemStatus(id: item.id, status: item.status == .done ? .open : .done)
                load()
                app.refresh()
            } label: {
                Image(systemName: item.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(item.status == .done ? Theme.ok : Theme.dim2)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14.5))
                    .foregroundStyle(item.status == .done ? Theme.dim2 : Theme.text)
                    .strikethrough(item.status == .done, color: Theme.dim2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Text(item.kind.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(kindColor(item.kind))
                    if !item.due.isEmpty {
                        Text("·").font(.system(size: 10)).foregroundStyle(Theme.dim2)
                        Text(item.due)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                dueDate = Date().addingTimeInterval(3600)
                app.addReminder(title: item.title, at: dueDate, repeatDaily: false)
            } label: { Label("一小时后提醒我", systemImage: "alarm") }
            Button(role: .destructive) {
                Store.shared.deleteItem(id: item.id)
                load()
                app.refresh()
            } label: { Label("删除", systemImage: "trash") }
        }
    }

    private func kindColor(_ k: ItemKind) -> Color {
        switch k {
        case .event: return Theme.blue
        case .todo: return Theme.accent
        case .promise: return Theme.purple
        case .idea: return Theme.warn
        case .memory: return Theme.ok
        }
    }

    // MARK: - 新增
    private var addSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("要做的事", text: $draft, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section {
                    Toggle("定个时间", isOn: $hasDue).tint(Theme.accent)
                    if hasDue {
                        DatePicker("什么时候", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                    Toggle("到点响铃提醒", isOn: $withAlarm).tint(Theme.accent)
                }
            }
            .navigationTitle("加一件事")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { resetDraft() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func resetDraft() {
        draft = ""
        hasDue = false
        showAdd = false
    }

    private func save() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var due = ""
        if hasDue {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm"
            due = f.string(from: dueDate)
        }
        app.addTodo(title: t, due: due)
        if hasDue && withAlarm {
            app.addReminder(title: t, at: dueDate, repeatDaily: false)
        }
        load()
        resetDraft()
    }

    private func load() {
        all = Store.shared.allItems(limit: 400)
    }
}
