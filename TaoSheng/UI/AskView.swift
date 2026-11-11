import SwiftUI

struct AskView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings

    @State private var input = ""
    @State private var sending = false
    @State private var errorText: String?
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
                        if app.askMessages.isEmpty && !sending {
                            intro
                        }
                        ForEach(app.askMessages) { m in
                            bubble(m).id(m.id)
                        }
                        if sending {
                            thinking.id("thinking")
                        }
                        if let e = errorText {
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
                .onChange(of: sending) { _ in
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
    }

    // MARK: - 头部
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("问问")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(settings.effectiveLLM.key.isEmpty
                     ? "还没配大模型，去设置 → 转写与大模型"
                     : "答句都带原话出处 · \(settings.llmModel)")
                    .font(.system(size: 12))
                    .foregroundStyle(settings.effectiveLLM.key.isEmpty ? Theme.warn : Theme.dim)
            }
            Spacer()
            Button {
                app.clearAsk()
                errorText = nil
            } label: {
                Image(systemName: "arrow.clockwise")
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
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
                .onSubmit { send() }
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
                Image(systemName: sending ? "ellipsis" : "arrow.up")
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
        .padding(.bottom, kb.isVisible ? 8 : 76)
        .background(Theme.bg)
    }

    private var canSend: Bool {
        !sending && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !sending else { return }
        input = ""
        errorText = nil
        sending = true
        app.recordAsk(question: q)

        Task {
            do {
                let ans = try await AskEngine.shared.ask(q)
                await MainActor.run {
                    app.recordAnswer(text: ans.text, citations: ans.citations.map { "\($0.timeText) \($0.speaker.isEmpty ? "" : "· \($0.speaker) ")\($0.transcript.prefix(40))" })
                    sending = false
                }
            } catch {
                await MainActor.run {
                    errorText = "问不出来：\(error.localizedDescription)"
                    sending = false
                }
            }
        }
    }
}
