import SwiftUI

/// 「大模型与整理」：整理用的大模型 + 什么时候整理。
/// 从「转写与原话」里拆出来，避免原话一多就把这两张卡挤到很远。
struct LLMSettingsView: View {
    @EnvironmentObject var settings: Settings
    @StateObject private var account = DeepSeekAccount()

    @State private var showLLM = false
    @State private var checking = false
    @State private var checkMessage: String?
    @State private var checkOK = false
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Theme.sp3) {
                llmCard
                timingCard
            }
            .padding(Theme.sp4)
        }
        .background(Theme.bg.ignoresSafeArea())
        .modifier(ShotBottomAnchor())
        .tabBarClearance()
        .navigationTitle("大模型与整理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLLM) {
            DeepSeekEditorSheet()
                .environmentObject(settings)
        }
        .task(id: settings.llmKey) {
            await account.refresh(key: settings.llmKey, base: settings.llmBaseURL)
        }
        .onDisappear { invalidateCheck() }
    }

    // MARK: 整理用的模型（固定 DeepSeek，不再提供切换服务商）

    private func intervalLabel(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) 分" : "\(minutes / 60) 小时"
    }

    private var llmCard: some View {
        VStack(alignment: .leading, spacing: Theme.sp3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(settings.llmReady ? Theme.ok : Theme.warn)
                    .frame(width: 9, height: 9)
                    .offset(y: -1)
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
                        Task { await account.refresh(key: settings.llmKey, base: settings.llmBaseURL, force: true) }
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
            Text("把转写好的原话整理成一件件事。转写格式在「转写与原话」里单独设置。")
                .font(.system(size: Theme.fsSmall))
                .foregroundColor(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("自动整理", isOn: $settings.autoDigest).tint(Theme.accent)
                .font(.system(size: Theme.fsBody))
            if settings.autoDigest {
                // 三档横排铺开，默认第一档「转写完就整理」：董事长要的是转出字就出结果
                VStack(spacing: 6) {
                    ForEach(DigestTiming.allCases) { t in
                        let on = settings.digestTiming == t
                        Button { settings.digestTiming = t } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 15))
                                    .foregroundColor(on ? Theme.accent : Theme.dim2)
                                    .padding(.top, 1)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(t.title)
                                        .font(.system(size: Theme.fsBody, weight: on ? .semibold : .regular))
                                        .foregroundColor(on ? Theme.accent : Theme.text)
                                    Text(t.detail)
                                        .font(.system(size: Theme.fsCaption))
                                        .foregroundColor(Theme.dim)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                                .fill(on ? Theme.accent.opacity(0.10) : Theme.bgDeep))
                            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t.title)
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                    }
                }
                if settings.digestTiming == .interval {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("多久整理一次")
                            .font(.system(size: Theme.fsSmall))
                            .foregroundColor(Theme.text2)
                        // 全部选项铺开：原来收在 Picker 里，只能看到当前这一档（董事长看不到 5 分钟和 10 分钟）
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
                            ForEach(Settings.digestIntervalOptions, id: \.self) { minutes in
                                let on = settings.digestIntervalMin == minutes
                                Button { settings.digestIntervalMin = minutes } label: {
                                    Text(intervalLabel(minutes))
                                        .font(.system(size: Theme.fsSmall, weight: on ? .semibold : .regular))
                                        .foregroundColor(on ? .white : Theme.text2)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                        .background(Capsule().fill(on ? Theme.accent : Theme.bgDeep))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(intervalLabel(minutes))
                                .accessibilityAddTraits(on ? [.isSelected] : [])
                            }
                        }
                    }
                } else if settings.digestTiming == .clock {
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
                await account.refresh(key: config.key, base: config.base, force: true)
            } catch {
                guard !Task.isCancelled else { return }
                checkOK = false
                checkMessage = "检测失败：\(error.localizedDescription)"
            }
        }
    }
}

// MARK: - 编辑 DeepSeek

struct DeepSeekEditorSheet: View {
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
