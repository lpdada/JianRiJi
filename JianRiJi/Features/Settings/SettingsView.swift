import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store

    @State private var showResetConfirm = false

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
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
                        row("翻面自动朗读", "用系统 TTS")
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
                    Button {
                        Speech.shared.speak("こんばんは。いい声が出ていますか。", rate: store.settings.speechRate)
                    } label: {
                        Label("试听一句", systemImage: "waveform")
                    }
                } header: {
                    Text("试听")
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
                    Text("简日记是独立实现，跟「识日」没有关系，也没有拷它的代码或词库。词表是手写的示例数据，你可以自己替换 Resources/seed_words.json。")
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

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.muted)
        }
    }
}
