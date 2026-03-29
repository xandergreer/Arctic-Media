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
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Active tab content — each tab has its own NavigationStack
            Group {
                switch selectedTab {
                case 0: NavigationStack { HomeView() }
                case 1: NavigationStack { LibraryView(kind: .movie) }
                case 2: NavigationStack { LibraryView(kind: .show) }
                case 3: NavigationStack { SearchView() }
                default: NavigationStack { SettingsView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Reserve space at the bottom so content isn't hidden behind the tab bar
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 49)
            }

            // Custom tab bar — bypasses iOS 18 floating pill entirely
            ArcticTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
        .tint(.arcticPrimary)
    }
}

// MARK: - Custom Tab Bar

private struct ArcticTabBar: View {
    @Binding var selectedTab: Int

    private let tabs: [(label: String, icon: String)] = [
        ("Home",     "house.fill"),
        ("Movies",   "film.fill"),
        ("TV Shows", "tv.fill"),
        ("Search",   "magnifyingglass"),
        ("Settings", "gearshape.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Top separator
            Color.arcticBorder.frame(height: 0.5)

            // Tab items
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    Button(action: { selectedTab = index }) {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20, weight: selectedTab == index ? .semibold : .regular))
                            Text(tab.label)
                                .font(.system(size: 10, weight: selectedTab == index ? .semibold : .regular))
                        }
                        .foregroundColor(selectedTab == index ? .arcticPrimary : .arcticMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 49)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.arcticBg)

            // Safe area fill below home indicator
            Color.arcticBg
                .frame(height: 34)
        }
    }
}
