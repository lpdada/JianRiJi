import SwiftUI

struct DictionaryView: View {
    @EnvironmentObject private var store: Store

    @State private var query = ""
    @State private var scope: Scope = .search
    @State private var selected: Word?

    enum Scope: String, CaseIterable, Identifiable {
        case search = "查词"
        case favorites = "收藏"

        var id: String { rawValue }
    }

    init(initialScope: Scope = .search) {
        _scope = State(initialValue: initialScope)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [Word] {
        switch scope {
        case .search:
            return trimmedQuery.isEmpty ? [] : store.search(trimmedQuery)
        case .favorites:
            return store.favoriteWords
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                Picker("范围", selection: $scope) {
                    ForEach(Scope.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if results.isEmpty {
                            EmptyHint(
                                icon: scope == .favorites ? "star" : "magnifyingglass",
                                title: scope == .favorites ? "还没有收藏" : "查点什么",
                                detail: scope == .favorites
                                    ? "词条右上角的星标，收着的都在这儿。"
                                    : "日文、假名、romaji、中文，四种都能搜。"
                            )
                            .padding(.top, 24)
                        } else {
                            ForEach(Array(results.enumerated()), id: \.element.id) { offset, word in
                                row(word)
                                if offset != results.count - 1 {
                                    Rectangle()
                                        .fill(Theme.hairline.opacity(0.45))
                                        .frame(height: 0.6)
                                        .padding(.leading, 16)
                                }
                            }
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                }
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("查词")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selected) { word in
            WordDetailView(word: word)
                .environmentObject(store)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)

            TextField("输入日文 或 假名", text: $query)
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

    private func row(_ word: Word) -> some View {
        Button {
            selected = word
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(word.term)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.primary)

                    Text("〔\(word.reading)〕")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)

                    Spacer(minLength: 6)

                    if store.isFavorite(word) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                    }
                }

                HStack(spacing: 8) {
                    Text(word.partOfSpeech)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.indigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.mint, in: RoundedRectangle(cornerRadius: 3, style: .continuous))

                    Text(word.meaning)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WordDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let word: Word

    private var state: SRSState { store.card(for: word) }

    /// 词性判断不出来时为 nil，整块不显示，不猜。
    private var conjugation: ConjugationForms? { Conjugation.conjugate(word) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if let example = word.example {
                        exampleCard(example)
                    }
                    if let note = word.note, !note.isEmpty {
                        noteCard(note)
                    }
                    memoryCard
                    if let forms = conjugation {
                        conjugationCard(forms)
                    }
                    if let variants = word.variants, !variants.isEmpty {
                        variantsCard(variants)
                    }
                    actions
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("词条")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        store.toggleFavorite(word)
                    } label: {
                        Image(systemName: store.isFavorite(word) ? "star.fill" : "star")
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(word.term)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text("\(word.reading)  |  \(word.romaji)")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)

            HStack(spacing: 6) {
                Pill(text: word.jlpt, tint: Theme.accent)
                Pill(text: word.partOfSpeech, tint: Theme.indigo)
            }
            .padding(.top, 2)

            Text(word.meaning)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Button {
                Speech.shared.speak(word.reading, rate: store.settings.speechRate)
            } label: {
                Label("读一遍", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(GhostButtonStyle(tint: Theme.accent))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .paperCard(padding: 18)
    }

    private func noteCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("解析")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.indigo)
            Text(note)
                .font(.system(size: 17))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 16)
    }

    private func exampleCard(_ example: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("例句")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.indigo)
            Text(example)
                .font(.system(size: 17))
            if let zh = word.exampleZh {
                Text(zh)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 16)
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("记忆状态")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.indigo)

            HStack(spacing: 0) {
                StatBlock(value: "Lv.\(state.level)", label: "台阶", tint: Theme.accent)
                Divider().frame(height: 26)
                StatBlock(value: "\(state.correct)", label: "记得", tint: Theme.jade)
                Divider().frame(height: 26)
                StatBlock(value: "\(state.wrong)", label: "忘了", tint: Color(red: 0.78, green: 0.32, blue: 0.28))
            }

            HStack {
                Text(state.isNew ? "还没开始学" : "下次到期")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(dueText)
                    .font(.caption.weight(.medium))
            }

            ProgressView(value: state.mastery)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 16)
    }

    private func conjugationCard(_ forms: ConjugationForms) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("变形")
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

    private func variantsCard(_ variants: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("补充形式")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.indigo)

            ForEach(variants.keys.sorted(), id: \.self) { key in
                HStack {
                    Text(key)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text(variants[key] ?? "")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 16)
    }

    private var dueText: String {
        guard !state.isNew else { return "—" }
        if state.due <= Date() { return "已到期" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: state.due, relativeTo: Date())
    }

    @State private var showAIExplanation = false

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                showAIExplanation = true
            } label: {
                Label("AI 讲解", systemImage: "sparkles")
            }
            .buttonStyle(GhostButtonStyle(tint: Theme.indigo))
            .sheet(isPresented: $showAIExplanation) {
                AIExplanationView(word: word)
            }

            Button {
                store.grade(word: word, grade: .again)
                dismiss()
            } label: {
                Text("我忘了，重新排")
            }
            .buttonStyle(PrimaryButtonStyle(fill: Theme.accent))

            Button {
                store.resetCard(for: word)
                dismiss()
            } label: {
                Text("重置这张卡")
            }
            .buttonStyle(GhostButtonStyle(tint: Theme.muted))
        }
    }
}
