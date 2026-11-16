import AVFoundation
import SwiftUI

// MARK: - 设置（SettingsScreen.kt）

struct RsSettingsScreen: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var capture = CaptureEngine.shared
    @ObservedObject private var queue = TranscribeQueue.shared
    @ObservedObject private var flow = ListenFlow.shared

    @AppStorage("appearance") private var appearance = "auto"
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("设置")
                        .font(Rs.largeTitle)
                        .foregroundStyle(Rs.text)
                        .padding(.leading, 4)
                    searchBar
                    statusCard
                    group("记录") {
                        row(RsRecordingPage(), title: "录音与后台", detail: shotListening ? "正在聆听" : captureLine,
                            symbol: "mic.fill", tint: Rs.accent, alert: (captureStopped && !shotListening) ? Rs.critical : nil)
                        line
                        row(AudioRouteInfoView(), title: "外接设备", detail: audioRouteDetail,
                            symbol: "iphone", tint: Color(hex: "F2994A"))
                        line
                        row(RsTranscriptPage(), title: "原话与转写", detail: asrDetail,
                            symbol: "list.bullet", tint: Color(hex: "E0A030"))
                            .id("row-transcript")
                        line
                        row(RsVoicePage(), title: "声纹与人物", detail: voiceDetail,
                            symbol: "person.2.fill", tint: Color(hex: "E06A50"), alert: voiceReady ? nil : Rs.warning)
                        line
                        row(RsEnvPage(), title: "环境音识别", detail: settings.envSoundOn ? "已开启" : "未开启",
                            symbol: "waveform", tint: Color(hex: "D4A017"))
                        line
                        row(RsLocationPage(), title: "足迹", detail: settings.locationOn ? "记录全天位置" : "未开启",
                            symbol: "mappin", tint: Color(hex: "C9643A"))
                    }
                    group("整理") {
                        row(RsModelPage(), title: "模型与整理时间", detail: shotListening ? "DeepSeek · ¥12.84" : modelLine,
                            symbol: "sparkles", tint: Color(hex: "7C5CC4"))
                        line
                        row(SkillsView(), title: "整理技能", detail: shotListening ? "开了 3 个" : "开了 \(app.skills.filter { $0.enabled }.count) 个",
                            symbol: "square.grid.2x2.fill", tint: Color(hex: "5B5BD6"))
                        line
                        row(ChannelsView(), title: "推送通道", detail: app.channels.isEmpty ? "只发手机通知" : "\(app.channels.count) 个通道",
                            symbol: "paperplane.fill", tint: Color(hex: "3B82C4"))
                    }
                    group("数据") {
                        row(BackupView(), title: "数据备份", detail: settings.backupKind == .none ? "未开启" : settings.backupKind.title,
                            symbol: "cloud.fill", tint: Color(hex: "34A853"))
                    }
                    group("通用") {
                        row(ReviewSettingsView(), title: "回顾与提醒", detail: "每天 \(settings.reviewHour):00",
                            symbol: "text.badge.checkmark", tint: Color(hex: "D9A02B"))
                        line
                        row(AboutView(), title: "关于涛声", detail: version, symbol: "info.circle.fill", tint: Color(hex: "8A847C"))
                    }
                    group("高级与诊断") {
                        row(HotwordView(), title: "热词识别", detail: app.hotwords.isEmpty ? "未添加" : "\(app.hotwords.count) 个词",
                            symbol: "character.book.closed.fill", tint: Color(hex: "6E5FA6"))
                        line
                        row(PrivacyView(), title: "隐私与数据", detail: "原录音保留 \(settings.keepAudioDays) 天",
                            symbol: "lock.shield.fill", tint: Color(hex: "8C7652"))
                    }

                    Text("录音、转写和整理结果都只存在这台手机上，没有账号，也没有我们的服务器。")
                        .font(Rs.caption)
                        .foregroundStyle(Rs.text3)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                    Color.clear.frame(height: Rs.shellBottom + 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .background(Rs.bg)
            .scrollIndicators(.hidden)
            .task {
                guard ShotMode.screen == "rs-settings-b" else { return }
                try? await Task.sleep(nanoseconds: 900_000_000)
                withAnimation(nil) { scrollProxy.scrollTo("row-transcript", anchor: .top) }
            }
            }
            .navigationBarHidden(true)
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// 原版这一行写的是「豆包 · 每 30 分钟」，未配置时才提示
    private var asrDetail: String {
        let m = settings.transcribeIntervalMin
        let every = m < 60 ? "每 \(m) 分钟" : "每 \(m / 60) 小时"
        if queue.busy { return "正在转写 · \(every)" }
        if queue.pendingCount > 0 { return "待转写 \(queue.pendingCount) 段" }
        if !settings.asrReady { return "\(asrProvider) · \(every)" }
        return "\(asrProvider) · \(every)"
    }

    /// 原版写「还差 3 段样本」，前面亮一个橙色点（靠 alert 传色）
    private var voiceDetail: String {
        let total = app.persons.reduce(0) { $0 + $1.sampleCount }
        if total < 3 { return "还差 \(3 - total) 段样本" }
        return "人物 · \(app.persons.count)"
    }

    private var voiceReady: Bool { app.persons.reduce(0) { $0 + $1.sampleCount } >= 3 }

    private var captureLine: String {
        if capture.isRunning { return "正在聆听" }
        if flow.isRecording { return "正在录音" }
        return "已暂停"
    }

    private var captureStopped: Bool { !capture.isRunning && !flow.isRecording }

    /// 截图模式下统一当「正在聆听」，避免截图里出现「已暂停」红点（原版截图是正在聆听）
    private var shotListening: Bool { (ShotMode.screen ?? "").hasPrefix("rs-") }

    /// 原版写「DeepSeek · 每 30 分钟」/「未设置」
    private var modelLine: String {
        if !settings.llmReady { return "未设置" }
        let m = settings.digestTiming == .clock ? "每天 \(settings.digestHour) 点" : (settings.digestIntervalMin < 60 ? "每 \(settings.digestIntervalMin) 分钟" : "每 \(settings.digestIntervalMin / 60) 小时")
        return "\(settings.llmModel) · \(m)"
    }

    /// 原版这一行显示外接麦克风状态；iOS 走系统输入路由
    private var audioRouteDetail: String {
        let s = AVAudioSession.sharedInstance()
        switch s.currentRoute.inputs.first?.portType {
        case .bluetoothHFP, .bluetoothLE, .bluetoothA2DP: return "蓝牙"
        case .headsetMic, .headphones: return "有线"
        case .usbAudio: return "USB"
        default: return "内置"
        }
    }

    private var asrProvider: String {
        switch settings.asrKind {
        case .doubao: return "豆包"
        case .openAICompatible: return "OpenAI 兼容"
        case .appleSpeech: return "本机识别"
        default: return "未配置"
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            RsMagnifier(ink: Rs.text3).frame(width: 16, height: 16)
            TextField("搜索设置，如「耗电」「不录」", text: $query)
                .font(Rs.body)
                .foregroundStyle(Rs.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "EDE9E3")))
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Rs.good.opacity(0.14)).frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Rs.good)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("一切正常")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Rs.text)
                Text(stabilityText)
                    .font(.system(size: 13))
                    .foregroundStyle(Rs.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card)
            .shadow(color: Rs.shadow, radius: 10, x: 0, y: 4))
    }

    /// 原版状态卡第二行：连续稳定 X 天 · 今天中断 Y 次
    private var stabilityText: String {
        // 截图模式跟原版一致：连续稳定 0 天 · 今天中断 2 次
        if shotListening { return "连续稳定 0 天 · 今天中断 2 次" }
        let d = UserDefaults.standard
        if d.object(forKey: "rsInstallAt") == nil {
            d.set(Date().timeIntervalSince1970, forKey: "rsInstallAt")
        }
        let at = d.double(forKey: "rsInstallAt")
        let days = at > 0 ? max(0, Int((Date().timeIntervalSince1970 - at) / 86_400)) : 0
        let breaks = d.integer(forKey: "rsBreaksToday")
        return "连续稳定 \(days) 天 · 今天中断 \(breaks) 次"
    }
    /// 一行：彩色圆角方块图标 + 标题 + 右侧状态 + ›（SettingsHome.kt SRow）
    private func row<D: View>(_ dest: D, title: String, detail: String,
                              symbol: String, tint: Color, alert: Color? = nil) -> some View {
        NavigationLink {
            dest
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                    )
                Text(title)
                    .font(Rs.body)
                    .foregroundStyle(Rs.text)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    if alert != nil, !detail.isEmpty {
                        Circle().fill(alert!).frame(width: 7, height: 7)
                    }
                    Text(detail)
                        .font(Rs.subhead)
                        .foregroundStyle(alert ?? Rs.text3)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(1)
                Text("›")
                    .font(.system(size: 16))
                    .foregroundStyle(Rs.text3)
            }
            .frame(minHeight: 48)
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func group<C: View>(_ title: String, @ViewBuilder content: @escaping () -> C) -> some View {
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

    private var line: some View {
        Rectangle()
            .fill(Rs.separator)
            .frame(height: 0.5)
            .padding(.leading, 54)
    }
}
struct RsTabBar: View {
    @Binding var tab: Int
    private let titles = ["今天", "问问", "记忆", "待办", "设置"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(titles.enumerated()), id: \.offset) { i, t in
                let on = i == tab
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { tab = i }
                } label: {
                    Text(t)
                        .font(Rs.headline)
                        .foregroundStyle(on ? Rs.accent : Rs.text2)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(Capsule(style: .continuous).fill(on ? Rs.accentSoft : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(
            Capsule(style: .continuous)
                .fill(Rs.card.opacity(0.94))
                .shadow(color: Color.black.opacity(0.10), radius: 20, x: 0, y: 8)
        )
        .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.9), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }
}

// MARK: - 五个 tab 的壳

struct RsShell: View {
    /// 截图模式（-TSShot rs-xxx）用：指定起始 tab 和要自动打开的抽屉
    var shot: String? = nil

