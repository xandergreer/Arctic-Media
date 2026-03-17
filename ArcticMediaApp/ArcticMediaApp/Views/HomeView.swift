import SwiftUI

struct HomeView: View {
    @EnvironmentObject var api: APIService
    @State private var recentItems: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.top, 80)
                    } else if let err = error {
                        ContentUnavailableView(
                            "Connection Error",
                            systemImage: "wifi.slash",
                            description: Text(err)
                        )
                        .padding(.top, 60)
                    } else {
                        // Recently Added
                        if !recentItems.isEmpty {
                            SectionHeader(title: "Recently Added")
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(recentItems) { item in
                                        NavigationLink(destination: destinationView(for: item)) {
                                            PosterCard(item: item)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        // Quick links
                        SectionHeader(title: "Library")
                        HStack(spacing: 12) {
                            NavigationLink(destination: LibraryView(kind: "movies")) {
                                QuickLinkCard(title: "Movies", icon: "film.fill", color: .blue)
                            }
                            .buttonStyle(.plain)
                            NavigationLink(destination: LibraryView(kind: "shows")) {
                                QuickLinkCard(title: "TV Shows", icon: "tv.fill", color: .purple)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Arctic Media")
            .refreshable { await load() }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func destinationView(for item: MediaItem) -> some View {
        switch item.kind {
        case "movie":
            MovieDetailView(itemId: item.id)
        case "show":
            ShowDetailView(itemId: item.id)
        default:
            MovieDetailView(itemId: item.id)
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            recentItems = try await api.fetchRecentlyAdded()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .padding(.horizontal)
    }
}

struct QuickLinkCard: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(title)
                .font(.headline)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PosterCard: View {
    @EnvironmentObject var api: APIService
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: api.posterURL(for: item)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    posterPlaceholder
                case .empty:
                    posterPlaceholder.overlay(ProgressView())
                @unknown default:
                    posterPlaceholder
                }
            }
            .frame(width: 130, height: 195)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(item.title)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .frame(width: 130, alignment: .leading)

            if let year = item.year {
                Text(String(year))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.secondarySystemBackground)
            .frame(width: 130, height: 195)
            .overlay(
                Image(systemName: item.kind == "show" ? "tv" : "film")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            )
    }
}

extension Color {
    static var secondarySystemBackground: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemBackground)
        #else
        return Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
