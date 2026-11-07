import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var cloud: CloudSync

    @AppStorage("tts.lastEngine") private var lastEngine = "system"

    @State private var showResetConfirm = false
    @State private var keyDraft = ""
    @State private var keyMessage = ""
    @State private var testing = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    /// 设置页右上那行小字：当前用的是哪一档语音。
    private var voiceSummary: String {
        if VoiceCatalog.hasNoJapaneseVoice { return "未安装" }
        guard let option = VoiceCatalog.current() else { return "默认" }
        return option.qualityLabel
    }

    /// 「朗读」区「上次」行的三档映射：语音包 / 服务器合成 / 系统语音。
    private var lastEngineText: String {
        switch lastEngine {
        case "voicepack": return "语音包"
        case "server": return "服务器合成（Nanami）"
        default: return "系统语音"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $store.settings.dailyGoal, in: 5...100, step: 5) {
                        row("每日新词", "\(store.settings.dailyGoal) 个")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        row("单轮上限", "\(store.settings.reviewLimit) 张")
                        Slider(
                            value: Binding(
                                get: { Double(store.settings.reviewLimit) },
                                set: { store.settings.reviewLimit = Int($0) }
                            ),
                            in: 20...200,
                            step: 10
                        )
                        .tint(Theme.accent)
                    }
                } header: {
                    Text("节奏")
                } footer: {
                    Text("新词是稀缺资源。一天二十个、走满一个月，比今天五百个明天躺平强得多。")
                }

                Section {
                    Toggle(isOn: $store.settings.showRomaji) {
                        row("显示罗马字", "帮助发音")
                    }
                    Toggle(isOn: $store.settings.autoSpeak) {
                        row("翻面自动朗读", "语音包优先")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        row("朗读速度", String(format: "%.2f", store.settings.speechRate))
                        Slider(value: $store.settings.speechRate, in: 0.30...0.60, step: 0.01)
                            .tint(Theme.jade)
                    }
                } header: {
                    Text("显示与声音")
                } footer: {
                    if !Speech.shared.hasJapaneseVoice {
                        Text("系统里没找到日语语音。去「设置 → 辅助功能 → 朗读内容 → 声音 → 日语」下载一个，发音才准。")
                    }
                }

                Section {
                    TextField("服务器地址，清空则跳过服务器", text: $store.settings.ttsServerURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)

                    row("上次", lastEngineText)
                } header: {
                    Text("朗读")
                } footer: {
                    Text("朗读按语音包、服务器、系统语音的顺序来，失败逐层退回；地址清空则跳过服务器。")
                }

                Section {
                    TextField("服务器地址，清空则关闭云功能", text: $store.settings.cloudBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)

                    NavigationLink {
                        LoginView()
                    } label: {
                        HStack {
                            Text("账号")
                            Spacer()
                            Text(cloud.account?.phone ?? "未登录")
                                .foregroundStyle(Theme.muted)
                        }
                    }

                    NavigationLink {
                        TeamView()
                    } label: {
                        HStack {
                            Text("组队打卡")
                            Spacer()
                            Text(cloud.team?.name ?? "未组队")
                                .foregroundStyle(Theme.muted)
                        }
                    }

                    HStack {
                        Button(cloud.syncing ? "正在同步…" : "立即同步") {
                            Task { await cloud.syncNow() }
                        }
                        .disabled(!cloud.isConfigured || cloud.account == nil || cloud.syncing)
                        Spacer()
                        Text(cloud.syncStatus)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                } header: {
                    Text("账号与同步")
                } footer: {
                    Text("登录后进度每 60 秒自动同步一次，换设备先拉云端再学。地址清空则不同步；登录 token 只存在本机 Keychain。")
                }

                Section {
                    NavigationLink {
                        VoiceSettingsView()
                            .environmentObject(store)
                    } label: {
                        HStack {
                            Text("语音")
                            Spacer()
                            Text(voiceSummary)
                                .foregroundStyle(Theme.muted)
                        }
                    }

                    Button {
                        Speech.shared.speak("こんばんは。いい声が出ていますか。", rate: store.settings.speechRate)
                    } label: {
                        Label("试听一句", systemImage: "waveform")
                    }
                } header: {
                    Text("声音")
                } footer: {
                    if VoiceCatalog.isUsingCompactVoice {
                        Text("现在是「默认」音质，也就是听着最机械的那一档。进「语音」里换增强 / 高级语音，或者装一个免费语音包。")
                    } else {
                        Text("朗读优先用语音包里的录音，其次服务器合成 Nanami，最后系统语音。")
                    }
                }

                Section {
                    Picker("厂商", selection: $store.settings.aiVendor) {
                        ForEach(AIVendor.allCases) { vendor in
                            Text(vendor.displayName).tag(vendor)
                        }
                    }

                    TextField(
                        "模型（空 = \(store.settings.aiVendor.defaultModel.isEmpty ? "请填模型名" : store.settings.aiVendor.defaultModel)）",
                        text: $store.settings.aiModel
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                    if store.settings.aiVendor == .custom {
                        TextField("接口地址，如 https://api.example.com/v1", text: $store.settings.aiBaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    } else {
                        row("接口地址", store.settings.aiVendor.defaultBaseURL ?? "")
                    }

                    row("API Key", AIClient.hasKey(settings: store.settings) ? "已保存" : "未设置")

                    SecureField("粘贴 API Key（只进 Keychain）", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    HStack(spacing: 12) {
                        Button("保存 Key") {
                            if KeychainHelper.save(keyDraft, account: store.settings.aiVendor.rawValue) {
                                keyDraft = ""
                                keyMessage = "已保存到 Keychain，换厂商就用对应厂商的 Key。"
                            } else {
                                keyMessage = "保存失败：Key 不能为空。"
                            }
                        }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if AIClient.hasKey(settings: store.settings) {
                            Button("删除 Key", role: .destructive) {
                                KeychainHelper.delete(account: store.settings.aiVendor.rawValue)
                                keyMessage = "已删除当前厂商的 Key。"
                            }
                        }
                    }

                    Button {
                        testConnection()
                    } label: {
                        Label(testing ? "正在测试…" : "测试连接", systemImage: "bolt.fill")
                    }
                    .disabled(testing)

                    if !keyMessage.isEmpty {
                        Text(keyMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                } header: {
                    Text("AI")
                } footer: {
                    Text("Key 只存在本机 Keychain，不进学习存档、不上传到除选中厂商外的任何地方。AI 讲解在词条详情里用，点一次发一次请求，不用不发。Opencode Go 会额外带 x-opencode-client / session / request 三个头。")
                }

                Section {
                    row("词库词条", "\(store.totalCount)")
                    row("已掌握", "\(store.masteredCount)")
                    row("累计复习", "\(store.log.count) 次")
                    if let accuracy = store.accuracy {
                        row("历史正确率", "\(Int(accuracy * 100))%")
                    }
                } header: {
                    Text("进度")
                }

                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Text("清空全部学习进度")
                    }
                } footer: {
                    Text("不会动词库，只是把每张卡的记忆状态和记录回到第一天。")
                }

                Section {
                    row("版本", version)
                    Link(destination: URL(string: "https://github.com/lpdada/JianRiJi")!) {
                        HStack {
                            Text("源码")
                            Spacer()
                            Text("GitHub").foregroundStyle(Theme.muted)
                        }
                    }
                    row("协议", "MIT")
                } header: {
                    Text("关于")
                } footer: {
                    Text("简日记是独立的日语学习 App。词库与语法来源见 README 的「词库」一节。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("清空全部学习进度？", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    store.resetAllProgress()
                }
                Button("算了", role: .cancel) {}
            } message: {
                Text("这个动作收不回来。")
            }
        }
    }

    private func testConnection() {
        testing = true
        keyMessage = ""
        let settings = store.settings
        Task {
            do {
                let reply = try await AIClient.chat(
                    settings: settings,
                    system: "你是一个简短的测试助手。",
                    user: "只回一个字：好"
                )
                await MainActor.run {
                    testing = false
                    keyMessage = "连接成功，模型回了：\(reply)"
                }
            } catch {
                await MainActor.run {
                    testing = false
                    keyMessage = "连接失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.muted)
        }
    }
}