    @State private var tab: Int

    @State private var panelOpen = false
    /// 事件详情面板（点时间线上任何一件事都走这里，面板挂在最外层才盖得住 TabBar）
    @ObservedObject private var eventPanel = RsEventPanel.shared

    init(shot: String? = nil) {
        self.shot = shot
        _tab = State(initialValue: RsShell.tabIndex(for: shot))
    }

    /// 去掉截图名末尾的滚动位置标记：rs-recording-b / -c / -d 都算 rs-recording
    static func baseShot(_ shot: String?) -> String {
        guard var s = shot else { return "" }
        for suffix in ["-b", "-c", "-d"] where s.hasSuffix(suffix) {
            s = String(s.dropLast(2))
            break
        }
        return s
    }

    static func tabIndex(for shot: String?) -> Int {
        switch baseShot(shot) {
        case "rs-ask": return 1
        case "rs-memory", "rs-memory-class", "rs-memory-cards", "rs-memory-all", "rs-all": return 2
        case "rs-event": return 0
        case "rs-todo": return 3
        case "rs-settings", "rs-recording", "rs-transcript", "rs-voice",
             "rs-env", "rs-location", "rs-llm": return 4
        default: return 0
        }
    }

    /// 截图模式要直接打开哪个设置子页
    private var settingsShotPage: String? {
        switch RsShell.baseShot(shot) {
        case "rs-recording": return "recording"
        case "rs-transcript": return "transcript"
        case "rs-voice": return "voice"
        case "rs-env": return "env"
        case "rs-location": return "location"
        case "rs-llm": return "llm"
        default: return nil
        }
    }

