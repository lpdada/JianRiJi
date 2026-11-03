import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: Store

    @State private var query = ""
    @State private var showDictation = false
    @State private var showReview = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleDecks: [Deck] {
        guard !trimmedQuery.isEmpty else { return store.decks }
        return store.decks.filter {
            $0.title.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.subtitle.localizedCaseInsensitiveContains(trimmedQuery)
                || $0.badge.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    todayStrip
                    searchBar
                    deckList
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("词本")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showReview) {
                ReviewView()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showDictation = true
                    } label: {
                        Image(systemName: "ear")
                    }
                }
            }
        }
        .sheet(isPresented: $showDictation) {
            DictationView()
                .environmentObject(store)
        }
    }

    // MARK: - 今日

    private var todayStrip: some View {
        HStack(spacing: 14) {
            ZStack {
                RingProgress(value: store.todayProgress, lineWidth: 7)
                Text("\(Int(store.todayProgress * 100))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(store.currentDeckTitle) · 今天")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 10) {
                    stat("待复习", "\(store.remainingDueCount)")
                    stat("新词", "\(min(store.newAllowance, store.freshWords.count))")
                    if store.streak > 0 {
                        stat("连击", "\(store.streak)")
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                showReview = true
            } label: {
                Image(systemName: "play.fill")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .paperCard(padding: 14)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: - 搜索

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)

            TextField("搜索词本", text: $query)
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

    // MARK: - 词本

    private var deckList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Text("全部词本")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            Rectangle()
                .fill(Theme.hairline.opacity(0.5))
                .frame(height: 0.6)

            if visibleDecks.isEmpty {
                EmptyHint(icon: "books.vertical", title: "没有匹配的词本", detail: "换个关键词，或者清空搜索。")
            } else {
                ForEach(Array(visibleDecks.enumerated()), id: \.element.id) { offset, deck in
                    deckRow(deck, tint: Theme.deckTints[offset % Theme.deckTints.count])
                    if offset != visibleDecks.count - 1 {
                        Rectangle()
                            .fill(Theme.hairline.opacity(0.4))
                            .frame(height: 0.6)
                            .padding(.leading, 76)
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func deckRow(_ deck: Deck, tint: Color) -> some View {
        Button {
            store.selectDeck(deck)
            showReview = true
        } label: {
            HStack(spacing: 14) {
                cover(deck, tint: tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text(deck.subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    Text("共 \(deck.count) 词")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 2)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted.opacity(0.6))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func cover(_ deck: Deck, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(0.16))
            VStack(spacing: 2) {
                Text(deck.badge)
                    .font(.system(size: deck.isAll ? 15 : 15, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                Text(deck.isAll ? "ALL" : "JLPT")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.75))
            }
        }
        .frame(width: 54, height: 68)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 0.8)
        )
    }

    private var footer: some View {
        VStack(spacing: 3) {
            Text("一天二十张，比一口气两百张有用。")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Text("简日记 v0.2.0 · MIT")
                .font(.caption2)
                .foregroundStyle(Theme.muted.opacity(0.7))
        }
        .padding(.top, 10)
    }
}
