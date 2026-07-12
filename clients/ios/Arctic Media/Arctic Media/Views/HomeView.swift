import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var recent: RecentlyAdded?
    @State private var continueWatching: [ContinueWatchingItem] = []
    @State private var error: String?
    @State private var loading = true

    let cardWidth: CGFloat = 130

    var body: some View {
        ZStack {
                Color.arcticBg.ignoresSafeArea()

                if loading {
                    ProgressView().tint(.arcticPrimary)
                } else if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.arcticMuted)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.arcticSub)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .foregroundColor(.arcticPrimary)
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            // Hero greeting
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Recently Added")
                                    .font(.largeTitle.bold())
                                    .foregroundColor(.arcticText)
                                Text("Jump back in or discover something new.")
                                    .font(.subheadline)
                                    .foregroundColor(.arcticSub)
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)

                            if !continueWatching.isEmpty {
                                continueWatchingShelf
                            }

                            if let movies = recent?.movies, !movies.isEmpty {
                                shelf(title: "Movies", items: movies)
                            }

                            if let shows = recent?.shows, !shows.isEmpty {
                                shelf(title: "TV Shows", items: shows)
                            }

                            if (recent?.movies.isEmpty ?? true) && (recent?.shows.isEmpty ?? true) {
                                VStack(spacing: 12) {
                                    Image(systemName: "tray")
                                        .font(.largeTitle)
                                        .foregroundColor(.arcticMuted)
                                    Text("No content yet.\nAdd a library in Settings.")
                                        .font(.body)
                                        .foregroundColor(.arcticSub)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.arcticBg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ARCTIC MEDIA")
                    .font(.system(size: 15, weight: .black))
                    .tracking(2)
                    .foregroundColor(.arcticText)
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func shelf(title: String, items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .foregroundColor(.arcticText)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(destination: MediaDetailView(item: item)) {
                            MediaCardView(item: item, serverURL: appState.serverURL)
                                .frame(width: cardWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var continueWatchingShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Watching")
                .font(.title3.bold())
                .foregroundColor(.arcticText)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(continueWatching) { item in
                        ContinueWatchingCard(item: item)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func load() async {
        loading = true
        error = nil
        async let recentTask = APIService.shared.recentlyAdded(
            serverURL: appState.serverURL, token: appState.token ?? "")
        async let cwTask = APIService.shared.continueWatching(
            serverURL: appState.serverURL, token: appState.token ?? "")
        do {
            recent = try await recentTask
        } catch {
            self.error = error.localizedDescription
        }
        continueWatching = (try? await cwTask) ?? []
        loading = false
    }
}

// MARK: - Continue Watching Card

private struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem
    @EnvironmentObject var appState: AppState
    @State private var navTarget: MediaItem?        // movies → push MediaDetailView
    @State private var episodeItem: MediaItem?      // episodes → episode detail sheet
    @State private var playRequest: _CWPlayRequest?
    @State private var fetching = false
    @State private var autoPlayAfter: MediaItem?    // episode that just finished; queue its successor

    var body: some View {
        Button {
            guard !fetching else { return }
            fetching = true
            Task {
                if item.kind == "episode" {
                    episodeItem = try? await APIService.shared.mediaItem(
                        serverURL: appState.serverURL, token: appState.token ?? "", id: item.mediaId)
                } else {
                    navTarget = try? await APIService.shared.mediaItem(
                        serverURL: appState.serverURL, token: appState.token ?? "", id: item.navigationId)
                }
                fetching = false
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottom) {
                    PosterImageView(url: item.posterUrl, serverURL: appState.serverURL)
                        .frame(width: 120, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.black.opacity(0.5)).frame(height: 3)
                            Rectangle()
                                .fill(Color.arcticPrimary)
                                .frame(width: geo.size.width * CGFloat(item.progressPct) / 100,
                                       height: 3)
                        }
                    }
                    .frame(height: 3)
                }

                Text(item.title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.arcticText)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)

                if let sub = item.subtitle {
                    Text(sub)
                        .font(.caption2)
                        .foregroundColor(.arcticMuted)
                        .frame(width: 120, alignment: .leading)
                }
            }
            .overlay(fetching ? ProgressView().tint(.white) : nil)
        }
        .buttonStyle(.plain)
        .navigationDestination(item: $navTarget) { MediaDetailView(item: $0) }
        .sheet(item: $episodeItem) { ep in
            EpisodeDetailSheet(
                episode: ep,
                serverURL: appState.serverURL,
                progress: WatchProgress(
                    positionSeconds: item.positionSeconds,
                    durationSeconds: item.durationSeconds,
                    completed: false),
                onPlay: { startAt in
                    guard let token = appState.token,
                          let url = APIService.shared.hlsURL(
                            serverURL: appState.serverURL, token: token, mediaId: ep.id)
                    else { return }
                    let resolvedStart = startAt ?? (item.positionSeconds > 30 ? item.positionSeconds : nil)
                    playRequest = _CWPlayRequest(
                        id: ep.id, url: url, title: ep.title,
                        startAt: resolvedStart,
                        onFinished: makeFinishedHandler(for: ep))
                }
            )
        }
        .fullScreenCover(item: $playRequest, onDismiss: {
            guard let finished = autoPlayAfter else { return }
            autoPlayAfter = nil
            Task {
                guard let token = appState.token,
                      let seasonId = finished.parentId,
                      let eps = try? await APIService.shared.episodes(
                          serverURL: appState.serverURL, token: token, seasonId: seasonId),
                      let idx = eps.firstIndex(where: { $0.id == finished.id }),
                      idx + 1 < eps.count else { return }
                let next = eps[idx + 1]
                guard let url = APIService.shared.hlsURL(
                          serverURL: appState.serverURL, token: token, mediaId: next.id) else { return }
                try? await Task.sleep(nanoseconds: 350_000_000)
                await MainActor.run {
                    playRequest = _CWPlayRequest(
                        id: next.id, url: url, title: next.title, startAt: nil,
                        onFinished: makeFinishedHandler(for: next))
                }
            }
        }) { req in
            VideoPlayerView(
                url: req.url, title: req.title, mediaId: req.id,
                serverURL: appState.serverURL, token: appState.token ?? "",
                startAt: req.startAt,
                onFinished: req.onFinished)
        }
    }

    private func makeFinishedHandler(for ep: MediaItem) -> (() -> Void)? {
        guard appState.autoPlayEnabled, ep.parentId != nil else { return nil }
        // Just mark which episode finished; the next-episode lookup happens
        // in onDismiss so the fetch can't race the cover dismissal.
        return { autoPlayAfter = ep }
    }
}

private struct _CWPlayRequest: Identifiable {
    let id: Int
    let url: URL
    let title: String
    let startAt: Double?
    var onFinished: (() -> Void)? = nil
}
