import SwiftUI

// MARK: - 专题类型（TopicUi.kt TopicKind）

enum RsTopicKind: String, CaseIterable, Identifiable {
    case meeting, training, call, script, normal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meeting: return "会议"
        case .training: return "培训"
        case .call: return "通话·访谈"
        case .script: return "口播稿"
        case .normal: return "普通"
        }
    }

    var symbol: String {
        switch self {
        case .meeting: return "person.2.wave.2"
        case .training: return "lightbulb"
        case .call: return "bubble.left.and.bubble.right"
        case .script: return "mic"
        case .normal: return "chart.bar.xaxis"
        }
    }

    /// 原版 kindIcon()：meeting / bulb / chat / mic / timeline
    var glyph: String {
        switch self {
        case .meeting: return "meeting"
        case .training: return "bulb"
        case .call: return "chat"
        case .script: return "mic"
        case .normal: return "timeline"
        }
    }

    var hint: String {
        switch self {
        case .meeting: return "多人讨论，结束后出会议纪要"
        case .training: return "一人主讲，不区分说话人，出培训笔记"
        case .call: return "两人一来一回，出通话记录"
        case .script: return "对着手机口述，出整理版和原话版两份稿子"
        case .normal: return "合成一件事，不出纪要"
        }
    }

    var buttonTitle: String { self == .call ? "开始访谈" : "开始\(title)" }

    /// 底层只有会议 / 培训两种收尾方式：会议分人出速记，其余按培训出笔记
    var mode: CaptureMode {
        switch self {
        case .meeting: return .meeting
        case .training: return .training
        case .call: return .call
        case .script: return .script
        case .normal: return .normal
        }
    }
}

/// 五格类型选择（TopicStartPanel 的 TopicKindChoice）
struct RsTopicKindPicker: View {
    @Binding var kind: RsTopicKind

    var body: some View {
        HStack(spacing: 8) {
            ForEach(RsTopicKind.allCases) { k in
                let on = k == kind
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { kind = k }
                } label: {
                    VStack(spacing: 7) {
                        RsSkillIcon(icon: k.glyph, size: 30)
                        Text(k.title.replacingOccurrences(of: " / ", with: "·"))
                            .font(.system(size: 12, weight: on ? .semibold : .medium))
                            .foregroundStyle(on ? Rs.text : Rs.text2)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(on ? Rs.accentSoft : Rs.fill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(on ? Rs.accent : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(RsSpringButtonStyle())
            }
        }
    }
}
/// 名字输入（TopicUi.kt NameInput）
struct RsNameInput: View {
    @Binding var text: String
    var placeholder: String = "名字，例如：产品讨论会（可不填）"

    var body: some View {
        TextField(placeholder, text: $text)
            .font(Rs.body)
            .foregroundStyle(Rs.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Rs.fill)
            )
    }
}

/// 什么时候结束（TopicUi.kt 四选）
struct RsEndChoices: View {
    @Binding var choice: Int     // 0 我来结束 / 30 / 60 / 120

    private let options: [(String, Int)] = [("我来结束", 0), ("30 分钟", 30), ("1 小时", 60), ("2 小时", 120)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.1) { label, minutes in
                RsChoicePill(text: label, on: choice == minutes) {
                    withAnimation(.easeOut(duration: 0.14)) { choice = minutes }
                }
            }
        }
    }
}

// MARK: - 正在聆听（ListenSheet.kt）

struct RsListenSheet: View {
    @ObservedObject private var capture = CaptureEngine.shared
    @ObservedObject private var quiet = RsQuiet.shared
    @ObservedObject private var flow = ListenFlow.shared


    @State private var pauseMinutes = RsQuiet.shared.lastPauseMinutes
    @State private var kind: RsTopicKind = .meeting
    @State private var name = ""
    @State private var endChoice = 0
    @State private var eraseMinutes = 10
    @State private var confirmErase = false

    /// 关掉抽屉（换成自定义抽屉后不再用环境 dismiss）
    var onClose: () -> Void = {}



    private let pauseChoices = [15, 30, 60, 120]
    private let eraseChoices = [10, 30, 60]

    /// 截图模式：模拟器没有麦克风，按原版显示「正在聆听」
    private var listening: Bool { capture.isRunning || ShotMode.screen == "rs-listen" }

    private var statusText: String {
        if quiet.isQuiet { return "已暂停 · \(quiet.resumeText) 恢复" }
        if flow.isRecording { return "正在录音" }
        if listening { return "正在聆听" }
        return "没在聆听"
    }

