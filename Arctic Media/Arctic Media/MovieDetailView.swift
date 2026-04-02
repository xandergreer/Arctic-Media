import SwiftUI

private struct StreamItem: Identifiable {
    let id: Int
    let url: URL
    let title: String
}

struct MovieDetailView: View {
    let item: MediaItem

    @EnvironmentObject private var api: APIService
    @State private var streamItem: StreamItem?
    @State private var progress: WatchProgress?
    @State private var showEdit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backdrop

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.title2.weight(.bold))
                            if let year = item.year {
                                Text(year).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if api.isAdmin {
                            Button { showEdit = true } label: {
                                Image(systemName: "pencil")
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                            }
                        }
                    }

                    Button {
                        if let url = api.streamURL(mediaId: item.id) {
                            streamItem = StreamItem(id: item.id, url: url, title: item.title)
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if let p = progress, let dur = p.duration_seconds, dur > 0,
                       p.position_seconds > 5, !p.completed {
                        let pct = CGFloat(p.position_seconds / dur)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.systemGray5)).frame(height: 4)
                                Capsule().fill(Color.blue)
                                    .frame(width: geo.size.width * pct, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }

                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { progress = try? await api.getProgress(mediaId: item.id) }
        .fullScreenCover(item: $streamItem) { s in
            VideoPlayerView(mediaId: s.id, streamURL: s.url, title: s.title)
                .environmentObject(api)
        }
        .sheet(isPresented: $showEdit) {
            EditMediaView(item: item)
                .environmentObject(api)
        }
    }

    private var backdrop: some View {
        Group {
            if let raw = item.backdrop_url ?? item.poster_url, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        backdropPlaceholder
                    }
                }
            } else {
                backdropPlaceholder
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220)
        .clipped()
    }

    private var backdropPlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .overlay(Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary))
    }
}
