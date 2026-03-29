import SwiftUI
import AVKit
import AVFoundation

// Carries everything VideoPlayerView needs
private struct PlayRequest: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let mediaId: Int
    let startAt: Double?
}

struct MediaDetailView: View {
    @EnvironmentObject var appState: AppState
    let item: MediaItem

    @State private var seasons: [MediaItem] = []
    @State private var selectedSeason: MediaItem?
    @State private var episodes: [MediaItem] = []
    @State private var loadingEpisodes = false
    @State private var playRequest: PlayRequest?
    @State private var progress: WatchProgress?

    var body: some View {
        ZStack {
            Color.arcticBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    backdrop
                    VStack(alignment: .leading, spacing: 20) {
                        // Title row
                        HStack(alignment: .bottom, spacing: 16) {
                            PosterImageView(url: item.posterUrl, serverURL: appState.serverURL)
                                .frame(width: 90, height: 135)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 12)
                                .offset(y: -20)

                            VStack(alignment: .leading, spacing: 6) {
                                if let year = item.year {
                                    Text(year)
                                        .font(.caption)
                                        .foregroundColor(.arcticMuted)
                                }
                                Text(item.title)
                                    .font(.title2.bold())
                                    .foregroundColor(.arcticText)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.kind == .movie ? "MOVIE" : "SERIES")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.arcticPrimary.opacity(0.2))
                                    .foregroundColor(.arcticPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            Spacer()
                        }
                        .padding(.horizontal)

                        if item.kind == .movie {
                            playButtons(mediaId: item.id, title: item.title)
                                .padding(.horizontal)
                        }

                        if let overview = item.overview, !overview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overview")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.arcticMuted)
                                    .textCase(.uppercase)
                                Text(overview)
                                    .font(.subheadline)
                                    .foregroundColor(.arcticSub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal)
                        }

                        if item.kind == .show && !seasons.isEmpty {
                            showContent
                        }

                        Spacer(minLength: 32)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(item: $playRequest) { req in
            VideoPlayerView(
                url: req.url,
                title: req.title,
                mediaId: req.mediaId,
                serverURL: appState.serverURL,
                token: appState.token ?? "",
                startAt: req.startAt
            )
        }
        .task {
            if item.kind == .show { await loadSeasons() }
            await loadProgress(mediaId: item.id)
        }
    }

    // MARK: - Subviews

    private var backdrop: some View {
        ZStack(alignment: .bottom) {
            if let backdropUrl = item.backdropUrl {
                PosterImageView(url: backdropUrl, serverURL: appState.serverURL)
                    .frame(maxWidth: .infinity).frame(height: 220).clipped()
                    .overlay(
                        LinearGradient(
                            colors: [.clear, Color.arcticBg.opacity(0.5), Color.arcticBg],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            } else {
                Rectangle()
                    .fill(Color.arcticSurface).frame(height: 220)
                    .overlay(
                        Image(systemName: item.kind == .movie ? "film" : "tv")
                            .font(.largeTitle).foregroundColor(.arcticMuted)
                    )
            }
        }
    }

    @ViewBuilder
    private func playButtons(mediaId: Int, title: String) -> some View {
        let hasResume = hasResumePoint(progress)

        if hasResume {
            VStack(spacing: 10) {
                // Resume button (primary)
                Button { play(mediaId: mediaId, title: title, startAt: progress?.positionSeconds) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Resume")
                                .font(.body.weight(.semibold))
                            if let pos = progress?.positionSeconds {
                                Text(formatTime(pos))
                                    .font(.caption2)
                                    .opacity(0.8)
                            }
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity).padding(14)
                    .background(Color.arcticPrimary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color.arcticPrimary.opacity(0.4), radius: 10, y: 4)
                }

                // Start from beginning (secondary)
                Button { play(mediaId: mediaId, title: title, startAt: 0) } label: {
                    Label("Start from Beginning", systemImage: "backward.end.fill")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity).padding(14)
                        .background(Color.arcticSurface)
                        .foregroundColor(.arcticText)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.arcticBorder, lineWidth: 1))
                }
            }
        } else {
            Button { play(mediaId: mediaId, title: title, startAt: nil) } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(14)
                    .background(Color.arcticPrimary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color.arcticPrimary.opacity(0.4), radius: 10, y: 4)
            }
        }
    }

    private func hasResumePoint(_ p: WatchProgress?) -> Bool {
        guard let p, !p.completed, p.positionSeconds > 30 else { return false }
        return true
    }

    private func formatTime(_ s: Double) -> String {
        let t = Int(s); let h = t / 3600; let m = (t % 3600) / 60; let sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    private var showContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(seasons) { season in
                        let label = season.seasonNumber.map { "Season \($0)" } ?? season.title
                        Button(label) {
                            selectedSeason = season
                            Task { await loadEpisodes(season: season) }
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(selectedSeason?.id == season.id ? Color.arcticPrimary : Color.arcticSurface)
                        .foregroundColor(selectedSeason?.id == season.id ? .white : .arcticSub)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)
            }

            if loadingEpisodes {
                ProgressView().tint(.arcticPrimary).padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(episodes) { ep in
                        EpisodeRowView(episode: ep, serverURL: appState.serverURL) {
                            play(mediaId: ep.id, title: ep.title)
                        }
                        Divider().background(Color.arcticBorder)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Playback

    private func play(mediaId: Int, title: String, startAt: Double? = nil) {
        guard let token = appState.token,
              let url = APIService.shared.hlsURL(serverURL: appState.serverURL, token: token, mediaId: mediaId) else {
            return
        }
        playRequest = PlayRequest(url: url, title: title, mediaId: mediaId, startAt: startAt)
    }

    private func loadProgress(mediaId: Int) async {
        guard let token = appState.token else { return }
        progress = try? await APIService.shared.watchProgress(
            serverURL: appState.serverURL, token: token, mediaId: mediaId)
    }

    // MARK: - Data

    private func loadSeasons() async {
        do {
            seasons = try await APIService.shared.seasons(
                serverURL: appState.serverURL, token: appState.token ?? "", showId: item.id
            )
            if let first = seasons.first {
                selectedSeason = first
                await loadEpisodes(season: first)
            }
        } catch {}
    }

    private func loadEpisodes(season: MediaItem) async {
        loadingEpisodes = true
        do {
            episodes = try await APIService.shared.episodes(
                serverURL: appState.serverURL, token: appState.token ?? "", seasonId: season.id
            )
        } catch {}
        loadingEpisodes = false
    }
}

struct EpisodeRowView: View {
    let episode: MediaItem
    let serverURL: String
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PosterImageView(url: episode.posterUrl, serverURL: serverURL)
                .frame(width: 100, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    Image(systemName: "play.circle.fill")
                        .font(.title2).foregroundColor(.white.opacity(0.8))
                )
                .onTapGesture { onPlay() }

            VStack(alignment: .leading, spacing: 4) {
                if let ep = episode.episodeNumber {
                    Text("E\(ep)").font(.caption2.weight(.bold)).foregroundColor(.arcticMuted)
                }
                Text(episode.title)
                    .font(.subheadline.weight(.semibold)).foregroundColor(.arcticText).lineLimit(1)
                if let overview = episode.overview {
                    Text(overview).font(.caption).foregroundColor(.arcticSub).lineLimit(2)
                }
            }
            Spacer()
            Button(action: onPlay) {
                Image(systemName: "play.fill").foregroundColor(.arcticPrimary)
            }
        }
        .padding(.vertical, 10)
    }
}
