import SwiftUI

/// 语法学习：270 个分级语法点，按级别筛选、可搜句型 / 意义 / 接续 / 备注 / 例句读音 / 标签。
/// 点一条进详情：接续、意义、例句（日文 + 假名 + 中文）、备注，全部可朗读，可标记为学会。
struct GrammarView: View {
    @EnvironmentObject private var store: Store

    @State private var query = ""
    @State private var level = "全部"
    @State private var selected: GrammarPoint?

    private let levels = ["全部", "N5", "N4", "N3", "N2", "N1"]

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [GrammarPoint] {
        store.grammarSearch(trimmedQuery, level: level)
    }

    private var learnedCount: Int { store.learnedGrammarCount(forLevel: level) }
    private var totalCount: Int { store.grammarPoints(forLevel: level).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                searchBar

                Picker("级别", selection: $level) {
                    ForEach(levels, id: \.self) { item in
                        Text(item).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Text("已学 \(learnedCount) / 共 \(totalCount) 个")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)

                if results.isEmpty {
                    EmptyHint(
                        icon: "book",
                        title: "没找到这个语法点",
                        detail: "换个级别或换个关键词试试，比如「逆接」「条件」。"
                    )
                    .padding(.top, 24)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results) { point in
                            row(point)
                            Rectangle()
                                .fill(Theme.hairline.opacity(0.45))
                                .frame(height: 0.6)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("语法学习")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { point in
            GrammarDetailView(point: point)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)

            TextField("搜语法点、意义或标签", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private func row(_ point: GrammarPoint) -> some View {
        Button {
            selected = point
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(point.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if store.isGrammarLearned(point) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.jade)
                    }
                    Pill(text: point.level, tint: Theme.accent)
                }
                if let meaning = point.meaning {
                    Text(meaning)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                if let tag = point.tag {
                    Text(tag)
                        .font(.caption2)
                        .foregroundStyle(Theme.indigo)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct GrammarDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store

    let point: GrammarPoint

    private var learned: Bool { store.isGrammarLearned(point) }

    private func speak(_ text: String) {
        Speech.shared.speak(text, rate: store.settings.speechRate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if let connection = point.connection, !connection.isEmpty {
                        section(title: "接续", body: connection) { speak(connection) }
                    }
                    if let meaning = point.meaning, !meaning.isEmpty {
                        section(title: "意义", body: meaning) { speak(meaning) }
                    }
                    if let examples = point.examples, !examples.isEmpty {
                        examplesCard(examples)
                    } else if let example = point.example, !example.isEmpty {
                        exampleCard(example)
                    }
                    if let note = point.note, !note.isEmpty {
                        section(title: "备注", body: note) { speak(note) }
                    }
                    learnButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("语法点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(point.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button {
                    speak(point.title)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.indigo)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Pill(text: point.level, tint: Theme.accent)
                if let tag = point.tag {
                    Pill(text: tag, tint: Theme.indigo)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 18)
    }

    private func section(title: String, body: String, speakAction: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.indigo)
                Spacer()
                Button(action: speakAction) {
                    Label("朗读", systemImage: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.indigo)
                }
                .buttonStyle(.plain)
            }
            Text(body)
                .font(.system(size: 17))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 16)
    }

    private func exampleCard(_ example: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("例句")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.indigo)
                Spacer()
                Button {
                    speak(example)
                } label: {
                    Label("朗读", systemImage: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.indigo)
                }
                .buttonStyle(.plain)
            }
            Text(example)
                .font(.system(size: 17))
            if let reading = point.exampleReading, !reading.isEmpty {
                Text(reading)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            if let zh = point.exampleZh, !zh.isEmpty {
                Text(zh)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 16)
    }

    private func examplesCard(_ examples: [GrammarExample]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("例句")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.indigo)
            ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(example.ja)
                            .font(.system(size: 17))
                        Spacer()
                        Button {
                            speak(example.ja)
                        } label: {
                            Label("朗读", systemImage: "speaker.wave.2.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.indigo)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(example.zh)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 16)
    }

    private var learnButton: some View {
        Button {
            store.markGrammarLearned(point)
        } label: {
            Text(learned ? "已标记为学会" : "标记为学会")
        }
        .buttonStyle(PrimaryButtonStyle(fill: learned ? Theme.jade : Theme.accent))
    }
}
