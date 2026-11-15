import SwiftUI

// MARK: - 设置子页（SettingsScreen.kt SubPageBar + 分组白卡）

struct RsSubPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    /// 截图模式：rs-xxx-b / -c 分别停在页面 55% 处与最底部，0 表示不滚
    static var fracForShot: CGFloat {
        guard let s = ShotMode.screen else { return 0 }
        if s.hasSuffix("-c") { return 1.0 }
        if s.hasSuffix("-b") { return 0.55 }
        return 0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    Text("‹ 设置")
                        .font(Rs.headline)
                        .foregroundStyle(Rs.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text(title)
                    .font(Rs.headline)
                    .foregroundStyle(Rs.text)
                Spacer(minLength: 0)
                Color.clear.frame(width: 64, height: 1)
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.top, 6)
            .padding(.bottom, 2)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content()
                    Color.clear.frame(height: 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .background(RsScrollFrac(frac: RsSubPage.fracForShot).frame(width: 0, height: 0))
            }
            .scrollIndicators(.hidden)
        }
        .background(Rs.bg)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// 分组：灰色小标题 + 白卡（SettingsHome.kt GroupSection）
struct RsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(Rs.section)
                .foregroundStyle(Rs.text3)
                .padding(.leading, 4)
            RsCard(padding: EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0)) {
                content()
            }
        }
    }
}

struct RsRowDivider: View {
    var inset: CGFloat = 16
    var body: some View {
        Rectangle().fill(Rs.separator).frame(height: 0.5).padding(.leading, inset)
    }
}

/// 开关行
struct RsToggleRow: View {
    let title: String
    var note: String?
    @Binding var on: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Rs.body).foregroundStyle(Rs.text)
                if let note {
                    Text(note).font(Rs.caption).foregroundStyle(Rs.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $on).labelsHidden().tint(Rs.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

/// 说明行（只读）
struct RsNoteRow: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Rs.caption)
            .foregroundStyle(Rs.text3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }
}

/// 小标题（段落内的 Label）
struct RsFormLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Rs.text3)
            .padding(.leading, 4)
            .padding(.top, 4)
    }
}

/// 输入行
struct RsFieldRow: View {
    let title: String
    var placeholder: String = ""
    @Binding var text: String
    var secure: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(Rs.body).foregroundStyle(Rs.text)
            Spacer(minLength: 8)
            if secure {
                SecureField(placeholder, text: $text)
                    .font(Rs.subhead)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 190)
            } else {
                TextField(placeholder, text: $text)
                    .font(Rs.subhead)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 190)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// 胶囊选择（一排，等宽）
struct RsPillRow: View {
    let options: [(String, Int)]
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.1) { label, value in
                RsSolidPill(text: label, on: selected == value) {
                    withAnimation(.easeOut(duration: 0.14)) { selected = value }
                }
            }
        }
    }
}

// MARK: - 子页公用件（照 SettingsScreen / TranscriptScreen 的卡内结构）

/// 分段控件：浅灰 track + 白色滑块（原版 Segmented）
struct RsSegControl: View {
    let options: [String]
    @Binding var index: Int
    /// 原版里有的分段控件只有内容宽（语音转写的 豆包 / 本地 / 自定义），有的撑满一行
    var fit: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, t in
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { index = i }
                } label: {
                    Text(t)
                        .font(.system(size: 13, weight: i == index ? .semibold : .regular))
                        .foregroundStyle(i == index ? Rs.text : Rs.text2)
                        .frame(maxWidth: fit ? nil : .infinity)
                        .padding(.horizontal, fit ? 18 : 0)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(i == index ? Rs.card : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color(hex: "EDE9E3")))
    }
}

/// 选项胶囊：默认选中浅橙底橙字；solid = 原版那种选中实心橙底白字
struct RsOptPill: View {
    let text: String
    var on: Bool
    var solid: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? (solid ? Color.white : Rs.accent) : Rs.text2)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(on ? (solid ? Rs.accent : Rs.accentSoft) : Rs.fill))
        }
        .buttonStyle(.plain)
    }
}

