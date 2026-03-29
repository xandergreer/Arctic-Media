import SwiftUI

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var query = ""
    @State private var results: SearchResult?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)]

    var body: some View {
        ZStack {
            Color.arcticBg.ignoresSafeArea()

            if loading {
                ProgressView().tint(.arcticPrimary)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundColor(.arcticMuted)
                    Text(errorMessage)
                        .font(.caption).foregroundColor(.arcticSub)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
            } else if let results {
                if results.total == 0 {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle).foregroundColor(.arcticMuted)
                        Text("No results for \"\(query)\"").foregroundColor(.arcticSub)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if !results.movies.isEmpty { section(title: "Movies", items: results.movies) }
                            if !results.shows.isEmpty  { section(title: "TV Shows", items: results.shows) }
                        }
                        .padding()
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle).foregroundColor(.arcticMuted)
                    Text("Search movies and TV shows").foregroundColor(.arcticSub)
                }
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.arcticBg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(text: $query, prompt: "Movies, shows…")
        .onChange(of: query) { _, _ in search() }
    }

    @ViewBuilder
    private func section(title: String, items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline.bold()).foregroundColor(.arcticText)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items) { item in
                    NavigationLink(destination: MediaDetailView(item: item)) {
                        MediaCardView(item: item, serverURL: appState.serverURL)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func search() {
        searchTask?.cancel()
        errorMessage = nil
        guard query.count >= 2 else { results = nil; return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { loading = true }
            do {
                let r = try await APIService.shared.search(
                    serverURL: appState.serverURL,
                    token: appState.token ?? "",
                    query: query
                )
                await MainActor.run { results = r; loading = false }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; loading = false }
            }
        }
    }
}
