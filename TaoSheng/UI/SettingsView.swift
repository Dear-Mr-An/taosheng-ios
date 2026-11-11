import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var app: AppState
    @EnvironmentObject var capture: CaptureEngine
    @EnvironmentObject var digest: DigestEngine

    @State private var showPurgeConfirm = false
    @State private var purgeMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                transcribeSection
                digestSection
                captureSection
                storageSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("设置")
            .tint(Theme.accent)
            .alert("清理旧原音？", isPresented: $showPurgeConfirm) {
                Button("取消", role: .cancel) {}
                Button("清理", role: .destructive) {
                    app.purgeOldAudio()
                    purgeMessage = "已清理超过 \(settings.keepAudioDays) 天的原音（转写文字保留）"
                }
            } message: {
                Text("只删除已转写的音频文件，文字记录全部保留。")
            }
        }
    }

    // MARK: - 转写

    private var transcribeSection: some View {
        Section {
            Picker("转写方式", selection: $settings.asrKind) {
                ForEach(ASRKind.allCases) { k in
                    Text(k.title).tag(k)
                }
            }
            .onChange(of: settings.asrKind) { _ in
                TranscribeQueue.shared.tick()
            }

            Text(settings.asrKind.hint)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)

            if settings.asrKind == .openAICompatible {
                LabeledField(title: "Base URL", text: $settings.asrBaseURL, placeholder: "https://api.openai.com/v1")
                LabeledField(title: "模型", text: $settings.asrModel, placeholder: "whisper-1")
                LabeledField(title: "API Key", text: $settings.asrKey, placeholder: "sk-...", secure: true)
            }
            if settings.asrKind == .appleSpeech {
                LabeledField(title: "语言", text: $settings.asrLanguage, placeholder: "zh")
            }
            HStack {
                Text(settings.asrReady ? "转写已就绪" : "转写未配置")
                    .font(.system(size: 12))
                    .foregroundStyle(settings.asrReady ? Theme.ok : Theme.warn)
                Spacer()
                if let m = TranscribeQueue.shared.lastMessage {
                    Text(m).font(.system(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                }
            }
        } header: {
            Text("转写").foregroundStyle(Theme.dim)
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - 整理

    private var digestSection: some View {
        Section {
            LabeledField(title: "Base URL", text: $settings.llmBaseURL, placeholder: "https://api.deepseek.com/v1")
            LabeledField(title: "模型", text: $settings.llmModel, placeholder: "deepseek-chat")
            LabeledField(title: "API Key", text: $settings.llmKey, placeholder: "sk-...", secure: true)

            Toggle("每天自动整理", isOn: $settings.autoDigest)
            if settings.autoDigest {
                Stepper("整理时间：\(settings.digestHour):00", value: $settings.digestHour, in: 0...23)
            }

            HStack {
                Text(settings.llmReady ? "整理已就绪" : "整理未配置")
                    .font(.system(size: 12))
                    .foregroundStyle(settings.llmReady ? Theme.ok : Theme.warn)
                Spacer()
                Button(digest.running ? "整理中…" : "立刻整理今天") {
                    digest.digest(day: DayKey.of(Date()))
                }
                .font(.system(size: 12, weight: .medium))
                .disabled(digest.running)
            }
            if let e = digest.lastError {
                Text(e).font(.system(size: 11)).foregroundStyle(Theme.bad)
            }
        } header: {
            Text("AI 整理").foregroundStyle(Theme.dim)
        } footer: {
            Text("任何 OpenAI 兼容接口都能用：DeepSeek、豆包、Kimi、通义、本地 Ollama（填 http://192.168.x.x:11434/v1）。原话只发给你自己填的服务。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim.opacity(0.8))
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - 采集

    private var captureSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("灵敏度").font(.system(size: 14)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(String(format: "%.3f", settings.sensitivity))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                }
                Slider(value: $settings.sensitivity, in: 0.005...0.08)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("静音多久断句").font(.system(size: 14)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(String(format: "%.1f 秒", settings.silenceGap))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                }
                Slider(value: $settings.silenceGap, in: 0.6...4.0)
            }

            Stepper("最短一段：\(Int(settings.minSegment)) 秒", value: $settings.minSegment, in: 1...10)
            Stepper("最长一段：\(Int(settings.maxSegment)) 秒", value: $settings.maxSegment, in: 30...600, step: 30)

            HStack {
                Text(capture.isRunning ? "正在收音" : "未收音")
                    .font(.system(size: 12))
                    .foregroundStyle(capture.isRunning ? Theme.ok : Theme.dim)
                Spacer()
                Button(capture.isRunning ? "停止" : "开始") {
                    if capture.isRunning { capture.stop() } else { capture.start() }
                }
                .font(.system(size: 12, weight: .medium))
            }
        } header: {
            Text("收音").foregroundStyle(Theme.dim)
        } footer: {
            Text("iOS 只允许「录音类」App 在后台持续用麦克风。自签安装后可以后台常驻；如果系统回收，回到 App 会自动续上。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim.opacity(0.8))
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - 存储

    private var storageSection: some View {
        Section {
            Stepper("原音保留 \(settings.keepAudioDays) 天", value: $settings.keepAudioDays, in: 1...30)
            Button("现在清理旧原音") { showPurgeConfirm = true }
                .foregroundStyle(Theme.accent)
            if let m = purgeMessage {
                Text(m).font(.system(size: 11)).foregroundStyle(Theme.ok)
            }
            HStack {
                Text("今天：\(app.stats.segments) 段 · \(Int(app.stats.seconds / 60)) 分钟")
                    .font(.system(size: 12)).foregroundStyle(Theme.dim)
                Spacer()
                Text("待转写 \(app.stats.pending)")
                    .font(.system(size: 12)).foregroundStyle(app.stats.pending > 0 ? Theme.warn : Theme.dim)
            }
        } header: {
            Text("存储").foregroundStyle(Theme.dim)
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本").foregroundStyle(Theme.text)
                Spacer()
                Text("0.1.0 (iOS 版)").foregroundStyle(Theme.dim)
            }
            HStack {
                Text("数据").foregroundStyle(Theme.text)
                Spacer()
                Text("只在本机").foregroundStyle(Theme.ok)
            }
            Link(destination: URL(string: "https://github.com/0xCoach/TaoSheng")!) {
                HStack {
                    Text("原项目 TaoSheng").foregroundStyle(Theme.text)
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Theme.dim)
                }
            }
            Text("涛声 iOS 版是按原 Android 项目重写的精简实现：全天收音 → 自动转写 → AI 整理成待办和约定。没有账号、没有我们的服务器。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim.opacity(0.85))
        } header: {
            Text("关于").foregroundStyle(Theme.dim)
        }
        .listRowBackground(Theme.card)
    }
}

struct LabeledField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var secure: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.dim)
            if secure {
                SecureField(placeholder, text: $text)
                    .font(.system(size: 14, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(Theme.text)
            } else {
                TextField(placeholder, text: $text)
                    .font(.system(size: 14, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(Theme.text)
            }
        }
        .padding(.vertical, 2)
    }
}
