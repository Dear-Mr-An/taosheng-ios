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
        ScrollViewReader { proxy in
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
                        // 换设备后音频引擎会自己停，必须重建一次，否则仍在用旧设备
                        if capture.isRunning { capture.restartSoon() }
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
                Text("录完先落盘，之后每 \(max(1, settings.transcribeIntervalMin)) 分钟批量转写一次（可在下方调整）。")
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
                    // 起止相同等于「时长 0」，代码里直接判为不在时段内，开关看起来开着但永不生效
                    if settings.silenceStartHour == settings.silenceEndHour {
                        Text("开始和结束不能是同一个小时，否则这段停录不会生效。")
                            .font(.system(size: 12)).foregroundStyle(Theme.warn)
                    }
                }
            }
            if ShotMode.active {
                Section {
                    Color.clear.frame(height: 1).id("shot-end")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .tabBarClearance()
        .modifier(ShotBottomAnchor())
        .navigationTitle("录音与后台")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { inputs = MicRouter.shared.inputs() }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            tick += 1
            if tick % 5 == 0 { inputs = MicRouter.shared.inputs() }
        }
        .onAppear {
            // 截图模式：滚到最后一行，验证「停录时段」不会被悬浮 TabBar 挡住
            guard ShotMode.active else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation(nil) { proxy.scrollTo("shot-end", anchor: .bottom) }
            }
        }
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
        .tabBarClearance()
        .navigationTitle("热词纠错")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 声纹与人物
