import SwiftUI

// MARK: - 设置（SettingsScreen.kt）

struct RsSettingsScreen: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var capture = CaptureEngine.shared
    @ObservedObject private var queue = TranscribeQueue.shared

    @AppStorage("appearance") private var appearance = "auto"
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("设置")
                        .font(Rs.largeTitle)
                        .foregroundStyle(Rs.text)
                        .padding(.leading, 4)
                    searchBar
                    statusCard
                    group("记录") {
                        row(RecordingSettingsView(), title: "录音与后台", detail: capture.isRunning ? "正在聆听" : "已暂停",
                            symbol: "mic.fill", tint: Rs.accent)
                        line
                        row(TranscribeOverviewView(), title: "原话与转写", detail: asrDetail,
                            symbol: "list.bullet", tint: Color(hex: "D9A02B"))
                        line
                        row(LLMSettingsView(), title: "大模型", detail: settings.llmReady ? settings.llmModel : "未填密钥",
                            symbol: "brain", tint: Color(hex: "E0603A"))
                        line
                        row(PersonsView(), title: "声纹与人物", detail: voiceDetail,
                            symbol: "person.2.fill", tint: Color(hex: "D9534F"))
                        line
                        row(EnvironmentSoundView(), title: "环境音识别", detail: settings.envSoundOn ? "已开启" : "未开启",
                            symbol: "waveform", tint: Color(hex: "C99A0E"))
                        line
                        row(FootprintView(), title: "足迹", detail: settings.locationOn ? "记录全天位置" : "未开启",
                            symbol: "mappin", tint: Color(hex: "C4693C"))
                    }
                    group("整理") {
                        row(SkillsView(), title: "整理技能", detail: "开了 \(app.skills.filter { $0.enabled }.count) 个",
                            symbol: "wand.and.stars", tint: Color(hex: "8A7BE0"))
                        line
                        row(HotwordView(), title: "热词识别", detail: app.hotwords.isEmpty ? "未添加" : "\(app.hotwords.count) 个词",
                            symbol: "character.book.closed.fill", tint: Color(hex: "4F86C6"))
                        line
                        row(ChannelsView(), title: "推送通道", detail: app.channels.isEmpty ? "只发手机通知" : "\(app.channels.count) 个通道",
                            symbol: "paperplane.fill", tint: Rs.good)
                    }
                    group("数据") {
                        row(BackupView(), title: "数据备份", detail: settings.backupKind == .none ? "未开启" : settings.backupKind.title,
                            symbol: "externaldrive.fill", tint: Color(hex: "6B8E23"))
                        line
                        row(PrivacyView(), title: "隐私与数据", detail: "原录音保留 \(settings.keepAudioDays) 天",
                            symbol: "lock.shield.fill", tint: Rs.text2)
                    }
                    group("关于") {
                        row(ReviewSettingsView(), title: "回顾与提醒", detail: "每天 \(settings.reviewHour):00",
                            symbol: "text.badge.checkmark", tint: Color(hex: "B4762E"))
                        line
                        row(AboutView(), title: "关于涛声", detail: version, symbol: "info.circle.fill", tint: Rs.text2)
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
        if !settings.asrReady { return "未配置 · \(every)" }
        return "\(asrProvider) · \(every)"
    }

    /// 原版写「● 还差 3 段样本」
    private var voiceDetail: String {
        let total = app.persons.reduce(0) { $0 + $1.sampleCount }
        if total < 3 { return "● 还差 \(3 - total) 段样本" }
        return "人物 · \(app.persons.count)"
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
                Circle().fill(Rs.good.opacity(0.14)).frame(width: 44, height: 44)
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Rs.good)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("一切正常")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Rs.text)
                Text(capture.isRunning ? "正在聆听 · 每 \(settings.transcribeIntervalMin) 分钟转写" : "没在聆听 · 点今天页的状态开始")
                    .font(.system(size: 15))
                    .foregroundStyle(Rs.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
        .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card)
            .shadow(color: Rs.shadow, radius: 10, x: 0, y: 4))
    }

    private var line: some View {
        Rectangle()
            .fill(Rs.separator)
            .frame(height: 0.5)
            .padding(.leading, 70)
    }

    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Rs.section)
                .foregroundStyle(Rs.text3)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: Rs.cardRadius, style: .continuous).fill(Rs.card)
                    .shadow(color: Rs.shadow, radius: 10, x: 0, y: 4))
        }
    }

    private func row<D: View>(_ dest: D, title: String, detail: String, symbol: String, tint: Color) -> some View {
        NavigationLink {
            dest
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint)
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.white))
                Text(title)
                    .font(Rs.headline)
                    .foregroundStyle(Rs.text)
                Spacer(minLength: 8)
                Text(detail)
                    .font(Rs.subhead)
                    .foregroundStyle(Rs.text3)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Rs.text3)
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 底部 TabBar（AppShell.kt TabBar）

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

    init(shot: String? = nil) {
        self.shot = shot
        _tab = State(initialValue: RsShell.tabIndex(for: shot))
    }

    static func tabIndex(for shot: String?) -> Int {
        switch shot ?? "" {
        case "rs-ask": return 1
        case "rs-memory": return 2
        case "rs-todo": return 3
        case "rs-settings": return 4
        default: return 0
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
                case 0: RsTodayScreen(autoSheet: todaySheet)
                case 1: RsAskScreen()
                case 2: RsMemoryScreen()
                case 3: RsTodoScreen()
                default: RsSettingsScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            RsTabBar(tab: $tab)
        }
        .background(Rs.bg.ignoresSafeArea())
    }
}
