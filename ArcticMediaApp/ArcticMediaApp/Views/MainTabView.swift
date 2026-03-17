import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var api: APIService

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            LibraryView(kind: "movies")
                .tabItem {
                    Label("Movies", systemImage: "film.fill")
                }

            LibraryView(kind: "shows")
                .tabItem {
                    Label("TV Shows", systemImage: "tv.fill")
                }

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(.blue)
        #if os(iOS)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        #endif
    }
}
