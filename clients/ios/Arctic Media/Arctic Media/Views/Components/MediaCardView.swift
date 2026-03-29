import SwiftUI

struct MediaCardView: View {
    let item: MediaItem
    var serverURL: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Poster
            PosterImageView(url: item.posterUrl, serverURL: serverURL)
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

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