/// 强调 / 次要按钮（现在转写 / 导入录音 …）
struct RsBtn: View {
    let text: String
    var filled: Bool = true
    var danger: Bool = false
    var small: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: small ? 12.5 : 13, weight: .semibold))
                .foregroundStyle(danger ? Rs.critical : (filled ? Color.white : Rs.accent))
                .padding(.horizontal, small ? 12 : 16)
                .padding(.vertical, small ? 6 : 10)
                .background(
                    Capsule().fill(danger ? Rs.critical.opacity(0.12) : (filled ? Rs.accent : Rs.accentSoft))
                )
        }
        .buttonStyle(.plain)
    }
}

/// 卡里的「标题 + 次要值 + ›」行（云端转写 / 原声 / 录音包 / 外接设备 …）
struct RsInfoRow: View {
    let title: String
    let value: String
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Rs.text2)
                    .frame(width: 72, alignment: .leading)
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(Rs.text2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text("›")
                    .font(.system(size: 15))
                    .foregroundStyle(Rs.text3)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 单行：左边黑色正常字号标题，右边右对齐的值 + ›（原版「外接设备」这类行）
struct RsValueRow: View {
    let title: String
    let value: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(Rs.body)
                    .foregroundStyle(Rs.text)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(Rs.text3)
                    .lineLimit(1)
                Text("›")
                    .font(.system(size: 15))
                    .foregroundStyle(Rs.text3)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 卡标题（正文强调）
struct RsCardTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Rs.body)
            .foregroundStyle(Rs.text)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }
}

/// 卡内说明
struct RsCardHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Rs.caption)
            .foregroundStyle(Rs.text3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
    }
}

/// 单选圆点
struct RsRadio: View {
    var on: Bool
    var body: some View {
        ZStack {
            Circle().stroke(on ? Rs.accent : Rs.text3.opacity(0.5), lineWidth: 1.6)
                .frame(width: 20, height: 20)
            if on {
                Circle().fill(Rs.accent).frame(width: 10, height: 10)
            }
        }
    }
}

/// 小绿点 + 文字
struct RsDotText: View {
    let text: String
    var color: Color = Rs.good
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 13)).foregroundStyle(Rs.text2)
        }
    }
}

// MARK: - 录音与后台（VerifyScreen.kt）

/// 卡外小标题（原版 verify 页的分组标题：左边标题、右边状态）
struct RsSectionLabel: View {
    let title: String
    var trailing: String? = nil
    var trailingColor: Color? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Rs.text2)
            Spacer(minLength: 0)
            if let t = trailing {
                Text(t)
                    .font(Rs.caption)
                    .foregroundStyle(trailingColor ?? Rs.text3)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// 卡外灰色说明
struct RsFootNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Rs.caption)
            .foregroundStyle(Rs.text3)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

/// 圆形首字头像（录音输入里「手 / 自」那两个小圆）
struct RsMiniAvatar: View {
    let text: String
    var body: some View {
        ZStack {
            Circle().fill(Rs.accentSoft).frame(width: 34, height: 34)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Rs.accent)
        }
    }
}

