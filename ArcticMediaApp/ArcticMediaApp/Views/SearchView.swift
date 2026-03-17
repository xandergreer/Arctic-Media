import SwiftUI

struct SearchView: View {
    @EnvironmentObject var api: APIService
    @State private var query = ""
    @State private var results: [MediaItem] = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    ContentUnavailableView(
                        "Search",
                        systemImage: "magnifyingglass",
                        description: Text("Search for movies and TV shows")
                    )
                } else if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { item in
                        NavigationLink(destination: destinationView(for: item)) {
                            SearchResultRow(item: item)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Movies, shows...")
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                    results = []
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    await performSearch(newValue)
                }
            }
        }
    }

    @ViewBuilder
    private func destinationView(for item: MediaItem) -> some View {
        switch item.kind {
        case "movie": MovieDetailView(itemId: item.id)
        case "show":  ShowDetailView(itemId: item.id)
        default:      MovieDetailView(itemId: item.id)
        }
    }

    private func performSearch(_ q: String) async {
        isSearching = true
        error = nil
        do {
            results = try await api.search(query: q)
        } catch {
            self.error = error.localizedDescription
            results = []
        }
        isSearching = false
    }
}

struct SearchResultRow: View {
    @EnvironmentObject var api: APIService
    let item: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: api.posterURL(for: item)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle()
                        .fill(Color.secondarySystemBackground)
                        .overlay(
                            Image(systemName: item.kind == "show" ? "tv" : "film")
                                .foregroundStyle(.tertiary)
                        )
                }
            }
            .frame(width: 50, height: 75)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let year = item.year {
                        Text(String(year))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(item.kind == "show" ? "TV Show" : "Movie")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.kind == "show" ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15))
                        .foregroundStyle(item.kind == "show" ? .purple : .blue)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }
}
