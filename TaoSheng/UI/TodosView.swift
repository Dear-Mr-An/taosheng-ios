import SwiftUI

struct TodosView: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var settings = Settings.shared

    @State private var tab = 0   // 0 待确认 1 进行中 2 已完成
    @State private var showAdd = false
    @State private var draft = ""
    @State private var parsing = false
    @State private var toast: String?
    @State private var newReminder: MemoryItem?

    private var list: [MemoryItem] {
        switch tab {
        case 0: return app.pendingItems
        case 1: return app.activeItems
        default: return app.doneItems
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    chips
                    content
                    Color.clear.frame(height: 120)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            fab
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showAdd) { addSheet }
        .alert("提示", isPresented: Binding(get: { toast != nil }, set: { if !$0 { toast = nil } })) {
            Button("好") { toast = nil }
        } message: { Text(toast ?? "") }
    }

    private var header: some View {
        HStack {
            Text("待办")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
            Spacer()
            if !app.reminders.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "bell.fill").font(.system(size: 11))
                    Text("\(app.reminders.count)").font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Theme.text2)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.card).clipShape(Capsule())
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            chip("待确认", 0, app.counts.pending)
            chip("进行中", 1, app.counts.accepted)
            chip("已完成", 2, app.counts.done)
            Spacer()
        }
    }

    private func chip(_ t: String, _ idx: Int, _ n: Int) -> some View {
        Button { tab = idx } label: {
            HStack(spacing: 4) {
                Text(t).font(.system(size: 13.5, weight: .medium))
                if n > 0 {
                    Text("\(n)").font(.system(size: 11))
                        .foregroundColor(tab == idx ? Color.white.opacity(0.85) : Theme.dim2)
                }
            }
            .foregroundColor(tab == idx ? .white : Theme.text2)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(tab == idx ? Theme.accent : Theme.card)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if list.isEmpty {
            EmptyHint(text: emptyText)
                .padding(.top, 40)
        } else {
            VStack(spacing: 10) {
                ForEach(list) { it in
                    card(it)
                }
            }
        }
    }

    private var emptyText: String {
        switch tab {
        case 0: return "没有要确认的了"
        case 1: return "手上没有进行中的事"
        default: return "还没有做完的事"
        }
    }

    private func card(_ it: MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    app.setItemStatus(it.id, status: it.status == .done ? .accepted : .done)
                } label: {
                    Image(systemName: it.status == .done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19))
                        .foregroundColor(it.status == .done ? Theme.ok : Theme.dim2)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 5) {
                    Text(it.content)
                        .font(.system(size: 14.5))
                        .foregroundColor(it.status == .done ? Theme.dim2 : Theme.text)
                        .strikethrough(it.status == .done, color: Theme.dim2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text(it.category)
                            .font(.system(size: 10.5))
                            .foregroundColor(it.categoryColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(it.categoryColor.opacity(0.1))
                            .clipShape(Capsule())
                        if let k = it.kind, !k.isEmpty {
                            Text(k).font(.system(size: 10.5)).foregroundColor(Theme.dim2)
                        }
                        if let d = it.dueDisplay {
                            Text(d).font(.system(size: 11)).foregroundColor(Theme.dim)
                        }
                        if let w = it.who, !w.isEmpty {
                            Text(w).font(.system(size: 11)).foregroundColor(Theme.dim2)
                        }
                        Spacer()
                    }
                }
            }

            if tab == 0 {
                HStack(spacing: 8) {
                    Button {
                        app.setItemStatus(it.id, status: .accepted)
                    } label: {
                        Text("确认")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Theme.accent).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        app.setItemStatus(it.id, status: .ignored)
                    } label: {
                        Text("不用记")
                            .font(.system(size: 12.5))
                            .foregroundColor(Theme.dim)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Theme.bgDeep).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }

            if let s = it.sourceText, !s.isEmpty {
                Text("原话：\(s)")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.dim2)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .contextMenu {
            if it.status != .done {
                Button {
                    newReminder = it
                } label: { Label("一小时后提醒", systemImage: "bell") }
            }
            Button(role: .destructive) {
                app.deleteItem(it.id)
            } label: { Label("删除", systemImage: "trash") }
        }
        .onChange(of: newReminder?.id) { _ in
            guard let it = newReminder else { return }
            let at = it.dueAt ?? Date().addingTimeInterval(3600)
            app.addReminder(title: it.content, at: at, repeatDaily: false)
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月d日 HH:mm"
            toast = "已加提醒：\(f.string(from: at))"
            newReminder = nil
        }
    }

    private var fab: some View {
        HStack(spacing: 10) {
            Text("点按打字 · 按住说话")
                .font(.system(size: 12.5))
                .foregroundColor(Theme.text2)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.card)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)

            Button { showAdd = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.accent)
                    .clipShape(Circle())
                    .shadow(color: Theme.accent.opacity(0.35), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 16)
        .padding(.bottom, 92)
    }

    // MARK: 添加待办

    private var addSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("像平时说话一样写，几件事写在一起也行。")
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.dim)

                TextEditor(text: $draft)
                    .font(.system(size: 15))
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if draft.isEmpty {
                            Text("例如：明天下午三点给张总回电话，周五前把报销单交了")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.dim2)
                                .padding(.horizontal, 12).padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }

                Button {
                    Task { await parseDraft() }
                } label: {
                    HStack {
                        if parsing { ProgressView().scaleEffect(0.8).tint(.white) }
                        Text(parsing ? "正在拆成待办卡…" : "生成待办卡")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.dim2 : Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(parsing || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !settings.effectiveLLM.key.isEmpty {
                    Text("会用 \(settings.llmModel) 帮你拆成一条条。")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.dim2)
                } else {
                    Text("还没配置大模型，只能整条存下。")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.warn)
                }
                Spacer()
            }
            .padding(16)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("添加待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { showAdd = false; draft = "" }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("直接存") { saveRaw() }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveRaw() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        app.addItem(content: t)
        draft = ""
        showAdd = false
        tab = 1
    }

    private func parseDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if settings.effectiveLLM.key.isEmpty {
            saveRaw()
            return
        }
        await MainActor.run { parsing = true }
        defer { Task { await MainActor.run { parsing = false } } }

        let system = """
        你是待办整理助手。把用户随口写下的一段话拆成一条条待办，只输出 JSON，不要多余文字。
        格式：{"items":[{"content":"一句话写清楚做什么","category":"待办|约定|备忘","due":"YYYY-MM-DD HH:mm 或 null","who":"和谁 / 谁来做，没有就 null"}]}
        今天：\(Prompts.todayText())
        \(Prompts.calendarTable())
        规则：一句话里有多件事就拆成多条；没有明确时间的 due 写 null；不要编造时间；保留原话里的对象和细节。
        """
        do {
            let reply = try await LLMClient.completeAny(system: system, user: text, temperature: 0.1)
            guard let obj = JSONExtract.object(from: reply),
                  let arr = obj["items"] as? [[String: Any]], !arr.isEmpty else {
                saveRaw()
                return
            }
            for raw in arr {
                let content = (raw["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !content.isEmpty else { continue }
                let cat = raw["category"] as? String ?? "待办"
                let due = raw["due"] as? String
                app.addItem(content: content, category: cat, due: due)
            }
            await MainActor.run {
                draft = ""
                showAdd = false
                tab = 1
                toast = "已生成 \(arr.count) 条待办"
            }
        } catch {
            await MainActor.run { toast = error.localizedDescription }
        }
    }
}