struct RsRecordingPage: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var capture = CaptureEngine.shared
    @ObservedObject private var flow = ListenFlow.shared
    @AppStorage("captureWanted") private var captureWanted = true
    @State private var inputAuto = false
    @AppStorage("rsVoiceContext") private var voiceCtx = false

    var body: some View {
        RsSubPage(title: "录音与后台") {
            statusCard

            RsSectionLabel(title: "停录时段", trailing: settings.silenceWindowOn ? "已开启" : "未开启")
            stopWindowCard
            RsFootNote(text: "时段内不录音，到点自动恢复；时段内点「现在恢复」只对这一次有效。")

            RsSectionLabel(title: "录音输入")
            inputCard
            RsDotText(text: "正在用：手机麦克风")
                .padding(.horizontal, 4)
            RsFootNote(text: "插上 Type-C 麦克风或领夹麦接收器、连上蓝牙耳机后，会出现在这里。")
            externalCard

            RsSectionLabel(title: "语音输入")
            voiceInputCard

            importCard
            backendCard
        }
    }

    // 顶部状态卡
    private var statusCard: some View {
        let listening = capture.isRunning || ShotMode.screen?.hasPrefix("rs-recording") == true
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(listening ? Rs.good : Rs.text3).frame(width: 9, height: 9)
                Text(listening ? (capture.isSpeaking ? "正在录音" : "正在聆听") : "没在聆听")
                    .font(Rs.headline)
                    .foregroundStyle(Rs.text)
                Spacer(minLength: 0)
                Text("手机麦克风")
                    .font(Rs.caption)
                    .foregroundStyle(Rs.text3)
            }
            Text(listening ? "安静中 · 已持续 " + uptimeText : "点了「开始聆听」才会录")
                .font(Rs.subhead)
                .foregroundStyle(Rs.text2)
            RsDotLine(active: listening)
                .frame(height: 10)
                .padding(.vertical, 2)
            HStack(spacing: 10) {
                RsBtn(text: "暂停 1 小时", filled: false) {
                    RsQuiet.shared.pause(minutes: 60)
                }
                RsBtn(text: "停止", filled: false, danger: false) {
                    captureWanted = false
                    if flow.isRecording { flow.stop() }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    private var uptimeText: String {
        // 截图里原版是「4小时32分」这种紧凑写法，模拟器没有麦克风时也用同一串
        if ShotMode.active && capture.startedAt == nil { return "4小时32分" }
        guard let start = capture.startedAt else { return "0分钟" }
        let m = Int(Date().timeIntervalSince(start) / 60)
        if m < 60 { return "\(m)分钟" }
        return "\(m / 60)小时\(m % 60)分"
    }

    // 停录时段
    private var stopWindowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("睡眠").font(Rs.body).foregroundStyle(Rs.text)
                    Text("\(settings.silenceStartHour):00 – 次日 \(settings.silenceEndHour):00 · 每天")
                        .font(Rs.caption).foregroundStyle(Rs.text3)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $settings.silenceWindowOn).labelsHidden().tint(Rs.accent)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)
            RsRowDivider(inset: 18)
            Button {
                settings.silenceWindowOn = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Rs.accentSoft)
                            .frame(width: 24, height: 24)
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Rs.accent)
                    }
                    Text("添加时段").font(.system(size: 13)).foregroundStyle(Rs.accent)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    // 录音输入：左侧圆形头像 + 标题说明，右侧单选圈
    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputRow(avatar: "手", title: "手机麦克风", note: "默认", on: !inputAuto) {
                inputAuto = false
            }
            RsRowDivider(inset: 18)
            inputRow(avatar: "自", title: "自动", note: "接上 USB 或有线麦克风就用它，拔掉自动回到手机", on: inputAuto) {
                inputAuto = true
            }
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    private func inputRow(avatar: String, title: String, note: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RsMiniAvatar(text: avatar)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Rs.body).foregroundStyle(Rs.text)
                    Text(note)
                        .font(Rs.caption)
                        .foregroundStyle(Rs.text3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                RsRadio(on: on)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // 外接设备单独一张卡
    private var externalCard: some View {
        VStack(spacing: 0) {
            RsValueRow(title: "外接设备", value: "未连接")
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    // 语音输入
    private var voiceInputCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            RsToggleRow(title: "语音输入时记上下文", note: "说之前那几句一起发过去，听懂上下文；语音输入用来记事，不进原话。",
                        on: $voiceCtx)
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    // 自动导入文件夹（原版：卡外小标题，卡里只有一行「＋ 添加文件夹」，说明在卡外灰字）
    private var importCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RsSectionLabel(title: "自动导入文件夹")
            Button { } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Rs.accentSoft).frame(width: 24, height: 24)
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Rs.accent)
                    }
                    Text("添加文件夹").font(.system(size: 15)).foregroundStyle(Rs.accent)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))

            RsFootNote(text: "录音笔 App、录音机把录音存在哪，就选哪个文件夹。新录音会自动导入转写，原文件不动、不删；同一个录音只导入一次。")
            RsFootNote(text: "大约每 15 分钟看一次，打开涛声时也会看；录音写完一两分钟后才会导入。")
        }
    }

    // 后台设置（原版：小标题在卡外，右侧橙色完成数；完成项浅绿方块 ✓，未完成项数字方块，按钮在该行右侧）
    private var backendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RsSectionLabel(title: "后台设置", trailing: "3 / 4 已完成", trailingColor: Rs.accent)
            VStack(alignment: .leading, spacing: 0) {
                backendItem("麦克风权限", "在应用权限里允许使用麦克风。", done: true)
                backendItem("通知权限", "允许通知，并允许录音中断提醒显示。", done: true)
                backendItem("锁屏继续录音", "使用后台音频，锁屏后仍会继续录音。", done: true)
                backendItem("低电量模式", "低电量模式下系统可能挂起后台录音，录音前先关掉。", done: false,
                            action: "我已设置") { }
            }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
        }
    }

    private func backendItem(_ title: String, _ note: String, done: Bool,
                             action: String? = nil, onAction: @escaping () -> Void = {}) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(done ? Color(hex: "E4F3E8") : Rs.fill)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Rs.good)
                } else {
                    Text("4").font(.system(size: 12, weight: .semibold)).foregroundStyle(Rs.text3)
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Rs.body).foregroundStyle(Rs.text)
                Text(note).font(Rs.caption).foregroundStyle(Rs.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let action {
                Button(action: onAction) {
                    Text(action)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Rs.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Rs.accentSoft))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

// MARK: - 原话与转写（TranscriptScreen.kt）

struct RsTranscriptPage: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var queue = TranscribeQueue.shared
    @ObservedObject private var net = NetWatcher.shared
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var store = StoreStatsProxy.shared

    @State private var source = 0
    @State private var cadence = 2
    @State private var showKey = false
    @State private var keyDraft = ""

    var body: some View {
        RsSubPage(title: "原话与转写") {
            queueCard
            transcribeCard
            cadenceCard
            switchCard
            speakerCard
            testCard
            hotwordCard
            rawCard
        }
    }

    // 队列状态卡
    private var queueCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(queueDot).frame(width: 9, height: 9)
                    Text(queueTitle).font(Rs.headline).foregroundStyle(Rs.text)
                    Spacer(minLength: 0)
                }
                Text(queueNote).font(Rs.subhead).foregroundStyle(Rs.text2)
                HStack(spacing: 10) {
                    RsBtn(text: "现在转写") { queue.transcribeNow() }
                    RsBtn(text: "导入录音", filled: false) { }
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)
            }
            .padding(18)
            RsRowDivider(inset: 18)
            RsInfoRow(title: "云端转写", value: ShotMode.active ? "今天 29 分 · 近 30 天 314 分 · 约 ¥4.2" : "今天 \(todayMinutes) 分 · 近 30 天 \(monthMinutes) 分 · 约 ¥\(costText)")
            RsRowDivider(inset: 18)
            RsInfoRow(title: "原声", value: "保留 \(settings.keepAudioDays > 0 ? "\(settings.keepAudioDays) 天" : "一直留") · 重点长期保留 · 占用 \(audioSize)")
            RsRowDivider(inset: 18)
            RsInfoRow(title: "录音包", value: "把手机里的原始录音打包导出")
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    private var queueDot: Color {
        if !settings.asrReady { return Rs.warning }
        if queue.busy { return Rs.accent }
        return queue.pendingCount > 0 ? Rs.accent : Rs.good
    }

    private var queueTitle: String {
        if !settings.asrReady { return "转写尚未就绪" }
        if queue.busy { return "正在转写…" }
        return queue.pendingCount > 0 ? "还有 \(queue.pendingCount) 段等着转" : "都转完了"
    }

    private var queueNote: String {
        var parts: [String] = []
        if let last = queue.lastRunAt { parts.append("上次 \(Fmt.hm.string(from: last))") }
        if let next = queue.nextRunAt {
            let mins = max(0, Int(next.timeIntervalSinceNow / 60))
            parts.append(mins == 0 ? "马上进行下一轮" : "约 \(mins) 分钟后下一轮")
        }
        if parts.isEmpty { return ShotMode.active ? "上次 今天 15:43 · 约 9 分钟后下一轮" : "还没有转写过" }
        return parts.joined(separator: " · ")
    }

    private var todayMinutes: Int { max(0, Int(store.todaySeconds / 60)) }
    private var monthMinutes: Int { max(0, Int(store.monthSeconds / 60)) }
    private var costText: String { String(format: "%.1f", Double(monthMinutes) * 0.012) }
    private var audioSize: String { ByteCountFormatter.string(fromByteCount: Int64(store.audioBytes), countStyle: .file) }

    // 语音转写
    private var transcribeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            RsCardTitle(text: "语音转写")
            HStack { RsSegControl(options: ["豆包", "本地", "自定义"], index: $source, fit: true) }
                .padding(.horizontal, 18)
            Divider().padding(.horizontal, 18).padding(.top, 12)
            Button { } label: {
                HStack {
                    Text("自定义请求头（可选）").font(.system(size: 13)).foregroundStyle(Rs.accent)
                    Text("›").font(.system(size: 15)).foregroundStyle(Rs.accent)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text(source == 2 ? "自定义服务密钥" : "豆包语音密钥")
                .font(Rs.body).foregroundStyle(Rs.text)
                .padding(.horizontal, 18)
                .padding(.top, 2)
            HStack(spacing: 12) {
                RsDotText(text: settings.asrReady ? "已填写" : "还没填")
                Spacer(minLength: 0)
                RsBtn(text: "更换", filled: false, small: true) { showKey = true }
                RsBtn(text: "清除", filled: false, small: true) { settings.asrKey = "" }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            RsCardHint(text: "只存在这台手机里，填好后任何地方都不再显示。")
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
        .sheet(isPresented: $showKey) {
            keySheet
        }
    }

    private var keySheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("填密钥").font(Rs.title).foregroundStyle(Rs.text)
            TextField("粘贴密钥", text: $keyDraft)
                .font(Rs.subhead)
                .textInputAutocapitalization(.never)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Rs.fill))
            HStack(spacing: 10) {
                RsBtn(text: "保存") {
                    settings.asrKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    showKey = false
                }
                RsBtn(text: "取消", filled: false) { showKey = false }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(260)])
        .background(Rs.bg)
    }

    // 多久转写一次
    private var cadenceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("多久转写一次").font(Rs.body).foregroundStyle(Rs.text)
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
            RsSegControl(options: ["实时", "15 分钟", "30 分钟", "自定义"],
                          index: Binding(get: { cadence }, set: { cadence = $0 }))
                .padding(.horizontal, 18)
            .padding(.bottom, 12)
            RsCardHint(text: "每 30 分钟把攒下的录音转写一次。整理成事件另在「模型与整理时间」里设置。")
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    // 两个开关
    private var switchCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            RsToggleRow(title: "只在 WiFi 下转写", note: "关掉后用流量也会上传，每小时录音约 10 MB",
                        on: $settings.wifiOnlyTranscribe)
            RsRowDivider(inset: 18)
            RsToggleRow(title: "外放声音时不转写", note: "手机扬声器在放视频、音乐时录到的先不转写，原话里可单段「仍然转写」；戴耳机不受影响",
                        on: Binding(get: { settings.skipWhenOutput }, set: { settings.skipWhenOutput = $0 }))
            RsRowDivider(inset: 18)
            RsToggleRow(title: "区分说话人与认人", note: "原话标出谁在说，认出「我」和已命名的人",
                        on: Binding(get: { settings.speakerSplitOn }, set: { settings.speakerSplitOn = $0 }))
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    // 培训专题入口
    private var speakerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("临时不区分说话人").font(Rs.body).foregroundStyle(Rs.text)
                        Text("一人讲、多人听时用，结束后出培训笔记").font(Rs.caption).foregroundStyle(Rs.text3)
                    }
                    Spacer(minLength: 0)
                    Text("开始培训专题 ›").font(.system(size: 13)).foregroundStyle(Rs.accent)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    // 测试一下
    private var testCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("测试一下").font(Rs.body).foregroundStyle(Rs.text)
                    Text("发一小段测试音频，确认密钥和服务可用").font(Rs.caption).foregroundStyle(Rs.text3)
                }
                Spacer(minLength: 0)
                RsBtn(text: "测试", filled: false) { }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    // 热词
    private var hotwordCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            RsCardTitle(text: "热词")
            HStack(spacing: 10) {
                TextField("输入词语，多个用逗号隔开", text: .constant(""))
                    .font(Rs.subhead)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Rs.fill))
                RsBtn(text: "添加", filled: false) { }
            }
            .padding(.horizontal, 18)
            RsCardHint(text: "豆包云端转写、手机本地转写和整理都会用到热词。")
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    // 录音原话
    private var rawCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("录音原话").font(Rs.body).foregroundStyle(Rs.text)
                Spacer(minLength: 0)
                Text("\(app.todaySegments.count) 段 · 已转 \(app.todaySegments.filter { $0.state == .transcribed }.count)")
                    .font(Rs.caption).foregroundStyle(Rs.text3)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)
            ForEach(Array(app.todaySegments.prefix(6))) { seg in
                HStack(alignment: .top, spacing: 12) {
                    Text(Fmt.hm.string(from: seg.startedAt))
                        .font(.subheadline).foregroundStyle(Rs.text2)
                        .frame(width: 52, alignment: .leading)
                    Text(seg.transcript.isEmpty ? "没有文字" : seg.transcript)
                        .font(Rs.body).foregroundStyle(Rs.text)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("· \(Int(seg.duration))秒").font(Rs.caption).foregroundStyle(Rs.text3)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                RsRowDivider(inset: 18)
            }
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }
}

