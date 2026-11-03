import SwiftUI

enum RootTab: Hashable {
    case home
    case study
    case kana
    case dictionary
    case settings
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @State private var selection: RootTab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("词本", systemImage: "books.vertical") }
                .tag(RootTab.home)

            StudyHubView()
                .tabItem { Label("学习", systemImage: "graduationcap") }
                .tag(RootTab.study)

            KanaChartView()
                .tabItem { Label("五十音", systemImage: "square.grid.3x3") }
                .tag(RootTab.kana)

            DictionaryView()
                .tabItem { Label("查词", systemImage: "magnifyingglass") }
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
