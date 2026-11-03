import SwiftUI

/// 连连看：左列日文、右列中文，两两配对。
/// 连连看模式：日文配中文，四组一轮。
struct LianliankaView: View {
    @EnvironmentObject private var store: Store

    @State private var pairs: [Word] = []
    @State private var left: [Word] = []
    @State private var right: [Word] = []
    @State private var selectedLeft: String?
    @State private var selectedRight: String?
    @State private var matched: Set<String> = []
    @State private var wrongPair: Set<String> = []
    @State private var cleared = 0
    @State private var locked = false
    /// 词本词数不足 4 时，deal() 会置此位，不再只剩一个空棋盘。
    @State private var insufficient = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if insufficient {
                    EmptyHint(
                        icon: "books.vertical",
                        title: "这个词本不够 4 个词",
                        detail: "连连看一次要发 4 组词。回词本页切到「全部词本」，或换一个词更多的词本再来。"
                    )
                    .padding(.top, 8)
                } else {
                    board
                }
                hint
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("连连看")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if pairs.isEmpty { deal() }
        }
    }

    private var header: some View {
        HStack {
            Text("日文配中文")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("已清 \(cleared) 组")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .paperCard(padding: 12)
    }

    private var board: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 10) {
                ForEach(left) { word in
                    card(word, side: .left)
                }
            }
            VStack(spacing: 10) {
                ForEach(right) { word in
                    card(word, side: .right)
                }
            }
        }
    }

    private enum Side { case left, right }

    private func card(_ word: Word, side: Side) -> some View {
        let isMatched = matched.contains(word.id)
        let isWrong = wrongPair.contains(word.id)
        let isSelected = (side == .left ? selectedLeft : selectedRight) == word.id

        return Button {
            tap(word, side: side)
        } label: {
            VStack(spacing: 3) {
                Text(side == .left ? word.term : word.meaning)
                    .font(.system(size: side == .left ? 17 : 15, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                if side == .left {
                    Text(word.reading)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
            }
            .foregroundStyle(isMatched ? Theme.muted : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(
                background(isMatched: isMatched, isWrong: isWrong, isSelected: isSelected),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isWrong ? Color(red: 0.78, green: 0.32, blue: 0.28) : Color.primary.opacity(0.06),
                        lineWidth: isWrong ? 1.4 : 1
                    )
            )
            .opacity(isMatched ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isMatched || locked)
    }

    private func background(isMatched: Bool, isWrong: Bool, isSelected: Bool) -> Color {
        if isMatched { return Theme.mint }
        if isWrong { return Color(red: 0.98, green: 0.90, blue: 0.88) }
        if isSelected { return Theme.mint }
        return Theme.card
    }

    private var hint: some View {
        Text("点左边一个日文，再点右边对应的中文。点错不扣分，只闪一下。")
            .font(.caption2)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 逻辑

    private func deal() {
        let pool = store.scopedWords.shuffled()
        guard pool.count >= 4 else {
            pairs = []
            left = []
            right = []
            insufficient = true
            return
        }
        insufficient = false

        pairs = Array(pool.prefix(4))
        left = pairs.shuffled()
        right = pairs.shuffled()
        selectedLeft = nil
        selectedRight = nil
        matched = []
        wrongPair = []
        locked = false
    }

    private func tap(_ word: Word, side: Side) {
        guard !locked else { return }
        switch side {
        case .left: selectedLeft = word.id
        case .right: selectedRight = word.id
        }
        resolveIfReady()
    }

    private func resolveIfReady() {
        guard let l = selectedLeft, let r = selectedRight else { return }

        if l == r {
            matched.insert(l)
            cleared += 1
            if let word = pairs.first(where: { $0.id == l }) {
                store.grade(word: word, grade: .good)
                Speech.shared.speak(word.term, rate: store.settings.speechRate)
            }
            selectedLeft = nil
            selectedRight = nil

            if matched.count == pairs.count {
                locked = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    deal()
                }
            }
        } else {
            locked = true
            wrongPair = [l, r]
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                wrongPair = []
                selectedLeft = nil
                selectedRight = nil
                locked = false
            }
        }
    }
}