// MARK: - 声纹与人物（VoiceprintUi.kt）

struct RsVoicePage: View {
    @ObservedObject private var app = AppState.shared
    @State private var localSplit = true   // 原版 local-asr「speakers-enabled」默认 true

    var body: some View {
        RsSubPage(title: "声纹与人物") {
            HStack(alignment: .firstTextBaseline) {
                Text("人物 · \(app.persons.count)").font(Rs.body).foregroundStyle(Rs.text2)
                Spacer(minLength: 0)
                RsBtn(text: "添加人物", filled: false) { }
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(app.persons) { p in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Theme.personColor(p.name).opacity(0.18)).frame(width: 40, height: 40)
                            Text(String(p.name.prefix(1)))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.personColor(p.name))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(Rs.body).foregroundStyle(Rs.text)
                            Text(p.sampleCount > 0 ? "\(p.sampleCount) 段样本" : "还没有声音")
                                .font(Rs.caption).foregroundStyle(Rs.text3)
                        }
                        Spacer(minLength: 0)
                        Text("›").font(.system(size: 15)).foregroundStyle(Rs.text3)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    RsRowDivider(inset: 18)
                }
            }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
            RsFootNote(text: "在原话里长按一句，选「这是谁」，就能指定人物并学习声音。")

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("本地多人分段").font(Rs.body).foregroundStyle(Rs.text)
                    Text("试用").font(.system(size: 12)).foregroundStyle(Rs.accent)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Rs.accentSoft))
                    Spacer(minLength: 0)
                    Toggle("", isOn: $localSplit).labelsHidden().tint(Rs.accent)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                RsCardHint(text: "本地转写时先分出不同的人。人多嘈杂时可能分错，长按原话可纠正。")
            }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))

            VStack(alignment: .leading, spacing: 0) {
                RsCardTitle(text: "样本声音")
                Text("暂无").font(Rs.body).foregroundStyle(Rs.text2)
                    .padding(.horizontal, 18)
                RsCardHint(text: "用来在人物详情里回放样本。清除后仍能照常认人，已有样本不能再回放。")
            }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))

            Text("还有 \(max(0, app.todaySegments.count)) 段等着匹配声音")
                .font(Rs.caption).foregroundStyle(Rs.text3)
                .padding(.horizontal, 4)
        }
    }
}

