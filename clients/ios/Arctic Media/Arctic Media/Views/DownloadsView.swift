import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var dm = DownloadManager.shared
    @State private var playRequest: _OfflinePlay?
    @State private var errorItem: DownloadedItem?

    var body: some View {
        ZStack {
            Color.arcticBg.ignoresSafeArea()

            if dm.downloads.isEmpty && dm.activeProgress.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.arcticBg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(item: $playRequest) { req in
            VideoPlayerView(
                url: req.url,
                title: req.title,
                mediaId: req.mediaId,
                serverURL: appState.serverURL,
                token: appState.token ?? ""
            )
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            // Storage summary
            Section {
                HStack {
                    Image(systemName: "internaldrive.fill").foregroundColor(.arcticPrimary)
                    Text("Downloaded Storage")
                    Spacer()
                    Text(DownloadManager.formatBytes(dm.totalDownloadedBytes))
                        .foregroundColor(.arcticMuted)
                }
                HStack {
                    Image(systemName: "iphone").foregroundColor(.arcticMuted)
                    Text("Available Storage")
                    Spacer()
                    Text(DownloadManager.formatBytes(DownloadManager.availableStorageBytes()))
                        .foregroundColor(.arcticMuted)
                }
            }
            .listRowBackground(Color.arcticSurface)
            .foregroundColor(.arcticText)

            // Active downloads
            if !dm.activeProgress.isEmpty {
                Section("Downloading") {
                    ForEach(Array(dm.activeProgress.keys.sorted()), id: \.self) { mediaId in
                        activeRow(mediaId: mediaId)
                    }
                }
                .listRowBackground(Color.arcticSurface)
            }

            // Download errors (transient banner rows)
            if !dm.activeErrors.isEmpty {
                Section("Failed") {
                    ForEach(Array(dm.activeErrors.keys.sorted()), id: \.self) { mediaId in
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                            Text(dm.activeErrors[mediaId] ?? "Unknown error")
                                .font(.caption).foregroundColor(.arcticSub)
                            Spacer()
                            Button {
                                dm.activeErrors.removeValue(forKey: mediaId)
                            } label: {
                                Image(systemName: "xmark").foregroundColor(.arcticMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowBackground(Color.arcticSurface)
            }

            // Completed downloads
            if !dm.downloads.isEmpty {
                Section("Ready to Watch") {
                    ForEach(dm.downloads) { item in
                        downloadedRow(item: item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    dm.deleteDownload(item.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listRowBackground(Color.arcticSurface)
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Row: active download

    @ViewBuilder
    private func activeRow(mediaId: Int) -> some View {
        let progress = dm.activeProgress[mediaId] ?? 0
        let info = dm.activeInfo[mediaId]
        HStack(spacing: 14) {
            // Poster with progress ring overlay
            ZStack {
                PosterImageView(url: info?.posterUrl, serverURL: appState.serverURL)
                    .frame(width: 50, height: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .opacity(0.5)

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 3)
                        .frame(width: 38, height: 38)
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(Color.arcticPrimary,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 38, height: 38)
                        .animation(.linear(duration: 0.4), value: progress)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(info?.title ?? "Downloading…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.arcticText)
                    .lineLimit(1)

                if let label = info?.episodeLabel {
                    Text(label).font(.caption).foregroundColor(.arcticMuted)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.arcticBorder)
                            .frame(height: 4)
                        Capsule()
                            .fill(Color.arcticPrimary)
                            .frame(width: geo.size.width * CGFloat(progress), height: 4)
                            .animation(.linear(duration: 0.4), value: progress)
                    }
                }
                .frame(height: 4)

                Text(info?.kind == "movie" ? "Movie" : "Episode")
                    .font(.caption2)
                    .foregroundColor(.arcticMuted)
            }

            Spacer()

            Button {
                dm.cancelDownload(mediaId)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.arcticMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Row: completed download

    @ViewBuilder
    private func downloadedRow(item: DownloadedItem) -> some View {
        Button {
            guard let url = dm.localURL(for: item.id) else { return }
            playRequest = _OfflinePlay(url: url, title: item.title, mediaId: item.id)
        } label: {
            HStack(spacing: 12) {
                PosterImageView(url: item.posterUrl, serverURL: appState.serverURL)
                    .frame(width: 50, height: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.arcticText)
                        .lineLimit(2)

                    if let label = item.episodeLabel {
                        Text(label).font(.caption).foregroundColor(.arcticMuted)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: item.kind == "movie" ? "film" : "tv")
                            .font(.caption2).foregroundColor(.arcticMuted)
                        Text(item.kind == "movie" ? "Movie" : "Episode")
                            .font(.caption2).foregroundColor(.arcticMuted)
                        Text("·").font(.caption2).foregroundColor(.arcticMuted)
                        Text(item.formattedSize)
                            .font(.caption2).foregroundColor(.arcticMuted)
                        Text("·").font(.caption2).foregroundColor(.arcticMuted)
                        Text(item.downloadedAt, style: .date)
                            .font(.caption2).foregroundColor(.arcticMuted)
                    }
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.arcticPrimary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 56))
                .foregroundColor(.arcticMuted)
            Text("No Downloads")
                .font(.title3.weight(.semibold))
                .foregroundColor(.arcticText)
            Text("Download movies and episodes\nto watch without internet.")
                .font(.subheadline)
                .foregroundColor(.arcticSub)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

private struct _OfflinePlay: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let mediaId: Int
}
