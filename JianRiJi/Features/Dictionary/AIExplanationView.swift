import SwiftUI

/// 词条 AI 讲解：点一次发一次请求，只发给设置里选中的厂商。
/// 内容是模型生成的，仅供参考，以词典和语法书为准；没配 Key 时不发请求，只提示去设置。
struct AIExplanationView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let word: Word

    @State private var result: String?
    @State private var errorMessage: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(word.term)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                        Text("\(word.reading)  ・  \(word.romaji)  ・  \(word.partOfSpeech)  ・  \(word.meaning)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .paperCard(padding: 16)

                    if loading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在问 \(store.settings.aiVendor.displayName)…")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .paperCard(padding: 16)
                    } else if let result {
                        Text(result)
                            .font(.system(size: 17))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .paperCard(padding: 16)
                    } else if let errorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(Color(red: 0.78, green: 0.32, blue: 0.28))
                            Button("再试一次") { ask() }
                                .buttonStyle(.plain)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .paperCard(padding: 16)
                    }

                    Text("AI 生成，仅供参考，以词典和语法书为准。")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("AI 讲解")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                if result == nil, errorMessage == nil {
                    ask()
                }
            }
        }
    }

    private func ask() {
        loading = true
        errorMessage = nil
        result = nil
        let settings = store.settings
        let word = word
        Task {
            do {
                let reply = try await AIClient.chat(
                    settings: settings,
                    system: "你是一位简明的日语老师，用中文回答，不超过 300 字。",
                    user: """
                    请讲解日语单词「\(word.term)」（\(word.reading)，\(word.partOfSpeech)，中文释义：\(word.meaning)），包括：
                    1. 词义辨析或易混点
                    2. 常用搭配
                    3. 再给 1-2 个例句（日文 + 中文）
                    """
                )
                await MainActor.run {
                    loading = false
                    result = reply
                }
            } catch {
                await MainActor.run {
                    loading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