// MARK: - 环境音识别（EnvSoundViews.kt）

struct RsEnvPage: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        RsSubPage(title: "环境音识别") {
            Text("只分析已经录下的人声片段，在转写前判断一次；录音方式不变，旧录音不补算。全部在手机上完成，不上传。")
                .font(Rs.caption).foregroundStyle(Rs.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("环境音识别").font(Rs.body).foregroundStyle(Rs.text)
                        Text("打开后下载约 27 MB 的识别模型").font(Rs.caption).foregroundStyle(Rs.text3)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(get: { settings.envSoundOn }, set: { settings.envSoundOn = $0 }))
                        .labelsHidden().tint(Rs.accent)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
        }
    }
}

// MARK: - 足迹（LocationPage.kt）

struct RsLocationPage: View {
    @ObservedObject private var settings = Settings.shared
    @State private var tab = 0

    var body: some View {
        RsSubPage(title: "足迹") {
            VStack(alignment: .leading, spacing: 0) {
                RsToggleRow(title: "记录全天位置",
                            note: "跟随收音服务，约每 5 分钟记一个点；位置记录只存手机本地。",
                            on: Binding(get: { settings.locationOn }, set: { settings.locationOn = $0 }))
            }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))

            HStack(spacing: 0) {
                Button { } label: {
                    Text("‹").font(.system(size: 20, weight: .semibold)).foregroundStyle(Rs.text3)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text(Fmt.df("M月d日 EEE").string(from: Date()) + " · 今天")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Rs.text)
                Spacer(minLength: 0)
                Button { } label: {
                    Text("›").font(.system(size: 20, weight: .semibold)).foregroundStyle(Rs.text3)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("这一天").font(.system(size: 15, weight: .semibold)).foregroundStyle(Rs.text)
                    Spacer(minLength: 0)
                    RsSegControl(options: ["时间轴", "路线"], index: $tab)
                        .frame(width: 150)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                Text("这一天没有位置记录")
                    .font(Rs.subhead).foregroundStyle(Rs.text3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 78)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    locStat("0 分", "在家")
                    locStat("0 分", "外出")
                    locStat("0.0 km", "移动距离")
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 18)
            }
            .frame(minHeight: 260, alignment: .top)
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))

            VStack(alignment: .leading, spacing: 0) {
                RsCardTitle(text: "显示地名")
                RsCardHint(text: "把停留处的坐标发给手机系统的地理服务查地址；查过的地方存在本机，不重复查。")
                RsRowDivider(inset: 18)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("高德 Key（可选）").font(Rs.body).foregroundStyle(Rs.text)
                        Text("不填用系统地理服务；国内建议填高德 Web 服务 Key").font(Rs.caption).foregroundStyle(Rs.text3)
                    }
                    Spacer(minLength: 0)
                    RsBtn(text: "填写", filled: false) { }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
        }
    }

    private func locStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 20, weight: .semibold)).foregroundStyle(Rs.text)
            Text(label).font(Rs.caption).foregroundStyle(Rs.text3)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 模型与整理时间（ProvidersCard.kt + DigestTimingCard.kt）

