import SwiftUI

enum RootTab: Hashable {
    case home
    case review
    case kana
    case dictionary
    case settings
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @State private var selection: RootTab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView(selection: $selection)
                .tabItem { Label("今天", systemImage: "sun.max") }
                .tag(RootTab.home)

            ReviewView()
                .tabItem { Label("背单词", systemImage: "rectangle.stack") }
                .tag(RootTab.review)

            KanaChartView()
                .tabItem { Label("五十音", systemImage: "square.grid.3x3") }
                .tag(RootTab.kana)

            DictionaryView()
                .tabItem { Label("词典", systemImage: "magnifyingglass") }
                .tag(RootTab.dictionary)

            SettingsView()
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
                .tag(RootTab.settings)
        }
        .task {
            store.bootstrap()
        }
    }
}
