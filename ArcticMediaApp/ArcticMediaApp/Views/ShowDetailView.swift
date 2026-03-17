import SwiftUI

struct ShowDetailView: View {
    @EnvironmentObject var api: APIService
    let itemId: Int

    @State private var show: MediaItem?
    @State private var seasons: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            } else if let err = error {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if let show = show {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero
                    AsyncImage(url: api.backdropURL(for: show) ?? api.posterURL(for: show)) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Rectangle().fill(Color.secondarySystemBackground)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)
                    .clipped()
                    .overlay(
                        LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    )

                    VStack(alignment: .leading, spacing: 20) {
                        // Title
                        VStack(alignment: .leading, spacing: 6) {
                            Text(show.title)
                                .font(.title.bold())
                            if let year = show.year {
                                Text(String(year))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Overview
                        if let overview = show.overview, !overview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overview").font(.headline)
                                Text(overview)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Seasons
                        if !seasons.isEmpty {
                            Text("Seasons").font(.headline)
                            ForEach(seasons.sorted { ($0.season_number ?? 0) < ($1.season_number ?? 0) }) { season in
                                NavigationLink(destination: SeasonView(season: season)) {
                                    SeasonRow(season: season)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            async let showTask = api.fetchMediaItem(itemId)
            async let seasonsTask = api.fetchSeasons(showId: itemId)
            let (s, seas) = try await (showTask, seasonsTask)
            show = s
            seasons = seas
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct SeasonRow: View {
    @EnvironmentObject var api: APIService
    let season: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: api.posterURL(for: season)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle().fill(Color.secondarySystemBackground)
                        .overlay(Image(systemName: "tv").foregroundStyle(.tertiary))
                }
            }
            .frame(width: 60, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(season.title)
                    .font(.headline)
                if let num = season.season_number {
                    Text("Season \(num)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct SeasonView: View {
    @EnvironmentObject var api: APIService
    let season: MediaItem

    @State private var episodes: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var playingEpisode: MediaItem?

    var body: some View {
        List {
            ForEach(episodes.sorted { ($0.episode_number ?? 0) < ($1.episode_number ?? 0) }) { ep in
                Button { playingEpisode = ep } label: {
                    EpisodeRow(episode: ep)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(season.title)
        .overlay {
            if isLoading { ProgressView() }
            else if let err = error {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if episodes.isEmpty {
                ContentUnavailableView("No Episodes", systemImage: "tv.slash")
            }
        }
        .fullScreenCover(item: $playingEpisode) { ep in
            VideoPlayerView(
                mediaId: ep.id,
                fileId: nil,
                audioIndex: nil,
                subtitleIndex: nil,
                title: ep.title
            )
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            episodes = try await api.fetchEpisodes(seasonId: season.id)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct EpisodeRow: View {
    @EnvironmentObject var api: APIService
    let episode: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: api.posterURL(for: episode)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle().fill(Color.secondarySystemBackground)
                        .overlay(Image(systemName: "play.rectangle").foregroundStyle(.tertiary))
                }
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                if let num = episode.episode_number {
                    Text("Episode \(num)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(episode.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                if let overview = episode.overview {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
            Image(systemName: "play.fill")
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
    }
}
