import AVFoundation
import Combine
import Foundation

// MARK: - Persisted model

struct DownloadedItem: Codable, Identifiable {
    let id: Int             // mediaId
    let title: String
    let posterUrl: String?
    let kind: String        // movie | episode
    let episodeLabel: String?
    var bookmarkData: Data  // resolves local asset URL across launches
    let downloadedAt: Date
    var fileSizeBytes: Int64

    var formattedSize: String { DownloadManager.formatBytes(fileSizeBytes) }
}

// MARK: - In-memory active task info

struct ActiveDownloadInfo {
    let mediaId: Int
    let title: String
    let posterUrl: String?
    let kind: String
    let episodeLabel: String?
}

// MARK: - Manager

final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published var downloads: [DownloadedItem] = []
    @Published var activeProgress: [Int: Double] = [:]   // mediaId → 0…1
    @Published var activeInfo: [Int: ActiveDownloadInfo] = [:]
    @Published var activeErrors: [Int: String] = [:]

    private var session: AVAssetDownloadURLSession!
    private var taskToInfo: [AVAssetDownloadTask: ActiveDownloadInfo] = [:]

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(
            withIdentifier: "com.arctic.offline.v1")
        config.isDiscretionary = false
        session = AVAssetDownloadURLSession(
            configuration: config,
            assetDownloadDelegate: self,
            delegateQueue: OperationQueue.main   // callbacks on main thread
        )
        loadDownloads()
    }

    // MARK: - Public API

    func isDownloaded(_ mediaId: Int) -> Bool {
        downloads.contains { $0.id == mediaId }
    }

    func isDownloading(_ mediaId: Int) -> Bool {
        activeProgress[mediaId] != nil
    }

    func localURL(for mediaId: Int) -> URL? {
        guard let item = downloads.first(where: { $0.id == mediaId }) else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: item.bookmarkData,
                        options: .withoutUI, relativeTo: nil,
                        bookmarkDataIsStale: &isStale)
    }

    func startDownload(mediaId: Int, title: String, posterUrl: String?,
                       kind: String, episodeLabel: String?, hlsURL: URL) {
        guard !isDownloaded(mediaId), !isDownloading(mediaId) else { return }

        let asset = AVURLAsset(url: hlsURL)
        guard let task = session.makeAssetDownloadTask(
            asset: asset,
            assetTitle: title,
            assetArtworkData: nil,
            options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 2_000_000]
        ) else { return }

        let info = ActiveDownloadInfo(mediaId: mediaId, title: title, posterUrl: posterUrl,
                                      kind: kind, episodeLabel: episodeLabel)
        taskToInfo[task] = info
        activeProgress[mediaId] = 0.0
        activeInfo[mediaId] = info
        task.resume()
    }

    func cancelDownload(_ mediaId: Int) {
        if let entry = taskToInfo.first(where: { $0.value.mediaId == mediaId }) {
            entry.key.cancel()
            taskToInfo.removeValue(forKey: entry.key)
        }
        activeProgress.removeValue(forKey: mediaId)
        activeInfo.removeValue(forKey: mediaId)
        activeErrors.removeValue(forKey: mediaId)
    }

    func deleteDownload(_ mediaId: Int) {
        if let url = localURL(for: mediaId) {
            try? FileManager.default.removeItem(at: url)
        }
        downloads.removeAll { $0.id == mediaId }
        saveDownloads()
    }

    // MARK: - Storage helpers

    static func estimatedBytes(durationSeconds: Double) -> Int64 {
        Int64(durationSeconds * 2_500_000 / 8)  // ~2.5 Mbps average
    }

    static func availableStorageBytes() -> Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let v = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 0.1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1  { return String(format: "%.0f MB", mb) }
        return "\(bytes) B"
    }

    var totalDownloadedBytes: Int64 { downloads.reduce(0) { $0 + $1.fileSizeBytes } }

    // MARK: - Persistence

    private func saveDownloads() {
        if let data = try? JSONEncoder().encode(downloads) {
            UserDefaults.standard.set(data, forKey: "offline.downloads.v1")
        }
    }

    private func loadDownloads() {
        guard let data = UserDefaults.standard.data(forKey: "offline.downloads.v1"),
              let items = try? JSONDecoder().decode([DownloadedItem].self, from: data)
        else { return }
        // Filter out items whose local files no longer exist
        downloads = items.filter { item in
            var isStale = false
            let url = try? URL(resolvingBookmarkData: item.bookmarkData,
                               options: .withoutUI, relativeTo: nil,
                               bookmarkDataIsStale: &isStale)
            return url != nil
        }
        if downloads.count != items.count { saveDownloads() }
    }

    private func directorySizeBytes(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return 0 }
        return enumerator
            .compactMap { $0 as? URL }
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(0) { $0 + Int64($1) }
    }
}

// MARK: - AVAssetDownloadDelegate

extension DownloadManager: AVAssetDownloadDelegate {

    func urlSession(_ session: URLSession,
                    assetDownloadTask: AVAssetDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let info = taskToInfo[assetDownloadTask] else { return }
        do {
            let bookmark = try location.bookmarkData()
            let size = directorySizeBytes(at: location)
            let item = DownloadedItem(
                id: info.mediaId, title: info.title, posterUrl: info.posterUrl,
                kind: info.kind, episodeLabel: info.episodeLabel,
                bookmarkData: bookmark, downloadedAt: Date(),
                fileSizeBytes: size
            )
            downloads.append(item)
            saveDownloads()
        } catch {
            activeErrors[info.mediaId] = "Save failed: \(error.localizedDescription)"
        }
        taskToInfo.removeValue(forKey: assetDownloadTask)
        activeProgress.removeValue(forKey: info.mediaId)
        activeInfo.removeValue(forKey: info.mediaId)
    }

    func urlSession(_ session: URLSession,
                    assetDownloadTask: AVAssetDownloadTask,
                    didLoad timeRange: CMTimeRange,
                    totalTimeRangesLoaded: [NSValue],
                    timeRangeExpectedToLoad: CMTimeRange) {
        guard let info = taskToInfo[assetDownloadTask] else { return }
        let loaded = totalTimeRangesLoaded.reduce(0.0) { $0 + $1.timeRangeValue.duration.seconds }
        let expected = timeRangeExpectedToLoad.duration.seconds
        guard expected > 0 else { return }
        activeProgress[info.mediaId] = min(loaded / expected, 0.99)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error,
              let assetTask = task as? AVAssetDownloadTask,
              let info = taskToInfo[assetTask]
        else { return }
        let nsErr = error as NSError
        if nsErr.code != NSURLErrorCancelled {
            activeErrors[info.mediaId] = error.localizedDescription
        }
        taskToInfo.removeValue(forKey: assetTask)
        activeProgress.removeValue(forKey: info.mediaId)
        activeInfo.removeValue(forKey: info.mediaId)
    }
}
