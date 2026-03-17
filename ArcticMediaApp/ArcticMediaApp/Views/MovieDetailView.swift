import SwiftUI

struct MovieDetailView: View {
    @EnvironmentObject var api: APIService
    let itemId: Int

    @State private var item: MediaItem?
    @State private var files: [MediaFile] = []
    @State private var streamInfo: StreamInfo?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingPlayer = false
    @State private var selectedFileId: Int?
    @State private var selectedAudio: Int?
    @State private var selectedSub: Int = -1  // -1 = none

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            } else if let err = error {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if let item = item {
                VStack(alignment: .leading, spacing: 0) {
                    // Backdrop / Hero
                    heroSection(item: item)

                    VStack(alignment: .leading, spacing: 20) {
                        // Title & metadata
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.title.bold())
                            HStack(spacing: 8) {
                                if let year = item.year {
                                    Text(String(year))
                                        .foregroundStyle(.secondary)
                                }
                                if let dur = files.first?.duration_seconds {
                                    Text("·")
                                        .foregroundStyle(.secondary)
                                    Text(formatDuration(dur))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.subheadline)
                        }

                        // Play button
                        Button(action: { showingPlayer = true }) {
                            Label("Play", systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Overview
                        if let overview = item.overview, !overview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Overview")
                                    .font(.headline)
                                Text(overview)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Audio tracks
                        if let info = streamInfo, !info.audio_tracks.isEmpty {
                            TrackPicker(
                                title: "Audio",
                                tracks: info.audio_tracks.map { TrackOption(index: $0.index, label: trackLabel($0.language, $0.title, $0.codec)) },
                                selected: Binding(get: { selectedAudio ?? 0 }, set: { selectedAudio = $0 })
                            )
                        }

                        // Subtitle tracks
                        if let info = streamInfo, !info.subtitle_tracks.isEmpty {
                            let options = [TrackOption(index: -1, label: "None")] +
                                info.subtitle_tracks.map { TrackOption(index: $0.index, label: trackLabel($0.language, $0.title, $0.codec)) }
                            TrackPicker(
                                title: "Subtitles",
                                tracks: options,
                                selected: $selectedSub
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingPlayer) {
            if let item = item {
                VideoPlayerView(
                    mediaId: item.id,
                    fileId: selectedFileId,
                    audioIndex: selectedAudio,
                    subtitleIndex: selectedSub >= 0 ? selectedSub : nil,
                    title: item.title
                )
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func heroSection(item: MediaItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: api.backdropURL(for: item) ?? api.posterURL(for: item)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle().fill(Color.secondarySystemBackground)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .clipped()

            // Gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 280)
        }
        .frame(height: 280)
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            async let itemTask = api.fetchMediaItem(itemId)
            async let filesTask = api.fetchMediaFiles(itemId)
            let (fetchedItem, fetchedFiles) = try await (itemTask, filesTask)
            item = fetchedItem
            files = fetchedFiles
            selectedFileId = fetchedFiles.first?.id

            if let fid = selectedFileId {
                streamInfo = try? await api.fetchStreamInfo(itemId, fileId: fid)
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func trackLabel(_ lang: String?, _ title: String?, _ codec: String?) -> String {
        var parts: [String] = []
        if let t = title, !t.isEmpty { parts.append(t) }
        if let l = lang, l != "und" { parts.append(l.uppercased()) }
        if let c = codec { parts.append("(\(c))") }
        return parts.isEmpty ? "Track" : parts.joined(separator: " ")
    }
}

struct TrackOption: Identifiable {
    let index: Int
    let label: String
    var id: Int { index }
}

struct TrackPicker: View {
    let title: String
    let tracks: [TrackOption]
    @Binding var selected: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tracks) { track in
                        Button {
                            selected = track.index
                        } label: {
                            Text(track.label)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selected == track.index ? Color.blue : Color.secondarySystemBackground)
                                .foregroundStyle(selected == track.index ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
