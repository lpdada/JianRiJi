import SwiftUI

/// 拼写：听读音 / 看释义，把罗马字敲出来。
///
/// 修了三件事：
///  1. **罗马字等价**。原来只做 lowercase + 去空格，用户敲 `susi`（训令式）或 `gakkō`
///     （带长音符）都会被判错——那是在考转写规则，不是考单词。现在走 `Romanization`。
///  2. **拼错不再直接扣记忆分**。原来 `store.grade(.again)`，一个手滑就让卡片倒退两级、
///     ease 掉 0.2。拼写是输出训练，打错一个字母不等于不认识。
///  3. 答错的词回到本轮队尾重练，而不是消失。
struct SpellModeView: View {
    @EnvironmentObject private var store: Store

    @State private var pool: [Word] = []
    @State private var retry: [Word] = []
    @State private var target: Word?
    @State private var input = ""
    @State private var verdict: Verdict = .idle
    @State private var hintShown = false
    @State private var correct = 0
    @State private var total = 0

    @FocusState private var inputFocused: Bool

    enum Verdict { case idle, right, wrong }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                scoreBar
                promptCard
                inputRow
                if verdict != .idle { feedback }
                footer
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(AppTheme.bgMint.ignoresSafeArea())
        .navigationTitle("拼写")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if target == nil {
                refill()
                next()
            }
        }
    }

    private var scoreBar: some View {
        HStack {
            Text(total == 0 ? "还没开始" : "\(correct) / \(total) 正确")
                .font(.caption)
                .foregroundStyle(AppTheme.ink3)
            Spacer()
            Button {
                Speech.shared.speak(target?.reading ?? "", rate: store.settings.speechRate)
            } label: {
                Label("再听一次", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.primary)
        }
    }

    private var promptCard: some View {
        VStack(spacing: 12) {
            Button {
                Speech.shared.speak(target?.reading ?? "", rate: store.settings.speechRate)
            } label: {
                ZStack {
                    Circle()
                        .fill(AppTheme.primarySoft)
                        .frame(width: 88, height: 88)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("再听一次读音")

            if let word = target {
                Text(word.meaning)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.ink)

                if hintShown {
                    Text("\(word.term)  ·  \(word.reading)")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink3)
                } else {
                    Text("听读音，把罗马字拼出来")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink3)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.card)
        )
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            TextField("例：gakkou（shi / si 都算对）", text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.done)
                .focused($inputFocused)
                .onSubmit(check)
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1.4)
                )

            Button {
                check()
            } label: {
                Image(systemName: "checkmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("提交答案")
        }
    }

    private var borderColor: Color {
        switch verdict {
        case .idle: return AppTheme.hairline
        case .right: return AppTheme.success
        case .wrong: return AppTheme.danger
        }
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 8) {
            if verdict == .right {
                Text("对了：\(target?.term ?? "")  ·  \(target?.reading ?? "")")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.success)
            } else {
                Text("正确答案：\(target?.romaji ?? "")   （\(target?.reading ?? "")）")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.danger)
                Text("拼写错不算忘记这个词，这一题不计入记忆进度；它会回到本轮末尾再练一次。")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.ink3)
            }

            HStack(spacing: 10) {
                Button {
                    hintShown = true
                } label: {
                    Text("看提示")
                }
                .buttonStyle(GhostButtonStyle(tint: AppTheme.ink2))

                Button {
                    next()
                } label: {
                    Text("下一题")
                }
                .buttonStyle(GhostButtonStyle(tint: AppTheme.primary))

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        Text("拼写答对会按「记得」推进记忆进度；答错只重练，不扣分。")
            .font(.caption2)
            .foregroundStyle(AppTheme.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 逻辑

    private func refill() {
        pool = store.scopedWords.shuffled()
        retry = []
    }

    private func next() {
        input = ""
        verdict = .idle
        hintShown = false

        if let retryWord = retry.popLast() {
            target = retryWord
        } else {
            if pool.isEmpty { refill() }
            target = pool.popLast()
        }
        inputFocused = true
        Speech.shared.speak(target?.reading ?? "", rate: store.settings.speechRate)
    }

    private func check() {
        guard let word = target, verdict == .idle else { return }
        let typed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }

        let isRight = Romanization.matches(typed: typed, word: word)
        verdict = isRight ? .right : .wrong
        total += 1

        if isRight {
            correct += 1
            store.grade(word: word, grade: .good)
        } else {
            hintShown = true
            // 拼错放回本轮队尾；不写 SRS。
            retry.append(word)
        }
        inputFocused = false
    }
}
