import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if !appState.isConfigured {
                ServerSetupView()
            } else if !appState.isAuthenticated {
                LoginView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isConfigured)
        .animation(.easeInOut(duration: 0.2), value: appState.isAuthenticated)
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack { LibraryView(kind: .movie) }
                .tabItem { Label("Movies", systemImage: "film.fill") }

            NavigationStack { LibraryView(kind: .show) }
                .tabItem { Label("TV Shows", systemImage: "tv.fill") }

            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.arcticPrimary)
    }
}
