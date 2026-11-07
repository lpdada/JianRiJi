import SwiftUI

/// 听写：听读音，敲罗马字，即时判分。
///
/// 修复：
///  1. **重复计分**。`check()` 原来没有 `verdict == .idle` 守卫，连点两次「✓」
///     会让 `total` 与 `correct` 各加两次，正确率直接失真。
///  2. 答错时输入框描边用的是主色绿（和答对的 jade 几乎一样），用户分不清对错。
///  3. 练的是**全库 10660 词**，而拼写模式练的是当前词书——同一个 App 两套口径。
///  4. 罗马字判分走 `Romanization`（shi/si、长音符都算对）。
struct DictationView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var pool: [Word] = []
    @State private var target: Word?
    @State private var input = ""
    @State private var verdict: Verdict = .idle
    @State private var hintShown = false
    @State private var correct = 0
    @State private var total = 0

    @FocusState private var inputFocused: Bool

    enum Verdict {
        case idle, right, wrong
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    scoreBar
                    playCard
                    inputArea
                    feedback
                    note
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(AppTheme.bgMint.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("听写")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        Speech.shared.stop()
                        dismiss()
                    }
                }
            }
        }
        .task {
            if target == nil { next() }
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
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(AppTheme.primary)
        }
    }

    private var playCard: some View {
        VStack(spacing: 12) {
            Button {
                Speech.shared.speak(target?.reading ?? "", rate: store.settings.speechRate)
            } label: {
                ZStack {
                    Circle()
                        .fill(AppTheme.primarySoft)
                        .frame(width: 96, height: 96)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(AppTheme.primary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("再听一次读音")

            Text("听读音，把罗马字敲出来")
                .font(.footnote)
                .foregroundStyle(AppTheme.ink3)

            if hintShown, let word = target {
                VStack(spacing: 4) {
                    Text(word.reading)
                        .font(.title3)
                        .foregroundStyle(AppTheme.ink)
                    Text(word.meaning)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink3)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.card)
        )
    }

    private var inputArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("例：gakkou", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .focused($inputFocused)
                    .onSubmit(check)
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
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
                        .frame(width: 44, height: 44)
                        .background(AppTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("提交答案")
            }

            HStack(spacing: 10) {
                Button {
                    hintShown = true
                    Speech.shared.speak(target?.reading ?? "", rate: store.settings.speechRate)
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

                Spacer(minLength: 0)
            }
        }
    }

    private var borderColor: Color {
        switch verdict {
        case .idle: return AppTheme.hairline
        case .right: return AppTheme.success
        case .wrong: return AppTheme.danger
        }
    }

    @ViewBuilder
    private var feedback: some View {
        switch verdict {
        case .idle:
            EmptyView()
        case .right:
            Text("对了。\(target?.reading ?? "") · \(target?.meaning ?? "")")
                .font(.footnote)
                .foregroundStyle(AppTheme.success)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .wrong:
            Text("正确答案：\(target?.romaji ?? "")　（\(target?.reading ?? "") · \(target?.meaning ?? "")）")
                .font(.footnote)
                .foregroundStyle(AppTheme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var note: some View {
        Text("听写只是当场的耳力练习，不动你的记忆进度——要推进度，去「背单词」。")
            .font(.caption2)
            .foregroundStyle(AppTheme.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 行为

    private func next() {
        if pool.isEmpty {
            // 和拼写模式对齐：练当前词书，而不是整个 10660 词库。
            pool = store.scopedWords.shuffled()
            if pool.count > 1, pool.last?.id == target?.id {
                pool.swapAt(0, pool.count - 1)
            }
        }
        target = pool.popLast()
        input = ""
        verdict = .idle
        hintShown = false
        inputFocused = true
        Speech.shared.speak(target?.reading ?? "", rate: store.settings.speechRate)
    }

    private func check() {
        guard let word = target,
              verdict == .idle,
              !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // 守卫 `verdict == .idle` 是这次的核心修复：没有它，连点两下会重复累加分数。
        let isRight = Romanization.matches(typed: input, word: word)
        verdict = isRight ? .right : .wrong
        total += 1
        if isRight {
            correct += 1
        } else {
            hintShown = true
        }
        inputFocused = false
    }
}
