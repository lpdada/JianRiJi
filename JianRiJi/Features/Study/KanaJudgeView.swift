import SwiftUI

/// 假名判断：给词形（汉字），从四个读音里选一个。
///
/// 修了三件事：
///  1. **干扰项原来是全库随机抽的**。正确读音是「がっこう」，干扰项可能是「たべる」——
///     这种题不用会日语也能选对，练不出任何东西。现在优先取**近音**干扰项
///     （编辑距离最近的 12 个里随机 3 个），才真的考「读没读准」。
///  2. 答错后只跳走、不给解释。现在停 1.5 秒并把正确读音和释义摆出来。
///  3. 进度用 `index / count`，最后一题永远差一格。
struct KanaJudgeView: View {
    @EnvironmentObject private var store: Store

    @State private var questions: [Question] = []
    @State private var index = 0
    @State private var picked: String?
    @State private var correctCount = 0
    @State private var locked = false
    @State private var insufficient = false
    @State private var advanceTask: Task<Void, Never>?

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
                        if let picked, picked != question.word.reading {
                            explanation(question)
                        }
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
        .background(AppTheme.bgMint.ignoresSafeArea())
        .navigationTitle("假名判断")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if questions.isEmpty { build() }
        }
        .onDisappear {
            advanceTask?.cancel()
        }
    }

    private var progressBar: some View {
        // 答完最后一题时 index == count，进度才会真正到 100%。
        ProgressView(value: Double(index), total: Double(max(1, questions.count)))
            .tint(AppTheme.primary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
    }

    private func prompt(_ question: Question) -> some View {
        VStack(spacing: 10) {
            Text(question.word.term)
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.primary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text("选出正确的读音")
                .font(.footnote)
                .foregroundStyle(AppTheme.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(AppTheme.primarySoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func optionGrid(_ question: Question) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
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
                .accessibilityLabel("读音 \(option)")
            }
        }
    }

    /// 答错时把正确读音与释义摆出来——原来答完直接跳走，用户不知道对的是什么意思。
    private func explanation(_ question: Question) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(question.word.reading)　\(question.word.meaning)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.ink)
                if let example = question.word.example, !example.isEmpty {
                    Text(example)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.ink3)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.primarySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transition(.opacity)
    }

    private func textColor(_ option: String, _ question: Question) -> Color {
        guard picked != nil else { return AppTheme.ink }
        if option == question.word.reading { return .white }
        return option == picked ? .white : AppTheme.ink3
    }

    private func fill(_ option: String, _ question: Question) -> Color {
        guard let picked else { return AppTheme.card }
        if option == question.word.reading { return AppTheme.success }
        if option == picked { return AppTheme.danger }
        return AppTheme.card
    }

    private func border(_ option: String, _ question: Question) -> Color {
        guard picked != nil else { return AppTheme.hairline }
        if option == question.word.reading || option == picked { return .clear }
        return AppTheme.hairline
    }

    private var summary: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(AppTheme.primary)
            Text("这组判断做完了")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text("答对 \(correctCount) / \(questions.count)")
                .font(.footnote)
                .foregroundStyle(AppTheme.ink3)
            Spacer(minLength: 0)
            Button {
                build()
            } label: {
                Text("再来一组")
            }
            .buttonStyle(PrimaryButtonStyle(fill: AppTheme.primary))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - 逻辑

    private func build() {
        advanceTask?.cancel()
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
            let distractors = pickDistractors(for: word.reading, from: readings)
            list.append(Question(word: word, options: ([word.reading] + distractors).shuffled()))
        }
        questions = list
        index = 0
        picked = nil
        correctCount = 0
        locked = false
    }

    /// 近音干扰项：按编辑距离取最近的候选，再随机抽 3 个。
    /// 全随机抽会让题目变成「四选一里只有一个像日语」的送分题。
    private func pickDistractors(for reading: String, from readings: [String]) -> [String] {
        let others = readings.filter { $0 != reading }
        let ranked = others.sorted {
            editDistance($0, reading) < editDistance($1, reading)
        }
        let nearPool = Array(ranked.prefix(12))
        var picked = Array(nearPool.shuffled().prefix(3))

        if picked.count < 3 {
            let remaining = others.filter { !picked.contains($0) }.shuffled()
            picked.append(contentsOf: remaining.prefix(3 - picked.count))
        }
        return picked
    }

    /// 标准 Levenshtein 距离。假名读音长度都很短（2–8），开销可以忽略。
    private func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a)
        let y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }

        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[y.count]
    }

    private func choose(_ option: String, in question: Question) {
        guard !locked else { return }
        locked = true
        picked = option

        let right = option == question.word.reading
        if right { correctCount += 1 }
        store.grade(word: question.word, grade: right ? .good : .again)
        Speech.shared.speak(question.word.reading, rate: store.settings.speechRate)

        // 答错多停一会儿，让用户看清正解与释义。
        let delay: UInt64 = right ? 650_000_000 : 1_600_000_000
        advanceTask?.cancel()
        advanceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            index += 1
            picked = nil
            locked = false
        }
    }
}
