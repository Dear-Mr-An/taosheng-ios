import SwiftUI

@MainActor
struct TodosView: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var speech = QuickSpeech.shared

    @State private var tab = 0   // 0 待确认 1 进行中 2 已完成
    @State private var showAdd = false
    @State private var sheetTip: String?
    @State private var draft = ""
    @State private var parsing = false
    @State private var toast: String?
    @State private var holding = false
    @State private var finishingVoice = false
    @State private var voiceStartTask: Task<Void, Never>?
    @State private var voiceFinishTask: Task<Void, Never>?
    @State private var parseTask: Task<Void, Never>?
    /// 批量「全部忽略」要点两次：第一次只是换个字，避免误触
    @State private var ignoreArmed = false
    @State private var deleting: MemoryItem?
    @Environment(\.scenePhase) private var scenePhase

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
                    // 给悬浮的语音按钮留位：按钮高 56 + 上下各 8
                    Color.clear.frame(height: 56 + 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            // 占位只加在滚动区上。加在 ZStack 外层会把 FAB 一起抬起来，
            // FAB 自己还有 floatingTabBarPadding，底部留白会算两遍。
            .tabBarClearance()

            fab
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showAdd, onDismiss: cancelParsing) { addSheet }
        .confirmationDialog("删除这条待办？", isPresented: Binding(get: { deleting != nil },
                                                        set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let it = deleting { app.deleteItem(it.id) }
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        }
        .alert("提示", isPresented: Binding(get: { toast != nil }, set: { if !$0 { toast = nil } })) {
            Button("好") { toast = nil }
        } message: { Text(toast ?? "") }
        .onDisappear { cancelVoice() }
        .onChange(of: scenePhase) { phase in
            // 只在这一页真正退到后台时才放弃；系统授权弹窗也会让 phase 变成 inactive，
            // 那种情况下取消就等于把用户刚开始说的那句话掐掉。
            if phase == .background { cancelVoice() }
        }
    }

    private var header: some View {
        HStack {
            Text("待办")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
            Spacer()
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
                        .foregroundColor(tab == idx ? Theme.accent.opacity(0.75) : Theme.dim2)
                }
            }
            .foregroundColor(tab == idx ? Theme.accent : Theme.text2)
            .padding(.horizontal, Theme.sp3).padding(.vertical, Theme.sp2)
            .background(tab == idx ? Theme.accentSoft : Theme.card)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tab == idx ? Color.clear : Theme.line, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if list.isEmpty {
            EmptyHint(symbol: emptySymbol, title: emptyText, detail: emptyDetail)
                .padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: Theme.sp3) {
                if tab == 0 && list.count > 1 { bulkBar }
                ForEach(groups, id: \.day) { g in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(g.title)
                            .font(.system(size: Theme.fsCaption, weight: .medium))
                            .foregroundColor(Theme.dim)
                            .padding(.leading, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(g.items.enumerated()), id: \.element.id) { idx, it in
                                SwipeRow(onDone: { toggle(it) },
                                         onDelete: { deleting = it }) {
                                    row(it)
                                }
                                if idx < g.items.count - 1 {
                                    Rectangle().fill(Theme.lineSoft)
                                        .frame(height: 0.6)
                                        .padding(.leading, 46)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    }
                }
            }
        }
    }

    private struct DayGroup: Identifiable {
        let day: String
        let title: String
        let items: [MemoryItem]
        var id: String { day }
    }

    /// 按天一张大卡：今天 / 昨天 / 10月24日
    private var groups: [DayGroup] {
        var order: [String] = []
        var map: [String: [MemoryItem]] = [:]
        let today = DayKey.of(Date())
        let yesterday = DayKey.of(Date().addingTimeInterval(-86400))
        for it in list {
            let d = it.day.isEmpty ? "未知" : it.day
            if map[d] == nil { order.append(d) }
            map[d, default: []].append(it)
        }
        return order.map { d in
            let title: String
            if d == today { title = "今天" }
            else if d == yesterday { title = "昨天" }
            else if let date = DayKey.date(from: d) { title = Fmt.monthDay.string(from: date) }
            else { title = d }
            return DayGroup(day: d, title: title, items: map[d] ?? [])
        }
    }

    private var bulkBar: some View {
        HStack(spacing: 8) {
            Button {
                for it in app.pendingItems { app.setItemStatus(it.id, status: .accepted) }
                toast = "已全部接受"
            } label: {
                Text("全部接受 \(app.pendingItems.count) 条")
                    .font(.system(size: Theme.fsSmall, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)

            Button {
                if ignoreArmed {
                    for it in app.pendingItems { app.setItemStatus(it.id, status: .ignored) }
                    ignoreArmed = false
                    toast = "已全部忽略"
                } else {
                    ignoreArmed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { ignoreArmed = false }
                }
            } label: {
                Text(ignoreArmed ? "再点一次全部忽略" : "全部忽略")
                    .font(.system(size: Theme.fsSmall, weight: ignoreArmed ? .semibold : .regular))
                    .foregroundColor(ignoreArmed ? .white : Theme.text2)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Capsule().fill(ignoreArmed ? Theme.bad : Theme.card))
                    .overlay(Capsule().stroke(ignoreArmed ? Color.clear : Theme.line, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    private func toggle(_ it: MemoryItem) {
        app.setItemStatus(it.id, status: it.status == .done ? .accepted : .done)
    }

    private var emptySymbol: String {
        switch tab { case 0: return "checklist"; case 1: return "hourglass"; default: return "checkmark.circle" }
    }

    private var emptyDetail: String {
        switch tab {
        case 0: return "录音整理出待办后会出现在这里"
        case 1: return "确认过的待办会进入进行中"
        default: return "勾掉的待办会归档到这里"
        }
    }
    private func tint(_ c: String) -> Color { Color(hex: MemoryItem.categoryColor(c)) }

    /// 原版的样子：类型胶囊写「待办 · 我要做」，后面跟截止和人物，不再重复写一遍 kind
    private func metaRow(_ it: MemoryItem) -> some View {
        HStack(spacing: 6) {
            Text(chipText(it))
                .font(.system(size: Theme.fsCaption, weight: .medium))
                .foregroundColor(tint(it.category))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint(it.category).opacity(0.13))
                .clipShape(Capsule())
            if let d = it.dueDisplay {
                Text(d).font(.system(size: Theme.fsCaption)).foregroundColor(Theme.dim)
            }
            if let w = it.who, !w.isEmpty {
                Text("· " + w).font(.system(size: Theme.fsCaption)).foregroundColor(Theme.dim2)
            }
            Spacer(minLength: 0)
        }
    }

    private func chipText(_ it: MemoryItem) -> String {
        if it.category == "待办", let k = it.kind, !k.isEmpty { return "待办 · " + k }
        return it.category
    }

    private var emptyText: String {
        switch tab {
        case 0: return "没有要确认的了"
        case 1: return "手上没有进行中的事"
        default: return "还没有做完的事"
        }
    }

    private func row(_ it: MemoryItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { toggle(it) } label: {
                Image(systemName: it.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundColor(it.status == .done ? Theme.ok : Theme.dim2)
                    .tapTarget(10)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(it.content)
                    .font(.system(size: Theme.fsBody))
                    .foregroundColor(it.status == .done ? Theme.dim2 : Theme.text)
                    .strikethrough(it.status == .done, color: Theme.dim2)
                    // 原版就是固定两行：短内容也占两行，列表节奏不跳
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                metaRow(it)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu {
            if tab == 0 {
                Button { app.setItemStatus(it.id, status: .accepted) } label: { Label("接受", systemImage: "checkmark") }
                Button { app.setItemStatus(it.id, status: .ignored) } label: { Label("不用记", systemImage: "xmark") }
            }
            if it.status != .done {
                Button { addReminder(for: it) } label: { Label("一小时后提醒", systemImage: "bell") }
            }
            Button(role: .destructive) { deleting = it } label: { Label("删除", systemImage: "trash") }
        }
    }

    private func addReminder(for item: MemoryItem) {
        let at = Date().addingTimeInterval(3600)
        app.addReminder(title: item.content, at: at, repeatDaily: false)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        toast = "已加提醒：\(formatter.string(from: at))"
    }

    private var voicePill: some View {
        HStack(spacing: 6) {
            Image(systemName: holding ? "waveform" : "mic")
                .font(.system(size: 12, weight: .medium))
            Text(voiceText)
                .font(.system(size: 12.5))
                .lineLimit(1)
        }
        .foregroundColor(holding ? Theme.accent : Theme.text2)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.card)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .allowsHitTesting(false)
    }

    private var voiceText: String {
        if holding {
            return speech.text.isEmpty ? "松手结束" : speech.text
        }
        if finishingVoice { return "正在识别…" }
        return "点 + 打字 · 按住 + 说话"
    }

    private func startVoice() {
        guard !holding, !finishingVoice else { return }
        speech.stop(discardText: true)
        holding = true
        voiceStartTask = Task { await speech.start() }
    }

    private func cancelVoice() {
        guard holding || finishingVoice else { return }
        holding = false
        finishingVoice = false
        voiceStartTask?.cancel()
        voiceStartTask = nil
        voiceFinishTask?.cancel()
        voiceFinishTask = nil
        speech.stop(discardText: true)
    }

    private func endVoice() {
        guard holding else { return }
        holding = false
        finishingVoice = true
        voiceFinishTask = Task { @MainActor in
            // 启动可能还卡在 await 里（首次授权、音频会话激活都要时间），
            // 这里 cancel 掉会让 finish() 拿到空串，用户说完只看到「没听清」。
            // 等它跑完再收尾。
            _ = await voiceStartTask?.value
            voiceStartTask = nil
            let text = await speech.finish()
            guard !Task.isCancelled else { return }
            finishingVoice = false
            voiceFinishTask = nil
            if text.isEmpty {
                toast = speech.hint ?? "没听清，再说一次"
            } else {
                draft = text
                showAdd = true
            }
        }
    }

    private var fab: some View {
        HStack(spacing: 10) {
            voicePill

            VoiceAddButton(onTap: { if !finishingVoice { sheetTip = nil; showAdd = true } }, onHold: startVoice,
                           onRelease: endVoice, onCancel: cancelVoice)
                .frame(width: 56, height: 56)
                .shadow(color: Theme.accent.opacity(0.35), radius: 10, x: 0, y: 5)
        }
        .padding(.trailing, 16)
        .floatingTabBarPadding(12)
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
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    .disabled(parsing)
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
                    guard !parsing else { return }
                    parseTask = Task { await parseDraft() }
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
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
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
                if let tip = sheetTip {
                    Text(tip)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(16)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("添加待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { cancelParsing(); showAdd = false; draft = "" }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("直接存") { saveRaw() }
                        .disabled(parsing || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func cancelParsing() {
        parseTask?.cancel()
        parseTask = nil
        parsing = false
    }

    private func parseDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Task.isCancelled, !text.isEmpty, !parsing else { return }
        if settings.effectiveLLM.key.isEmpty {
            saveRaw()
            return
        }
        parsing = true
        defer { if !Task.isCancelled { parsing = false } }

        let system = """
        你是待办整理助手。把用户随口写下的一段话拆成一条条待办，只输出 JSON，不要多余文字。
        格式：{"items":[{"content":"一句话写清楚做什么","category":"待办|约定|备忘","due":"YYYY-MM-DD HH:mm 或 null","who":"和谁 / 谁来做，没有就 null"}]}
        今天：\(Prompts.todayText())
        \(Prompts.calendarTable())
        规则：一句话里有多件事就拆成多条；没有明确时间的 due 写 null；不要编造时间；保留原话里的对象和细节。
        """
        do {
            let reply = try await LLMClient.completeAny(system: system, user: text, temperature: 0.1)
            try Task.checkCancellation()
            guard let obj = JSONExtract.object(from: reply),
                  let arr = obj["items"] as? [[String: Any]] else {
                sheetTip = "整理结果不正确，原文已保留，可重试或直接存"
                return
            }
            var drafts: [(content: String, category: String, due: String?)] = []
            for raw in arr {
                let content = (raw["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !content.isEmpty else { continue }
                let category = raw["category"] as? String ?? "待办"
                let cat = ["待办", "约定", "备忘"].contains(category) ? category : "待办"
                // 模型经常把「没有时间」写成字符串 "null" / "n/a"，直接透传会变成一条解析不出时间的假截止
                let dueRaw = (raw["due"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let bad = ["", "null", "nil", "none", "n/a", "na", "-", "无"]
                let due = (dueRaw.map { bad.contains($0.lowercased()) } ?? true) ? nil : dueRaw
                drafts.append((content: content, category: cat, due: due))
            }
            let added = drafts.count
            if added > 0 { app.addItems(drafts) }
            guard added > 0 else {
                sheetTip = "没有识别出待办，原文已保留，可修改或直接存"
                return
            }
            draft = ""
            showAdd = false
            tab = 1
            toast = "已生成 \(added) 条待办"
        } catch {
            guard !Task.isCancelled else { return }
            sheetTip = error.localizedDescription
        }
    }
}
