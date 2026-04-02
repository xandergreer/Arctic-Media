import Combine
import Foundation
import UIKit

// MARK: - Persisted model

struct DownloadedItem: Codable, Identifiable {
    let id: Int             // mediaId
    let title: String
    let posterUrl: String?
    let kind: String        // movie | episode
    let episodeLabel: String?
    var bookmarkData: Data  // resolves local playlist.m3u8 URL
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

// MARK: - Resumable download (persisted so we can restore after kill/crash)

private struct ResumableDownload: Codable {
    let mediaId: Int
    let title: String
    let posterUrl: String?
    let kind: String
    let episodeLabel: String?
    let hlsURL: URL
}

// MARK: - Error

enum DownloadError: Error, LocalizedError {
    case invalidPlaylist(String)
    case segmentFailed(String, Int)
    var errorDescription: String? {
        switch self {
        case .invalidPlaylist(let msg): return "Playlist error: \(msg)"
        case .segmentFailed(let name, let code): return "Segment \(name) failed (HTTP \(code))"
        }
    }
}

// MARK: - Manager

final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published var downloads: [DownloadedItem] = []
    @Published var activeProgress: [Int: Double] = [:]   // mediaId → 0…1
    @Published var activeInfo: [Int: ActiveDownloadInfo] = [:]
    @Published var activeErrors: [Int: String] = [:]
    @Published var activeSpeed: [Int: Double] = [:]      // mediaId → bytes/sec
    @Published var pausedMediaIds: Set<Int> = []

