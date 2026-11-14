import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var app: AppState
    @EnvironmentObject var capture: CaptureEngine
    @ObservedObject private var queue = TranscribeQueue.shared

    @AppStorage("appearance") private var appearance = "auto"

    private var asrDot: Color {
        if !settings.asrReady { return Theme.warn }
        return queue.pendingCount > 0 ? Theme.warn : Theme.ok
    }

    private var asrDetail: String {
        if !settings.asrReady { return "转写未就绪" }
        if queue.busy { return "正在转写" }
        if queue.pendingCount > 0 { return "待转写 \(queue.pendingCount) 段" }
        return "都转完了"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    group("记录") {
                        nav(RecordingSettingsView(), icon: "waveform", title: "录音与后台",
                            dot: capture.isRunning ? Theme.ok : Theme.dim2,
                            detail: capture.isRunning ? "正在聆听" : "已暂停")
                        sep
                        nav(TranscribeOverviewView(), icon: "text.bubble", title: "转写与原话",
                            dot: asrDot,
                            detail: asrDetail)
                        sep
                        nav(LLMSettingsView(), icon: "brain", title: "大模型与整理",
                            dot: settings.llmReady ? Theme.ok : Theme.warn,
                            detail: settings.llmReady ? settings.llmModel : "未填密钥")
                        sep
                        nav(EnvironmentSoundView(), icon: "wind", title: "环境音识别",
                            dot: settings.envSoundOn ? Theme.ok : Theme.dim2,
                            detail: settings.envSoundOn ? "已开启" : "未开启")
                        sep
                        nav(FootprintView(), icon: "location", title: "足迹",
                            dot: settings.locationOn ? Theme.ok : Theme.dim2,
                            detail: settings.locationOn ? "记录全天位置" : "未开启")
                    }

                    group("智能") {
                        nav(SkillsView(), icon: "wand.and.stars", title: "整理技能",
                            dot: Theme.dim2,
                            detail: "开了 \(app.skills.filter { $0.enabled }.count) 个")
                        sep
                        nav(HotwordView(), icon: "character.book.closed", title: "热词识别",
                            dot: Theme.dim2,
                            detail: app.hotwords.isEmpty ? "未添加" : "\(app.hotwords.count) 个词")
                        sep
                        nav(ChannelsView(), icon: "paperplane", title: "推送通道",
                            dot: Theme.dim2,
                            detail: app.channels.isEmpty ? "只发手机通知" : "通道 · \(app.channels.count)")
                        sep
                        nav(PersonsView(), icon: "person.2", title: "声纹与人物",
                            dot: Theme.dim2,
                            detail: "人物 · \(app.persons.count)")
                    }

                    group("数据") {
                        nav(BackupView(), icon: "externaldrive", title: "数据备份",
                            dot: settings.backupKind == .none ? Theme.dim2 : Theme.ok,
                            detail: settings.backupKind == .none ? "未开启" : settings.backupKind.title)
                    }

                    group("外观") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "circle.lefthalf.filled")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.dim)
                                    .frame(width: 22)
                                Text("日间 / 夜间")
                                    .font(.system(size: Theme.fsBody))
                                    .foregroundColor(Theme.text)
                                Spacer()
                            }
                            Picker("", selection: $appearance) {
                                Text("日间").tag("light")
                                Text("夜间").tag("dark")
                                Text("跟随系统").tag("auto")
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                    }

                    group("关于") {
                        nav(AboutView(), icon: "info.circle", title: "关于涛声",
                            dot: Theme.dim2,
                            detail: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        sep
                        nav(PrivacyView(), icon: "lock.shield", title: "隐私与数据",
                            dot: Theme.dim2, detail: "原录音保留 \(settings.keepAudioDays) 天")
                        sep
                        nav(ReviewSettingsView(), icon: "text.badge.checkmark", title: "回顾与提醒",
                            dot: Theme.dim2, detail: "每天 \(settings.reviewHour):00")
                    }

                    Text("录音、转写和整理结果都只存在这台手机上，没有账号，也没有我们的服务器。\n转写时音频会发给你配置的转写服务，整理时原话会发给你配置的大模型服务。")
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(Theme.dim2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
        .tabBarClearance()
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("设置")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(Theme.text)
        }
    }

    private var sep: some View {
        Divider().overlay(Theme.lineSoft).padding(.leading, 44)
    }

    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: Theme.fsSmall, weight: .medium))
                .foregroundColor(Theme.dim)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        }
    }

    private func nav<D: View>(_ dest: D, icon: String, title: String,
                              dot: Color, detail: String) -> some View {
        NavigationLink { dest } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.dim)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: Theme.fsBody))
                    .foregroundColor(Theme.text)
                Spacer()
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(detail)
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.dim2)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: Theme.fsCaption, weight: .semibold))
                    .foregroundColor(Theme.dim2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 环境音识别

struct EnvironmentSoundView: View {
    @EnvironmentObject var settings: Settings
    @State private var todayTags: [String: String] = [:]

    private var summary: String {
        guard !todayTags.isEmpty else { return "" }
        var count: [String: Int] = [:]
        for v in todayTags.values { count[v, default: 0] += 1 }
        return count.sorted { $0.value > $1.value }
            .prefix(2)
            .map { "\($0.key) \($0.value)" }
            .joined(separator: " · ")
    }

    var body: some View {
        Form {
            Section {
                Toggle("环境音识别", isOn: $settings.envSoundOn)
            } footer: {
                Text("只分析已经录下的人声片段，在转写时判断一次；录音方式不变，旧录音不补算。全部在手机上完成，不上传。")
            }
            Section(header: Text("今天")) {
                if todayTags.isEmpty {
                    Text(settings.envSoundOn ? "还没有识别记录，转写几段就会出现" : "打开后，新转写的片段会带上环境标签")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.dim)
                } else {
                    HStack {
                        Text("已识别 \(todayTags.count) 段")
                            .font(.system(size: 14))
                        Spacer()
                        Text(summary)
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.dim)
                    }
                }
            }
            Section {
                Text("能分辨的：人声、音乐、键盘、家电、环境噪音、安静。用的是本地轻量特征，不联网；结果会附在整理时的原话行后面。")
                    .font(.system(size: Theme.fsSmall))
                    .foregroundColor(Theme.dim)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .tabBarClearance()
        .navigationTitle("环境音识别")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { todayTags = Store.shared.envTags(day: DayKey.of(Date())) }
    }
}

// MARK: - 足迹

struct FootprintView: View {
    @EnvironmentObject var settings: Settings
    @State private var places: [PlaceVisit] = []

    var body: some View {
        Form {
            Section {
                Toggle("记录全天位置", isOn: $settings.locationOn)
            } footer: {
                Text("跟随收音服务，约每 5 分钟记一个点；位置记录只存手机本地。")
            }
            Section(header: Text("今天")) {
                if places.isEmpty {
                    Text("这一天没有位置记录").foregroundColor(Theme.dim)
                } else {
                    ForEach(places) { p in
                        HStack {
                            Text(p.name).font(.system(size: 14))
                            Spacer()
                            Text(p.durationText).font(.system(size: Theme.fsSmall)).foregroundColor(Theme.dim)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .tabBarClearance()
        .navigationTitle("足迹")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            places = Store.shared.places(day: DayKey.of(Date()))
            LocationEngine.shared.syncWithSettings()
        }
        .onChange(of: settings.locationOn) { _ in
            LocationEngine.shared.syncWithSettings()
        }
    }
}
