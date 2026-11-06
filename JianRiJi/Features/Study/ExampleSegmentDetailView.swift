import SwiftUI

/// 点例句里的某一段时弹出的详情。
///
/// 能对上词条（`segment.word != nil`）就展示完整词条；
/// 对不上就**如实说没收录**，顺手把这一段的读音、它出现在哪句里一并给出，
/// 不拿近义词硬凑一个释义。
struct ExampleSegmentDetailView: View {
    let segment: ExampleSegment
    /// 这一句例句本身，给未收录的段一个上下文
    let sentence: String
    let sentenceZh: String?

    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if let word = segment.word {
                        meaningCard(word)
                        if let forms = Conjugation.conjugate(word) {
                            conjugationCard(forms)
                        }
                        if let example = word.example, !example.isEmpty {
                            exampleCard(word, example)
                        }
                    } else {
                        notFoundCard
                    }
                    contextCard
                    actions
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("这一小段")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let word = segment.word {
                        Button {
                            store.toggleFavorite(word)
                        } label: {
                            Image(systemName: store.isFavorite(word) ? "star.fill" : "star")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(spacing: 8) {
            Text(segment.surface)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(segment.hasDictionaryEntry ? Theme.accent : Theme.indigo)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let reading = segment.reading, !reading.isEmpty {
                Text("\(reading)  ・  \(segment.romaji ?? KanaRomaji.romaji(for: reading))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            HStack(spacing: 6) {
                Pill(text: kindTitle, tint: kindTint)
                if let word = segment.word {
                    Pill(text: word.jlpt, tint: Theme.accent)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .paperCard(padding: 18)
    }

    private var kindTitle: String {
        switch segment.kind {
        case .word: return "词库词条"
        case .inflection: return "活用形"
        case .particle: return "助词 / 助动词"
        case .kana: return "假名"
        case .unknownKanji: return "未收录"
        case .punctuation: return "标点"
        case .other: return "其它"
        }
    }

    private var kindTint: Color {
        switch segment.kind {
        case .word, .inflection: return Theme.accent
        case .unknownKanji: return Color(red: 0.78, green: 0.32, blue: 0.28)
        default: return Theme.indigo
        }
    }

    // MARK: - 卡片

    private func meaningCard(_ word: Word) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("释义")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.indigo)

            HStack(alignment: .top, spacing: 8) {
                Pill(text: word.partOfSpeech, tint: Theme.indigo)
                Text(word.meaning)
                    .font(.system(size: 18, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if segment.kind == .inflection {
                Text("这是「\(word.term)」的活用形。")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 16)
    }

    private func conjugationCard(_ forms: ConjugationForms) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("活用")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.indigo)

            ForEach(Array(forms.displayRows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.label)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text(row.value)
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 16)
    }

    private func exampleCard(_ word: Word, _ example: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这个词的例句")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.indigo)

            Text(example)
                .font(.system(size: 17))
                .fixedSize(horizontal: false, vertical: true)

            if let zh = word.exampleZh, !zh.isEmpty {
                Text(zh)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }

            Button {
                Speech.shared.speak(example, rate: store.settings.speechRate)
            } label: {
                Label("读一遍", systemImage: "speaker.wave.2.fill")
                    .font(.caption)
            }
            .buttonStyle(GhostButtonStyle(tint: Theme.indigo))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 16)
    }

    private var notFoundCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("词库里没有这一条")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.indigo)

            Text(notFoundHint)
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 16)
    }

    /// 按段的类型给出不同的、真实成立的解释。
    private var notFoundHint: String {
        switch segment.kind {
        case .particle:
            return "「\(segment.surface)」是功能词（助词 / 助动词），词库不收这类词条。它在这里负责把前后的词连起来，本身没有独立释义。"
        case .unknownKanji:
            return "「\(segment.surface)」在 10660 条词库里没有对应词条，所以这里不标读音、也不给释义——猜一个读音或凑一个意思都会把你带偏。"
        case .kana:
            return "「\(segment.surface)」是词库外的假名块，通常跟着前一个词一起用。"
        default:
            return "「\(segment.surface)」这一小段没有对应的词条。"
        }
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("它出现在")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.indigo)

            Text(sentence)
                .font(.system(size: 16))
                .fixedSize(horizontal: false, vertical: true)

            if let zh = sentenceZh, !zh.isEmpty {
                Text(zh)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 16)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                let text = segment.reading ?? segment.surface
                Speech.shared.speak(text, rate: store.settings.speechRate)
            } label: {
                Label("读这一小段", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(PrimaryButtonStyle(fill: Theme.accent))

            if let word = segment.word {
                Button {
                    Speech.shared.speak(word.reading, rate: max(0.30, store.settings.speechRate - 0.15))
                } label: {
                    Text("慢速读词条")
                }
                .buttonStyle(GhostButtonStyle(tint: Theme.indigo))
            }
        }
    }
}
