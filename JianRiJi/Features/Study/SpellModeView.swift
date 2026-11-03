import SwiftUI

/// 拼写：听读音 / 看释义，把罗马字敲出来。
/// 拼写模式：听读音、看释义，敲罗马字作答。
struct SpellModeView: View {
    @EnvironmentObject private var store: Store

    @State private var pool: [Word] = []
    @State private var target: Word?
    @State private var input = ""
    @State private var verdict: Verdict = .idle
    @State private var hintShown = false
    @State private var correct = 0
    @State private var total = 0

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
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("拼写")
        .navigationBarTitleDisplayMode(.inline)
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
                .foregroundStyle(Theme.muted)
            Spacer()
            Button {
                Speech.shared.speak(target?.reading ?? "", rate: store.settings.speechRate)
            } label: {
                Label("再听一次", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
    }

    private var promptCard: some View {
        VStack(spacing: 12) {
            Button {
                Speech.shared.speak(target?.reading ?? "", rate: store.settings.speechRate)
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.mint)
                        .frame(width: 88, height: 88)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.accent)
                }
            }
            .buttonStyle(.plain)

            if let word = target {
                Text(word.meaning)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                if hintShown {
                    Text("\(word.term)  ·  \(word.reading)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                } else {
                    Text("听读音，把罗马字拼出来")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .paperCard(padding: 18)
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            TextField("例：gakkou", text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.done)
                .onSubmit(check)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var borderColor: Color {
        switch verdict {
        case .idle: return Color.primary.opacity(0.08)
        case .right: return Theme.jade
        case .wrong: return Color(red: 0.78, green: 0.32, blue: 0.28)
        }
    }

    private var feedback: some View {
        VStack(alignment: .leading, spacing: 8) {
            if verdict == .right {
                Text("对了：\(target?.term ?? "")  ·  \(target?.reading ?? "")")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
            } else {
                Text("正确答案：\(target?.romaji ?? "")   （\(target?.reading ?? "")）")
                    .font(.footnote)
                    .foregroundStyle(Color(red: 0.78, green: 0.32, blue: 0.28))
            }

            HStack(spacing: 10) {
                Button {
                    hintShown = true
                } label: {
                    Text("看提示")
                }
                .buttonStyle(GhostButtonStyle(tint: Theme.indigo))

                Button {
                    next()
                } label: {
                    Text("下一题")
                }
                .buttonStyle(GhostButtonStyle(tint: Theme.accent))

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        Text("拼写会推进记忆进度：答对按「记得」，答错按「忘了」。")
            .font(.caption2)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 逻辑

    private func refill() {
        pool = store.scopedWords.shuffled()
    }

    private func next() {
        if pool.isEmpty { refill() }
        target = pool.popLast()
        input = ""
        verdict = .idle
        hintShown = false
        Speech.shared.speak(target?.reading ?? "", rate: store.settings.speechRate)
    }

    private func check() {
        guard let word = target,
              !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              verdict == .idle else { return }

        let typed = normalize(input)
        let answer = normalize(word.romaji)
        let isRight = typed == answer || input.trimmingCharacters(in: .whitespacesAndNewlines) == word.reading

        verdict = isRight ? .right : .wrong
        total += 1
        if isRight { correct += 1 } else { hintShown = true }
        store.grade(word: word, grade: isRight ? .good : .again)
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
