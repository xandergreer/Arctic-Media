import SwiftUI

// Wraps the stream URL so fullScreenCover(item:) only fires when non-nil
private struct StreamItem: Identifiable {
    let id: Int
    let url: URL
    let title: String
}

struct MovieDetailView: View {
    let item: MediaItem

    @EnvironmentObject private var api: APIService
    @State private var streamItem: StreamItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backdrop

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.title2.weight(.bold))
                        if let year = item.year {
                            Text(year).foregroundStyle(.secondary)
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

                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $streamItem) { s in
            VideoPlayerView(mediaId: s.id, streamURL: s.url, title: s.title)
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
