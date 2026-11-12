import SwiftUI
import UniformTypeIdentifiers

// MARK: - 录音与后台
struct RecordingSettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var capture: CaptureEngine
    @EnvironmentObject var app: AppState
    @State private var inputs: [MicRouter.Input] = []
    @State private var tick = 0

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Circle()
                        .fill(capture.isRunning ? Theme.ok : Theme.dim2)
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(capture.isRunning ? "正在聆听" : "已暂停")
                            .font(.system(size: 15, weight: .semibold))
                        Text(capture.isRunning ? "已持续 \(uptime)" : "点右边开始，它会一直在后台听")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Button(capture.isRunning ? "暂停" : "开始") {
                        if capture.isRunning {
                            capture.stop()
                            UserDefaults.standard.set(false, forKey: "captureWanted")
                        } else {
                            capture.start()
                            UserDefaults.standard.set(true, forKey: "captureWanted")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
            }

            Section("录音输入") {
                ForEach(inputs) { i in
                    Button {
                        settings.preferredInputUID = i.id
                        MicRouter.shared.applyPreferred()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: iconFor(i.kind))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(i.name).foregroundStyle(Theme.text)
                                Text(i.kind).font(.system(size: 11)).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            if settings.preferredInputUID == i.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
                Text("正在用：\(MicRouter.shared.currentName())")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.dim)
                Button("刷新设备列表") { inputs = MicRouter.shared.inputs() }
                    .font(.system(size: 13))
            }

            Section {
                Toggle("自动转写", isOn: $settings.autoTranscribe).tint(Theme.accent)
                Toggle("热词纠错", isOn: $settings.hotwordEnabled).tint(Theme.accent)
                NavigationLink("热词表（\(app.hotwords.count)）") { HotwordView() }
            } header: {
                Text("转写")
            } footer: {
                Text("录完 1 分钟就自动转，不用自己调间隔。")
            }

            Section {
                VStack(alignment: .leading) {
                    Text("灵敏度 \(String(format: "%.3f", settings.sensitivity))")
                        .font(.system(size: 13))
                    Slider(value: $settings.sensitivity, in: 0.005...0.08)
                        .tint(Theme.accent)
                }
                Stepper(value: $settings.minSegment, in: 1...10, step: 0.5) {
                    Text("最短 \(String(format: "%.0f", settings.minSegment)) 秒")
                }
                Toggle("手机在放视频/音乐时不转写", isOn: $settings.skipWhenOutput).tint(Theme.accent)
            } header: {
                Text("只录人声")
            } footer: {
                Text("停顿多久算断句跟着「今天」页的模式走：日常 1.5 秒、会议 2.5 秒、培训 3 秒、通话 1.8 秒。")
            }

            Section("停录时段") {
                Toggle("夜里自动停录", isOn: $settings.silenceWindowOn).tint(Theme.accent)
                if settings.silenceWindowOn {
                    Stepper(value: $settings.silenceStartHour, in: 0...23) {
                        Text("从 \(settings.silenceStartHour):00 开始")
                    }
                    Stepper(value: $settings.silenceEndHour, in: 0...23) {
                        Text("到 \(settings.silenceEndHour):00 结束")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("录音与后台")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { inputs = MicRouter.shared.inputs() }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            tick += 1
            if tick % 5 == 0 { inputs = MicRouter.shared.inputs() }
        }
    }

    private var uptime: String {
        guard let t = capture.startedAt else { return "刚刚开始" }
        let s = Int(Date().timeIntervalSince(t))
        if s < 60 { return "\(s) 秒" }
        let m = s / 60
        if m < 60 { return "\(m) 分钟" }
        return "\(m / 60) 小时 \(m % 60) 分"
    }

    private func iconFor(_ kind: String) -> String {
        if kind.contains("蓝牙") { return "airpodspro" }
        if kind.contains("USB") { return "cable.connector" }
        if kind.contains("耳机") { return "headphones" }
        if kind.contains("车载") { return "car" }
        return "iphone"
    }
}

// MARK: - 热词
struct HotwordView: View {
    @EnvironmentObject var app: AppState
    @State private var word = ""
    @State private var repl = ""

    var body: some View {
        Form {
            Section("添加") {
                TextField("听到的（如：涛生）", text: $word)
                TextField("改成（如：涛声）", text: $repl)
                Button("加进去") {
                    guard !word.isEmpty else { return }
                    app.addHotword(word: word, replacement: repl.isEmpty ? word : repl)
                    word = ""; repl = ""
                }
            }
            Section("已有 \(app.hotwords.count) 条") {
                ForEach(app.hotwords) { h in
                    HStack {
                        Text(h.word)
                        Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Theme.dim2)
                        Text(h.replacement).foregroundStyle(Theme.text2)
                        Spacer()
                        Button {
                            app.deleteHotword(h.id)
                        } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.bad)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("热词纠错")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 声纹与人物
struct PersonsView: View {
    @EnvironmentObject var app: AppState
    @State private var newName = ""
    @State private var showAdd = false

    var body: some View {
        Form {
            Section {
                ForEach(app.persons) { p in
                    HStack(spacing: 10) {
                        SpeakerDot(name: p.name, size: 9)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).foregroundStyle(Theme.text)
                            Text(detail(p))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        if p.isMe {
                            Text("是我").font(.system(size: 10.5))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Theme.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .swipeActions {
                        if !p.isMe {
                            Button(role: .destructive) {
                                app.deletePerson(p.id)
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
            } header: {
                Text("人物 · \(app.persons.count)")
            } footer: {
                Text("在原话上长按选「这是谁」，指定一次就会把这个人的声音记下来，之后自动认出。")
            }

            Section {
                Button {
                    newName = ""
                    showAdd = true
                } label: {
                    Label("添加人物", systemImage: "person.badge.plus")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("声纹与人物")
        .navigationBarTitleDisplayMode(.inline)
        .alert("新的人物", isPresented: $showAdd) {
            TextField("名字", text: $newName)
            Button("添加") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { app.addPerson(name: n) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func detail(_ p: Person) -> String {
        if p.sampleCount == 0 { return "还没有样本 · 长按原话指定" }
        return "已能认出 · \(p.sampleCount) 段样本"
    }
}

// MARK: - 技能详情
struct SkillDetailView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings

    @State private var skill: SkillDef
    @State private var busy = false
    @State private var msg: String?
    @State private var card: SkillCard?

    init(skill: SkillDef) {
        _skill = State(initialValue: skill)
    }

    var body: some View {
        Form {
            Section {
                TextField("名字", text: $skill.name)
                TextField("说明", text: $skill.desc)
            } header: {
                Text("名字和说明")
            }

            Section {
                Picker("什么时候运行", selection: $skill.schedule) {
                    Text("说完自动识别").tag(SkillSchedule.afterDigest)
                    Text("每天定时").tag(SkillSchedule.daily)
                    Text("每周定时").tag(SkillSchedule.weekly)
                    Text("只手动").tag(SkillSchedule.manual)
                }
                if skill.schedule == .daily || skill.schedule == .weekly {
                    Stepper(value: $skill.hour, in: 0...23) {
                        Text("时间 \(String(format: "%02d:%02d", skill.hour, skill.minute))")
                    }
                }
                Toggle("生成后推送", isOn: $settings.pushOnDigest)
            } header: {
                Text("什么时候运行")
            } footer: {
                Text("改完保存，回到技能页可以「试一下」看效果。已出的旧卡不受影响。")
            }

            Section {
                if skill.fields.isEmpty {
                    Text("默认：一句话 + 要点").foregroundColor(Theme.dim)
                }
                ForEach(skill.fields) { f in
                    HStack {
                        Text(f.label).font(.system(size: 14))
                        Spacer()
                        Text(f.typeText + (f.required ? " · 必有" : ""))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.dim)
                    }
                }
            } header: {
                Text("卡片上有什么")
            }

            Section {
                Button {
                    runNow()
                } label: {
                    HStack {
                        Text(busy ? "正在生成…" : "试一下")
                        Spacer()
                        if busy { ProgressView().scaleEffect(0.7) }
                    }
                }
                .disabled(busy)

                if let m = msg {
                    Text(m).font(.system(size: 12)).foregroundColor(Theme.dim)
                }
                if let c = card {
                    ForEach(Array(c.fields.keys.sorted()), id: \.self) { k in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(k).font(.system(size: 11)).foregroundColor(Theme.dim)
                            Text(c.fields[k] ?? "").font(.system(size: 13.5))
                        }
                    }
                }
            } header: {
                Text("生成一张看看")
            }

            Section {
                Button("保存") {
                    app.saveSkill(skill)
                    msg = "已保存"
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle(skill.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runNow() {
        busy = true
        msg = nil
        Task {
            do {
                let c = try await SkillEngine.shared.run(skill, day: DayKey.of(Date()))
                await MainActor.run {
                    card = c
                    busy = false
                    msg = c.isNothing ? (c.nothingReason ?? "今天没有相关内容") : "生成完成，已放进今天的记忆里"
                }
            } catch {
                await MainActor.run {
                    busy = false
                    msg = "没跑成：\(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - 整理技能
struct SkillsView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var engine = SkillEngine.shared
    @State private var busy = false
    @State private var err: String?

    var body: some View {
        Form {
            Section {
                ForEach(app.skills) { s in
                    NavigationLink {
                        SkillDetailView(skill: s)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: s.symbol)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name).foregroundStyle(Theme.text)
                                Text("\(s.desc) · \(s.scheduleText)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { s.enabled },
                                set: { _ in app.toggleSkill(s.id) }
                            ))
                            .labelsHidden()
                            .tint(Theme.accent)
                        }
                    }
                }
            } header: {
                Text("技能 · \(app.skills.count)")
            } footer: {
                Text("每个技能就是一份提示词 + 一个运行时间。跑完的结果会出现在这里，也会推送给你。")
            }

            Section {
                Button {
                    generate()
                } label: {
                    HStack {
                        Label(busy ? "正在想…" : "智能生成一个新技能", systemImage: "sparkles")
                        Spacer()
                        if busy { ProgressView().scaleEffect(0.7) }
                    }
                }
                .disabled(busy)
            }

            if let err {
                Section {
                    Text(err)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.bad)
                }
            }

            if let autoErr = engine.lastError {
                Section {
                    Text(autoErr)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.bad)
                } header: {
                    Text("自动运行出错")
                }
            }

            if !app.skillRuns.isEmpty {
                Section("最近的产出") {
                    ForEach(app.skillRuns) { r in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(r.skillName) · \(DayKey.display(r.day))")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.dim)
                            Text(r.title).font(.system(size: 14, weight: .medium))
                            Text(r.output)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.text2)
                                .lineLimit(4)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("整理技能")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func generate() {
        guard !busy else { return }
        busy = true
        err = nil
        Task {
            do {
                let s = try await SkillEngine.shared.suggestSkill(day: DayKey.of(Date()))
                Store.shared.upsertSkill(s)
                await MainActor.run { busy = false; app.refresh() }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { busy = false; err = "生成失败：\(msg)" }
            }
        }
    }
}

// MARK: - 推送通道
struct ChannelsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settings: Settings
    @State private var adding = false
    @State private var kind: ChannelKind = .webhook
    @State private var name = ""
    @State private var url = ""
    @State private var extra = ""
    @State private var testing: String?
    @State private var testResult: String?

    var body: some View {
        Form {
            Section {
                ForEach(app.channels) { c in
                    HStack(spacing: 10) {
                        Image(systemName: c.kind.symbol)
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name).foregroundStyle(Theme.text)
                            Text(c.kind.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim)
                                .lineLimit(2)
                            if let t = c.lastPushAt {
                                Text("\(timeText(t)) · \(c.lastStatus)")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(c.lastStatus.contains("失败") ? Theme.bad : Theme.ok)
                            }
                        }
                        Spacer()
                        Button("测试") { test(c) }
                            .font(.system(size: 12))
                            .buttonStyle(.bordered)
                            .tint(Theme.accent)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            app.deleteChannel(c.id)
                        } label: { Label("删除", systemImage: "trash") }
                    }
                }
            } header: {
                Text("通道 · \(app.channels.count)")
            } footer: {
                Text("整理完的原话和结果会按通道推出去，只推新增、修改和删除。你的 Agent 可以直接调用。")
            }

            Section("推送时机") {
                Toggle("整理完就推", isOn: $settings.pushOnDigest).tint(Theme.accent)
                Toggle("回顾生成就推", isOn: $settings.pushOnReview).tint(Theme.accent)
                Toggle("有新待办就推", isOn: $settings.pushOnTodo).tint(Theme.accent)
            }

            Section {
                Button {
                    name = ""; url = ""; extra = ""
                    adding = true
                } label: {
                    Label("添加通道", systemImage: "plus.circle")
                }
            }

            if let r = testResult {
                Section("测试结果") {
                    Text(r).font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("推送通道")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    Picker("类型", selection: $kind) {
                        ForEach(ChannelKind.allCases) { k in
                            Text(k.title).tag(k)
                        }
                    }
                    TextField("名字", text: $name)
                    if kind.needsURL {
                        TextField(kind.urlHint, text: $url)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    TextField("附加参数（可选）", text: $extra)
                }
                .navigationTitle("新通道")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { adding = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") {
                            let c = Channel(id: shortID(),
                                            kind: kind,
                                            name: name.isEmpty ? kind.title : name,
                                            url: url,
                                            extra: extra,
                                            enabled: true,
                                            lastPushAt: nil,
                                            lastStatus: "",
                                            createdAt: Date())
                            app.addChannel(c)
                            adding = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func test(_ c: Channel) {
        testing = c.id
        testResult = "正在测试 \(c.name)…"
        Task {
            let r = await PushEngine.shared.test(c)
            await MainActor.run {
                testing = nil
                testResult = r
                app.refresh()
            }
        }
    }

    private func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:mm"
        return f.string(from: d)
    }
}

// MARK: - 数据备份
struct BackupView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var app: AppState
    @State private var busy = false
    @State private var msg: String?

    var body: some View {
        Form {
            Section {
                Picker("存到哪", selection: $settings.backupKindRaw) {
                    ForEach(BackupKind.allCases) { k in
                        Text(k.title).tag(k.rawValue)
                    }
                }
            } footer: {
                Text("坚果云用应用密码；WebDAV 填完整地址；S3 兼容存储填 Endpoint。")
            }

            if settings.backupKind != .none {
                Section("连接") {
                    TextField("地址 / Endpoint", text: $settings.backupURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("账号 / AccessKey", text: $settings.backupUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码 / SecretKey", text: $settings.backupPass)
                    if settings.backupKind == .s3 {
                        TextField("Bucket", text: $settings.backupBucket)
                        TextField("Region", text: $settings.backupRegion)
                    }
                }

                Section("自动") {
                    Toggle("每晚自动备份", isOn: $settings.backupAuto).tint(Theme.accent)
                    Picker("保留版本", selection: $settings.backupKeepVersions) {
                        Text("3 份").tag(3)
                        Text("7 份").tag(7)
                        Text("30 份").tag(30)
                    }
                }

                Section {
                    Button {
                        backupNow()
                    } label: {
                        HStack {
                            Label(busy ? "正在传…" : "立即备份今天", systemImage: "arrow.up.to.line")
                            Spacer()
                            if busy { ProgressView().scaleEffect(0.7) }
                        }
                    }
                    .disabled(busy)

                    Button {
                        restore()
                    } label: {
                        Label("从云端恢复", systemImage: "arrow.down.to.line")
                    }
                    .disabled(busy)
                }

                if let m = msg {
                    Section("结果") { Text(m).font(.system(size: 12.5)) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("数据备份")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func backupNow() {
        guard !busy else { return }
        busy = true
        Task {
            let r = await BackupEngine.shared.backupNow(day: DayKey.of(Date()))
            await MainActor.run { busy = false; msg = r }
        }
    }

    private func restore() {
        guard !busy else { return }
        busy = true
        Task {
            let r = await BackupEngine.shared.restoreLatest()
            await MainActor.run {
                busy = false
                msg = r
                app.refresh()
            }
        }
    }
}

// MARK: - 模型与转写
struct ModelSettingsView: View {
    enum Part { case both, asr, llm }

    var part: Part = .both

    @EnvironmentObject var settings: Settings

    var body: some View {
        Form {
            if part != .llm {
            Section {
                SecureField("豆包语音 API Key", text: $settings.doubaoApiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: settings.doubaoApiKey) { v in
                        if !v.isEmpty && settings.asrKind != .doubao {
                            settings.asrKind = .doubao
                        }
                    }

                Text(settings.asrReady
                     ? "已填好，转写会自动开始。"
                     : "在火山引擎语音控制台复制 API Key 贴进来就行，别的都不用填。")
                    .font(.system(size: 12))
                    .foregroundColor(settings.asrReady ? Theme.ok : Theme.dim)

                DisclosureGroup("用别的转写服务（可选）") {
                    Picker("方式", selection: $settings.asrKind) {
                        ForEach(ASRKind.allCases) { k in
                            Text(k.title).tag(k)
                        }
                    }
                    if settings.asrKind == .doubao {
                        TextField("Resource Id", text: $settings.doubaoResourceId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        DisclosureGroup("老版 App Key + Access Key") {
                            TextField("App Key", text: $settings.doubaoAppKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            SecureField("Access Key", text: $settings.doubaoAccessKey)
                        }
                    }
                    if settings.asrKind == .openAICompatible {
                        TextField("接口地址", text: $settings.asrBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("模型", text: $settings.asrModel)
                            .textInputAutocapitalization(.never)
                        SecureField("API Key", text: $settings.asrKey)
                        TextField("或填完整请求地址", text: $settings.asrFullURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if !settings.asrKind.hint.isEmpty {
                        Text(settings.asrKind.hint)
                            .font(.caption)
                            .foregroundColor(Theme.dim)
                    }
                }
            } header: {
                Text("转写服务")
            } footer: {
                Text(settings.asrReady ? "转写已就绪。" : "\(settings.asrReadyHint)，转写会停在「待转写」。")
            }
            }

        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("原话与转写")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 回顾与提醒
struct ReviewSettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var app: AppState

    private let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    var body: some View {
        Form {
            Section("每日回顾") {
                Stepper(value: $settings.reviewHour, in: 0...23) {
                    Text("每天 \(settings.reviewHour):00 生成")
                }
                Text("自动整理的间隔和时间点在「整理模型」里设置。")
                    .font(.caption).foregroundColor(Theme.dim)
            }

            Section("每周回顾") {
                Picker("哪一天", selection: $settings.weeklyReviewWeekday) {
                    ForEach(1...7, id: \.self) { i in
                        Text(weekdays[i - 1]).tag(i)
                    }
                }
            }

            Section {
                Toggle("整理完推给我", isOn: $settings.pushOnDigest).tint(Theme.accent)
                Toggle("回顾生成推给我", isOn: $settings.pushOnReview).tint(Theme.accent)
            }

            Section("提醒") {
                ForEach(app.reminders) { r in
                    HStack {
                        Text(r.title)
                        Spacer()
                        Text(r.fireAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("回顾与提醒")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 隐私与数据
struct PrivacyView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var app: AppState
    @State private var showExport = false
    @State private var items: [Any] = []
    @State private var confirmWipe = false

    var body: some View {
        Form {
            Section {
                Stepper(value: $settings.keepAudioDays, in: 1...365) {
                    Text("原录音保留 \(settings.keepAudioDays) 天")
                }
                Button("现在就清掉过期的") {
                    app.purgeOldAudio()
                }
            } header: {
                Text("原录音")
            } footer: {
                Text("标了重点的不会被清掉。转写文本和整理结果一直留着。")
            }

            Section("导出") {
                Button {
                    let md = app.exportMarkdown(day: DayKey.of(Date()))
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("涛声-\(DayKey.of(Date())).md")
                    if (try? md.write(to: url, atomically: true, encoding: .utf8)) != nil {
                        items = [url]
                        showExport = true
                    }
                } label: {
                    Label("导出今天的原话和整理", systemImage: "doc.text")
                }
                NavigationLink("导入录音文件") { ImportView() }
            }

            Section {
                Toggle("记下每天去过哪", isOn: $settings.locationOn).tint(Theme.accent)
                Toggle("整理时参考地点和环境音", isOn: $settings.usePlaceInDigest).tint(Theme.accent)
                Toggle("识别环境音", isOn: $settings.envSoundOn).tint(Theme.accent)
            } footer: {
                Text("地点默认只保存在本机；开启「整理时参考地点和环境音」后，会随原话发送给 DeepSeek。")
            }

            Section {
                Button(role: .destructive) {
                    confirmWipe = true
                } label: {
                    Label("清空所有数据", systemImage: "trash")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("隐私与数据")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showExport) { ShareSheet(items: items) }
        .alert("确定清空？", isPresented: $confirmWipe) {
            Button("清空", role: .destructive) {
                app.wipeAll()
                app.refresh()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("录音、原话、待办、回顾、人物和通道全部删掉，不能恢复。")
        }
    }
}

// MARK: - 导入
struct ImportView: View {
    @State private var msg: String?
    @State private var busy = false
    @State private var showPicker = false

    var body: some View {
        Form {
            Section {
                Button {
                    showPicker = true
                } label: {
                    Label(busy ? "正在导入…" : "选择音频文件", systemImage: "doc.badge.plus")
                }
                .disabled(busy)
            } footer: {
                Text("支持 m4a / mp3 / wav / aac / caf / amr / flac / ogg。导入后会自动转写、认人、整理。")
            }
            if let m = msg {
                Section("结果") { Text(m).font(.system(size: 12.5)) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("导入录音")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            DocumentPicker { urls in
                guard !urls.isEmpty else { return }
                busy = true
                Task {
                    let r = await ImportEngine.shared.importFiles(urls)
                    await MainActor.run { busy = false; msg = r }
                }
            }
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.audio, .mpeg4Audio, .wav, .mp3]
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        vc.allowsMultipleSelection = true
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

// MARK: - 关于
struct AboutView: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("涛声").font(.system(size: 18, weight: .bold))
                        Text("0.2.0 · iOS").font(.system(size: 12)).foregroundStyle(Theme.dim)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Text("一直在听，从不外传。录音、转写、整理都在你自己的设备和你的接口上完成。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text2)
            }

            Section("说明") {
                Text("· 后台持续录音靠系统音频后台模式维持，被系统回收后回到 App 会自动续上。\n· 声纹认人是本机比对，样本只存在手机上。\n· 模型和转写服务都用你自己填的密钥，我们不收任何数据。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text2)
                    .lineSpacing(3)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("关于涛声")
        .navigationBarTitleDisplayMode(.inline)
    }
}
