import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var api: APIService
    let kind: String  // "movies" or "shows"

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var sortOrder = SortOrder.titleAsc

    enum SortOrder: String, CaseIterable {
        case titleAsc = "Title (A–Z)"
        case titleDesc = "Title (Z–A)"
        case yearDesc = "Newest First"
        case yearAsc = "Oldest First"
    }

    private var title: String { kind == "movies" ? "Movies" : "TV Shows" }

    private var sorted: [MediaItem] {
        switch sortOrder {
        case .titleAsc:  return items.sorted { ($0.sort_title ?? $0.title) < ($1.sort_title ?? $1.title) }
        case .titleDesc: return items.sorted { ($0.sort_title ?? $0.title) > ($1.sort_title ?? $1.title) }
        case .yearDesc:  return items.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .yearAsc:   return items.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = error {
                    ContentUnavailableView(
                        "Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(err)
                    )
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "No \(title)",
                        systemImage: kind == "movies" ? "film" : "tv",
                        description: Text("Add a library on the server to get started.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(sorted) { item in
                                NavigationLink(destination: destinationView(for: item)) {
                                    GridPosterCell(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Button {
                                sortOrder = order
                            } label: {
                                if sortOrder == order {
                                    Label(order.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(order.rawValue)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func destinationView(for item: MediaItem) -> some View {
        if kind == "movies" {
            MovieDetailView(itemId: item.id)
        } else {
            ShowDetailView(itemId: item.id)
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            items = kind == "movies"
                ? try await api.fetchMovies()
                : try await api.fetchShows()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct GridPosterCell: View {
    @EnvironmentObject var api: APIService
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: api.posterURL(for: item)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(2/3, contentMode: .fill)
                case .failure, .empty:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondarySystemBackground)
                        .aspectRatio(2/3, contentMode: .fit)
                        .overlay(
                            Image(systemName: item.kind == "show" ? "tv" : "film")
                                .font(.title)
                                .foregroundStyle(.tertiary)
                        )
                @unknown default:
                    EmptyView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

            Text(item.title)
                .font(.caption.weight(.medium))
                .lineLimit(2)

            if let year = item.year {
                Text(String(year))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
