import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var app: AppState
    @EnvironmentObject var capture: CaptureEngine

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    VStack(spacing: 0) {
                        nav(RecordingSettingsView(), icon: "waveform", title: "录音与后台",
                            detail: capture.isRunning ? "正在聆听 · \(MicRouter.shared.currentName())" : "已暂停")
                        Divider().overlay(Theme.lineSoft).padding(.leading, 48)
                        nav(PersonsView(), icon: "person.2", title: "声纹与人物",
                            detail: "人物 · \(app.persons.count)")
                        Divider().overlay(Theme.lineSoft).padding(.leading, 48)
                        nav(SkillsView(), icon: "wand.and.stars", title: "整理技能",
                            detail: "\(app.skills.filter { $0.enabled }.count) 个已开启")
                        Divider().overlay(Theme.lineSoft).padding(.leading, 48)
                        nav(ChannelsView(), icon: "paperplane", title: "推送通道",
                            detail: "通道 · \(app.channels.count)")
                        Divider().overlay(Theme.lineSoft).padding(.leading, 48)
                        nav(BackupView(), icon: "externaldrive", title: "数据备份",
                            detail: settings.backupKind == .none ? "只存在本机" : settings.backupKind.title)
                    }
                    .card(padding: 6)

                    VStack(spacing: 0) {
                        nav(ModelSettingsView(), icon: "brain", title: "模型与转写",
                            detail: settings.llmReady ? "\(settings.llmModel) · 已就绪" : "还没配密钥")
                        Divider().overlay(Theme.lineSoft).padding(.leading, 48)
                        nav(ReviewSettingsView(), icon: "text.badge.checkmark", title: "回顾与提醒",
                            detail: "每天 \(settings.reviewHour):00 生成")
                        Divider().overlay(Theme.lineSoft).padding(.leading, 48)
                        nav(PrivacyView(), icon: "lock.shield", title: "隐私与数据",
                            detail: "原录音保留 \(settings.keepAudioDays) 天")
                    }
                    .card(padding: 6)

                    VStack(spacing: 0) {
                        nav(AboutView(), icon: "info.circle", title: "关于涛声",
                            detail: "0.2.0")
                    }
                    .card(padding: 6)

                    Text("所有录音、转写和整理结果都只存在这台手机上。没有账号，没有我们的服务器。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dim2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 110)
            }
            .background(Theme.bg.ignoresSafeArea())
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("设置")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.text)
            Text("涛声 · 一直在听，从不外传")
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
        }
    }

    private func nav<D: View>(_ dest: D, icon: String, title: String, detail: String) -> some View {
        NavigationLink {
            dest
        } label: {
            SettingRow(icon: icon, title: title, detail: detail)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }
}