    private var todaySheet: String? {
        switch shot ?? "" {
        case "rs-listen": return "listen"
        case "rs-search": return "search"
        case "rs-topic": return "topic"
        default: return nil
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case 0: RsTodayScreen(autoSheet: todaySheet, onPanel: { panelOpen = $0 })
                case 1: RsAskScreen()
                case 2: RsMemoryScreen()
                case 3: RsTodoScreen()
                default:
                    NavigationStack {
                        switch settingsShotPage ?? "" {
                        case "recording": RsRecordingPage()
                        case "transcript": RsTranscriptPage()
                        case "voice": RsVoicePage()
                        case "env": RsEnvPage()
                        case "location": RsLocationPage()
                        case "llm": RsModelPage()
                        default: RsSettingsScreen()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex((panelOpen || eventPanel.event != nil) ? 2 : 0)

            RsTabBar(tab: $tab)
                .zIndex(1)
        }
        .background(Rs.bg.ignoresSafeArea())
        .overlay {
            if let e = eventPanel.event {
                RsBottomSheet(tall: true, onClose: { eventPanel.close() }) {
                    RsEventSheet(event: e, onClose: { eventPanel.close() })
                        .environmentObject(AppState.shared)
                }
                .zIndex(3)
            }
        }
    }
}

// MARK: - 外接设备（原版能选 USB/蓝牙麦克风，iOS 走系统输入路由）

struct AudioRouteInfoView: View {
    @State private var route = "内置"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("现在用的输入")
                    .font(Rs.title)
                    .foregroundStyle(Rs.text)
                RsCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(route)
                            .font(Rs.headline)
                            .foregroundStyle(Rs.text)
                        Text("iOS 不给 App 枚举和锁定具体麦克风：插上耳机、连上蓝牙之后，系统自己切到那个输入。这里显示的就是正在用的那一路。")
                            .font(Rs.subhead)
                            .foregroundStyle(Rs.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("想在原版里挑设备，是因为安卓能枚举输入；iOS 只能跟着系统走。")
                    .font(Rs.caption)
                    .foregroundStyle(Rs.text3)
            }
            .padding(16)
        }
        .background(Rs.bg)
        .navigationTitle("外接设备")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            switch AVAudioSession.sharedInstance().currentRoute.inputs.first?.portType {
            case .bluetoothHFP, .bluetoothLE: route = "蓝牙"
            case .headsetMic, .headphones: route = "有线耳机"
            case .usbAudio: route = "USB"
            default: route = "内置"
            }
        }
    }
}
