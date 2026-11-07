import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: Store

    @State private var query = ""
    @State private var category = "全部"
    @State private var showDictation = false
    @State private var showReview = false

    private let categories = ["全部", "常用词单", "考试词单", "生活实用", "日常高频", "已学词单"]

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleBooks: [WordBook] {
        store.books.filter { book in
            let inCategory = category == "全部" || book.categories.contains(category)
            guard inCategory else { return false }
            guard !trimmedQuery.isEmpty else { return true }
            return book.title.localizedCaseInsensitiveContains(trimmedQuery)
                || book.note.localizedCaseInsensitiveContains(trimmedQuery)
                || book.badge.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private var currentBook: WordBook { store.currentBook }
    private var currentBookCount: Int { store.wordCount(in: currentBook) }
    private var currentBookEmpty: Bool { currentBookCount == 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    todayStrip
                    searchBar
                    categoryChips
                    bookList
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    RingProgress(value: store.todayProgress, lineWidth: 7)
                    Text("\(Int(store.todayProgress * 100))%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(store.currentBookTitle) · 今天")
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
                .disabled(currentBookEmpty)
                .opacity(currentBookEmpty ? 0.4 : 1)
            }

            if currentBookEmpty {
                Text("这本词书还没有词，换一本词书，或者用导入工具加词。")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
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

    // MARK: - 搜索与分类

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

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { item in
                    Button {
                        category = item
                    } label: {
                        Text(item)
                            .font(.footnote.weight(category == item ? .semibold : .regular))
                            .foregroundStyle(category == item ? .white : Theme.muted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                category == item ? Theme.accent : Theme.card,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 词书

    private var bookList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Text("词书")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            Rectangle()
                .fill(Theme.hairline.opacity(0.5))
                .frame(height: 0.6)

            if visibleBooks.isEmpty {
                EmptyHint(icon: "books.vertical", title: "没有匹配的词书", detail: "换个分类或关键词，或者清空搜索。")
            } else {
                ForEach(Array(visibleBooks.enumerated()), id: \.element.id) { offset, book in
                    bookRow(book, tint: Theme.deckTints[offset % Theme.deckTints.count])
                    if offset != visibleBooks.count - 1 {
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

    private func bookRow(_ book: WordBook, tint: Color) -> some View {
        let words = store.words(in: book)
        let learned = store.learnedCount(in: book)
        let isCurrent = book.id == store.currentBook.id

        return Button {
            store.selectBook(book)
            showReview = true
        } label: {
            HStack(spacing: 14) {
                cover(book, tint: tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                    Text(book.note)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                    Text("共 \(words.count) 词 · 已学 \(learned) 词")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 2)
                }

                Spacer(minLength: 6)

                if isCurrent {
                    Text("学习中")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.mint, in: Capsule())
                } else if words.isEmpty {
                    Text("暂无词")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted.opacity(0.7))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.muted.opacity(0.6))
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(words.isEmpty)
        .opacity(words.isEmpty && !isCurrent ? 0.55 : 1)
    }

    private func cover(_ book: WordBook, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(0.16))
            VStack(spacing: 2) {
                Text(book.badge)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(book.isAll ? "ALL" : "BOOK")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.75))
            }
            .padding(2)
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
            Text("简日记 v0.4.0 · MIT")
                .font(.caption2)
                .foregroundStyle(Theme.muted.opacity(0.7))
        }
        .padding(.top, 10)
    }
}
