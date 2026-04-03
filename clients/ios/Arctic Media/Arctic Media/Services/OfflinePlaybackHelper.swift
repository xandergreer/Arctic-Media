import AVFoundation
import Foundation

/// Serves locally-downloaded HLS content to AVPlayer via a custom URL scheme.
/// AVPlayer refuses to play file:// m3u8 playlists, so we intercept requests
/// with a resource loader and feed it data straight from disk.
final class OfflinePlaybackHelper: NSObject, AVAssetResourceLoaderDelegate {

    static let scheme = "arctic-local"

    private let mediaId: Int
    private let dir: URL   // folder containing playlist.m3u8 + seg_*.ts files

    init(mediaId: Int, localPlaylistURL: URL) {
        self.mediaId = mediaId
        self.dir = localPlaylistURL.deletingLastPathComponent()
    }

    /// Returns a ready-to-use AVPlayerItem. Hold a strong reference to this
    /// OfflinePlaybackHelper for as long as the item is in use.
    func makePlayerItem() -> AVPlayerItem {
        let fakeURL = URL(string: "\(Self.scheme)://localhost/\(mediaId)/playlist.m3u8")!
        let asset = AVURLAsset(url: fakeURL)
        asset.resourceLoader.setDelegate(self, queue: .global(qos: .userInitiated))
        // Retain self via the asset's external metadata so the asset keeps us alive
        // even if the caller drops its own reference temporarily.
        return AVPlayerItem(asset: asset)
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url,
              url.scheme == Self.scheme else { return false }
        handle(loadingRequest, url: url)
        return true
    }

    private func handle(_ req: AVAssetResourceLoadingRequest, url: URL) {
        let filename = url.lastPathComponent
        let localFile = dir.appendingPathComponent(filename)

        if filename == "playlist.m3u8" {
            guard let text = try? String(contentsOf: localFile, encoding: .utf8) else {
                req.finishLoading(with: URLError(.fileDoesNotExist)); return
            }
            // Rewrite relative segment paths to use our custom scheme so the
            // resource loader can intercept those requests too.
            let rewritten = text.components(separatedBy: "\n").map { line -> String in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard t.hasSuffix(".ts"), !t.hasPrefix("#") else { return line }
                return "\(Self.scheme)://localhost/\(mediaId)/\(t)"
            }.joined(separator: "\n")

            let data = Data(rewritten.utf8)
            if let info = req.contentInformationRequest {
                info.contentType = "com.apple.mpegurl"
                info.isByteRangeAccessSupported = false
                info.contentLength = Int64(data.count)
            }
            req.dataRequest?.respond(with: data)
            req.finishLoading()

        } else if filename.hasSuffix(".ts") {
            guard let data = try? Data(contentsOf: localFile) else {
                req.finishLoading(with: URLError(.fileDoesNotExist)); return
            }
            if let info = req.contentInformationRequest {
                info.contentType = "video/mp2t"
                info.isByteRangeAccessSupported = false
                info.contentLength = Int64(data.count)
            }
            req.dataRequest?.respond(with: data)
            req.finishLoading()

        } else {
            req.finishLoading(with: URLError(.fileDoesNotExist))
        }
    }

}
