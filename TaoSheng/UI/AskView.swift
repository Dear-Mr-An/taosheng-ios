import SwiftUI
import UIKit

struct AskView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings

    @State private var input = ""
    @State private var showHistory = false
    @FocusState private var focused: Bool
    @StateObject private var kb = KeyboardObserver.shared

    private let samples = [
        "上周我答应老王什么了？",
        "这两天提到过哪些待办？",
        "上次和张总聊的报价是怎么说的？"
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        if app.askMessages.isEmpty && !app.askSending {
                            intro
                        }
                        ForEach(app.askMessages) { m in
                            bubble(m).id(m.id)
                        }
                        if app.askSending {
                            thinking.id("thinking")
                        }
                        if let e = app.askError {
                            Text(e)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.bad)
                                .padding(.horizontal, 4)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { focused = false })
                .onChange(of: app.askMessages.count) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: app.askSending) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: kb.isVisible) { vis in
                    if vis {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputBar
        }
        .sheet(isPresented: $showHistory) {
            AskHistoryView { q in
                input = q
                focused = true
            }
            .environmentObject(app)
        }
        // 预填问题由 RootView 写进 AppState.askPending；这里既处理「切过来就已经有值」，
        // 也处理「已经停在问问页、值后到」的情况，两种情况都能落到输入框里。
        .onAppear {
            if let q = app.askPending, !q.isEmpty {
                app.askPending = nil
                input = q
            }
        }
        .onChange(of: app.askPending) { q in
            guard let q, !q.isEmpty else { return }
            app.askPending = nil
            input = q
            focused = true
        }
    }

    // MARK: - 头部
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("问问")
                    .font(.system(size: Theme.fsHero, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(settings.effectiveLLM.key.isEmpty
                     ? "还没配大模型，去设置 → 模型与整理"
                     : "答句都带原话出处 · \(settings.llmModel)")
                    .font(.system(size: 12))
                    .foregroundStyle(settings.effectiveLLM.key.isEmpty ? Theme.warn : Theme.dim)
            }
            Spacer()
            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 36, height: 36)
                    .background(Theme.card)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - 空态
    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("可以直接这样问")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text2)
            }
            ForEach(samples, id: \.self) { s in
                Button {
                    input = s
                    send()
                } label: {
                    HStack(spacing: 8) {
                        Text(s)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.dim2)
                    }
                    .padding(12)
                    .background(Theme.cardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - 气泡
    @ViewBuilder
    private func bubble(_ m: AskMessage) -> some View {
        if m.role == .me {
            HStack {
                Spacer(minLength: 40)
                Text(m.text)
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("涛声")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                }
                Text(m.text)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if !m.citations.isEmpty {
                    Divider().overlay(Theme.line)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("原话出处")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.dim2)
                        ForEach(Array(m.citations.prefix(4)), id: \.self) { c in
                            HStack(spacing: 6) {
                                Circle().fill(Theme.accent.opacity(0.6)).frame(width: 4, height: 4)
                                Text(c)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.text2)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
    }

    private var thinking: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text("在翻你之前的原话…")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.dim)
        }
        .padding(.vertical, 6)
    }

    // MARK: - 输入
    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("想问点什么…", text: $input, axis: .vertical)
                .font(.system(size: 14.5))
                .focused($focused)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
                .onChange(of: input) { v in
                    // axis: .vertical 的 TextField 里回车是换行，onSubmit 不会触发，
                    // 所以在这里拦掉末尾换行，做「回车即发送」。
                    if v.hasSuffix("\n") {
                        input = String(v.dropLast())
                        send()
                    }
                }
                .submitLabel(.send)

            if kb.isVisible {
                Button {
                    focused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 34, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收起键盘")
            }

            Button(action: send) {
                Image(systemName: app.askSending ? "ellipsis" : "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(canSend ? Theme.accent : Theme.dim2.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, kb.isVisible ? 8 : TabBar.reservedHeight + 12)
        .background(Theme.bg)
    }

    private var canSend: Bool {
        !app.askSending && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !app.askSending else { return }
        input = ""
        focused = false
        app.ask(q)
    }
}

// MARK: - 历史对话

struct AskThread: Identifiable {
    let id: String
    let question: AskMessage
    let answer: AskMessage?
}

struct DayGroup: Identifiable {
    let id: String
    let day: String
    let items: [AskThread]
}

struct AskHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: ((String) -> Void)? = nil

    @State private var keyword = ""
    @State private var results: [AskMessage] = []
    @State private var detail: AskThread?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                if groups.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(groups) { g in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(dayLabel(g.day))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.dim)
                                        .padding(.leading, 2)
                                    VStack(spacing: 8) {
                                        ForEach(g.items) { t in
                                            row(t)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
                }
            }
            .background(Theme.bg)
            .navigationTitle("历史对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Theme.text2)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            // 走 AppState，问问页的气泡才会跟着消失
                            AppState.shared.clearAsk()
                            reload()
                        } label: {
                            Label("清空全部", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Theme.text2)
                    }
                }
            }
            .sheet(item: $detail) { t in
                AskThreadDetail(thread: t) { q in
                    detail = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onPick?(q)
                        dismiss()
                    }
                }
            }
            .onAppear { reload() }
        }
    }

    // MARK: - 搜索框

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.dim2)
            TextField("搜问过的话、答案里的字", text: $keyword)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .focused($searchFocused)
                .submitLabel(.search)
                // 关键字只在本地过滤 threads，不需要每敲一个字就查 600 行历史
            if !keyword.isEmpty {
                Button {
                    keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.dim2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: keyword.isEmpty ? "clock" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(Theme.dim2)
            Text(keyword.isEmpty ? "还没有问过" : "没搜到")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text2)
            if !keyword.isEmpty {
                Text("换个说法，或者只搜一两个关键字")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 一行

    private func row(_ t: AskThread) -> some View {
        Button {
            detail = t
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(t.question.text)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    Text(clock(t.question.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim2)
                }
                if let a = t.answer {
                    Text(a.text.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("没有答出来")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.bad.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIPasteboard.general.string = t.question.text
            } label: {
                Label("复制问题", systemImage: "doc.on.doc")
            }
            if let a = t.answer {
                Button {
                    UIPasteboard.general.string = a.text
                } label: {
                    Label("复制答案", systemImage: "doc.on.doc")
                }
            }
            Button(role: .destructive) {
                Store.shared.deleteAsk(id: t.question.id)
                if let a = t.answer { Store.shared.deleteAsk(id: a.id) }
                AppState.shared.refresh()
                reload()
            } label: {
                Label("删除这一条", systemImage: "trash")
            }
        }
    }

    // MARK: - 数据

    private func reload() {
        // 先取完整的最近对话再按「问题或答案」筛选。先按消息搜索会
        // 把没有命中关键字的另一半丢掉，导致答案配错问题或显示占位问题。
        results = Store.shared.askMessages(limit: 600)
    }

    private var groups: [DayGroup] {
        var order: [String] = []
        var map: [String: [AskThread]] = [:]
        for t in threads {
            let d = DayKey.of(t.question.createdAt)
            if map[d] == nil {
                order.append(d)
                map[d] = []
            }
            map[d]?.append(t)
        }
        return order.map { DayGroup(id: $0, day: $0, items: map[$0] ?? []) }
    }

    /// 把 me / ai 两条消息配成一轮对话，新的排前面
    private var threads: [AskThread] {
        var out: [AskThread] = []
        for m in results {
            if m.role == .me {
                out.append(AskThread(id: m.id, question: m, answer: nil))
            } else if let last = out.popLast() {
                out.append(AskThread(id: last.id, question: last.question, answer: m))
            } else {
                // 只命中答案（关键词只出现在涛声的回答里）时，前面没有 me 可配，
                // 按时间往前找最近的一条提问配成一轮，别把这条答案丢掉。
                let q = results.last { $0.role == .me && $0.createdAt <= m.createdAt }
                if let q = q {
                    out.append(AskThread(id: q.id, question: q, answer: m))
                } else {
                    out.append(AskThread(id: m.id,
                                         question: AskMessage(id: m.id, role: .me, text: "（没有找到对应的问题）",
                                                              citations: [], createdAt: m.createdAt),
                                         answer: m))
                }
            }
        }
        let k = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = k.isEmpty ? out : out.filter {
            $0.question.text.localizedCaseInsensitiveContains(k) ||
            ($0.answer?.text.localizedCaseInsensitiveContains(k) ?? false)
        }
        return matched.reversed()
    }

    private func dayLabel(_ day: String) -> String {
        let today = DayKey.of(Date())
        if day == today { return "今天" }
        let cal = Calendar.current
        if let d = DayKey.date(from: day) {
            if cal.isDateInYesterday(d) { return "昨天" }
            return Fmt.monthDay.string(from: d)
        }
        return day
    }

    private func clock(_ d: Date) -> String { Fmt.hm.string(from: d) }
}

// MARK: - 一轮对话详情

struct AskThreadDetail: View {
    let thread: AskThread
    var onAskAgain: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("你问")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                        Text(thread.question.text)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))

                    if let a = thread.answer {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("涛声答")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.dim)
                            Text(a.text)
                                .font(.system(size: 14.5))
                                .foregroundStyle(Theme.text)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))

                        if !a.citations.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("原话出处")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.dim)
                                ForEach(Array(a.citations.enumerated()), id: \.offset) { i, c in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("\(i + 1)")
                                            .font(.system(size: 10.5, weight: .bold))
                                            .foregroundStyle(Theme.accent)
                                            .frame(width: 16, height: 16)
                                            .background(Theme.accentSoft)
                                            .clipShape(Circle())
                                        Text(c)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(Theme.text2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Theme.cardSoft)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        }
                    } else {
                        Text("这一轮没有答出来。检查一下大模型设置再问一次。")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    }

                    Button {
                        onAskAgain?(thread.question.text)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .semibold))
                            Text("再问一次")
                                .font(.system(size: 14.5, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.heroGradient)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle(clock(thread.question.createdAt))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(Theme.text2)
                }
            }
        }
    }

    private func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }
}
