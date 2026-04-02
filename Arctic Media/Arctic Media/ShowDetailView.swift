import SwiftUI

private struct EpisodeStreamItem: Identifiable {
    let id: Int
    let url: URL
    let title: String
}

struct ShowDetailView: View {
    let item: MediaItem

    @EnvironmentObject private var api: APIService
    @State private var seasons: [MediaItem] = []
    @State private var isLoading = true
    @State private var showEdit = false

    var body: some View {
        List {
            // Header section
            Section {
                HStack(alignment: .top, spacing: 14) {
                    PosterView(url: item.poster_url)
                        .frame(width: 80, height: 120)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title).font(.headline)
                        if let year = item.year {
                            Text(year).font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let overview = item.overview {
                            Text(overview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                        }
                    }
                }
                .padding(.vertical, 8)

                if api.isAdmin {
                    Button { showEdit = true } label: {
                        Label("Edit Metadata", systemImage: "pencil")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Seasons
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else {
                ForEach(seasons) { season in
                    Section(header: Text(season.title)) {
                        SeasonRowsView(season: season)
                            .environmentObject(api)
                    }
                }
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSeasons() }
        .sheet(isPresented: $showEdit) {
            EditMediaView(item: item)
                .environmentObject(api)
        }
    }

    private func loadSeasons() async {
        isLoading = true
        seasons = (try? await api.getSeasons(showId: item.id)) ?? []
        isLoading = false
    }
}

// MARK: - Episodes for a season (lazy loaded)

struct SeasonRowsView: View {
    let season: MediaItem

    @EnvironmentObject private var api: APIService
    @State private var episodes: [MediaItem] = []
    @State private var progressMap: [Int: WatchProgress] = [:]
    @State private var isLoading = true
    @State private var streamItem: EpisodeStreamItem?

    var body: some View {
        Group {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                ForEach(episodes) { episode in
                    Button {
                        if let url = api.streamURL(mediaId: episode.id) {
                            streamItem = EpisodeStreamItem(
                                id: episode.id,
                                url: url,
                                title: episodeTitle(for: episode)
                            )
                        }
                    } label: {
                        EpisodeRow(episode: episode, progress: progressMap[episode.id])
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await load() }
        .fullScreenCover(item: $streamItem) { s in
            VideoPlayerView(mediaId: s.id, streamURL: s.url, title: s.title)
                .environmentObject(api)
        }
    }

    private func load() async {
        isLoading = true
        episodes = (try? await api.getEpisodes(seasonId: season.id)) ?? []
        isLoading = false
        await loadProgress()
    }

    private func loadProgress() async {
        await withTaskGroup(of: (Int, WatchProgress?).self) { group in
            for ep in episodes {
                group.addTask {
                    let p = try? await api.getProgress(mediaId: ep.id)
                    return (ep.id, p)
                }
            }
            for await (id, p) in group {
                if let p { progressMap[id] = p }
            }
        }
    }

    private func episodeTitle(for ep: MediaItem) -> String {
        if let e = ep.episode_number {
            return "E\(e) – \(ep.title)"
        }
        return ep.title
    }
}

// MARK: - Episode row

struct EpisodeRow: View {
    let episode: MediaItem
    var progress: WatchProgress?

    var body: some View {
        HStack(spacing: 12) {
            if let epNum = episode.episode_number {
                Text("\(epNum)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.body)
                    .lineLimit(1)
                if let overview = episode.overview {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let p = progress, let dur = p.duration_seconds, dur > 0,
                   p.position_seconds > 5, !p.completed {
                    let pct = CGFloat(p.position_seconds / dur)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemGray5)).frame(height: 3)
                            Capsule().fill(Color.blue)
                                .frame(width: geo.size.width * pct, height: 3)
                        }
                    }
                    .frame(height: 3)
                }
            }

            Spacer()

            if progress?.completed == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "play.circle")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}
