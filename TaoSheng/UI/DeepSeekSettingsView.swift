import SwiftUI

@MainActor
struct DeepSeekSettingsView: View {
    @EnvironmentObject private var settings: Settings
    @StateObject private var account = DeepSeekAccount()
    @State private var editing = false
    @State private var addingProvider = false
    @State private var checking = false
    @State private var checkMessage: String?
    @State private var checkOK = false
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                modelCard
                providerCard
                timingCard
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("整理模型")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) {
            DeepSeekEditorView().environmentObject(settings)
        }
        .sheet(isPresented: $addingProvider) {
            ProviderAddView().environmentObject(settings)
        }
        .task(id: settings.llmKey) {
            await account.refresh(key: settings.llmKey)
        }
        .onChange(of: settings.llmKey) { _ in invalidateCheck() }
        .onChange(of: settings.llmModel) { _ in invalidateCheck() }
        .onDisappear { invalidateCheck() }
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("整理用的大模型").font(.system(size: 20, weight: .semibold))
                Text("整理、问问、技能、回顾都用这一个，只需填一次密钥。")
                    .font(.system(size: 13)).foregroundStyle(Theme.dim)
            }
            HStack(spacing: 12) {
                Image(systemName: "largecircle.fill.circle")
                    .font(.system(size: 24)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("DeepSeek").font(.system(size: 19, weight: .medium))
                    Text(settings.llmModel + (settings.llmReady ? "" : " · 未填密钥"))
                        .font(.system(size: 12.5)).foregroundStyle(settings.llmReady ? Theme.dim : Theme.warn)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Button("编辑") { editing = true }.foregroundStyle(Theme.accent)
            }
            if settings.llmReady {
                balanceContent
                HStack(spacing: 18) {
                    Button(checking ? "检测中…" : "检测") { check() }
                        .disabled(checking)
                    Button(account.loading ? "查询中…" : "刷新余额") {
                        Task { await account.refresh(key: settings.llmKey, force: true) }
                    }
                    .disabled(account.loading)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accent)
            } else {
                Button("填写 DeepSeek 密钥") { editing = true }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Theme.accent.opacity(0.1)).clipShape(Capsule())
            }
            if let checkMessage {
                Text(checkMessage).font(.system(size: 12))
                    .foregroundStyle(checkOK ? Theme.ok : Theme.bad)
            }
            Divider()
            Picker("余额提醒", selection: $settings.balanceAlertThreshold) {
                Text("不提醒").tag(0.0)
                Text("低于 ¥5").tag(5.0)
                Text("低于 ¥10").tag(10.0)
                Text("低于 ¥20").tag(20.0)
            }
            .tint(Theme.accent)
            .font(.system(size: 13))
            Text("只用 DeepSeek，不切换其他服务商。密钥保存在本机，页面不显示。")
                .font(.system(size: 11.5)).foregroundStyle(Theme.dim2)
        }
        .foregroundStyle(Theme.text)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    /// 服务商：DeepSeek 为主，其余只能当备用
    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("服务商").font(.system(size: 20, weight: .semibold))
                Text("DeepSeek 是主服务商。再加一个填好密钥的，主服务商出问题时可以自动接手。")
                    .font(.system(size: 13)).foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(settings.providers) { p in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: p.id == settings.llmProviderID ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(p.id == settings.llmProviderID ? Theme.accent : Theme.dim2)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(p.name).font(.system(size: 15, weight: .medium))
                            if p.id == "deepseek" {
                                Text("主")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.accent.opacity(0.12)).clipShape(Capsule())
                            }
                        }
                        // DeepSeek 预设那条的 key 存在 llmKey 里，providersJSON 里恒为空，
                        // 不能只看 p.key，否则上面显示已配置、这里永远「未填密钥」。
                        Text(p.model + (hasKey(p) ? " · 已填密钥" : " · 未填密钥"))
                            .font(.system(size: 12))
                            .foregroundStyle(hasKey(p) ? Theme.dim : Theme.warn)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if p.id != "deepseek" {
                        Button(role: .destructive) {
                            settings.deleteProvider(id: p.id)
                        } label: { Image(systemName: "trash").font(.system(size: 13)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.dim2)
                    }
                }
            }

            Toggle("出问题时自动换备用", isOn: $settings.llmFallback).tint(Theme.accent)
            Text("主服务商报错或超时，依次试下面填好密钥的服务商。整理、问问、回顾都会换。")
                .font(.system(size: 11.5)).foregroundStyle(Theme.dim2)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                addingProvider = true
            } label: {
                Label("添加服务商", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(Theme.accent.opacity(0.1)).clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Text("密钥分开保存在手机本地，页面上不显示。")
                .font(.system(size: 11.5)).foregroundStyle(Theme.dim2)
        }
        .foregroundStyle(Theme.text)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    /// 主服务商的密钥存在 llmKey 里，providersJSON 中那条恒为空
    private func hasKey(_ p: LLMProvider) -> Bool {
        p.id == settings.llmProviderID ? !settings.llmKey.isEmpty : !p.key.isEmpty
    }

    @ViewBuilder private var balanceContent: some View {        if account.loading {
            Text("余额查询中…").font(.system(size: 13)).foregroundStyle(Theme.dim)
        } else if let error = account.error {
            Text(error).font(.system(size: 13)).foregroundStyle(Theme.warn)
        } else if let balance = account.balance {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(balance.available ? "余额" : "账户暂不可用")
                        .font(.system(size: 13)).foregroundStyle(Theme.dim)
                    Text(balance.totalText).font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(balance.isLow(threshold: settings.balanceAlertThreshold) ? Theme.warn : Theme.text)
                }
                if let granted = balance.granted, granted > 0, let text = balance.grantedText {
                    Text("含赠送 \(text)").font(.system(size: 11.5)).foregroundStyle(Theme.dim)
                }
                if balance.isLow(threshold: settings.balanceAlertThreshold) {
                    Link("余额不足，去充值 ›", destination: DeepSeekConfiguration.topUpURL)
                        .font(.system(size: 12)).foregroundStyle(Theme.warn)
                }
                if let date = account.updatedAt {
                    Text("更新于 \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.dim2)
                }
            }
        }
    }

    private var timingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("什么时候整理").font(.system(size: 20, weight: .semibold))
            Text("把转写好的原话整理成一件件事。转写在「原话与转写」里单独设置。")
                .font(.system(size: 13)).foregroundStyle(Theme.dim)
            Toggle("自动整理", isOn: $settings.autoDigest).tint(Theme.accent)
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
                } else {
                    Picker("每天整理", selection: $settings.digestHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                }
            }
            Divider()
            Toggle("整理前先思考", isOn: $settings.deepThinking).tint(Theme.accent)
            Text("让模型先推理再整理，可能更慢、费用更高。仅影响整理，不影响连接检测。")
                .font(.system(size: 11.5)).foregroundStyle(Theme.dim)
            Toggle("整理时参考地点和环境音", isOn: $settings.usePlaceInDigest).tint(Theme.accent)
            Text("打开后，当时的地点和环境音会随原话发送给 DeepSeek；定位和环境音需另行开启。")
                .font(.system(size: 11.5)).foregroundStyle(Theme.dim)
        }
        .foregroundStyle(Theme.text)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func invalidateCheck() {
        checkTask?.cancel()
        checkTask = nil
        checking = false
        checkMessage = nil
    }

    private func check() {
        let config = settings.effectiveLLM
        checking = true
        checkMessage = nil
        checkTask = Task { @MainActor in
            defer { if !Task.isCancelled { checking = false } }
            do {
                let reply = try await LLMClient(baseURL: config.base, apiKey: config.key, model: config.model).complete(
                    system: "只输出 JSON。", user: "输出 {\"ok\":true}", temperature: 0)
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
}

private struct DeepSeekEditorView: View {    @EnvironmentObject private var settings: Settings
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
                    Text("官方地址和余额接口已配好，不需要填写。整理、问问、回顾和技能使用同一密钥。")
                        .font(.system(size: 12)).foregroundStyle(Theme.dim)
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

/// 添加一个备用服务商：任意 OpenAI 兼容地址
private struct ProviderAddView: View {
    @EnvironmentObject private var settings: Settings
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var base = ""
    @State private var model = ""
    @State private var key = ""

    private var canSave: Bool {
        !base.trimmingCharacters(in: .whitespaces).isEmpty &&
        !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("服务商") {
                    TextField("名字，例如 硅基流动", text: $name)
                    TextField("接口地址，例如 https://api.siliconflow.cn/v1", text: $base)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("模型，例如 deepseek-ai/DeepSeek-V3", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API Key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("只要是 OpenAI 兼容的 /chat/completions 就能用。它只在你打开「自动换备用」时接手，不会替换 DeepSeek。")
                        .font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
            }
            .scrollContentBackground(.hidden).background(Theme.bg)
            .navigationTitle("添加服务商").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        settings.upsertProvider(LLMProvider(
                            id: UUID().uuidString,
                            name: n.isEmpty ? "自定义服务商" : n,
                            baseURL: base.trimmingCharacters(in: .whitespaces),
                            model: model.trimmingCharacters(in: .whitespaces),
                            key: key.trimmingCharacters(in: .whitespaces),
                            note: "",
                            builtin: false))
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
