import SwiftUI

struct DictionaryView: View {
    @EnvironmentObject private var store: Store

    @State private var query = ""
    @State private var scope: Scope = .search
    @State private var selected: Word?

    enum Scope: String, CaseIterable, Identifiable {
        case search = "搜索"
        case favorites = "收藏"

        var id: String { rawValue }
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
            VStack(spacing: 12) {
                Picker("范围", selection: $scope) {
                    ForEach(Scope.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                searchBar
                    .padding(.horizontal, 16)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        if !trimmedQuery.isEmpty || scope == .favorites {
                            Text("\(results.count) 条结果")
                                .font(.caption2)
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if results.isEmpty {
                            EmptyHint(
                                icon: scope == .favorites ? "bookmark" : "magnifyingglass",
                                title: scope == .favorites ? "还没有收藏" : "查点什么",
                                detail: scope == .favorites
                                    ? "词条详情页右上角的书签，收着的都在这儿。"
                                    : "汉字、假名、romaji、中文，四种都能搜。"
                            )
                        } else {
                            ForEach(results) { word in
                                row(word)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .padding(.top, 6)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("词典")
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

            TextField("汉字 / 假名 / romaji / 中文", text: $query)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func row(_ word: Word) -> some View {
        Button {
            selected = word
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(word.term)
                            .font(.headline)
                        Text(word.reading)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    Text(word.meaning)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if store.isFavorite(word) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }

                Pill(text: word.jlpt, tint: Theme.indigo)
            }
            .paperCard(padding: 12)
        }
        .buttonStyle(.plain)
    }
}

struct WordDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let word: Word

    private var state: SRSState { store.card(for: word) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if let example = word.example {
                        exampleCard(example)
                    }
                    memoryCard
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
                    Button {
                        dismiss()
                    } label: {
                        Text("关闭")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        store.toggleFavorite(word)
                    } label: {
                        Image(systemName: store.isFavorite(word) ? "bookmark.fill" : "bookmark")
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(word.term)
                .font(.system(size: 44, weight: .medium, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(word.reading)
                .font(.title3)
                .foregroundStyle(Theme.muted)

            Text(word.romaji)
                .font(.footnote)
                .foregroundStyle(Theme.muted.opacity(0.8))

            HStack(spacing: 6) {
                Pill(text: word.jlpt, tint: Theme.indigo)
                Pill(text: word.partOfSpeech)
            }
            .padding(.top, 2)

            Text(word.meaning)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            Button {
                Speech.shared.speak(word.reading, rate: store.settings.speechRate)
            } label: {
                Label("读一遍", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(GhostButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .paperCard(padding: 20)
    }

    private func exampleCard(_ example: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("例句")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Text(example)
                .font(.body)
            if let zh = word.exampleZh {
                Text(zh)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard(padding: 16)
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("记忆状态")
                .font(.caption)
                .foregroundStyle(Theme.muted)

            HStack(spacing: 0) {
                StatBlock(value: "Lv.\(state.level)", label: "台阶", tint: Theme.accent)
                Divider().frame(height: 26)
                StatBlock(value: "\(state.correct)", label: "记得", tint: Theme.jade)
                Divider().frame(height: 26)
                StatBlock(value: "\(state.wrong)", label: "忘了", tint: Color.orange)
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
                .tint(Theme.jade)
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

    private var actions: some View {
        VStack(spacing: 10) {
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