struct PersonsView: View {
    @EnvironmentObject var app: AppState
    @State private var newName = ""
    @State private var showAdd = false
    @State private var shotOpened = false

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
        .tabBarClearance()
        .navigationTitle("声纹与人物")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 截图模式：直接弹出新增人物，看输入框有没有被裁
            if ShotMode.screen == "person-add", !shotOpened {
                shotOpened = true
                showAdd = true
            }
        }
        .sheet(isPresented: $showAdd) {
            TextInputSheet(title: "新的人物",
                           fields: [TextInputField(label: "名字", placeholder: "例如 老王", text: newName)],
                           confirmTitle: "添加",
                           message: "指定一次原话，之后就能自动认出这个人的声音。") { values in
                let n = values.first ?? ""
                if !n.isEmpty { app.addPerson(name: n) }
                newName = ""
            }
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
                    if skill.schedule == .weekly {
                        Picker("周几", selection: $skill.weekday) {
                            ForEach(1...7, id: \.self) { w in
                                Text(SkillDef.weekName(w)).tag(w)
                            }
                        }
                    }
                    Stepper("小时 \(skill.hour) 点", value: $skill.hour, in: 0...23)
                    Stepper("分钟 \(skill.minute) 分", value: $skill.minute, in: 0...55, step: 5)
                }
                // 推送开关是全局设置，放在单个技能里会让人以为只影响这个技能

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
                    let name = skill.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else {
                        msg = "名字不能为空"
                        return
                    }
                    skill.name = name
                    app.saveSkill(skill)
                    msg = "已保存"
                }
                .disabled(skill.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .tabBarClearance()
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
                    HStack(spacing: 10) {
                        // 开关必须放在 NavigationLink 外面：塞进 label 里时点开关会同时触发跳转
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
                                Spacer(minLength: 0)
                            }
                        }
                        Toggle("", isOn: Binding(
                            get: { s.enabled },
                            set: { app.setSkillEnabled(s.id, $0) }
                        ))
                        .labelsHidden()
                        .tint(Theme.accent)
                    }
                    .swipeActions {
                        if !s.builtin {
                            Button(role: .destructive) {
                                app.deleteSkill(s.id)
                            } label: { Label("删除", systemImage: "trash") }
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
        .tabBarClearance()
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
    @State private var davUser = ""
    @State private var davPass = ""
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
                            .disabled(testing != nil)
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
                    name = ""; url = ""; extra = ""; davUser = ""; davPass = ""
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
        .tabBarClearance()
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
                    if kind == .nutstore {
                        TextField("WebDAV 地址（https://dav.jianguoyun.com/dav/）", text: $url)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        TextField("账号（邮箱）", text: $davUser)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                        SecureField("应用密码", text: $davPass)
                        TextField("保存路径（可选，默认 taosheng/digest.md）", text: $extra)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        TextField("附加参数（可选）", text: $extra)
                    }
                }
                .navigationTitle("新通道")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { adding = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") {
                            let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
                            let c = Channel(id: shortID(),
                                            kind: kind,
                                            name: name.isEmpty ? kind.title : name,
                                            url: u,
                                            extra: extra.trimmingCharacters(in: .whitespacesAndNewlines),
                                            enabled: true,
                                            lastPushAt: nil,
                                            lastStatus: "",
                                            createdAt: Date(),
                                            user: davUser.trimmingCharacters(in: .whitespacesAndNewlines),
                                            pass: davPass)
                            app.addChannel(c)
                            adding = false
                        }
                        .disabled(!canSaveChannel)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// 必填校验：坚果云要地址+账号+密码，其他只要地址（ntfy 还要频道名）
    private var canSaveChannel: Bool {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .nutstore {
            return !u.isEmpty && !davUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if kind.needsURL && u.isEmpty { return false }
        if kind == .ntfy && extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 频道名可以直接写在地址里，这时地址必须带路径
            if let comp = URLComponents(string: u), !comp.path.isEmpty, comp.path != "/" { return true }
            return false
        }
        return true
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

    private func timeText(_ d: Date) -> String { Fmt.monthDayTime.string(from: d) }
}

// MARK: - 数据备份
struct BackupView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var app: AppState
    @State private var busy = false
    @State private var msg: String?
    @State private var confirmRestore = false

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
                        confirmRestore = true
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
        .tabBarClearance()
        .navigationTitle("数据备份")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("从云端恢复会用云上的内容覆盖本机这一天和待办", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("继续恢复", role: .destructive) { restore() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("恢复只覆盖整理结果与待办，原话录音不会被动。")
        }
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

// MARK: - 模型与整理
struct ModelSettingsView: View {
    @EnvironmentObject var settings: Settings
    @ObservedObject private var queue = TranscribeQueue.shared
    @StateObject private var account = DeepSeekAccount()

    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var exporting = false
    @State private var showAdvanced = false
    @State private var showLLM = false
    @State private var showImport = false
    @State private var showKeepDays = false
    @State private var stats = Stats()
    @State private var showTranscribe = false
    @State private var todaySegments: [Segment] = []
    @State private var checking = false
    @State private var checkMessage: String?
    @State private var checkOK = false
    @State private var checkTask: Task<Void, Never>?
    @State private var purgeTip = ""

    private struct Stats {
        var todayMinutes: Double = 0
        var monthMinutes: Double = 0
        var bytes: Int64 = 0
        var total: Int = 0
        var done: Int = 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Theme.sp3) {
                statusCard
                rawLinesCard
                llmCard
                timingCard
            }
            .padding(Theme.sp4)
        }
        .background(Theme.bg.ignoresSafeArea())
        .tabBarClearance()
        .navigationTitle("模型与整理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTranscribe) {
            TranscribeSettingsSheet()
                .environmentObject(settings)
        }
        .onAppear { reload() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            reload()
        }
        .sheet(isPresented: Binding(get: { exportURL != nil },
                                    set: { if !$0 { exportURL = nil } })) {
            if let u = exportURL { ShareSheet(items: [u]) }
        }
        .sheet(isPresented: $showLLM) {
            DeepSeekEditorSheet()
                .environmentObject(settings)
        }
        .task(id: settings.llmKey) {
            await account.refresh(key: settings.llmKey)
        }
        .onDisappear { invalidateCheck() }
        .sheet(isPresented: $showKeepDays) {
            keepDaysSheet
        }
        .fileImporter(isPresented: $showImport,
                      allowedContentTypes: [.audio, .mpeg4Audio, .wav, .mp3],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task {
                    let msg = await ImportEngine.shared.importFiles(urls)
                    await MainActor.run { exportError = msg; reload() }
                }
            }
        }
        .alert("提示", isPresented: Binding(get: { exportError != nil },
                                            set: { if !$0 { exportError = nil } })) {
            Button("好") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    // MARK: 状态卡

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(queue.pendingCount > 0 ? Theme.warn : Theme.ok)
                    .frame(width: 9, height: 9)
                    .offset(y: -1)
                Text(statusTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer(minLength: 0)
                Button { showTranscribe = true } label: {
                    Text("模型和转写设置")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)
            }

            Text(statusLine)
                .font(.system(size: 12.5))
                .foregroundColor(Theme.dim)
                .padding(.top, 6)

            HStack(spacing: 10) {
                Button {
                    queue.transcribeNow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { reload() }
                } label: {
                    Text(queue.busy ? "转写中…" : "现在转写")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(queue.busy || !settings.asrReady)

                Button { showImport = true } label: {
                    Text("导入录音")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Theme.accentSoft)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)

            Divider().overlay(Theme.lineSoft).padding(.vertical, 12)

            statRow("云端转写", cloudLine) { exportError = cloudDetail }
            Divider().overlay(Theme.lineSoft)
            statRow("原声", audioLine) { showKeepDays = true }
            Divider().overlay(Theme.lineSoft)
            statRow("录音包", exporting ? "正在打包录音…" : "把手机里的原始录音打包导出") { exportAudio() }

            HStack {
                Text("录音原话")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.dim)
                Spacer()
                Text("\(stats.total) 段 · 已转 \(stats.done)")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.text2)
            }
            .padding(.top, 12)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private var statusTitle: String {
        if queue.busy { return "正在转写" }
        if !settings.asrReady { return "转写尚未就绪" }
        if queue.pendingCount > 0 { return "还有 \(queue.pendingCount) 段待转写" }
        return "都转完了"
    }

    private var statusLine: String {
        if !settings.asrReady { return settings.asrReadyHint }
        var parts: [String] = []
        if let last = queue.lastRunAt {
            parts.append("上次 \(Self.timeText(last))")
        } else {
            parts.append("还没转过")
        }
        if let next = queue.nextRunAt {
            let m = max(1, Int(next.timeIntervalSinceNow / 60))
            parts.append("约 \(m) 分钟后下一轮")
        } else {
            parts.append("有新的原话就自动转")
        }
        return parts.joined(separator: " · ")
    }

    private var cloudLine: String {
        let today = Self.minutesText(stats.todayMinutes)
        let month = Self.minutesText(stats.monthMinutes)
        if stats.monthMinutes <= 0 { return "今天 0 分 · 近 30 天 0 分" }
        return "今天 \(today) · 近 30 天 \(month) · 约 ¥\(Self.cost(stats.monthMinutes))"
    }

    private var cloudDetail: String {
        "云端转写按分钟计费，豆包录音文件识别约 ¥0.8/小时。\n今天 \(Self.minutesText(stats.todayMinutes))，近 30 天 \(Self.minutesText(stats.monthMinutes))，估算 ¥\(Self.cost(stats.monthMinutes))。\n只有转写时才会把录音发出去。"
    }

    private var audioLine: String {
        "保留 \(settings.keepAudioDays) 天 · 重点长期保留 · 占用 \(ByteText.short(stats.bytes))"
    }

    private func statRow(_ label: String, _ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.dim)
                    .frame(width: 62, alignment: .leading)
                Text(value)
                    .font(.system(size: 13.5))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.dim2)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 多久转写一次

    // MARK: 语言 / 原声 / 热词

    private var rawLinesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("今天的原话")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Text("\(todaySegments.count) 段")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.dim)
            }

            if todaySegments.isEmpty {
                Text("今天还没有录到原话。回「今天」页点「开始聆听」。")
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(todaySegments.prefix(5)) { s in
                    SegmentRow(seg: s,
                               starred: Store.shared.isStarred(id: s.id),
                               onPlay: { SegmentPlayer.shared.toggle(segment: s) },
                               onStar: {
                                   Store.shared.setStar(id: s.id, starred: !Store.shared.isStarred(id: s.id))
                                   Task { await reloadAsync() }
                               })
                }
                NavigationLink {
                    RawLinesView(day: DayKey.of(Date()))
                } label: {
                    HStack(spacing: 4) {
                        Text(todaySegments.count > 5 ? "看全部 \(todaySegments.count) 段" : "打开原话页")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    // MARK: 工具

    // MARK: 整理用的模型（固定 DeepSeek，不再提供切换服务商）

    private var llmCard: some View {
        VStack(alignment: .leading, spacing: Theme.sp3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("整理用的大模型")
                    .font(.system(size: Theme.fsCardTitle, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer(minLength: 0)
                Button("编辑") { showLLM = true }
                    .font(.system(size: Theme.fsSmall, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .buttonStyle(.plain)
            }

            Text(settings.llmReady
                 ? "\(settings.llmModel) · 已填密钥"
                 : "还没填 DeepSeek 密钥，整理、问问、技能、回顾都用它")
                .font(.system(size: Theme.fsSmall))
                .foregroundColor(settings.llmReady ? Theme.dim : Theme.warn)
                .fixedSize(horizontal: false, vertical: true)

            if settings.llmReady {
                balanceLine

                HStack(spacing: Theme.sp4) {
                    Button(checking ? "检测中…" : "检测连接") { checkLLM() }
                        .disabled(checking)
                    Button(account.loading ? "查询中…" : "刷新余额") {
                        Task { await account.refresh(key: settings.llmKey, force: true) }
                    }
                    .disabled(account.loading)
                    Spacer(minLength: 0)
                }
                .font(.system(size: Theme.fsBody, weight: .medium))
                .foregroundColor(Theme.accent)
                .buttonStyle(.plain)

                if let checkMessage {
                    Text(checkMessage)
                        .font(.system(size: Theme.fsCaption))
                        .foregroundColor(checkOK ? Theme.ok : Theme.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                Picker("余额提醒", selection: $settings.balanceAlertThreshold) {
                    Text("不提醒").tag(0.0)
                    Text("低于 ¥5").tag(5.0)
                    Text("低于 ¥10").tag(10.0)
                    Text("低于 ¥20").tag(20.0)
                }
                .tint(Theme.accent)
                .font(.system(size: Theme.fsSmall))
            } else {
                Button { showLLM = true } label: {
                    Text("填写 DeepSeek 密钥")
                        .font(.system(size: Theme.fsBody, weight: .semibold))
                        .foregroundColor(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.accentSoft)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Text("只用 DeepSeek，密钥保存在本机，页面上不显示。")
                .font(.system(size: Theme.fsCaption))
                .foregroundColor(Theme.dim2)
        }
        .padding(Theme.sp4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    @ViewBuilder private var balanceLine: some View {
        if account.loading {
            Text("余额查询中…").font(.system(size: Theme.fsSmall)).foregroundColor(Theme.dim)
        } else if let error = account.error {
            Text(error).font(.system(size: Theme.fsSmall)).foregroundColor(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
        } else if let balance = account.balance {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(balance.available ? "余额" : "账户暂不可用")
                        .font(.system(size: Theme.fsSmall)).foregroundColor(Theme.dim)
                    Text(balance.totalText)
                        .font(.system(size: Theme.fsCardTitle, weight: .semibold, design: .rounded))
                        .foregroundColor(balance.isLow(threshold: settings.balanceAlertThreshold) ? Theme.warn : Theme.text)
                }
                if let granted = balance.granted, granted > 0, let text = balance.grantedText {
                    Text("含赠送 \(text)").font(.system(size: Theme.fsCaption)).foregroundColor(Theme.dim)
                }
                if balance.isLow(threshold: settings.balanceAlertThreshold) {
                    Link("余额不足，去充值 ›", destination: DeepSeekConfiguration.topUpURL)
                        .font(.system(size: Theme.fsCaption)).foregroundColor(Theme.warn)
                }
            }
        }
    }

    // MARK: 什么时候整理

    private var timingCard: some View {
        VStack(alignment: .leading, spacing: Theme.sp3) {
            Text("什么时候整理")
                .font(.system(size: Theme.fsCardTitle, weight: .semibold))
                .foregroundColor(Theme.text)
            Text("把转写好的原话整理成一件件事。转写格式在上面单独设置。")
                .font(.system(size: Theme.fsSmall))
                .foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("自动整理", isOn: $settings.autoDigest).tint(Theme.accent)
                .font(.system(size: Theme.fsBody))
            if settings.autoDigest {
                Picker("整理方式", selection: $settings.digestByInterval) {
                    Text("按间隔").tag(true)
                    Text("按时间点").tag(false)
                }
                .pickerStyle(.segmented)
                if settings.digestByInterval {
                    Picker("多久整理一次", selection: $settings.digestIntervalMin) {
                        ForEach([15, 30, 60, 120, 240, 720], id: \.self) { minutes in
                            Text(minutes < 60 ? "\(minutes) 分钟" : "\(minutes / 60) 小时").tag(minutes)
                        }
                    }
                    .font(.system(size: Theme.fsBody))
                } else {
                    Picker("每天整理", selection: $settings.digestHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .font(.system(size: Theme.fsBody))
                }
            }
            Divider()
            Toggle("整理前先思考", isOn: $settings.deepThinking).tint(Theme.accent)
                .font(.system(size: Theme.fsBody))
            Text("让模型先推理再整理，可能更慢、费用更高。仅影响整理，不影响连接检测。")
                .font(.system(size: Theme.fsCaption)).foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("整理时参考地点和环境音", isOn: $settings.usePlaceInDigest).tint(Theme.accent)
                .font(.system(size: Theme.fsBody))
            Text("打开后，当时的地点和环境音会随原话发送给 DeepSeek；定位和环境音需另行开启。")
                .font(.system(size: Theme.fsCaption)).foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.sp4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func invalidateCheck() {
        checkTask?.cancel()
        checkTask = nil
        checking = false
        checkMessage = nil
    }

    private func checkLLM() {
        let config = settings.effectiveLLM
        checking = true
        checkMessage = nil
        checkTask = Task { @MainActor in
            defer { if !Task.isCancelled { checking = false } }
            do {
                let reply = try await LLMClient(baseURL: config.base, apiKey: config.key, model: config.model)
                    .complete(system: "只输出 JSON。", user: "输出 {\"ok\":true}", temperature: 0)
                try Task.checkCancellation()
                checkOK = (JSONExtract.object(from: reply)?["ok"] as? Bool) == true
                checkMessage = checkOK ? "连接正常 · JSON 整理能力通过" : "连接成功，但未返回要求的 JSON，请重试"
                await account.refresh(key: config.key, force: true)
            } catch {
                guard !Task.isCancelled else { return }
                checkOK = false
                checkMessage = "检测失败：\(error.localizedDescription)"
            }
        }
    }

    private var keepDaysSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("原声保留 \(settings.keepAudioDays) 天")
                    .font(.system(size: 18, weight: .semibold))
                Stepper("保留天数", value: $settings.keepAudioDays, in: 1...365)
                Text("标了重点的录音长期保留。现在占用 \(ByteText.short(stats.bytes))。")
                    .font(.system(size: 12)).foregroundColor(Theme.dim)
                Button {
                    Task {
                        let n = await AppState.shared.purgeOldAudio()
                        await MainActor.run {
                            reload()
                            purgeTip = n > 0 ? "已清理 \(n) 段原声，转写文字和整理结果都还在" : "没有需要清理的原声"
                        }
                    }
                } label: {
                    Text("立即清理过期录音")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Theme.accent).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                if !purgeTip.isEmpty {
                    Text(purgeTip)
                        .font(.system(size: Theme.fsSmall))
                        .foregroundStyle(Theme.dim)
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("原声")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { showKeepDays = false } } }
        }
    }

    // MARK: 工具

    private func reload() {
        Task { await reloadAsync() }
    }

    /// 6 次查询全部放到后台：以前每 5 秒在主线程同步跑一遍，停留在这页会持续掉帧
    private func reloadAsync() async {
        struct Snap { let today: Double; let month: Double; let bytes: Int64; let total: Int; let done: Int; let segs: [Segment] }
        let snap = await Task.detached(priority: .utility) { () -> Snap in
            let p = Store.shared.todayTranscribeProgress()
            return Snap(today: Store.shared.transcribedMinutes(days: 0),
                        month: Store.shared.transcribedMinutes(days: 30),
                        bytes: Store.shared.audioBytes(),
                        total: p.total,
                        done: p.done,
                        segs: Store.shared.segments(day: DayKey.of(Date()), limit: 200))
        }.value
        stats = Stats(todayMinutes: snap.today, monthMinutes: snap.month, bytes: snap.bytes, total: snap.total, done: snap.done)
        todaySegments = snap.segs
        queue.refreshPending()
    }

    private func exportAudio() {
        guard !exporting else { return }
        exportError = nil
        exporting = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
                do { return .success(try AudioExport.zipAudio()) }
                catch { return .failure(error) }
            }.value
            await MainActor.run {
                exporting = false
                switch outcome {
                case .success(let u): exportURL = u
                case .failure(let e): exportError = e.localizedDescription
                }
            }
        }
    }

    private static func minutesText(_ m: Double) -> String {
        if m < 1 { return "\(Int((m * 60).rounded())) 秒" }
        if m < 60 { return "\(Int(m.rounded())) 分" }
        return String(format: "%.1f 小时", m / 60)
    }

    private static func cost(_ minutes: Double) -> String {
        // 豆包录音文件识别极速版约 ¥0.8/小时
        String(format: "%.2f", minutes / 60 * 0.8)
    }

    private static func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "今天 HH:mm" : "M月d日 HH:mm"
        return f.string(from: d)
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
                Text("自动整理的间隔和时间点在「模型与整理」里设置。")
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
        .tabBarClearance()
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
    @State private var purgeTip = ""
    @State private var exportingMd = false
    @State private var exportTip = ""

    var body: some View {
        Form {
            Section {
                Stepper(value: $settings.keepAudioDays, in: 1...365) {
                    Text("原录音保留 \(settings.keepAudioDays) 天")
                }
                Button("现在就清掉过期的") {
                    Task {
                        let n = await app.purgeOldAudio()
                        await MainActor.run {
                            purgeTip = n > 0 ? "已清理 \(n) 段原声，转写和整理结果保留" : "没有需要清理的原声"
                        }
                    }
                }
            } header: {
                Text("原录音")
            } footer: {
                Text(purgeTip.isEmpty ? "标了重点的不会被清掉。转写文本和整理结果一直留着。" : purgeTip)
            }

            Section("导出") {
                Button {
                    guard !exportingMd else { return }
                    exportingMd = true
                    exportTip = ""
                    let day = DayKey.of(Date())
                    Task {
                        // 一天上千段时拼 Markdown + 写文件也不轻，别堵主线程
                        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
                            let md = AppState.shared.exportMarkdown(day: day)
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent("涛声-\(day).md")
                            do {
                                try md.write(to: url, atomically: true, encoding: .utf8)
                                return .success(url)
                            } catch {
                                return .failure(error)
                            }
                        }.value
                        await MainActor.run {
                            exportingMd = false
                            switch outcome {
                            case .success(let u):
                                items = [u]
                                showExport = true
                            case .failure(let e):
                                exportTip = "导出失败：\(e.localizedDescription)"
                            }
                        }
                    }
                } label: {
                    HStack {
                        Label(exportingMd ? "正在整理导出文件…" : "导出今天的原话和整理", systemImage: "doc.text")
                        Spacer()
                        if exportingMd { ProgressView().scaleEffect(0.7) }
                    }
                }
                .disabled(exportingMd)
                if !exportTip.isEmpty {
                    Text(exportTip).font(.system(size: Theme.fsCaption)).foregroundColor(Theme.bad)
                }
                NavigationLink("导入录音文件") { ImportView() }
            }

            Section {
                Toggle("记下每天去过哪", isOn: $settings.locationOn).tint(Theme.accent)
                    .onChange(of: settings.locationOn) { on in
                        LocationEngine.shared.syncWithSettings()
                    }
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
        .tabBarClearance()
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
        .tabBarClearance()
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
    /// 版本号从 Bundle 读，别再手写（之前写死 0.2.0，和实际包版本对不上）
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "—"
        let b = info?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b)) · iOS"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("涛声").font(.system(size: 18, weight: .bold))
                        Text(versionText).font(.system(size: 12)).foregroundStyle(Theme.dim)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Text("一直在听。录音留在本机；转写时音频会发给你配置的转写服务（默认豆包云端），整理时原话会发给你配置的大模型服务。除此之外不上传任何地方。")
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
        .tabBarClearance()
        .navigationTitle("关于涛声")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 模型和转写设置（弹窗）

struct TranscribeSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: Settings

    @State private var showAdvanced = false
    @State private var testResult: String?
    @State private var testing = false
    // 密钥用草稿编辑：直接绑 settings.doubaoApiKey 时，输入第一个字符就让「未填写」变「已填写」，
    // 输入框随条件消失，用户看到的是打一个字就没了
    @State private var keyDraft = ""
    @State private var editingKey = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    asrCard
                    langCard
                    intervalCard
                    switchCard
                    testCard
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("模型和转写设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var asrCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("语音转写").font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text)

            HStack(spacing: 0) {
                asrSeg("豆包", .doubao)
                asrSeg("本地", .appleSpeech)
                asrSeg("自定义", .openAICompatible)
            }
            .padding(3)
            .background(Theme.cardSoft)
            .clipShape(Capsule())

            if settings.asrKind == .doubao {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showAdvanced.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Text("自定义请求头（可选）").font(.system(size: 13))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                    }
                    .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)

                if showAdvanced {
                    field("一行一个，例如 X-Api-Key: xxx", text: $settings.asrCustomHeaders)
                }

                Text("豆包语音密钥")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.text)

                HStack(spacing: 8) {
                    Circle()
                        .fill(settings.doubaoApiKey.isEmpty ? Theme.warn : Theme.ok)
                        .frame(width: 8, height: 8)
                    Text(settings.doubaoApiKey.isEmpty ? "未填写" : "已填写")
                        .font(.system(size: 13.5))
                        .foregroundColor(Theme.text2)
                    Spacer(minLength: 0)
                    Button {
                        keyDraft = settings.doubaoApiKey
                        editingKey = true
                        keyFocused = true
                    } label: {
                        Text(settings.doubaoApiKey.isEmpty ? "填写" : "更换")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Theme.accentSoft).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    if !settings.doubaoApiKey.isEmpty {
                        Button { settings.doubaoApiKey = ""; keyDraft = ""; editingKey = false } label: {
                            Text("清除")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Theme.accentSoft).clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if editingKey {
                    HStack(spacing: 8) {
                        SecureField("豆包语音 API Key", text: $keyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($keyFocused)
                            .font(.system(size: 14))
                            .padding(11)
                            .background(Theme.cardSoft)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).stroke(Theme.line, lineWidth: 0.8))
                        Button("保存") {
                            settings.doubaoApiKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            editingKey = false
                            keyFocused = false
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Text("只存在这台手机的安全区里，填好后任何地方都不再显示。")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.dim2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("识别档位")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.text)
                    .padding(.top, 4)

                Picker("识别档位", selection: $settings.doubaoResourceId) {
                    ForEach(DoubaoResource.all, id: \.id) { item in
                        Text(DoubaoResource.shortTitle(item.id)).tag(item.id)
                    }
                }
                .pickerStyle(.segmented)

                if let note = DoubaoResource.all.first(where: { $0.id == settings.doubaoResourceId })?.note {
                    Text(note)
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.dim2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("账号没开通的档位会报「未授权」，换另一个档位即可；这一项和密钥配套使用。")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.dim2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if settings.asrKind == .appleSpeech {
                        Text("用手机自带的中文识别，录音不出手机。识别完仍然会发给你配的大模型去整理。")
                            .font(.system(size: 12.5)).foregroundColor(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if settings.asrKind == .openAICompatible {
                        field("接口地址", text: $settings.asrBaseURL)
                        field("模型", text: $settings.asrModel)
                        secure("API Key", text: $settings.asrKey)
                        field("或填完整请求地址", text: $settings.asrFullURL)
                    }
                    if !settings.asrKind.hint.isEmpty {
                        Text(settings.asrKind.hint)
                            .font(.system(size: 11.5)).foregroundColor(Theme.dim2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func asrSeg(_ title: String, _ kind: ASRKind) -> some View {
        let on = settings.asrKind == kind
        return Button {
            settings.asrKind = kind
        } label: {
            Text(title)
                .font(.system(size: 13.5, weight: on ? .semibold : .regular))
                .foregroundColor(on ? Theme.text : Theme.dim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(on ? Theme.card : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }


    private var langCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("主要识别语言").font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text)
            Picker("语言", selection: $settings.asrLanguage) {
                Text("自动识别").tag("auto")
                Text("普通话").tag("zh")
                Text("粤语").tag("yue")
                Text("英语").tag("en")
                Text("中英混合").tag("zh-en")
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
            Text("只影响之后的转写，已经转好的原话不会重算。带口音的普通话建议选普通话。")
                .font(.system(size: 11.5)).foregroundColor(Theme.dim2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 14))
            .padding(11)
            .background(Theme.cardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private func secure(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 14))
            .padding(11)
            .background(Theme.cardSoft)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private var intervalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("多久转写一次").font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text)

            HStack(spacing: 0) {
                intervalSeg("实时", 1)
                intervalSeg("15 分钟", 15)
                intervalSeg("30 分钟", 30)
                intervalSeg("自定义", -1)
            }
            .padding(3)
            .background(Theme.cardSoft)
            .clipShape(Capsule())

            if settings.transcribeIntervalMin > 0 && ![1, 15, 30].contains(settings.transcribeIntervalMin) {
                Stepper("每 \(settings.transcribeIntervalMin) 分钟",
                        value: $settings.transcribeIntervalMin, in: 1...720)
                    .font(.system(size: 14))
            }

            Text("每 \(max(1, settings.transcribeIntervalMin)) 分钟把攒下的录音转写一次。整理成事件另在「模型与整理」里设置。")
                .font(.system(size: 11.5)).foregroundColor(Theme.dim2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func intervalSeg(_ title: String, _ minutes: Int) -> some View {
        let on: Bool = minutes > 0
            ? settings.transcribeIntervalMin == minutes
            : (settings.transcribeIntervalMin > 0 && ![1, 15, 30].contains(settings.transcribeIntervalMin))
        return Button {
            if minutes > 0 {
                settings.transcribeIntervalMin = minutes
            } else if [1, 15, 30].contains(settings.transcribeIntervalMin) {
                settings.transcribeIntervalMin = 45
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundColor(on ? Theme.text : Theme.dim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(on ? Theme.card : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 开关

    private var switchCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            toggleLine("只在 WiFi 下转写",
                       "关掉后用流量也会上传，每小时录音约 10 MB",
                       $settings.wifiOnlyTranscribe)
            Divider().overlay(Theme.lineSoft).padding(.vertical, 12)
            toggleLine("外放声音时不转写",
                       "手机扬声器在放视频、音乐时录到的先不转写，原话里可单段「仍然转写」；戴耳机不受影响",
                       $settings.skipWhenOutput)
            Divider().overlay(Theme.lineSoft).padding(.vertical, 12)
            toggleLine("区分说话人与认人",
                       "原话标出谁在说，认出「我」和已命名的人",
                       $settings.speakerSplitOn)
            Divider().overlay(Theme.lineSoft).padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("临时不区分说话人")
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundColor(Theme.text)
                Text("上课、听讲座时开始一个「培训」专题：这段时间不分人，结束后出培训笔记")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    settings.captureMode = .training
                    if !CaptureEngine.shared.isRunning { CaptureEngine.shared.start() }
                    testResult = "已切到培训模式，这段时间不分人。"
                } label: {
                    HStack(spacing: 3) {
                        Text("开始培训专题").font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(Theme.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func toggleLine(_ title: String, _ detail: String, _ on: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundColor(Theme.text)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: on)
                .labelsHidden()
                .tint(Theme.accent)
        }
    }

    // MARK: 测试

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("测试一下")
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundColor(Theme.text)
                    Text("发一小段测试音频，确认密钥和服务可用")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.dim)
                }
                Spacer(minLength: 0)
                Button {
                    runTest()
                } label: {
                    Text(testing ? "测试中…" : "测试")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Theme.accentSoft).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(testing || !settings.asrReady)
            }
            if let r = testResult {
                Text(r)
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func runTest() {
        guard let t = TranscriberFactory.make() else {
            testResult = "还没有可用的转写服务，先填豆包密钥。"
            return
        }
        let recent = Store.shared.segments(day: DayKey.of(Date()), limit: 1)
        guard let seg = recent.first else {
            testResult = "今天还没有录音，先说一句话再测。"
            return
        }
        let url = Store.audioDir.appendingPathComponent(seg.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            testResult = "这段录音的原声已经按保留规则删掉了，换一段再测。"
            return
        }
        testing = true
        testResult = nil
        Task {
            do {
                let text = try await t.transcribe(fileURL: url)
                await MainActor.run {
                    testing = false
                    let head = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    testResult = head.isEmpty ? "服务通了，但这小段没识别出字。" : "通了：\(head.prefix(50))"
                }
            } catch {
                await MainActor.run {
                    testing = false
                    testResult = "失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - 编辑 DeepSeek
private struct DeepSeekEditorSheet: View {
    @EnvironmentObject private var settings: Settings
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var model = DeepSeekConfiguration.models[0]

    var body: some View {
        NavigationStack {
            Form {
                Section("DeepSeek") {
                    Picker("模型", selection: $model) {
                        Text("Flash · 推荐").tag(DeepSeekConfiguration.models[0])
                        Text("V4 Pro").tag(DeepSeekConfiguration.models[1])
                    }
                    SecureField("API Key", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Link("去申请密钥 ›", destination: DeepSeekConfiguration.keyURL)
                }
                Section {
                    Text("官方地址和余额接口已配好，不需要填写。整理、问问、回顾和技能使用同一密钥，不再切换其他服务商。")
                        .font(.system(size: Theme.fsSmall)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("编辑 DeepSeek").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { settings.saveDeepSeek(key: key, model: model); dismiss() }
                }
            }
            .onAppear { key = settings.llmKey; model = settings.llmModel }
        }
    }
}