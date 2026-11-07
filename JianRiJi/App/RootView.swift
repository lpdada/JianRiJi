import SwiftUI

enum RootTab: Hashable {
    case home
    case books
    case settings
}

/// 首页内的跳转目标（首页 Tab 自己的 NavigationStack）。
enum HomeDestination: Hashable {
    case studyClassic
    case grammar
    case dictionary
    case favorites
    case kana
    case studyHub
    case connect
    case listen
    case voiceSettings
}

/// 词本 Tab 内的跳转目标。
enum BooksDestination: Hashable {
    case studyClassic
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var brainwash = BrainwashStore()
    @State private var selection: RootTab = .home
    @State private var homePath = NavigationPath()
    @State private var booksPath = NavigationPath()

    var body: some View {
        Group {
            if store.isReady {
                tabs
            } else {
                LaunchPlaceholder()
            }
        }
        .tint(AppTheme.primary)
        .environmentObject(brainwash)
        .task { store.bootstrap() }
        .task(id: scenePhase) {
            if scenePhase != .active { store.flush() }
        }
    }

    @ViewBuilder
    private var tabs: some View {
        TabView(selection: $selection) {
            NavigationStack(path: $homePath) {
                HomeDashboardView(
                    state: dashboardState,
                    onStartStudy: { homePath.append(HomeDestination.studyClassic) },
                    onSwitchBook: { selection = .books },
                    onQuickWords: { homePath.append(HomeDestination.studyClassic) },
                    onGrammar: { homePath.append(HomeDestination.grammar) },
                    onWordBooks: { selection = .books },
                    onSearch: { homePath.append(HomeDestination.dictionary) },
                    onKana: { homePath.append(HomeDestination.kana) },
                    onFavorites: { homePath.append(HomeDestination.favorites) },
                    onReviewRecords: { homePath.append(HomeDestination.studyHub) },
                    onConnect: { homePath.append(HomeDestination.connect) },
                    onListen: { homePath.append(HomeDestination.listen) },
                    onVoicePack: { homePath.append(HomeDestination.voiceSettings) }
                )
                .navigationDestination(for: HomeDestination.self) { destination in
                    homeDestinationView(destination)
                }
            }
            .tabItem { Label("首页", systemImage: "house.fill") }
            .tag(RootTab.home)

            NavigationStack(path: $booksPath) {
                BookSwitchView(
                    categories: bookCategories,
                    allBooks: bookRows,
                    onToggleStudy: { row in
                        if let book = store.books.first(where: { $0.id == row.id }) {
                            store.selectBook(book)
                        }
                    },
                    onStartStudy: { _ in booksPath.append(BooksDestination.studyClassic) }
                )
                .navigationDestination(for: BooksDestination.self) { _ in
                    WordStudyPageView()
                }
            }
            .tabItem { Label("词本", systemImage: "books.vertical.fill") }
            .tag(RootTab.books)

            // SettingsView 自带 NavigationStack，这里不再包一层。
            SettingsView()
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(RootTab.settings)
        }
    }

    @ViewBuilder
    private func homeDestinationView(_ destination: HomeDestination) -> some View {
        switch destination {
        case .studyClassic:
            WordStudyPageView()
        case .grammar: GrammarView()
        case .dictionary: DictionaryView()
        case .favorites: DictionaryView(initialScope: .favorites)
        case .kana: KanaChartView()
        case .studyHub: StudyHubView()
        case .connect: LianliankaView()
        case .listen: SuishentingView()
        case .voiceSettings: VoiceSettingsView()
        }
    }

    /// 首页 Hero 卡：全部数字都从 Store 的真实数据算，不写死。
    private var dashboardState: DashboardState {
        let book = store.currentBook
        let lastWord: String? = {
            guard let last = store.log.last,
                  let word = store.word(withID: last.wordID) else { return nil }
            return "\(word.term)（\(word.reading)）"
        }()
        return DashboardState(
            bookTitle: book.title,
            bookBadge: book.badge,
            bookTint: book.tint,
            learned: store.learnedCount(in: book),
            total: store.wordCount(in: book),
            dueCount: store.remainingDueCount,
            newTarget: store.settings.dailyGoal,
            lastWord: lastWord
        )
    }

    private var bookCategories: [String] {
        ["已学词单", "常用词单", "考试词单", "生活实用", "日常高频"]
    }

    private var bookRows: [BookRowData] {
        store.books.map { book in
            BookRowData(
                id: book.id,
                title: book.title,
                badge: book.badge,
                tint: book.tint,
                categories: book.categories,
                learned: store.learnedCount(in: book),
                total: store.wordCount(in: book),
                studying: book.id == store.currentBook.id
            )
        }
    }
}
