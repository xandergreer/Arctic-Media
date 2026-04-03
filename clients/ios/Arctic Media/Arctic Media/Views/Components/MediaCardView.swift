import SwiftUI

struct MediaCardView: View {
    let item: MediaItem
    var serverURL: String = ""

    @ObservedObject private var dm = DownloadManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Poster with optional download overlay
            ZStack {
                PosterImageView(url: item.posterUrl, serverURL: serverURL)
                    .aspectRatio(2/3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if let progress = dm.activeProgress[item.id] {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.5))
                        .aspectRatio(2/3, contentMode: .fit)

                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.25), lineWidth: 3)
                                .frame(width: 44, height: 44)
                            Circle()
                                .trim(from: 0, to: CGFloat(progress))
                                .stroke(dm.isPaused(item.id) ? Color.white.opacity(0.5) : Color.arcticPrimary,
                                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 44, height: 44)
                                .animation(.linear(duration: 0.4), value: progress)
                            if dm.isPaused(item.id) {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        Text(dm.activeSpeed[item.id].map { DownloadManager.formatSpeed($0) } ?? "")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                    }
                } else if dm.isDownloaded(item.id) {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, Color.arcticPrimary)
                                .padding(6)
                        }
                    }
                    .aspectRatio(2/3, contentMode: .fit)
                }
            }

            // Title
            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.arcticText)
                .lineLimit(2)

            if let year = item.year {
                Text(year)
                    .font(.caption2)
                    .foregroundColor(.arcticMuted)
            }
        }
    }
}

struct PosterImageView: View {
    let url: String?
    var serverURL: String = ""

    private var resolvedURL: URL? {
        guard let url else { return nil }
        if url.hasPrefix("http") { return URL(string: url) }
        return URL(string: serverURL + url)
    }

    var body: some View {
        if let resolved = resolvedURL {
            AsyncImage(url: resolved) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    Rectangle()
                        .fill(Color.arcticSurface)
                        .overlay(ProgressView().tint(.arcticMuted))
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.arcticSurface)
            .overlay(
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundColor(.arcticMuted)
            )
    }
}