    var body: some View {
        RsSheetBody(title: quiet.isQuiet ? "已暂停" : (listening ? "正在聆听" : "没在聆听"),
                    subtitle: quiet.isQuiet ? "到 \(quiet.resumeText) 自动恢复" : "只在有人说话时录音") {
            if flow.isRecording {
                recordingTopicPanel
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    RsLabel("暂停多久")
                    HStack(spacing: 8) {
                        ForEach(pauseChoices, id: \.self) { m in
                            RsSolidPill(text: m < 60 ? "\(m) 分钟" : "\(m / 60) 小时", on: pauseMinutes == m) {
                                pauseMinutes = m
                            }
                        }
                    }
                    RsActionButton(title: quiet.isQuiet ? "恢复聆听" : "暂停") {
                        if quiet.isQuiet {
                            quiet.resume()
                        } else {
                            quiet.pause(minutes: pauseMinutes)
                        }
                        onClose()
                    }
                }
                divider
                topicSection
            }
            divider
            eraseSection
        }
    }

    private var divider: some View {
        Rectangle().fill(Rs.separator).frame(height: 0.5)
    }

    // 专题录音：开始面板
    private var topicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            RsLabel("专题录音")
            RsTopicKindPicker(kind: $kind)
            Text(kind.hint)
                .font(Rs.subhead)
                .foregroundStyle(Rs.text2)
                .fixedSize(horizontal: false, vertical: true)
            RsNameInput(text: $name)
            RsLabel("什么时候结束")
            RsEndChoices(choice: $endChoice)
            RsActionButton(title: kind.buttonTitle, enabled: !flow.working) {
                start()
            }
            // 预约专题、忘了点开始都还没做——不摆只有提示的假入口（见 INDEX 的「未实现」）
        }
    }

    private var recordingTopicPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            RsLabel("这一场")
            if let t = flow.topicName {
                Text(t).font(Rs.subhead).foregroundStyle(Rs.text2)
            }
            HStack(spacing: 8) {
                Text(flow.current?.mode.title ?? "会议")
                    .font(Rs.headline)
                    .foregroundStyle(Rs.text)
                Text(flow.statusText)
                    .font(Rs.subhead)
                    .foregroundStyle(Rs.accent)
                Spacer(minLength: 0)
            }
            RsActionButton(title: "结束这一场", kind: .primary) {
                flow.stop()
                onClose()
            }
            Text("结束后整场分说话人，再整理成速记。")
                .font(Rs.subhead)
                .foregroundStyle(Rs.text2)
        }
    }

    // 删掉哪段时间
    private var eraseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            RsLabel("不想留的话：删掉哪段时间")
            HStack(spacing: 8) {
                ForEach(eraseChoices, id: \.self) { m in
                    RsSolidPill(text: "\(m) 分钟", on: eraseMinutes == m) { eraseMinutes = m }
                }
            }
            RsActionButton(title: "删掉最近 \(eraseMinutes) 分钟的录音", kind: .danger) {
                confirmErase = true
            }
            // eraseRecent 只删段和音频；整理出的事件要等当天录音全删光才会一起清掉，说明不能夸大
            Text("录音和原话会彻底删除，无法恢复。已经整理出的事件不会跟着删，要删请在时间线里点开那件事删除。")
                .font(Rs.caption)
                .foregroundStyle(Rs.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog("删掉最近 \(eraseMinutes) 分钟的录音？", isPresented: $confirmErase,
                            titleVisibility: .visible) {
            Button("删除", role: .destructive) { erase() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("录音和原话删掉后无法恢复。")
        }
    }

    private func erase() {
        let minutes = eraseMinutes
        let n = Store.shared.eraseRecent(minutes: minutes)
        AppState.shared.refresh()
        RsToast.shared.show(n > 0 ? "已删掉 \(n) 段录音" : "最近 \(minutes) 分钟没有录音")
        onClose()
    }

    private func start() {
        if !(name.trimmingCharacters(in: .whitespaces).isEmpty) {
            UserDefaults.standard.set(name.trimmingCharacters(in: .whitespaces), forKey: "rsTopicName")
        } else {
            UserDefaults.standard.removeObject(forKey: "rsTopicName")
        }
        if quiet.isQuiet { quiet.resume() }
        flow.start(mode: kind.mode, topicName: name, endMinutes: endChoice)
        onClose()
    }
}

// MARK: - 专题（TopicUi.kt TopicSheet）

struct RsTopicSheet: View {
    @ObservedObject private var flow = ListenFlow.shared
    @ObservedObject private var app = AppState.shared

    var onClose: () -> Void = {}

    @State private var tab = 0
    @State private var kind: RsTopicKind = .meeting
    @State private var name = ""
    @State private var endChoice = 0
    @State private var sessions: [ListenSession] = []

