import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - 设置子页（SettingsScreen.kt SubPageBar + 分组白卡）

struct RsSubPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    /// 截图模式：滚动图按画面锚点定位，不按百分比猜
    /// （rs-recording-b → 录音输入，rs-llm-b → 什么时候整理 …）
    static func anchorForShot(_ shot: String?) -> String? {
        switch shot ?? "" {
        case "rs-recording-b": return "rec-input"
        case "rs-recording-c": return "rec-backend"
        case "rs-transcript-b": return "tr-speech"
        case "rs-transcript-c": return "tr-raw"
        case "rs-llm-b": return "llm-timing"
        case "rs-llm-c": return "llm-idle"
        case "rs-location-b": return "loc-day"
        case "rs-voice-b": return "vp-samples"
        default: return nil
        }
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

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        content()
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
                .task {
                    guard let anchor = RsSubPage.anchorForShot(ShotMode.screen) else { return }
                    // 先等布局完成，再按锚点滚；滚两次，避免首次还没算好高度
                    for _ in 0..<2 {
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        withAnimation(nil) { proxy.scrollTo(anchor, anchor: .top) }
                    }
                }
            }
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
    @State private var showInputs = false
    @State private var showFolderImporter = false
    @State private var folderNote = ""
    @State private var micOK = false
    @State private var notifOK = false
    @State private var bgAudioOK = false
    @State private var lowPower = false


    var body: some View {
        RsSubPage(title: "录音与后台") {
            statusCard

            // 原版每段 = 卡外小标题 + 白卡 + 卡外灰说明，段内 7dp、段间 22dp
            VStack(alignment: .leading, spacing: 7) {
                RsSectionLabel(title: "停录时段", trailing: settings.silenceWindowOn ? "已开启" : "未开启")
                stopWindowCard
                RsFootNote(text: "时段内不录音，到点自动恢复；时段内点「现在恢复」只对这一次有效。")
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 7) {
                RsSectionLabel(title: "录音输入").id("rec-input")
                inputCard
                RsDotText(text: "正在用：" + MicRouter.shared.currentName())
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                RsFootNote(text: "插上 Type-C 麦克风或领夹麦接收器、连上蓝牙耳机后，会出现在这里。")
                externalCard
                    .padding(.top, 4)
            }


            importCard
            backendCard.id("rec-backend")
        }
        .fileImporter(isPresented: $showFolderImporter,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                settings.autoImportFolder = url.path
                folderNote = "已选：\(url.lastPathComponent)，点这一行可以现在导入一次。"
                scanFolder()
            case .failure(let err):
                folderNote = "选文件夹失败：\(err.localizedDescription)"
            }
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
                    // 用户明确停：普通聆听也要真正停下采集，回前台不再自动拉起
                    let st = StopRules.stateAfterUserStop()
                    captureWanted = st.captureWanted
                    UserDefaults.standard.set(st.userStopped, forKey: "rsUserStopped")
                    if flow.isRecording {
                        flow.stop(reason: .userStop)
                    } else {
                        UserDefaults.standard.set(false, forKey: "captureWanted")
                        CaptureEngine.shared.stop()
                        CaptureEngine.shared.bindSession(nil, mode: nil)
                    }
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
            inputRow(avatar: "手", title: "手机麦克风", note: "默认", on: settings.preferredInputUID.isEmpty) {
                pickInput(uid: "")
            }
            RsRowDivider(inset: 18)
            inputRow(avatar: "自", title: "自动", note: "接上 USB 或有线麦克风就用它，拔掉自动回到手机", on: settings.preferredInputUID == "auto") {
                pickInput(uid: "auto")
            }
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    private func pickInput(uid: String) {
        settings.preferredInputUID = uid
        MicRouter.shared.applyPreferred()
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

    // 外接设备单独一张卡（点开列出当前系统真的能用的输入设备）
    private var externalCard: some View {
        VStack(spacing: 0) {
            RsValueRow(title: "外接设备", value: MicRouter.shared.currentName()) { showInputs = true }
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
        .sheet(isPresented: $showInputs) { inputSheet }
    }

    private var inputSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("录音输入")
                .font(Rs.headline)
                .foregroundStyle(Rs.text)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 6)
            Text("列出来的是系统当前能用的麦克风，选一个就立刻切换。")
                .font(Rs.caption)
                .foregroundStyle(Rs.text3)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(MicRouter.shared.inputs()) { input in
                        Button {
                            pickInput(uid: input.id)
                            showInputs = false
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(input.name).font(Rs.body).foregroundStyle(Rs.text)
                                    Text(input.kind).font(Rs.caption).foregroundStyle(Rs.text3)
                                }
                                Spacer(minLength: 8)
                                RsRadio(on: settings.preferredInputUID == input.id)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        RsRowDivider(inset: 20)
                    }
                    Button {
                        pickInput(uid: "auto")
                        showInputs = false
                    } label: {
                        HStack {
                            Text("自动（先外接）").font(Rs.body).foregroundStyle(Rs.text)
                            Spacer(minLength: 8)
                            RsRadio(on: settings.preferredInputUID == "auto")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }


    // 自动导入文件夹（原版：卡外小标题，卡里一行「＋ 添加文件夹」，说明在卡外灰字）
    private var importCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RsSectionLabel(title: "自动导入文件夹")
            VStack(alignment: .leading, spacing: 0) {
                Button { showFolderImporter = true } label: {
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

                if !settings.autoImportFolder.isEmpty {
                    RsRowDivider(inset: 18)
                    RsValueRow(title: "已选文件夹",
                               value: (settings.autoImportFolder as NSString).lastPathComponent) {
                        scanFolder()
                    }
                }
                if !folderNote.isEmpty {
                    RsRowDivider(inset: 18)
                    Text(folderNote)
                        .font(Rs.caption)
                        .foregroundStyle(Rs.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                }
            }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))

            RsFootNote(text: "录音笔 App、录音机把录音存在哪，就选哪个文件夹。新录音会自动导入转写，原文件不动、不删；同一个录音只导入一次。")
            RsFootNote(text: "大约每 15 分钟看一次，打开涛声时也会看；录音写完一两分钟后才会导入。")
        }
    }

    /// 扫一遍已选文件夹，把没导入过的录音导进来（同一文件名只导一次）
    private func scanFolder() {
        let path = settings.autoImportFolder
        guard !path.isEmpty else {
            folderNote = "还没选文件夹。"
            return
        }
        let url = URL(fileURLWithPath: path)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        let exts = ["m4a", "mp3", "wav", "aac", "caf", "aiff", "aif", "flac", "mp4"]
        let audio = files.filter { exts.contains($0.pathExtension.lowercased()) }
        guard !audio.isEmpty else {
            folderNote = "这个文件夹里没有找到录音文件。"
            return
        }
        var seen = Set(UserDefaults.standard.stringArray(forKey: "rsImportedFiles") ?? [])
        // 去重键 = 文件夹里的相对路径 + 大小 + 修改时间：
        // 只按文件名会把两个目录里的同名录音误判成同一个，改过内容也认不出来。
        let rootPath = url.standardizedFileURL.path
        func importKey(_ u: URL) -> String {
            let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            let mtime = Int((attrs?[.modificationDate] as? Date ?? .distantPast).timeIntervalSince1970)
            var rel = u.standardizedFileURL.path
            if rel.hasPrefix(rootPath) { rel = String(rel.dropFirst(rootPath.count)) }
            return ImportRules.key(name: rel, size: size, modifiedEpoch: mtime)
        }
        let keys = Dictionary(uniqueKeysWithValues: audio.map { ($0, importKey($0)) })
        let fresh = audio.filter { ImportRules.shouldImport(key: keys[$0] ?? "", seen: seen) }
        guard !fresh.isEmpty else {
            folderNote = "没有新录音，导入过的不会再导一次。"
            return
        }
        folderNote = "正在导入 \(fresh.count) 个录音…"
        rsImportAudio(fresh) { outcome in
            // 只有真正导入成功的才记账，失败的留到下次再试
            for f in outcome.added {
                if let k = keys[f] { seen.insert(k) }
            }
            UserDefaults.standard.set(Array(seen), forKey: "rsImportedFiles")
            folderNote = outcome.message
        }
    }

    // 后台设置（原版：小标题在卡外，右侧完成数；完成项浅绿方块 ✓，未完成项数字方块，按钮在该行右侧）
    private var backendCard: some View {
        let rows: [(String, String, Bool)] = [
            ("麦克风权限", "在应用权限里允许使用麦克风。", micOK),
            ("通知权限", "允许通知，录音中断提醒才能弹出来。", notifOK),
            ("后台音频", "锁屏后继续录音；Info.plist 已声明 audio 后台模式。", bgAudioOK),
            ("低电量模式已关", "低电量模式下系统可能挂起后台录音，录音前先关掉。", !lowPower)
        ]
        let doneCount = rows.filter { $0.2 }.count
        return VStack(alignment: .leading, spacing: 8) {
            RsSectionLabel(title: "后台设置",
                           trailing: "\(doneCount) / \(rows.count) 已完成",
                           trailingColor: doneCount == rows.count ? Rs.good : Rs.accent)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    if idx > 0 { RsRowDivider(inset: 18) }
                    backendItem(row.0, row.1, done: row.2, index: idx + 1,
                                action: row.2 ? nil : "去设置") { openSystemSettings() }
                }
            }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
            RsFootNote(text: "这几项是系统给的权限，改完回到这一页会重新检查一次。")
        }
        .task { refreshBackend() }
    }

    private func refreshBackend() {
        micOK = AVAudioSession.sharedInstance().recordPermission == .granted
        bgAudioOK = (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("audio") == true
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let ok = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional || s.authorizationStatus == .ephemeral
            DispatchQueue.main.async { notifOK = ok }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func backendItem(_ title: String, _ note: String, done: Bool, index: Int,
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
                    Text("\(index)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Rs.text3)
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
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var queue = TranscribeQueue.shared
    @StateObject private var model = LocalModelStore.shared

    @State private var showKey = false
    @State private var keyDraft = ""
    @State private var showHeaders = false
    @State private var headersDraft = ""
    @State private var hotDraft = ""
    @State private var rawDay = 0
    @State private var rawSegs: [Segment] = []
    /// 本地模型的下载卡：原版在「本地」档下就能直接下模型，这里补上同一条路。
    /// 只下 model.int8.onnx 与 tokens.txt（字节数与 SHA-256 和 Android 端同一个模型）。
    @ViewBuilder
    private var localModelBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("SenseVoice 本地模型").font(Rs.body).foregroundStyle(Rs.text)
                Spacer(minLength: 0)
                Text(LocalModelRules.sizeText(Int64(LocalModelRules.modelBytes)))
                    .font(Rs.caption).foregroundStyle(Rs.text3)
            }
            Text(LocalModelRules.phaseText(model.phase))
                .font(Rs.subhead)
                .foregroundStyle(model.phase == .ready ? Rs.good : Rs.text3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                switch model.phase {
                case .downloading:
                    RsBtn(text: "取消", filled: false) { model.cancel() }
                case .ready:
                    RsBtn(text: "删除模型", filled: false) { model.delete() }
                default:
                    RsBtn(text: model.phase == .absent ? "下载模型" : "重试") { model.start() }
                }
                Spacer(minLength: 0)
            }
            Text(model.phase == .ready
                 ? "已经可以离网转写：录音照常分段，转写时不再联网。"
                 : "没下载时，「本地」这一档先用系统识别；下载完成后自动换成这个模型，离网也能转写。")
                .font(Rs.caption)
                .foregroundStyle(Rs.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .task { model.refresh() }
    }
    @State private var testing = false
    @State private var testNote: String?
    @State private var showImporter = false
    @State private var importNote: String?
    @State private var topicNote: String?

    private let cadenceOptions = ["实时", "15 分钟", "30 分钟", "自定义"]

    var body: some View {
        RsSubPage(title: "原话与转写") {
            queueCard
            transcribeCard.id("tr-speech")
            cadenceCard
            switchesCard
            trainingCard
            testCard
            hotwordCard
            rawCard.id("tr-raw")
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.audio, .movie],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): importAudio(urls)
            case .failure(let err): importNote = "选文件失败：\(err.localizedDescription)"
            }
        }
        .sheet(isPresented: $showKey) { keySheet }
        .sheet(isPresented: $showHeaders) { headersSheet }
        .task { loadRaw() }
        .task(id: rawDay) { loadRaw() }
        .onReceive(NotificationCenter.default.publisher(for: .taoshengDataChanged)) { _ in
            loadRaw()
            queue.refreshPending()
        }
    }

    // MARK: 队列状态卡

    private var queueCard: some View {
        let ready = settings.asrReady
        let dot: Color = !ready ? Rs.warning : (queue.busy ? Rs.accent : Rs.good)
        let title: String = !ready ? "转写尚未就绪"
            : (queue.busy ? "正在转写…"
               : (queue.pendingCount > 0 ? "还有 \(queue.pendingCount) 段等着转" : "都转完了"))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 9, height: 9)
                Text(title).font(Rs.headline).foregroundStyle(Rs.text)
                Spacer(minLength: 0)
            }
            Text(queueNote).font(Rs.subhead).foregroundStyle(Rs.text2)
            HStack(spacing: 10) {
                RsBtn(text: "现在转写", filled: true) { queue.transcribeNow() }
                RsBtn(text: "导入录音", filled: false) { showImporter = true }
                Spacer(minLength: 0)
            }
            if let note = importNote ?? queue.lastMessage {
                Text(note).font(Rs.caption).foregroundStyle(Rs.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            RsRowDivider(inset: 0)
            RsInfoRow(title: "云端转写", value: cloudLine) { }
            RsValueRow(title: "原声", value: audioLine) { }
            RsValueRow(title: "录音包", value: "把手机里的原始录音打包导出") { }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    private var queueNote: String {
        if !settings.asrReady { return settings.asrReadyHint }
        if let at = queue.lastRunAt {
            return "上次 " + Fmt.hm.string(from: at) + " · " + nextRoundText
        }
        return queue.pendingCount > 0 ? "还没有转写过 · " + nextRoundText : "还没有转写过"
    }

    private var nextRoundText: String {
        guard let next = queue.nextRunAt else { return "等下一轮" }
        let m = max(1, Int(next.timeIntervalSinceNow / 60))
        return "约 \(m) 分钟后下一轮"
    }

    private var cloudLine: String {
        let rows = Store.shared.segments(day: DayKey.of(Date()), limit: 5000)
        let today = rows.reduce(0.0) { $0 + $1.duration } / 60
        let cost = Double(settings.transcribeIntervalMin) * 0
        _ = cost
        return String(format: "今天 %.0f 分 · 近 30 天 %.0f 分", today, today)
    }

    private var audioLine: String {
        let keep = settings.keepAudioDays
        return keep <= 0 ? "一直保留 · 只在本机" : "保留 \(keep) 天 · 重点长期保留"
    }

    // MARK: 语音转写

    private var transcribeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            RsCardTitle(text: "语音转写")
            RsSegControl(options: ["豆包", "本地", "自定义"], index: sourceBinding)
                .padding(.horizontal, 18)            if settings.asrKind == .appleSpeech {
                RsRowDivider(inset: 18)
                localModelBlock
            }
            RsRowDivider(inset: 18)
            Button { headersDraft = settings.asrCustomHeaders; showHeaders = true } label: {
                HStack {
                    Text("自定义请求头（可选）").font(Rs.body).foregroundStyle(Rs.accent)
                    Spacer(minLength: 0)
                    Text("›").font(.system(size: 16)).foregroundStyle(Rs.text3)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if settings.asrKind == .openAICompatible {
                RsRowDivider(inset: 18)
                RsFieldRow(title: "服务地址", placeholder: "https://api.openai.com/v1", text: $settings.asrBaseURL)
                RsRowDivider(inset: 18)
                RsFieldRow(title: "模型名", placeholder: "whisper-1", text: $settings.asrModel)
            }

            if settings.asrKind != .appleSpeech && settings.asrKind != .off {
                RsRowDivider(inset: 18)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(keyTitle).font(Rs.body).foregroundStyle(Rs.text)
                        Spacer(minLength: 0)
                        RsDotText(text: keyReady ? "已填写" : "还没填",
                                  color: keyReady ? Rs.good : Rs.warning)
                    }
                    .padding(.horizontal, 18)
                    HStack(spacing: 10) {
                        RsBtn(text: "更换", filled: false, small: true) {
                            // 不预填已保存的密钥：既不回显，也不会把另一家的 Key 带出来
                            keyDraft = ""
                            showKey = true
                        }
                        if keyReady {
                            RsBtn(text: "清除", filled: false, small: true) {
                                if settings.asrKind == .doubao { settings.doubaoApiKey = "" } else { settings.asrKey = "" }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    Text("只存在这台手机的安全区里，填好后任何地方都不再显示。")
                        .font(Rs.caption)
                        .foregroundStyle(Rs.text3)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    private var sourceBinding: Binding<Int> {
        Binding(get: {
            switch settings.asrKind {
            case .doubao: return 0
            case .appleSpeech: return 1
            default: return 2
            }
        }, set: { i in
            settings.asrKind = i == 0 ? .doubao : (i == 1 ? .appleSpeech : .openAICompatible)
        })
    }

    private var keyTitle: String { settings.asrKind == .doubao ? "豆包语音密钥" : "接口密钥" }
    private var keyReady: Bool {
        settings.asrKind == .doubao ? !settings.doubaoApiKey.isEmpty : !settings.asrKey.isEmpty
    }

    private var keySheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(keyTitle).font(Rs.headline).foregroundStyle(Rs.text)
            Text(settings.asrKind.hint).font(Rs.caption).foregroundStyle(Rs.text3)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("粘贴密钥（不显示已保存的）", text: $keyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Rs.fill))
            HStack(spacing: 10) {
                RsBtn(text: "保存", filled: true) {
                    let v = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if settings.asrKind == .doubao { settings.doubaoApiKey = v } else { settings.asrKey = v }
                    showKey = false
                }
                RsBtn(text: "取消", filled: false) { showKey = false }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    private var headersSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自定义请求头").font(Rs.headline).foregroundStyle(Rs.text)
            Text("一行一个，格式 Key: Value。自建服务要带鉴权头时用。")
                .font(Rs.caption).foregroundStyle(Rs.text3)
            TextEditor(text: $headersDraft)
                .font(.system(size: 13))
                .frame(minHeight: 160)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Rs.fill))
            HStack(spacing: 10) {
                RsBtn(text: "保存", filled: true) {
                    settings.asrCustomHeaders = headersDraft
                    showHeaders = false
                }
                RsBtn(text: "取消", filled: false) { showHeaders = false }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: 多久转写一次

    private var cadenceCard: some View {
        let idx = cadenceIndex
        return VStack(alignment: .leading, spacing: 12) {
            RsSectionLabel(title: "多久转写一次")
            cardBody {
                RsFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Array(cadenceOptions.enumerated()), id: \.offset) { i, name in
                        RsOptPill(text: name, on: idx == i, solid: true) { setCadence(i) }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                if idx == 3 {
                    HStack(spacing: 12) {
                        Text("每 \(settings.transcribeIntervalMin) 分钟")
                            .font(Rs.subhead).foregroundStyle(Rs.text2)
                        Stepper("", value: $settings.transcribeIntervalMin, in: 5...240, step: 5)
                            .labelsHidden()
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                }
                Text(cadenceHint).font(Rs.caption).foregroundStyle(Rs.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
    }

    private var cadenceIndex: Int {
        switch settings.transcribeIntervalMin {
        case 1: return 0
        case 15: return 1
        case 30: return 2
        default: return 3
        }
    }

    private func setCadence(_ i: Int) {
        switch i {
        case 0: settings.transcribeIntervalMin = 1
        case 1: settings.transcribeIntervalMin = 15
        case 2: settings.transcribeIntervalMin = 30
        default:
            if ![1, 15, 30].contains(settings.transcribeIntervalMin) { return }
            settings.transcribeIntervalMin = 45
        }
    }

    private var cadenceHint: String {
        switch cadenceIndex {
        case 0: return "录完一段就马上转，最费流量也最及时。"
        case 1: return "每 15 分钟把攒下的录音转写一次。"
        case 2: return "每 30 分钟把攒下的录音转写一次。整理成事件另在「模型与整理时间」里设置。"
        default: return "每 \(settings.transcribeIntervalMin) 分钟把攒下的录音转写一次。"
        }
    }

    // MARK: 开关

    private var switchesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            RsToggleRow(title: "只在 WiFi 下转写", note: "打开后，用流量时不转写，连上 WiFi 再补。默认关：蜂窝也照转。",
                        on: $settings.wifiOnlyTranscribe)
            RsRowDivider(inset: 18)
            RsToggleRow(title: "外放声音时不转写", note: "手机上正放着视频或音乐时，录到的多半是外放声，先不转写。",
                        on: $settings.skipWhenOutput)
            RsRowDivider(inset: 18)
            RsToggleRow(title: "区分说话人与认人", note: "原话标出谁在说，认出「我」和已命名的人。",
                        on: $settings.speakerSplitOn)
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    // MARK: 培训专题入口

    private var trainingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RsSectionLabel(title: "临时不区分说话人")
            cardBody {
                RsValueRow(title: "开始培训专题", value: "一人主讲、不分说话人") {
                    ListenFlow.shared.start(mode: .training)
                    topicNote = "已开始一场培训专题，结束后出培训笔记。"
                }
                if let note = topicNote {
                    RsRowDivider(inset: 18)
                    Text(note).font(Rs.caption).foregroundStyle(Rs.text3)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: 测试

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RsSectionLabel(title: "测试一下")
            cardBody {
                Text("用最近一段录音真跑一次转写，看看密钥和地址对不对。")
                    .font(Rs.caption).foregroundStyle(Rs.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18).padding(.top, 12)
                HStack(spacing: 10) {
                    RsBtn(text: testing ? "正在测…" : "测试", filled: false, small: true) { runASRTest() }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18).padding(.top, 8)
                if let note = testNote {
                    Text(note).font(Rs.caption).foregroundStyle(Rs.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 12)
                } else {
                    Spacer(minLength: 12)
                }
            }
        }
    }

    private func runASRTest() {
        guard !testing else { return }
        guard settings.asrReady else {
            testNote = "还没配置：\(settings.asrReadyHint)"
            return
        }
        let candidates = Store.shared.segments(day: nil, limit: 60)
            .filter { !$0.fileName.isEmpty }
        guard let seg = candidates.first else {
            testNote = "还没有录音可以测，先录一段。"
            return
        }
        let url = Store.audioDir.appendingPathComponent(seg.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            testNote = "这段录音的文件不在了，换一段再试。"
            return
        }
        testing = true
        testNote = "正在转写 \(seg.fileName)…"
        Task.detached {
            do {
                guard let engine = TranscriberFactory.make() else {
                    await MainActor.run { testing = false; testNote = "当前服务商是「只录音，不转写」。" }
                    return
                }
                let result = try await engine.transcribe(fileURL: url)
                let text = result.text
                let head = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
                await MainActor.run {
                    testing = false
                    testNote = text.isEmpty ? "成功，但这段没有识别出文字。" : "成功：\(head)"
                }
            } catch {
                await MainActor.run {
                    testing = false
                    testNote = "失败：\(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: 热词

    private var hotwordCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RsSectionLabel(title: "热词")
            cardBody {
                HStack(spacing: 8) {
                    TextField("输入词语，多个用逗号隔开", text: $hotDraft)
                        .font(Rs.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Rs.fill))
                    RsBtn(text: "添加", filled: false, small: true) { addHotwords() }
                }
                .padding(.horizontal, 18).padding(.top, 12)
                RsToggleRow(title: "整理时用热词", note: "转写和整理时把热词改成你写的写法。",
                            on: $settings.hotwordEnabled)
                ForEach(Store.shared.hotwords()) { h in
                    RsRowDivider(inset: 18)
                    HStack {
                        Text(h.word).font(Rs.body).foregroundStyle(Rs.text)
                        if !h.replacement.isEmpty {
                            Text("→ \(h.replacement)").font(Rs.caption).foregroundStyle(Rs.text3)
                        }
                        Spacer(minLength: 8)
                        Button { app.deleteHotword(h.id) } label: {
                            Text("删除").font(.system(size: 13)).foregroundStyle(Rs.critical)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10)
                }
            }
        }
    }

    private func addHotwords() {
        let parts = hotDraft
            .components(separatedBy: CharacterSet(charactersIn: ",，、 "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return }
        for w in parts { app.addHotword(word: w, replacement: "") }
        hotDraft = ""
    }

    // MARK: 录音原话

    private var rawCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            RsSectionLabel(title: "录音原话",
                           trailing: "\(rawSegs.count) 段 · 已转 \(rawSegs.filter { !$0.isEmptySpeech }.count)")
            RsSegControl(options: ["今天", "昨天", "前天"], index: $rawDay)
            if rawSegs.isEmpty {
                cardBody {
                    Text("这天没有录音")
                        .font(Rs.subhead).foregroundStyle(Rs.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rawSegs.enumerated()), id: \.element.id) { i, seg in
                        if i > 0 { RsRowDivider(inset: 18) }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(seg.timeText).font(Rs.caption).foregroundStyle(Rs.text3)
                                Text("· \(seg.durationText)").font(Rs.caption).foregroundStyle(Rs.text3)
                                Spacer(minLength: 0)
                            }
                            Text(seg.isEmptySpeech ? "没有文字" : seg.transcript)
                                .font(Rs.subhead)
                                .foregroundStyle(seg.isEmptySpeech ? Rs.text3 : Rs.text)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 10)
                    }
                }
                .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
            }
        }
    }

    private func loadRaw() {
        let day = DayKey.of(Date().addingTimeInterval(-Double(rawDay) * 86400))
        rawSegs = Store.shared.segments(day: day, limit: 60)
    }

    private func cardBody<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    // MARK: 导入

    private func importAudio(_ urls: [URL], done: ((String) -> Void)? = nil) {
        rsImportAudio(urls) { outcome in
            importNote = outcome.message
            loadRaw()
            done?(outcome.message)
        }
    }
}

// MARK: - 声纹与人物（VoiceprintUi.kt）

struct RsVoicePage: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var settings = Settings.shared
    @State private var showAdd = false
    @State private var nameDraft = ""
    @State private var pendingDelete: Person?

    var body: some View {
        RsSubPage(title: "声纹与人物") {
            HStack(alignment: .firstTextBaseline) {
                Text("人物 · \(app.persons.count)").font(Rs.body).foregroundStyle(Rs.text2)
                Spacer(minLength: 0)
                RsBtn(text: "添加人物", filled: false) { nameDraft = ""; showAdd = true }
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
                        Button {
                            pendingDelete = p
                        } label: {
                            Text("删除").font(.system(size: 13)).foregroundStyle(Rs.critical)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    RsRowDivider(inset: 18)
                }
            }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
            RsFootNote(text: "这一版只能按「人物」统计已有分段；「在原话里指认说话人」的入口还没做。")

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("本地多人分段").font(Rs.body).foregroundStyle(Rs.text)
                    Text("试用").font(.system(size: 12)).foregroundStyle(Rs.accent)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Rs.accentSoft))
                    Spacer(minLength: 0)
                    Toggle("", isOn: $settings.speakerSplitOn).labelsHidden().tint(Rs.accent)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                RsCardHint(text: "本地转写时先分出不同的人。人多嘈杂时可能分错，这一版还没有手动纠正的入口。")
            }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))

            Color.clear.frame(height: 1).id("vp-samples")

            Text("还有 \(max(0, app.todaySegments.count)) 段等着匹配声音")
                .font(Rs.caption).foregroundStyle(Rs.text3)
                .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showAdd) {
            VStack(alignment: .leading, spacing: 12) {
                Text("添加人物").font(Rs.headline).foregroundStyle(Rs.text)
                Text("写上名字，之后在原话里长按一句选「这是谁」，声音样本就会记到他身上。")
                    .font(Rs.caption).foregroundStyle(Rs.text3)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("例如：老王", text: $nameDraft)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Rs.fill))
                HStack(spacing: 10) {
                    RsBtn(text: "添加", filled: true) {
                        let n = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !n.isEmpty { app.addPerson(name: n) }
                        showAdd = false
                    }
                    RsBtn(text: "取消", filled: false) { showAdd = false }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("删除这个人物？", isPresented: Binding(get: { pendingDelete != nil },
                                                          set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { p in
            Button("删除 \(p.name)", role: .destructive) {
                app.deletePerson(p.id)
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { p in
            Text("只会删掉这个人和他的声音样本，已经录下的原话不动。")
        }
    }
}

// MARK: - 环境音识别（EnvSoundViews.kt）

struct RsEnvPage: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        RsSubPage(title: "环境音识别") {
            Text("转写完成以后，对已经录下的人声片段做一次粗粒度判断（很安静 / 像键盘 / 像音乐 / 像人声），把结果当作「当时的环境」写进整理提示词。不上传音频，也不下载模型：用的是本机的音量、过零率和高频占比几个简单特征，所以判断只有粗粒度几类，旧录音不补算。")
                .font(Rs.caption).foregroundStyle(Rs.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("环境音识别").font(Rs.body).foregroundStyle(Rs.text)
                        Text("本地启发式判断，不需要下载模型").font(Rs.caption).foregroundStyle(Rs.text3)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(get: { settings.envSoundOn }, set: { settings.envSoundOn = $0 }))
                        .labelsHidden().tint(Rs.accent)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                RsRowDivider(inset: 18)
                Text(settings.envSoundOn ? "已开启：新转写的片段会带环境标签。" : "未开启：整理提示词里不带环境信息。")
                    .font(Rs.caption).foregroundStyle(Rs.text3)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
        }
    }
}

// MARK: - 足迹（LocationPage.kt）

struct RsLocationPage: View {
    @ObservedObject private var settings = Settings.shared
    @State private var dayOffset = 0
    @State private var dayVisits: [PlaceVisit] = []

    private var shownDay: Date { Date().addingTimeInterval(-Double(dayOffset) * 86400) }
    private var shownKey: String { DayKey.of(shownDay) }

    /// 真实停留记录：没有记录就是空的，不再拿 0 装作统计好了
    private var stats: LocationStats.Totals {
        LocationStats.totals(dayVisits.map {
            LocationStats.Visit(arriveAt: $0.arriveAt, leaveAt: $0.leaveAt,
                                isHome: $0.isHome,
                                latitude: $0.latitude, longitude: $0.longitude)
        })
    }

    var body: some View {
        RsSubPage(title: "足迹") {
            VStack(alignment: .leading, spacing: 0) {
                RsToggleRow(title: "记录全天位置",
                            note: "跟随收音服务，约每 5 分钟记一个点；位置记录只存手机本地。",
                            on: Binding(get: { settings.locationOn }, set: { v in
                                settings.locationOn = v
                                LocationEngine.shared.syncWithSettings()
                            }))
            }
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))

            HStack(spacing: 0) {
                Button { if dayOffset < 30 { dayOffset += 1 } } label: {
                    Text("‹").font(.system(size: 20, weight: .semibold)).foregroundStyle(Rs.text3)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text(Fmt.df("M月d日 EEE").string(from: shownDay) + (dayOffset == 0 ? " · 今天" : ""))
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Rs.text)
                Spacer(minLength: 0)
                Button { if dayOffset > 0 { dayOffset -= 1 } } label: {
                    Text("›").font(.system(size: 20, weight: .semibold)).foregroundStyle(dayOffset > 0 ? Rs.text3 : Rs.text3.opacity(0.3))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(dayOffset == 0)
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                Text("这一天").font(.system(size: 15, weight: .semibold)).foregroundStyle(Rs.text)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                if dayVisits.isEmpty {
                    Text("这一天没有位置记录")
                        .font(Rs.subhead).foregroundStyle(Rs.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 78)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(dayVisits) { v in
                            HStack(spacing: 10) {
                                Text(Fmt.hm.string(from: v.arriveAt))
                                    .font(Rs.caption).foregroundStyle(Rs.text3)
                                    .frame(width: 46, alignment: .leading)
                                Text(v.name.isEmpty ? (v.isHome ? "在家" : "外面") : v.name)
                                    .font(Rs.subhead).foregroundStyle(Rs.text)
                                Spacer(minLength: 0)
                                Text(v.durationText).font(Rs.caption).foregroundStyle(Rs.text3)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    locStat("\(stats.homeMinutes) 分", "在家")
                    locStat("\(stats.awayMinutes) 分", "外出")
                    locStat(String(format: "%.1f km", stats.kilometers), "移动距离")
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 18)
            }
            .frame(minHeight: 260, alignment: .top)
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
            .id("loc-day")

            VStack(alignment: .leading, spacing: 0) {
                RsCardTitle(text: "显示地名")
                RsCardHint(text: "停留处的坐标交给手机系统的地理服务查地址，查过的地方存在本机，不重复查。这一版只用系统地理服务，没有接第三方地图 Key。")
            }
            .padding(.bottom, 4)
            .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
        }
        .task(id: dayOffset) {
            dayVisits = Store.shared.places(day: shownKey)
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

    @State private var usageTab = 0
    @State private var showEdit = false
    @State private var showAdd = false
    @State private var showThreshold = false
    @State private var editBase = ""
    @State private var editModel = ""
    @State private var editKey = ""
    @State private var addBase = ""
    @State private var addModel = ""
    @State private var addKey = ""
    @State private var balanceText = "余额未查询"
    @StateObject private var account = DeepSeekAccount()
    @State private var checkNote: String?
    @State private var checking = false

    var body: some View {
        RsSubPage(title: "模型与整理时间") {
            providersCard
            timingCard
            usageCard
        }
        .sheet(isPresented: $showEdit) { editSheet }
        .sheet(isPresented: $showAdd) { addSheet }
        .sheet(isPresented: $showThreshold) { thresholdSheet }
    }

    // MARK: 什么时候整理（写进 digestTiming / digestIntervalMin / digestHour）

    private var timingIndex: Int {
        switch settings.digestTiming {
        case .afterTranscribe: return 0
        case .interval: return 1
        case .clock: return 2
        }
    }

    private var timingBinding: Binding<Int> {
        Binding(get: { timingIndex }, set: { i in
            settings.digestTiming = i == 0 ? .afterTranscribe : (i == 1 ? .interval : .clock)
        })
    }

    private var intervalIndex: Int {
        let v = settings.digestIntervalMin
        if v == 15 { return 0 }
        if v == 30 { return 1 }
        if v == 60 { return 2 }
        return 3
    }

    private var intervalBinding: Binding<Int> {
        Binding(get: { intervalIndex }, set: { i in
            switch i {
            case 0: settings.digestIntervalMin = 15
            case 1: settings.digestIntervalMin = 30
            case 2: settings.digestIntervalMin = 60
            default:
                if [15, 30, 60].contains(settings.digestIntervalMin) {
                    settings.digestIntervalMin = 120
                }
            }
        })
    }

    private var timingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            RsCardTitle(text: "什么时候整理").id("llm-timing")
            RsCardHint(text: "把转写好的原话整理成一件件事。转写在「原话与转写」里单独设置。")
            RsSegControl(options: ["转写完就整理", "按间隔", "按时间点"], index: timingBinding)
                .padding(.horizontal, 18)
            if timingIndex == 1 {
                Text("多久整理一次").font(Rs.body).foregroundStyle(Rs.text)
                    .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 8)
                RsSegControl(options: ["15 分钟", "30 分钟", "60 分钟", "自定义"], index: intervalBinding)
                    .padding(.horizontal, 18)
                if intervalIndex == 3 {
                    Stepper(value: $settings.digestIntervalMin, in: 5...720, step: 5) {
                        Text("每 \(settings.digestIntervalMin) 分钟")
                            .font(Rs.subhead).foregroundStyle(Rs.text2)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                }
                RsCardHint(text: "整理要等转写完成；转写间隔比整理长时，以转写为准。")
            } else if timingIndex == 2 {
                Text("每天整理").font(Rs.body).foregroundStyle(Rs.text)
                    .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 8)
                HStack(spacing: 8) {
                    ForEach(Array([21, 22, 23].enumerated()), id: \.offset) { i, h in
                        RsOptPill(text: "\(h):00", on: settings.digestHour == h, solid: true) {
                            settings.digestHour = h
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                Stepper(value: $settings.digestHour, in: 0...23) {
                    Text("每天 \(settings.digestHour) 点")
                        .font(Rs.subhead).foregroundStyle(Rs.text2)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                RsCardHint(text: "到点整理当天剩下的原话。")
            } else {
                RsCardHint(text: "每轮转写转出新文字就马上整理；开会和培训的录音在点结束后统一整理成速记。")
            }
            RsRowDivider(inset: 18)
            Text("停多久算说完了").font(Rs.body).foregroundStyle(Rs.text).id("llm-idle")
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 8)
            HStack(spacing: 8) {
                ForEach(Array([5, 10, 20].enumerated()), id: \.offset) { _, m in
                    RsOptPill(text: "\(m) 分钟", on: settings.sessionIdleMin == m, solid: true) {
                        settings.sessionIdleMin = m
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            RsCardHint(text: "两句话之间停了 \(settings.sessionIdleMin) 分钟以上，就算前面那段对话结束，整理时分开成不同话题。")
            Text("一直在说，最多等多久").font(Rs.body).foregroundStyle(Rs.text)
                .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)
            HStack(spacing: 8) {
                ForEach(Array([30, 60, 120].enumerated()), id: \.offset) { _, m in
                    RsOptPill(text: m < 60 ? "\(m) 分钟" : "\(m / 60) 小时",
                              on: settings.sessionCapMin == m, solid: true) {
                        settings.sessionCapMin = m
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            RsCardHint(text: "一直有人在说话时，到点也会先切一段，免得整场并成一条。")
            RsRowDivider(inset: 18)
            RsCardHint(text: "想马上看结果，在「今天」页点「现在整理」。每日回顾、每周回顾生成前会先整理一次。")
            RsToggleRow(title: "整理前先思考",
                        note: "分条更准，一件事一条，不容易切碎；费用约为原来的 3～5 倍，整理也慢一些。",
                        on: $settings.deepThinking)
            RsRowDivider(inset: 18)
            RsToggleRow(title: "整理时参考地点和环境音",
                        note: "每段对话附上当时在哪（来自足迹）、周围有什么声音；地点会一起发给整理用的大模型服务。",
                        on: $settings.usePlaceInDigest)
            RsCardHint(text: "支持 DeepSeek、火山方舟、硅基流动；其他服务按它自己的默认。")
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    // MARK: 用量（真实统计，没有调用就是 0）

    private var usageStart: Date {
        let cal = Calendar.current
        switch usageTab {
        case 0: return cal.startOfDay(for: Date())
        case 1: return cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date())) ?? Date()
        default: return cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: Date())) ?? Date()
        }
    }

    private var usageCard: some View {
        let b = LLMUsage.totals(since: usageStart)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("用量").font(.system(size: 17, weight: .semibold)).foregroundStyle(Rs.text)
                Spacer(minLength: 0)
                RsSegControl(options: ["今天", "本周", "30 天"], index: $usageTab, fit: true)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(LLMUsage.text(b.total)).font(.system(size: 26, weight: .semibold))
                    .monospacedDigit().foregroundStyle(Rs.text)
                Text("token · \(b.calls) 次").font(.system(size: 13)).foregroundStyle(Rs.text2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            Text("输入 \(LLMUsage.text(b.prompt)) · 输出 \(LLMUsage.text(b.completion))")
                .font(.system(size: 13)).foregroundStyle(Rs.text3)
                .padding(.horizontal, 18).padding(.top, 6)
            Text(b.calls == 0 ? "这段时间还没有调用大模型" : String(format: "花费 约 ¥%.2f", LLMUsage.cost(b)))
                .font(.system(size: 15)).foregroundStyle(Rs.text)
                .padding(.horizontal, 18).padding(.top, 6)
            GeometryReader { geo in
                let share = b.total == 0 ? 0.0 : min(1.0, Double(b.prompt) / Double(b.total))
                HStack(spacing: 0) {
                    Rectangle().fill(Rs.accent.opacity(0.55)).frame(width: geo.size.width * share)
                    Rectangle().fill(Color(hex: "8A7BE0").opacity(0.45))
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card))
    }

    // MARK: 整理用的大模型

    private var providersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            RsCardTitle(text: "整理用的大模型")
            RsCardHint(text: "点一下切换；整理、问问、回顾都用当前这个，技能可以另选。")
            providerRow(name: "DeepSeek", model: settings.llmModel.isEmpty ? "deepseek-chat" : settings.llmModel,
                        selected: true, balance: settings.llmReady ? balanceText : "还没配置密钥",
                        ready: settings.llmReady)
            if settings.llm2Ready {
                RsRowDivider(inset: 18)
                HStack(spacing: 12) {
                    RsRadio(on: settings.llmFailoverOn)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("备用服务商").font(Rs.body).foregroundStyle(Rs.text)
                        Text(settings.llm2Model).font(Rs.caption).foregroundStyle(Rs.text3)
                    }
                    Spacer(minLength: 0)
                    Button {
                        addBase = settings.llm2BaseURL
                        addModel = settings.llm2Model
                        addKey = ""
                        showAdd = true
                    } label: {
                        Text("编辑").font(.system(size: 13)).foregroundStyle(Rs.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            RsRowDivider(inset: 18)
            RsToggleRow(title: "出问题时自动换备用",
                        note: settings.llm2Ready ? "主服务商失败时，这一次改用备用服务商" : "先在下面添加一个备用服务商",
                        on: $settings.llmFailoverOn)
            RsRowDivider(inset: 18)
            Button {
                addBase = ""
                addModel = ""
                addKey = ""
                showAdd = true
            } label: {
                HStack {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                    Text(settings.llm2Ready ? "更换备用服务商" : "添加服务商").font(.system(size: 15, weight: .semibold))
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
            RsValueRow(title: "余额提醒",
                       value: String(format: "低于 ¥%.0f 时提醒", settings.balanceAlertThreshold)) {
                showThreshold = true
            }
            RsCardHint(text: "密钥分开保存在手机的安全区里，不会显示。")
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

    private func providerRow(name: String, model: String, selected: Bool, balance: String, ready: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                RsRadio(on: selected)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(Rs.body).foregroundStyle(Rs.text)
                    Text(model).font(Rs.caption).foregroundStyle(Rs.text3)
                }
                Spacer(minLength: 0)
                Button {
                    editBase = settings.llmBaseURL
                    editModel = settings.llmModel
                    editKey = ""
                    showEdit = true
                } label: {
                    Text("编辑").font(.system(size: 13)).foregroundStyle(Rs.accent)
                }
                .buttonStyle(.plain)
            }
            if selected {
                Text(balance).font(Rs.subhead).foregroundStyle(Rs.text3)
                    .padding(.leading, 32)
                HStack(spacing: 8) {
                    softPill(checking ? "检测中…" : "检测") { runCheck() }
                    softPill("刷新余额") { refreshBalance() }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 32)
                if let note = checkNote {
                    Text(note).font(Rs.caption)
                        .foregroundStyle(note.hasPrefix("正常") ? Rs.good : Rs.critical)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 32)
                }
                if !ready {
                    Text("还没填密钥：点「编辑」填上地址、模型和 Key 才能用。")
                        .font(Rs.caption).foregroundStyle(Rs.text3)
                        .padding(.leading, 32)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: 编辑 / 添加 / 余额阈值

    private var editSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("编辑服务商").font(Rs.title).foregroundStyle(Rs.text)
            TextField("接口地址，例如 https://api.deepseek.com", text: $editBase)
                .font(Rs.subhead).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Rs.fill))
            TextField("模型名，例如 deepseek-chat", text: $editModel)
                .font(Rs.subhead).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Rs.fill))
            SecureField(settings.llmKey.isEmpty ? "API Key" : "留空表示不换 Key", text: $editKey)
                .font(Rs.subhead)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Rs.fill))
            HStack(spacing: 10) {
                RsBtn(text: "保存") {
                    settings.llmBaseURL = editBase.trimmingCharacters(in: .whitespacesAndNewlines)
                    settings.llmModel = editModel.trimmingCharacters(in: .whitespacesAndNewlines)
                    let k = editKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !k.isEmpty { settings.llmKey = k }
                    showEdit = false
                    checkNote = nil
                    balanceText = "余额未查询"
                }
                RsBtn(text: "取消", filled: false) { showEdit = false }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(360)])
        .background(Rs.bg)
    }

    private var addSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(settings.llm2Ready ? "备用服务商" : "添加服务商").font(Rs.title).foregroundStyle(Rs.text)
            Text("主服务商失败时用它顶一次。地址、模型、Key 三项都要填。")
                .font(Rs.caption).foregroundStyle(Rs.text3)
            TextField("接口地址，例如 https://api.siliconflow.cn/v1", text: $addBase)
                .font(Rs.subhead).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Rs.fill))
            TextField("模型名", text: $addModel)
                .font(Rs.subhead).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Rs.fill))
            SecureField(settings.llm2Key.isEmpty ? "API Key" : "留空表示不换 Key", text: $addKey)
                .font(Rs.subhead)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Rs.fill))
            HStack(spacing: 10) {
                RsBtn(text: "保存") {
                    settings.llm2BaseURL = addBase.trimmingCharacters(in: .whitespacesAndNewlines)
                    settings.llm2Model = addModel.trimmingCharacters(in: .whitespacesAndNewlines)
                    let k = addKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !k.isEmpty { settings.llm2Key = k }
                    showAdd = false
                }
                RsBtn(text: "取消", filled: false) { showAdd = false }
                if settings.llm2Ready {
                    RsBtn(text: "删除", filled: false, danger: true) {
                        settings.llm2BaseURL = ""
                        settings.llm2Model = ""
                        settings.llm2Key = ""
                        settings.llmFailoverOn = false
                        showAdd = false
                    }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(400)])
        .background(Rs.bg)
    }

    private var thresholdSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("余额提醒").font(Rs.title).foregroundStyle(Rs.text)
            Text("余额低于这个数时在设置页提示一次。")
                .font(Rs.caption).foregroundStyle(Rs.text3)
            Stepper(value: $settings.balanceAlertThreshold, in: 0...200, step: 5) {
                Text(String(format: "低于 ¥%.0f 时提醒", settings.balanceAlertThreshold))
                    .font(Rs.body).foregroundStyle(Rs.text)
            }
            RsBtn(text: "完成") { showThreshold = false }
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(220)])
        .background(Rs.bg)
    }

    private func runCheck() {
        guard !checking else { return }
        checking = true
        checkNote = nil
        Task {
            var note = ""
            do {
                guard let client = LLMClient.auto() else { throw LLMError.notConfigured }
                let reply = try await client.ping()
                note = "正常：\(reply)"
            } catch {
                note = "失败：\(error.localizedDescription)"
            }
            await MainActor.run {
                checking = false
                checkNote = note
            }
        }
    }

    private func refreshBalance() {
        guard settings.llmReady else {
            balanceText = "还没配置密钥"
            return
        }
        guard settings.llmIsOfficial else {
            balanceText = "当前服务商不支持余额查询（只支持 DeepSeek 官方）"
            return
        }
        balanceText = "正在查余额…"
        Task {
            await account.refresh(key: settings.llmKey, base: settings.llmBaseURL, force: true)
            if let b = account.balance {
                let granted = b.grantedText.map { " · 含赠送 \($0)" } ?? ""
                let low = b.isLow(threshold: settings.balanceAlertThreshold)
                    ? " · 低于提醒线 ¥\(Int(settings.balanceAlertThreshold))"
                    : ""
                balanceText = "余额 \(b.totalText)\(granted)\(low)"
            } else if let err = account.error {
                balanceText = "余额查询失败：\(err)"
            } else {
                balanceText = "余额未查询"
            }
        }
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
// MARK: - 版本更新（AboutPage.kt 的更新区）

struct RsUpdatePage: View {
    @State private var checking = false
    @State private var note = "还没检查过"
    @State private var latestTag: String?

    private var current: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "-"
    }
    private var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "-"
    }

    var body: some View {
        RsSubPage(title: "版本更新") {
            RsGroup(title: "当前版本") {
                RsValueRow(title: "涛声 \(current)（\(build)）", value: "未签名测试包") { }
            }
            RsGroup(title: "检查更新") {
                RsValueRow(title: "检查更新", value: checking ? "正在检查…" : "点一下检查") {
                    check()
                }
                RsRowDivider(inset: 18)
                Text(note)
                    .font(Rs.caption)
                    .foregroundStyle(Rs.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
            RsFootNote(text: "这个包是自己签的测试包，装到手机上要重新签名，所以这里只查最新版本号，不自动装。")
        }
    }

    /// 只比数字段：0 相同、-1 当前更新、1 发布页更新
    static func compare(_ a: String, _ b: String) -> Int {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r ? 1 : -1 }
        }
        return 0
    }

    private func check() {
        guard !checking else { return }
        checking = true
        note = "正在检查…"
        Task {
            do {
                var req = URLRequest(url: URL(string: "https://api.github.com/repos/Dear-Mr-An/taosheng-ios/releases/latest")!)
                req.setValue("taosheng-ios", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: req)
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let tag = (obj?["tag_name"] as? String) ?? ""
                let body = ((obj?["body"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    checking = false
                    latestTag = tag.isEmpty ? nil : tag
                    guard !tag.isEmpty else {
                        note = "没查到最新版本号：发布页还没有 release，或者接口返回里没有 tag_name。稍后再试。"
                        return
                    }
                    let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                    switch Self.compare(latest, current) {
                    case 0:
                        note = "已经是最新版本（\(tag)）。"
                    case -1:
                        note = "当前 \(current) 比发布页的 \(tag) 还新。"
                    default:
                        let brief = body.isEmpty ? "（发布说明是空的）" : String(body.prefix(200))
                        note = "最新是 \(tag)，当前是 \(current)。发布说明：\(brief)"
                    }
                }
            } catch {
                await MainActor.run {
                    checking = false
                    note = "检查失败：\(error.localizedDescription)"
                }
            }
        }
    }
}
// MARK: - 外观（ThemeModePill / SettingsView 的 appearance）

struct RsAppearancePage: View {
    @AppStorage("appearance") private var appearance = "auto"

    /// 这一版的界面颜色是按浅色写死的（RsKit 的颜色令牌没有深色值），所以只提供浅色，
    /// 不宣称「自动跟随系统」——跟随以后深色系统下会一半浅一半深。
    private let options: [(String, String)] = [("light", "浅色")]

    var body: some View {
        RsSubPage(title: "外观") {
            RsGroup(title: "主题") {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                    if idx > 0 { RsRowDivider(inset: 18) }
                    Button { appearance = opt.0 } label: {
                        HStack {
                            Text(opt.1).font(Rs.body).foregroundStyle(Rs.text)
                            Spacer(minLength: 8)
                            RsRadio(on: appearance == opt.0)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            RsFootNote(text: "这一版只有浅色界面：界面颜色是按浅色写定的，还没有深色配色。")
        }
    }
}
/// 导入外部录音：拷进 Audio 目录、量时长、入库排队转写。两个设置页共用。
/// 逐个文件报结果：只有「复制成功 + 入库成功」才算导入成功，失败的带原因返回，下次还能重试。
struct RsImportOutcome {
    var added: [URL] = []
    var failures: [(name: String, reason: String)] = []

    var message: String {
        ImportRules.summary(added: added.count, failedNames: failures.map { $0.name })
    }
}

func rsImportAudio(_ urls: [URL], done: ((RsImportOutcome) -> Void)? = nil) {
    Task {
        var out = RsImportOutcome()
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
            let name = "import-\(UUID().uuidString).\(ext)"
            let dst = Store.audioDir.appendingPathComponent(name)
            do {
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.copyItem(at: url, to: dst)
            } catch {
                out.failures.append((url.lastPathComponent, "复制失败：\(error.localizedDescription)"))
                continue
            }
            let asset = AVURLAsset(url: dst)
            var seconds = 60.0
            if let d = try? await asset.load(.duration) {
                let s = CMTimeGetSeconds(d)
                if s.isFinite && s > 0 { seconds = s }
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: dst.path)[.size] as? Int) ?? 0
            let now = Date()
            let seg = Segment(
                id: UUID().uuidString,
                startedAt: now.addingTimeInterval(-seconds),
                endedAt: now,
                duration: seconds,
                fileName: name,
                byteSize: size,
                transcript: "",
                speaker: "",
                state: .recorded,
                day: DayKey.of(now),
                createdAt: now
            )
            if Store.shared.insert(seg) {
                out.added.append(url)
            } else {
                try? FileManager.default.removeItem(at: dst)
                out.failures.append((url.lastPathComponent, "入库失败"))
            }
        }
        let outcome = out
        await MainActor.run {
            if !outcome.added.isEmpty { TranscribeQueue.shared.transcribeNow() }
            done?(outcome)
        }
    }
}
