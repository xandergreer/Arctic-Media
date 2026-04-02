import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var api: APIService
    @State private var recentMovies: [MediaItem] = []
    @State private var recentShows: [MediaItem]  = []
    @State private var allMovies: [MediaItem]    = []
    @State private var allShows: [MediaItem]     = []
    @State private var continueWatching: [ContinueWatchingItem] = []
    @State private var isLoading = true
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            homeTab
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            moviesTab
                .tabItem { Label("Movies", systemImage: "film.fill") }
                .tag(1)

            showsTab
                .tabItem { Label("TV Shows", systemImage: "tv.fill") }
                .tag(2)

            settingsTab
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(3)
        }
        .task { await load() }
    }

    // MARK: - Tabs

    private var homeTab: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            if !continueWatching.isEmpty {
                                continueWatchingSection
                            }
                            if !recentMovies.isEmpty {
                                shelfSection(title: "Recently Added Movies", items: recentMovies) { item in
                                    MovieDetailView(item: item)
                                }
                            }
                            if !recentShows.isEmpty {
                                shelfSection(title: "Recently Added Shows", items: recentShows) { item in
                                    ShowDetailView(item: item)
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Arctic Media")
        }
    }

    // MARK: - Continue Watching

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Continue Watching")
                .font(.title3.weight(.semibold))
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(continueWatching) { item in
                        ContinueWatchingCard(item: item)
                            .environmentObject(api)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var moviesTab: some View {
        NavigationStack {
            List(allMovies) { movie in
                NavigationLink(destination: MovieDetailView(item: movie)) {
                    MediaRow(item: movie)
                }
            }
            .navigationTitle("Movies")
            .overlay {
                if allMovies.isEmpty && !isLoading { emptyState(icon: "film", text: "No movies yet") }
            }
        }
    }

    private var showsTab: some View {
        NavigationStack {
            List(allShows) { show in
                NavigationLink(destination: ShowDetailView(item: show)) {
                    MediaRow(item: show)
                }
            }
            .navigationTitle("TV Shows")
            .overlay {
                if allShows.isEmpty && !isLoading { emptyState(icon: "tv", text: "No shows yet") }
            }
        }
    }

    private var settingsTab: some View {
        NavigationStack {
            SettingsView()
        }
    }

    // MARK: - Shelf row

    private func shelfSection<Dest: View>(
        title: String,
        items: [MediaItem],
        destination: @escaping (MediaItem) -> Dest
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(destination: destination(item)) {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Helpers

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func load() async {
        isLoading = true
        async let recent   = try? api.getRecentlyAdded()
        async let movies   = try? api.getMovies()
        async let shows    = try? api.getShows()
        async let cw       = try? api.getContinueWatching()
        let (r, m, s, c)   = await (recent, movies, shows, cw)
        recentMovies       = r?.movies ?? []
        recentShows        = r?.shows  ?? []
        allMovies          = m ?? []
        allShows           = s ?? []
        continueWatching   = c ?? []
        isLoading          = false
        // Refresh user info in case it changed
        if api.currentUser == nil { await api.fetchCurrentUser() }
    }
}

// MARK: - Continue Watching card

struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem
    @EnvironmentObject private var api: APIService
    @State private var streamItem: _StreamItem?

    var body: some View {
        Button {
            if let url = api.streamURL(mediaId: item.media_id) {
                streamItem = _StreamItem(id: item.media_id, url: url, title: cardTitle)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottom) {
                    PosterView(url: item.poster_url)
                        .frame(width: 120, height: 180)

                    // Progress bar
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color(.systemGray4))
                            .frame(height: 3)
                            .overlay(
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(width: geo.size.width * CGFloat(item.progress_pct) / 100, height: 3),
                                alignment: .leading
                            )
                    }
                    .frame(height: 3)
                }

                Text(item.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)

                if let sub = item.subtitle {
                    Text(sub)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .fullScreenCover(item: $streamItem) { s in
            VideoPlayerView(mediaId: s.id, streamURL: s.url, title: s.title)
                .environmentObject(api)
        }
    }

    private var cardTitle: String {
        if let sub = item.subtitle { return "\(item.title) – \(sub)" }
        return item.title
    }
}

private struct _StreamItem: Identifiable {
    let id: Int
    let url: URL
    let title: String
}

// MARK: - Poster card (shelf)

struct PosterCard: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterView(url: item.poster_url)
                .frame(width: 120, height: 180)

            Text(item.title)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)
        }
    }
}

// MARK: - Media list row

struct MediaRow: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            PosterView(url: item.poster_url)
                .frame(width: 50, height: 75)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.body.weight(.medium))
                if let year = item.year {
                    Text(year).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