struct RsModelPage: View {
    @ObservedObject private var settings = Settings.shared
    @State private var timing = 0
    @State private var interval = 1
    @State private var idleGap = 1
    @State private var maxGap = 1

    var body: some View {
        RsSubPage(title: "模型与整理时间") {
            providersCard
            VStack(alignment: .leading, spacing: 0) {
                RsCardTitle(text: "什么时候整理")
                RsCardHint(text: "把转写好的原话整理成一件件事。转写在「原话与转写」里单独设置。")
                HStack(spacing: 8) {
                    RsOptPill(text: "按间隔", on: timing == 0, solid: true) { timing = 0 }
                    RsOptPill(text: "按时间点", on: timing == 1, solid: true) { timing = 1 }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                if timing == 0 {
                    Text("多久整理一次").font(Rs.body).foregroundStyle(Rs.text)
                        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 8)
                    RsSegControl(options: ["15 分钟", "30 分钟", "60 分钟", "自定义"], index: $interval)
                        .padding(.horizontal, 18)
                    RsCardHint(text: "整理要等转写完成；转写间隔比整理长时，以转写为准。")
                } else {
                    Text("每天整理").font(Rs.body).foregroundStyle(Rs.text)
                        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 8)
                    HStack(spacing: 8) {
                        ForEach(Array(["21:00", "22:00", "23:00"].enumerated()), id: \.offset) { i, label in
                            RsOptPill(text: label, on: min(interval, 2) == i, solid: true) { interval = i }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    RsCardHint(text: "到点整理当天剩下的原话。")
                }
                RsRowDivider(inset: 18)
                Text("停多久算说完了").font(Rs.body).foregroundStyle(Rs.text)
                    .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 8)
                HStack(spacing: 8) {
                    ForEach(Array(["5 分钟", "10 分钟", "20 分钟"].enumerated()), id: \.offset) { i, label in
                        RsOptPill(text: label, on: idleGap == i, solid: true) { idleGap = i }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                RsCardHint(text: "两句话之间停了 10 分钟以上，就算前面那段对话结束。")
                Text("一直在说，最多等多久").font(Rs.body).foregroundStyle(Rs.text)
                    .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)
                HStack(spacing: 8) {
                    ForEach(Array(["30 分钟", "1 小时", "2 小时"].enumerated()), id: \.offset) { i, label in
                        RsOptPill(text: label, on: maxGap == i, solid: true) { maxGap = i }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                RsCardHint(text: "一直有人在说话时，到点也会先切一段，免得整场并成一条。")
                RsRowDivider(inset: 18)
                RsToggleRow(title: "整理前先思考",
                            note: "分条更准，一件事一条，不容易切碎；费用约为原来的 3～5 倍，整理也慢一些。",
                            on: Binding(get: { settings.deepThinking }, set: { settings.deepThinking = $0 }))
                RsRowDivider(inset: 18)
                RsToggleRow(title: "整理时参考地点和环境音",
                            note: "每段对话附上当时在哪（来自足迹）、周围有什么声音；地点会一起发给整理用的大模型服务。",
                            on: Binding(get: { settings.usePlaceInDigest }, set: { settings.usePlaceInDigest = $0 }))
                RsCardHint(text: "支持 DeepSeek、火山方舟、硅基流动；其他服务按它自己的默认。")
            }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
        }
    }

    // 整理用的大模型
    private var providersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            RsCardTitle(text: "整理用的大模型")
            RsCardHint(text: "点一下切换；整理、问问、回顾都用当前这个，技能可以另选。")
            providerRow(name: "DeepSeek", model: settings.llmModel.isEmpty ? "deepseek-chat" : settings.llmModel,
                        selected: true, balance: "余额 ¥12.88 · 含赠送 ¥0.00")
            RsRowDivider(inset: 18)
            RsToggleRow(title: "出问题时自动换备用",
                        note: "再添加一个服务商并填好密钥，就能当备用",
                        on: .constant(false))
            RsRowDivider(inset: 18)
            Button { } label: {
                HStack {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text("添加服务商").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Rs.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(Rs.accentSoft))
                .padding(18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            RsRowDivider(inset: 18)
            RsValueRow(title: "余额提醒", value: "低于 ¥10 时提醒")
            RsCardHint(text: "密钥分开保存在手机里，不会显示。")
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    private func softPill(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Rs.accent)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(Capsule().fill(Rs.accentSoft))
        }
        .buttonStyle(.plain)
    }

    private func providerRow(name: String, model: String, selected: Bool, balance: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                RsRadio(on: selected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(Rs.body).foregroundStyle(Rs.text)
                    Text(model).font(Rs.caption).foregroundStyle(Rs.text3)
                }
                Spacer(minLength: 0)
                Text("编辑").font(.system(size: 13)).foregroundStyle(Rs.accent)
            }
            if selected {
                Text(balance).font(Rs.subhead).foregroundStyle(Rs.text3)
                    .padding(.leading, 32)
                HStack(spacing: 8) {
                    softPill("检测") { }
                    softPill("刷新余额") { }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 32)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

struct RsWaveDots: View {
    var active: Bool
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<14, id: \.self) { i in
                Capsule()
                    .fill((active ? Rs.card : Rs.text3).opacity(0.85))
                    .frame(width: 2.5, height: 3 + CGFloat((i * 7) % 9))
            }
        }
        .frame(height: 12)
    }
}

// MARK: - 存储统计（子页里复用）

final class StoreStatsProxy: ObservableObject {
    static let shared = StoreStatsProxy()

    var todaySeconds: Double {
        AppState.shared.todaySegments.reduce(0) { $0 + $1.duration }
    }

    var monthSeconds: Double {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let rows = Store.shared.segments(day: nil, limit: 5000)
        return rows.filter { $0.startedAt >= start }.reduce(0) { $0 + $1.duration }
    }

    var audioBytes: Int {
        AppState.shared.todaySegments.reduce(0) { $0 + $1.byteSize }
    }
}

/// 截图用：按比例把外层 ScrollView 滚到指定位置（-b / -c / -d 三张滚动图）
struct RsScrollFrac: UIViewRepresentable {
    var frac: CGFloat

    func makeUIView(context: Context) -> UIView { Probe(frac: frac) }
    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Probe: UIView {
        let frac: CGFloat
        init(frac: CGFloat) {
            self.frac = frac
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard frac > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self else { return }
                var node: UIView? = self
                while let v = node {
                    if let sv = v as? UIScrollView {
                        let maxY = max(0, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
                        sv.setContentOffset(CGPoint(x: 0, y: maxY * min(1, self.frac)), animated: false)
                        return
                    }
                    node = v.superview
                }
            }
        }
    }
}