    private var activeTasks: [Int: Task<Void, Never>] = [:]
    private var speedPoints: [Int: (time: Date, bytes: Int64)] = [:]

    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 86400
        return URLSession(configuration: config)
    }()

    private override init() {
        super.init()
        loadDownloads()
        restoreInterruptedDownloads()
        setupLifecycleObservers()
    }

    // MARK: - Lifecycle (background / foreground)

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.pauseAllDownloads() }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.resumePausedDownloads() }
    }

    private func pauseAllDownloads() {
        for mediaId in Array(activeTasks.keys) {
            pausedMediaIds.insert(mediaId)      // mark BEFORE cancelling so catch handler sees it
            activeTasks[mediaId]?.cancel()
            activeTasks.removeValue(forKey: mediaId)
            activeSpeed.removeValue(forKey: mediaId)
            speedPoints.removeValue(forKey: mediaId)
        }
    }

    private func resumePausedDownloads() {
        let toResume = loadResumableDownloads().filter { pausedMediaIds.contains($0.mediaId) }
        pausedMediaIds.removeAll()
        for rd in toResume {
            guard activeProgress[rd.mediaId] != nil else { continue }
            let task = Task { [weak self] in
                guard let self else { return }
                await self.performDownload(
                    mediaId: rd.mediaId, title: rd.title, posterUrl: rd.posterUrl,
                    kind: rd.kind, episodeLabel: rd.episodeLabel, hlsURL: rd.hlsURL)
            }
            activeTasks[rd.mediaId] = task
        }
    }

    // MARK: - Public API

    func isDownloaded(_ mediaId: Int) -> Bool {
        downloads.contains { $0.id == mediaId }
    }

    func isDownloading(_ mediaId: Int) -> Bool {
        activeProgress[mediaId] != nil
    }

    func isPaused(_ mediaId: Int) -> Bool {
        pausedMediaIds.contains(mediaId)
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

        saveResumableDownload(ResumableDownload(
            mediaId: mediaId, title: title, posterUrl: posterUrl,
            kind: kind, episodeLabel: episodeLabel, hlsURL: hlsURL))

        let info = ActiveDownloadInfo(mediaId: mediaId, title: title, posterUrl: posterUrl,
                                      kind: kind, episodeLabel: episodeLabel)
        activeProgress[mediaId] = 0.0
        activeInfo[mediaId] = info

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performDownload(
                mediaId: mediaId, title: title, posterUrl: posterUrl,
                kind: kind, episodeLabel: episodeLabel, hlsURL: hlsURL)
        }
        activeTasks[mediaId] = task
    }

    func cancelDownload(_ mediaId: Int) {
        pausedMediaIds.remove(mediaId)
        activeTasks[mediaId]?.cancel()
        activeTasks.removeValue(forKey: mediaId)
        activeProgress.removeValue(forKey: mediaId)
        activeInfo.removeValue(forKey: mediaId)
        activeErrors.removeValue(forKey: mediaId)
        activeSpeed.removeValue(forKey: mediaId)
        speedPoints.removeValue(forKey: mediaId)
        removeResumableDownload(mediaId)
        let dir = downloadsDirectory.appendingPathComponent("\(mediaId)")
        try? FileManager.default.removeItem(at: dir)
    }

    func deleteDownload(_ mediaId: Int) {
        if let url = localURL(for: mediaId) {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        downloads.removeAll { $0.id == mediaId }
        saveDownloads()
    }

    // MARK: - Download Implementation

    private var downloadsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("ArcticDownloads")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func performDownload(mediaId: Int, title: String, posterUrl: String?,
                                  kind: String, episodeLabel: String?, hlsURL: URL) async {
        do {
            // Step 1: Fetch master.m3u8
            let (masterData, masterResp) = try await urlSession.data(from: hlsURL)
            if let http = masterResp as? HTTPURLResponse, http.statusCode != 200 {
                throw DownloadError.invalidPlaylist("master.m3u8 returned HTTP \(http.statusCode)")
            }
            let masterText = String(data: masterData, encoding: .utf8) ?? ""

            let playlistURLStr = masterText
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { $0.hasPrefix("http") }
            guard let playlistURLStr, let playlistURL = URL(string: playlistURLStr) else {
                throw DownloadError.invalidPlaylist("No playlist URL in master.m3u8")
            }

            // Step 2: Fetch playlist.m3u8 (server starts transcoding and waits for first segment)
            let (playlistData, playlistResp) = try await urlSession.data(from: playlistURL)
            if let http = playlistResp as? HTTPURLResponse, http.statusCode != 200 {
                throw DownloadError.invalidPlaylist("playlist.m3u8 returned HTTP \(http.statusCode)")
            }
            let playlistText = String(data: playlistData, encoding: .utf8) ?? ""

            // Step 3: Parse segment URLs
            let playlistLines = playlistText.components(separatedBy: "\n")
            let segURLStrings = playlistLines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.hasPrefix("http") && $0.contains(".ts") }

            guard !segURLStrings.isEmpty else {
                throw DownloadError.invalidPlaylist("No .ts segments in playlist")
            }

            // Step 4: Create per-media download directory
            let dir = downloadsDirectory.appendingPathComponent("\(mediaId)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let total = segURLStrings.count
            var savedSegNames: [String] = []
            var totalBytes: Int64 = 0

            // Step 5: Download each segment — skip any already on disk (resume support)
            for (idx, urlStr) in segURLStrings.enumerated() {
                try Task.checkCancellation()
                guard let segURL = URL(string: urlStr) else { continue }

                let segName = segURL.lastPathComponent
                let localPath = dir.appendingPathComponent(segName)

                // Already downloaded? Skip the network request.
                if let attrs = try? FileManager.default.attributesOfItem(atPath: localPath.path),
                   (attrs[.size] as? Int64 ?? 0) > 0 {
                    totalBytes += attrs[.size] as? Int64 ?? 0
                    savedSegNames.append(segName)
                    let progress = Double(idx + 1) / Double(total) * 0.99
                    await MainActor.run { self.activeProgress[mediaId] = progress }
                    continue
                }

                let (data, response) = try await urlSession.data(from: segURL)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw DownloadError.segmentFailed(segName, http.statusCode)
                }
                try data.write(to: localPath)
                totalBytes += Int64(data.count)
                savedSegNames.append(segName)

                let progress = Double(idx + 1) / Double(total) * 0.99

                // Update speed ~once per second
                let now = Date()
                var speed: Double? = nil
                if let prev = speedPoints[mediaId] {
                    let elapsed = now.timeIntervalSince(prev.time)
                    if elapsed >= 1.0 {
                        speed = Double(totalBytes - prev.bytes) / elapsed
                        speedPoints[mediaId] = (now, totalBytes)
                    }
                } else {
                    speedPoints[mediaId] = (now, totalBytes)
                }

                await MainActor.run {
                    self.activeProgress[mediaId] = progress
                    if let speed { self.activeSpeed[mediaId] = speed }
                }
            }

            try Task.checkCancellation()

            // Step 6: Build local m3u8 with relative segment paths
            var localLines: [String] = []
            var savedIdx = 0
            for line in playlistLines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("http") && trimmed.contains(".ts") {
                    if savedIdx < savedSegNames.count {
                        localLines.append(savedSegNames[savedIdx])
                        savedIdx += 1
                    }
                } else {
                    localLines.append(trimmed)
                }
            }

            let playlistPath = dir.appendingPathComponent("playlist.m3u8")
            try localLines.joined(separator: "\n")
                .write(to: playlistPath, atomically: true, encoding: .utf8)

            // Step 7: Bookmark and persist
            let bookmark = try playlistPath.bookmarkData()
            let item = DownloadedItem(
                id: mediaId, title: title, posterUrl: posterUrl,
                kind: kind, episodeLabel: episodeLabel,
                bookmarkData: bookmark, downloadedAt: Date(),
                fileSizeBytes: totalBytes
            )

            await MainActor.run {
                self.downloads.append(item)
                self.saveDownloads()
                self.removeResumableDownload(mediaId)
                self.activeTasks.removeValue(forKey: mediaId)
                self.activeProgress.removeValue(forKey: mediaId)
                self.activeInfo.removeValue(forKey: mediaId)
                self.activeSpeed.removeValue(forKey: mediaId)
                self.speedPoints.removeValue(forKey: mediaId)
            }

        } catch is CancellationError {
            await MainActor.run {
                self.activeTasks.removeValue(forKey: mediaId)
                self.activeSpeed.removeValue(forKey: mediaId)
                self.speedPoints.removeValue(forKey: mediaId)
                // If paused, keep progress/info visible so the user sees the paused state.
                // If user-cancelled, clean everything up.
                if !self.pausedMediaIds.contains(mediaId) {
                    self.activeProgress.removeValue(forKey: mediaId)
                    self.activeInfo.removeValue(forKey: mediaId)
                }
            }
        } catch {
            await MainActor.run {
                self.activeErrors[mediaId] = error.localizedDescription
                self.removeResumableDownload(mediaId)
                self.activeTasks.removeValue(forKey: mediaId)
                self.activeProgress.removeValue(forKey: mediaId)
                self.activeInfo.removeValue(forKey: mediaId)
                self.activeSpeed.removeValue(forKey: mediaId)
                self.speedPoints.removeValue(forKey: mediaId)
            }
        }
    }

    // MARK: - Resumable download persistence

    private func saveResumableDownload(_ rd: ResumableDownload) {
        var all = loadResumableDownloads()
        all.removeAll { $0.mediaId == rd.mediaId }
        all.append(rd)
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: "offline.inprogress.v1")
    }

    private func removeResumableDownload(_ mediaId: Int) {
        var all = loadResumableDownloads()
        all.removeAll { $0.mediaId == mediaId }
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: "offline.inprogress.v1")
    }

    private func loadResumableDownloads() -> [ResumableDownload] {
        guard let data = UserDefaults.standard.data(forKey: "offline.inprogress.v1"),
              let items = try? JSONDecoder().decode([ResumableDownload].self, from: data)
        else { return [] }
        return items
    }

    /// Called on init — restores downloads that were interrupted by a force-kill or crash.
    private func restoreInterruptedDownloads() {
        for rd in loadResumableDownloads() {
            let dir = downloadsDirectory.appendingPathComponent("\(rd.mediaId)")
            let hasPartialSegments = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
                .contains { $0.hasSuffix(".ts") } ?? false
            guard hasPartialSegments else {
                removeResumableDownload(rd.mediaId)
                continue
            }
            activeProgress[rd.mediaId] = 0.01
            activeInfo[rd.mediaId] = ActiveDownloadInfo(
                mediaId: rd.mediaId, title: rd.title, posterUrl: rd.posterUrl,
                kind: rd.kind, episodeLabel: rd.episodeLabel)
            pausedMediaIds.insert(rd.mediaId)
        }
    }

    // MARK: - Storage helpers

    static func estimatedBytes(durationSeconds: Double) -> Int64 {
        Int64(durationSeconds * 2_500_000 / 8)
    }

    static func availableStorageBytes() -> Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return v?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_000_000)
        }
        return String(format: "%.0f KB/s", bytesPerSec / 1_000)
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
        downloads = items.filter { item in
            var isStale = false
            let url = try? URL(resolvingBookmarkData: item.bookmarkData,
                               options: .withoutUI, relativeTo: nil,
                               bookmarkDataIsStale: &isStale)
            return url != nil
        }
        if downloads.count != items.count { saveDownloads() }
    }
}
