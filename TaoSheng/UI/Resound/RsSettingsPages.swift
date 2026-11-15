import SwiftUI

// MARK: - 设置子页（SettingsScreen.kt SubPageBar + 分组白卡）

struct RsSubPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss

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
            .font(.system(size: 12.5, weight: .medium))
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

// MARK: - 录音与后台

struct RsRecordingPage: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var capture = CaptureEngine.shared
    @AppStorage("captureWanted") private var captureWanted = true

    var body: some View {
        RsSubPage(title: "录音与后台") {
            statusCard
            RsGroup(title: "停录时段") {
                RsToggleRow(title: "睡眠", note: "\(settings.silenceStartHour):00 – 次日 \(settings.silenceEndHour):00 · 每天",
                            on: $settings.silenceWindowOn)
                RsRowDivider()
                Button {
                    settings.silenceWindowOn = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("添加时段").font(Rs.subhead)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Rs.accent)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("时段内不录音，到点自动恢复；时段内点「现在恢复」只对这一次有效。")
                .font(Rs.caption).foregroundStyle(Rs.text3)
                .padding(.horizontal, 4)
            RsGroup(title: "录制") {
                RsToggleRow(title: "一直在听", note: "关了就只在点「开始聆听」之后才录", on: $captureWanted)
                RsRowDivider()
                RsToggleRow(title: "别的应用出声时不录", note: "看视频、开会时有声音，就不重复录一遍", on: $settings.skipWhenOutput)
            }
            RsGroup(title: "保留") {
                VStack(alignment: .leading, spacing: 10) {
                    RsFormLabel("原录音保留多久")
                    RsPillRow(options: [("7 天", 7), ("30 天", 30), ("90 天", 90), ("一直留", 0)],
                              selected: Binding(get: { settings.keepAudioDays }, set: { settings.keepAudioDays = $0 }))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                RsRowDivider(inset: 0)
                RsToggleRow(title: "夜里自动停录", on: $settings.silenceWindowOn)
                if settings.silenceWindowOn {
                    RsRowDivider(inset: 0)
                    Text("从 \(settings.silenceStartHour):00 到 \(settings.silenceEndHour):00 不录。")
                        .font(Rs.caption).foregroundStyle(Rs.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            RsGroup(title: "切段") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("多大声音算在说话").font(Rs.body).foregroundStyle(Rs.text)
                        Spacer(minLength: 0)
                        Text(String(format: "%.3f", settings.sensitivity))
                            .font(Rs.subhead).foregroundStyle(Rs.text3)
                    }
                    Slider(value: $settings.sensitivity, in: 0.006...0.03)
                        .tint(Rs.accent)
                    Text("越小越灵敏。会议用 0.014，培训 0.018。")
                        .font(Rs.caption).foregroundStyle(Rs.text3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                RsRowDivider(inset: 0)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("最短一段").font(Rs.body).foregroundStyle(Rs.text)
                        Spacer(minLength: 0)
                        Text("\(Int(settings.minSegment)) 秒").font(Rs.subhead).foregroundStyle(Rs.text3)
                    }
                    Slider(value: $settings.minSegment, in: 1...12, step: 1)
                        .tint(Rs.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    /// 顶部状态卡：原版第一张卡
    private var statusCard: some View {
        let listening = capture.isRunning || ShotMode.screen == "rs-recording"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(listening ? Rs.good : Rs.text3)
                    .frame(width: 8, height: 8)
                Text(listening ? (capture.isSpeaking ? "正在录音" : "正在聆听") : "没在聆听")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Rs.text)
                Spacer(minLength: 0)
                Text("内置麦克风")
                    .font(Rs.subhead)
                    .foregroundStyle(Rs.text3)
            }
            Text(listening ? "安静中 · 已持续 \(uptimeText)" : "点了「开始聆听」才会录")
                .font(Rs.subhead)
                .foregroundStyle(Rs.text3)
            RsDotLine(active: listening)
                .frame(height: 8)
            HStack(spacing: 10) {
                Button {
                    RsQuiet.shared.pause(minutes: 60)
                } label: {
                    Text("暂停 1 小时")
                        .font(Rs.subhead)
                        .foregroundStyle(Rs.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Rs.accentSoft))
                }
                .buttonStyle(.plain)
                Button {
                    UserDefaults.standard.set(false, forKey: "captureWanted")
                    CaptureEngine.shared.stop()
                } label: {
                    Text("停止")
                        .font(Rs.subhead)
                        .foregroundStyle(Rs.critical)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Rs.critical.opacity(0.10)))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card)
        )
    }

    private var uptimeText: String {
        guard let start = capture.startedAt else { return "0 分钟" }
        let m = Int(Date().timeIntervalSince(start) / 60)
        if m < 60 { return "\(m) 分钟" }
        return "\(m / 60) 小时 \(m % 60) 分"
    }
}

// MARK: - 原话与转写

struct RsTranscriptPage: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var queue = TranscribeQueue.shared

    private let intervalOptions = [(5, "5 分"), (10, "10 分"), (30, "30 分"), (60, "1 小时")]

    var body: some View {
        RsSubPage(title: "原话与转写") {
            RsGroup(title: "服务商") {
                VStack(alignment: .leading, spacing: 10) {
                    RsPillRow(options: [(ASRKind.doubao.title, 0), (ASRKind.openAICompatible.title, 1), (ASRKind.appleSpeech.title, 2)],
                              selected: Binding(get: {
                                  switch settings.asrKind {
                                  case .doubao: return 0
                                  case .openAICompatible: return 1
                                  default: return 2
                                  }
                              }, set: { v in
                                  settings.asrKind = v == 0 ? .doubao : (v == 1 ? .openAICompatible : .appleSpeech)
                              }))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                if settings.asrKind == .openAICompatible {
                    RsRowDivider(inset: 0)
                    RsFieldRow(title: "地址", placeholder: "https://…", text: $settings.asrBaseURL)
                    RsRowDivider(inset: 0)
                    RsFieldRow(title: "模型", placeholder: "whisper-1", text: $settings.asrModel)
                    RsRowDivider(inset: 0)
                    RsFieldRow(title: "密钥", placeholder: "sk-…", text: $settings.asrKey, secure: true)
                }
                if settings.asrKind == .doubao {
                    RsRowDivider(inset: 0)
                    RsFieldRow(title: "API Key", placeholder: "豆包语音的 Key", text: $settings.doubaoApiKey, secure: true)
                }
            }
            RsGroup(title: "节奏") {
                VStack(alignment: .leading, spacing: 10) {
                    RsFormLabel("多久转写一次")
                    RsPillRow(options: intervalOptions.map { ($0.1, $0.0) },
                              selected: Binding(get: { settings.transcribeIntervalMin }, set: { settings.transcribeIntervalMin = $0 }))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                RsRowDivider(inset: 0)
                RsToggleRow(title: "只在 WiFi 下转写", note: "打开后，用流量时不转写，连上 WiFi 再补。默认关：蜂窝也照转。", on: $settings.wifiOnlyTranscribe)
            }
            RsGroup(title: "现在") {
                RsNoteRow(text: queue.pendingCount > 0 ? "还有 \(queue.pendingCount) 段没转写，可以点下面马上转。" : "没有待转写的片段。")
                RsRowDivider(inset: 0)
                Button {
                    queue.transcribeNow()
                } label: {
                    Text("马上转写")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Rs.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 声纹与人物

struct RsVoicePage: View {
    @ObservedObject private var app = AppState.shared

    private var samples: Int { app.persons.reduce(0) { $0 + $1.sampleCount } }

    var body: some View {
        RsSubPage(title: "声纹与人物") {
            RsGroup(title: "进度") {
                RsNoteRow(text: samples >= 3
                          ? "够了，已经能认出你；会议里再按声音区分其他说话人。"
                          : "还差 \(3 - samples) 段样本。录几段自己的原话，认人就更准。")
            }
            RsGroup(title: "人物") {
                if app.persons.isEmpty {
                    RsNoteRow(text: "还没有人物。分过说话人之后，这里会列出每场会议出现过的人。")
                } else {
                    ForEach(Array(app.persons.enumerated()), id: \.element.id) { i, p in
                        HStack(spacing: 12) {
                            Text(String(p.name.prefix(1)))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Theme.personColor(p.name)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(Rs.body).foregroundStyle(Rs.text)
                                Text("\(p.sampleCount) 段样本").font(Rs.caption).foregroundStyle(Rs.text3)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        if i < app.persons.count - 1 { RsRowDivider() }
                    }
                }
            }
        }
    }
}

// MARK: - 环境音识别

struct RsEnvPage: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        RsSubPage(title: "环境音识别") {
            RsGroup(title: "开关") {
                RsToggleRow(title: "认一下当时的环境", note: "把雨声、咖啡馆、电视这些写进原话旁边，整理时能当参考。", on: $settings.envSoundOn)
            }
            RsGroup(title: "说明") {
                RsNoteRow(text: "只在本机判断，不外传音频。关掉也不影响录音和转写。")
            }
        }
    }
}

// MARK: - 足迹

struct RsLocationPage: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        RsSubPage(title: "足迹") {
            RsGroup(title: "开关") {
                RsToggleRow(title: "记录全天位置", note: "低频记录去过哪，整理时标一句「在公司」「在外地」。", on: $settings.locationOn)
                RsRowDivider()
                RsToggleRow(title: "整理时参考地点", on: $settings.usePlaceInDigest)
            }
            RsGroup(title: "说明") {
                RsNoteRow(text: "位置只存在这台手机上，可以随时删。关掉后不再记录新的位置。")
            }
        }
    }
}

// MARK: - 模型与整理时间

struct RsModelPage: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var digest = DigestEngine.shared

    var body: some View {
        RsSubPage(title: "模型与整理时间") {
            RsGroup(title: "大模型") {
                RsFieldRow(title: "地址", placeholder: "https://api.deepseek.com", text: $settings.llmBaseURL)
                RsRowDivider(inset: 0)
                RsFieldRow(title: "模型", placeholder: "deepseek-chat", text: $settings.llmModel)
                RsRowDivider(inset: 0)
                RsFieldRow(title: "密钥", placeholder: "sk-…", text: $settings.llmKey, secure: true)
                RsRowDivider(inset: 0)
                RsToggleRow(title: "整理前先思考", note: "慢一点，结论更稳", on: $settings.deepThinking)
            }
            RsGroup(title: "什么时候整理") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(DigestTiming.allCases) { t in
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) { settings.digestTiming = t }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: settings.digestTiming == t ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 17))
                                    .foregroundStyle(settings.digestTiming == t ? Rs.accent : Rs.text3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title).font(Rs.body).foregroundStyle(Rs.text)
                                    Text(t.detail).font(Rs.caption).foregroundStyle(Rs.text3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(settings.digestTiming == t ? Rs.accentSoft.opacity(0.6) : Color.clear)
                        }
                        .buttonStyle(.plain)
                        if t != DigestTiming.allCases.last { RsRowDivider() }
                    }
                }
            }
            if settings.digestTiming == .interval {
                RsGroup(title: "间隔") {
                    VStack(alignment: .leading, spacing: 10) {
                        RsFormLabel("多久整理一次")
                        RsPillRow(options: [("5 分", 5), ("10 分", 10), ("30 分", 30), ("1 小时", 60)],
                                  selected: Binding(get: { settings.digestIntervalMin }, set: { settings.digestIntervalMin = $0 }))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            if settings.digestTiming == .clock {
                RsGroup(title: "时间点") {
                    Stepper(value: $settings.digestHour, in: 0...23) {
                        Text("每天 \(settings.digestHour):00").font(Rs.body).foregroundStyle(Rs.text)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            RsGroup(title: "状态") {
                RsNoteRow(text: settings.llmReady
                          ? (digest.running ? "正在整理…" : (digest.lastError.map { "上次出错：\($0)" } ?? "模型已就绪。"))
                          : "还没填密钥：可以先录音、转写，填好后回来点「现在整理」。")
            }
        }
    }
}