    var body: some View {
        RsSheetBody(title: "专题") {
            HStack(spacing: 0) {
                ForEach([("开始专题", 0), ("专题记录", 1)], id: \.1) { label, i in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { tab = i }
                    } label: {
                        Text(label)
                            .font(.system(size: 13, weight: tab == i ? .semibold : .regular))
                            .foregroundStyle(tab == i ? Rs.text : Rs.text2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Capsule(style: .continuous).fill(tab == i ? Rs.card : Color.clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Capsule(style: .continuous).fill(Rs.track))

            if tab == 0 { startPanel } else { recordList }
        }
        .onAppear { sessions = Store.shared.sessions(limit: 100) }
    }

    private var startPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            RsTopicKindPicker(kind: $kind)
            Text(kind.hint)
                .font(Rs.subhead)
                .foregroundStyle(Rs.text2)
                .fixedSize(horizontal: false, vertical: true)
            RsNameInput(text: $name)
            RsLabel("什么时候结束")
            RsEndChoices(choice: $endChoice)
            RsActionButton(title: kind.buttonTitle, enabled: !flow.working) {
                if RsQuiet.shared.isQuiet { RsQuiet.shared.resume() }
                flow.start(mode: kind.mode, topicName: name, endMinutes: endChoice)
                onClose()
            }
            // 预约专题 / 忘了点开始还没做，入口先不摆在面板上（见 INDEX 的「未实现」）
        }
    }

    private var recordList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if sessions.isEmpty {
                Text("还没有专题记录。开始一个专题，结束后会出现在这里。")
                    .font(Rs.body)
                    .foregroundStyle(Rs.text2)
            } else {
                ForEach(sessions) { s in
                    HStack(spacing: 10) {
                        Image(systemName: s.mode.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Rs.accent)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Rs.accentSoft))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(TopicStore.name(sessionId: s.id) ?? s.mode.title)
                                .font(Rs.headline)
                                .foregroundStyle(Rs.text)
                            Text("\(s.day) \(s.timeRangeText) · \(s.durationText) · \(s.mode.title)")
                                .font(Rs.caption)
                                .foregroundStyle(Rs.text3)
                        }
                        Spacer(minLength: 0)
                        Text(s.state.text)
                            .font(Rs.caption)
                            .foregroundStyle(s.state == .done ? Rs.good : Rs.accent)
                            .lineLimit(1)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Rs.fill)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Rs.separator, lineWidth: 0.5))
                    )
                }
            }
        }
    }

    private func entry(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Rs.text3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Rs.subhead).foregroundStyle(Rs.text)
                Text(detail).font(Rs.caption).foregroundStyle(Rs.text3)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Rs.fill))
    }
}

// MARK: - 搜索记录（RecordSearchSheet.kt）

struct RsRecordSearchSheet: View {
    var onClose: () -> Void = {}
    @ObservedObject private var player = SegmentPlayer.shared

    @State private var query = ""
    @State private var segments: [Segment] = []
    @State private var events: [MemoryEvent] = []

    var body: some View {
        RsSheetBody(title: "搜索记录") {
            HStack(spacing: 9) {
                TextField("搜原话或事件，空格分开多个词", text: $query)
                    .font(Rs.body)
                    .foregroundStyle(Rs.text)
                    .submitLabel(.search)
                    .onSubmit { run() }
                    .onChange(of: query) { _ in run() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: "EDE9E3")))

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("例如：合同、老王周五、报销")
                    .font(Rs.subhead)
                    .foregroundStyle(Rs.text3)
            } else if segments.isEmpty && events.isEmpty {
                Text("没有找到「\(query)」。")
                    .font(Rs.subhead)
                    .foregroundStyle(Rs.text2)
            }

            if !events.isEmpty {
                RsLabel("事件")
                ForEach(events) { e in
                    Button {
                        RsEventPanel.shared.open(e)
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(e.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Rs.text)
                                    .multilineTextAlignment(.leading)
                                Text(eventLine(e))
                                    .font(Rs.caption)
                                    .foregroundStyle(Rs.text2)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Rs.text3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Rs.fill))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !segments.isEmpty {
                RsLabel("原话")
                ForEach(segments) { s in
                    let on = player.isPlaying(s.id)
                    Button {
                        player.toggle(segment: s)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: on ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Rs.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(DayKey.display(s.day)) \(s.timeText)")
                                    .font(Rs.caption)
                                    .foregroundStyle(Rs.text3)
                                Text(s.transcript)
                                    .font(Rs.body)
                                    .foregroundStyle(Rs.text)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Rs.fill))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(on ? "暂停播放" : "播放这段录音")
                }
            }
        }
    }

    private func eventLine(_ e: MemoryEvent) -> String {
        let head = "\(DayKey.display(e.day)) \(e.timeText)"
        return e.summary.isEmpty ? head : head + " · " + e.summary
    }

    private func run() {
        // 全角空格也算分隔：中文输入法里打出来的空格常常是全角的
        let words = query.split(whereSeparator: { $0 == " " || $0 == "\u{3000}" }).map(String.init)
        guard let first = words.first else { segments = []; events = []; return }
        // Store.search 是整串 LIKE，多个词直接传进去永远搜不到：先按第一个词取候选，再要求每个词都出现
        segments = Array(Store.shared.search(first, limit: 200)
            .filter { s in words.allSatisfy { s.transcript.localizedCaseInsensitiveContains($0) } }
            .prefix(20))
        events = Array(Store.shared.events(limit: 400).filter { e in
            words.allSatisfy { w in
                e.title.localizedCaseInsensitiveContains(w) || e.summary.localizedCaseInsensitiveContains(w)
                    || e.points.contains { $0.localizedCaseInsensitiveContains(w) }
            }
        }.prefix(20))
    }
}
