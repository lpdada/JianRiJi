import SwiftUI

/// 假名判断：给词形（汉字），从四个读音里选一个。
/// 假名判断模式：看词形选读音，四选一。
struct KanaJudgeView: View {
    @EnvironmentObject private var store: Store

    @State private var questions: [Question] = []
    @State private var index = 0
    @State private var picked: String?
    @State private var correctCount = 0
    @State private var locked = false
    /// 词本词数或不同读音数不足 4 时，build() 会置此位，不再用 0/0 的结算页糊弄过去。
    @State private var insufficient = false

    struct Question: Identifiable {
        let id = UUID()
        let word: Word
        let options: [String]
    }

    private var current: Question? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if let question = current {
                progressBar
                ScrollView {
                    VStack(spacing: 18) {
                        prompt(question)
                        optionGrid(question)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
            } else if insufficient {
                EmptyHint(
                    icon: "books.vertical",
                    title: "这个词本不够 4 个词",
                    detail: "假名判断需要至少 4 个不同读音的词。回词本页切到「全部词本」，或换一个词更多的词本再来。"
                )
                .padding(.horizontal, 20)
            } else {
                summary
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("假名判断")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if questions.isEmpty { build() }
        }
    }

    private var progressBar: some View {
        ProgressView(value: Double(index), total: Double(max(1, questions.count)))
            .tint(Theme.accent)
            .padding(.horizontal, 16)
            .padding(.top, 10)
    }

    private func prompt(_ question: Question) -> some View {
        VStack(spacing: 10) {
            Text(question.word.term)
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text("选出正确的读音")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(Theme.mint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func optionGrid(_ question: Question) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(question.options, id: \.self) { option in
                Button {
                    choose(option, in: question)
                } label: {
                    Text(option)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(textColor(option, question))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            fill(option, question),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(border(option, question), lineWidth: 1.2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func textColor(_ option: String, _ question: Question) -> Color {
        guard picked != nil else { return Color.primary }
        if option == question.word.reading { return .white }
        return option == picked ? .white : Theme.muted
    }

    private func fill(_ option: String, _ question: Question) -> Color {
        guard let picked else { return Theme.card }
        if option == question.word.reading { return Theme.accent }
        if option == picked { return Color(red: 0.78, green: 0.32, blue: 0.28) }
        return Theme.card
    }

    private func border(_ option: String, _ question: Question) -> Color {
        if picked == nil { return Color.primary.opacity(0.07) }
        if option == question.word.reading { return .clear }
        if option == picked { return .clear }
        return Color.primary.opacity(0.07)
    }

    private var summary: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("这组判断做完了")
                .font(.title3.weight(.semibold))
            Text("答对 \(correctCount) / \(questions.count)")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            Button {
                build()
            } label: {
                Text("再来一组")
            }
            .buttonStyle(PrimaryButtonStyle(fill: Theme.accent))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - 逻辑

    private func build() {
        let pool = store.scopedWords.shuffled()
        let readings = Array(Set(pool.map(\.reading)))
        guard pool.count >= 4, readings.count >= 4 else {
            questions = []
            index = 0
            picked = nil
            correctCount = 0
            locked = false
            insufficient = true
            return
        }
        insufficient = false

        var list: [Question] = []
        for word in pool.prefix(10) {
            var options = [word.reading]
            var others = readings.filter { $0 != word.reading }
            others.shuffle()
            options.append(contentsOf: others.prefix(3))
            list.append(Question(word: word, options: options.shuffled()))
        }
        questions = list
        index = 0
        picked = nil
        correctCount = 0
        locked = false
    }

    private func choose(_ option: String, in question: Question) {
        guard !locked else { return }
        locked = true
        picked = option

        let right = option == question.word.reading
        if right { correctCount += 1 }
        store.grade(word: question.word, grade: right ? .good : .again)
        Speech.shared.speak(question.word.reading, rate: store.settings.speechRate)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            index += 1
            picked = nil
            locked = false
        }
    }
}
