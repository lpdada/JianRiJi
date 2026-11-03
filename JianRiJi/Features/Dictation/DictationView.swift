import SwiftUI

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
            .background(Theme.paper.ignoresSafeArea())
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
                .foregroundStyle(Theme.muted)
            Spacer()
            Button {
                Speech.shared.speak(target?.reading ?? "", rate: store.settings.speechRate)
            } label: {
                Label("再听一次", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Theme.jade)
        }
    }

    private var playCard: some View {
        VStack(spacing: 12) {
            Button {
                Speech.shared.speak(target?.reading ?? "", rate: store.settings.speechRate)
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.12))
                        .frame(width: 96, height: 96)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Theme.accent)
                }
            }
            .buttonStyle(.plain)

            Text("听读音，把罗马字敲出来")
                .font(.footnote)
                .foregroundStyle(Theme.muted)

            if hintShown, let word = target {
                VStack(spacing: 4) {
                    Text(word.reading)
                        .font(.title3)
                    Text(word.meaning)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .paperCard(padding: 20)
    }

    private var inputArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("例：gakkou", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .onSubmit(check)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
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
                        .frame(width: 44, height: 44)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button {
                    hintShown = true
                    Speech.shared.speak(target?.reading ?? "", rate: store.settings.speechRate)
                } label: {
                    Text("看提示")
                }
                .buttonStyle(GhostButtonStyle(tint: Theme.indigo))

                Button {
                    next()
                } label: {
                    Text("下一题")
                }
                .buttonStyle(GhostButtonStyle(tint: Theme.jade))

                Spacer(minLength: 0)
            }
        }
    }

    private var borderColor: Color {
        switch verdict {
        case .idle: return Color.primary.opacity(0.08)
        case .right: return Theme.jade
        case .wrong: return Theme.accent
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
                .foregroundStyle(Theme.jade)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .wrong:
            Text("正确答案：\(target?.romaji ?? "")　（\(target?.reading ?? "") · \(target?.meaning ?? "")）")
                .font(.footnote)
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var note: some View {
        Text("听写只是当场的耳力练习，不动你的记忆进度——要推进度，去「背单词」。")
            .font(.caption2)
            .foregroundStyle(Theme.muted.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 行为

    private func next() {
        if pool.isEmpty {
            pool = store.words.shuffled()
            if pool.count > 1, pool.last?.id == target?.id {
                pool.swapAt(0, pool.count - 1)
            }
        }
        target = pool.popLast()
        input = ""
        verdict = .idle
        hintShown = false
        Speech.shared.speak(target?.reading ?? "", rate: store.settings.speechRate)
    }

    private func check() {
        guard let word = target, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let typed = normalize(input)
        let answer = normalize(word.romaji)
        let isRight = typed == answer || input.trimmingCharacters(in: .whitespacesAndNewlines) == word.reading
        verdict = isRight ? .right : .wrong
        total += 1
        if isRight { correct += 1 }
        if !isRight { hintShown = true }
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
