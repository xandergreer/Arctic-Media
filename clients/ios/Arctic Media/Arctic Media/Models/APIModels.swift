import Foundation

// MARK: - Auth

struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType   = "token_type"
    }
}

struct UserInfo: Codable {
    let id: Int
    let username: String
    let isSuperuser: Bool
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case isSuperuser = "is_superuser"
    }
}

// MARK: - Media

enum MediaKind: String, Codable {
    case movie, show, season, episode
}

struct MediaItem: Codable, Identifiable {
    let id: Int
    let kind: MediaKind
    let title: String
    let sortTitle: String?
    let overview: String?
    let releaseDate: String?
    let posterUrl: String?
    let backdropUrl: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let libraryId: Int?
    let parentId: Int?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, overview
        case sortTitle    = "sort_title"
        case releaseDate  = "release_date"
        case posterUrl    = "poster_url"
        case backdropUrl  = "backdrop_url"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case libraryId    = "library_id"
        case parentId     = "parent_id"
    }

    var year: String? {
        guard let d = releaseDate, d.count >= 4 else { return nil }
        return String(d.prefix(4))
    }
}

struct RecentlyAdded: Codable {
    let movies: [MediaItem]
    let shows: [MediaItem]
}

struct MediaFile: Codable, Identifiable {
    let id: Int
    let filename: String
    let sizeBytes: Int
    enum CodingKeys: String, CodingKey {
        case id, filename
        case sizeBytes = "size_bytes"
    }
}

// MARK: - Search

struct SearchResult: Codable {
    let movies: [MediaItem]
    let shows: [MediaItem]
    let total: Int
}

// MARK: - Media Requests

struct MediaRequest: Codable, Identifiable {
    let id: Int
    let userId: Int
    let username: String
    let message: String
    let status: String
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, username, message, status
        case userId    = "user_id"
        case createdAt = "created_at"
    }
}

// MARK: - Watch History

struct WatchProgress: Codable {
    let positionSeconds: Double
    let durationSeconds: Double?
    let completed: Bool
    enum CodingKeys: String, CodingKey {
        case positionSeconds = "position_seconds"
        case durationSeconds = "duration_seconds"
        case completed
    }
}

// MARK: - Stream Info

struct AudioTrack: Codable, Identifiable {
    let index: Int
    let codec: String?
    let language: String?
    let title: String?
    var id: Int { index }
}

struct SubtitleTrack: Codable, Identifiable {
    let index: Int
    let codec: String?
    let language: String?
    let title: String?
    let isImage: Bool
    var id: Int { index }
    enum CodingKeys: String, CodingKey {
        case index, codec, language, title
        case isImage = "is_image"
    }
}

struct StreamInfo: Codable {
    let vcodec: String?
    let acodec: String?
    let duration: Double?
    let canDirectPlay: Bool?
    let audioTracks: [AudioTrack]
    let subtitleTracks: [SubtitleTrack]
    enum CodingKeys: String, CodingKey {
        case vcodec, acodec, duration
        case canDirectPlay    = "can_direct_play"
        case audioTracks      = "audio_tracks"
        case subtitleTracks   = "subtitle_tracks"
    }
}

// MARK: - Media Edit

struct MediaUpdate: Codable {
    var title: String?
    var overview: String?
    var posterUrl: String?
    var backdropUrl: String?
    var tmdbId: Int?
    var refreshFromTmdb: Bool?
    enum CodingKeys: String, CodingKey {
        case title, overview
        case posterUrl       = "poster_url"
        case backdropUrl     = "backdrop_url"
        case tmdbId          = "tmdb_id"
        case refreshFromTmdb = "refresh_from_tmdb"
    }
}

// MARK: - Admin: Live

struct LiveViewer: Codable, Identifiable {
    let username: String
    let mediaId: Int
    let mediaKind: String
    let displayTitle: String
    let epLabel: String?
    let posterUrl: String?
    let positionSeconds: Double
    let durationSeconds: Double?
    let positionFmt: String
    let durationFmt: String?
    let progressPct: Int
    let secondsAgo: Int
    let ip: String?
    let device: DeviceInfo
    var id: Int { mediaId }
    enum CodingKeys: String, CodingKey {
        case username
        case mediaId        = "media_id"
        case mediaKind      = "media_kind"
        case displayTitle   = "display_title"
        case epLabel        = "ep_label"
        case posterUrl      = "poster_url"
        case positionSeconds = "position_seconds"
        case durationSeconds = "duration_seconds"
        case positionFmt    = "position_fmt"
        case durationFmt    = "duration_fmt"
        case progressPct    = "progress_pct"
        case secondsAgo     = "seconds_ago"
        case ip, device
    }
}

struct DeviceInfo: Codable {
    let type: String
    let label: String
}

struct LiveViewerResponse: Codable {
    let viewers: [LiveViewer]
    let activeWindowSeconds: Int
    enum CodingKeys: String, CodingKey {
        case viewers
        case activeWindowSeconds = "active_window_seconds"
    }
}

// MARK: - Admin: Server

struct ServerMetrics: Codable {
    let available: Bool
    let cpuPct: Double?
    let cpuCoresLogical: Int?
    let memTotal: Int?
    let memUsed: Int?
    let memPct: Double?
    let netBytesSent: Int?
    let netBytesRecv: Int?
    let uptimeSeconds: Int?
    enum CodingKeys: String, CodingKey {
        case available
        case cpuPct           = "cpu_pct"
        case cpuCoresLogical  = "cpu_cores_logical"
        case memTotal         = "mem_total"
        case memUsed          = "mem_used"
        case memPct           = "mem_pct"
        case netBytesSent     = "net_bytes_sent"
        case netBytesRecv     = "net_bytes_recv"
        case uptimeSeconds    = "uptime_seconds"
    }
}

struct LibraryStat: Codable, Identifiable {
    let id: Int
    let name: String
    let type: String
    let path: String
    let movieCount: Int
    let showCount: Int
    let episodeCount: Int
    let fileCount: Int
    let totalBytes: Int
    let disk: DiskStat?
    enum CodingKeys: String, CodingKey {
        case id, name, type, path, disk
        case movieCount   = "movie_count"
        case showCount    = "show_count"
        case episodeCount = "episode_count"
        case fileCount    = "file_count"
        case totalBytes   = "total_bytes"
    }
}

struct DiskStat: Codable {
    let totalBytes: Int
    let usedBytes: Int
    let freeBytes: Int
    enum CodingKeys: String, CodingKey {
        case totalBytes = "total_bytes"
        case usedBytes  = "used_bytes"
        case freeBytes  = "free_bytes"
    }
}

struct ServerStatsResponse: Codable {
    let libraries: [LibraryStat]
    let totals: ServerTotals
    let dbSizeBytes: Int
    enum CodingKeys: String, CodingKey {
        case libraries, totals
        case dbSizeBytes = "db_size_bytes"
    }
}

struct ServerTotals: Codable {
    let movies: Int
    let shows: Int
    let episodes: Int
    let files: Int
    let totalBytes: Int
    enum CodingKeys: String, CodingKey {
        case movies, shows, episodes, files
        case totalBytes = "total_bytes"
    }
}

// MARK: - Admin: Users

struct AdminUser: Codable, Identifiable {
    let id: Int
    let username: String
    let isSuperuser: Bool
    let isActive: Bool
    let createdAt: String?
    let lastActive: String?
    let itemsWatched: Int
    let watchSeconds: Int
    let isSelf: Bool
    enum CodingKeys: String, CodingKey {
        case id, username
        case isSuperuser  = "is_superuser"
        case isActive     = "is_active"
        case createdAt    = "created_at"
        case lastActive   = "last_active"
        case itemsWatched = "items_watched"
        case watchSeconds = "watch_seconds"
        case isSelf       = "is_self"
    }
}

struct AdminUsersResponse: Codable {
    let users: [AdminUser]
}

// MARK: - Admin: Invites

struct InviteCode: Codable, Identifiable {
    let id: Int
    let code: String
    let createdBy: String?
    let createdAt: String?
    let usedBy: String?
    let usedAt: String?
    let expiresAt: String?
    let expired: Bool
    enum CodingKeys: String, CodingKey {
        case id, code, expired
        case createdBy  = "created_by"
        case createdAt  = "created_at"
        case usedBy     = "used_by"
        case usedAt     = "used_at"
        case expiresAt  = "expires_at"
    }
}

struct InvitesResponse: Codable {
    let openRegistration: Bool
    let invites: [InviteCode]
    enum CodingKeys: String, CodingKey {
        case invites
        case openRegistration = "open_registration"
    }
}

// MARK: - Admin: History

struct HistoryStats: Codable {
    let totals: HistoryTotals
    let mostWatchedMovies: [WatchedItem]
    let mostWatchedShows: [WatchedShow]
    let users: [UserHistory]
    enum CodingKeys: String, CodingKey {
        case totals, users
        case mostWatchedMovies = "most_watched_movies"
        case mostWatchedShows  = "most_watched_shows"
    }
}

struct HistoryTotals: Codable {
    let totalPlays: Int
    let totalSeconds: Int
    let totalCompleted: Int
    let uniqueWatchers: Int
    enum CodingKeys: String, CodingKey {
        case totalPlays      = "total_plays"
        case totalSeconds    = "total_seconds"
        case totalCompleted  = "total_completed"
        case uniqueWatchers  = "unique_watchers"
    }
}

struct WatchedItem: Codable, Identifiable {
    let mediaId: Int
    let title: String
    let posterUrl: String?
    let playCount: Int
    let totalSeconds: Int
    var id: Int { mediaId }
    enum CodingKeys: String, CodingKey {
        case title
        case mediaId      = "media_id"
        case posterUrl    = "poster_url"
        case playCount    = "play_count"
        case totalSeconds = "total_seconds"
    }
}

struct WatchedShow: Codable, Identifiable {
    let mediaId: Int
    let title: String
    let posterUrl: String?
    let epCount: Int
    let totalSeconds: Int
    var id: Int { mediaId }
    enum CodingKeys: String, CodingKey {
        case title
        case mediaId      = "media_id"
        case posterUrl    = "poster_url"
        case epCount      = "ep_count"
        case totalSeconds = "total_seconds"
    }
}

struct UserHistory: Codable, Identifiable {
    let userId: Int
    let username: String
    let totalSeconds: Int
    let itemCount: Int
    let history: [HistoryItem]
    var id: Int { userId }
    enum CodingKeys: String, CodingKey {
        case username, history
        case userId       = "user_id"
        case totalSeconds = "total_seconds"
        case itemCount    = "item_count"
    }
}

struct HistoryItem: Codable, Identifiable {
    let mediaId: Int
    let title: String
    let epLabel: String?
    let kind: String
    let posterUrl: String?
    let progressPct: Int
    let completed: Bool
    let positionSeconds: Int
    let durationSeconds: Int?
    let lastWatchedAt: String?
    var id: Int { mediaId }
    enum CodingKeys: String, CodingKey {
        case title, kind, completed
        case mediaId         = "media_id"
        case epLabel         = "ep_label"
        case posterUrl       = "poster_url"
        case progressPct     = "progress_pct"
        case positionSeconds = "position_seconds"
        case durationSeconds = "duration_seconds"
        case lastWatchedAt   = "last_watched_at"
    }
}

// MARK: - Admin: Scan

struct ScanStatusResponse: Codable {
    let scanning: Bool
    let libraries: [LibraryScanState]
}

struct LibraryScanState: Codable, Identifiable {
    let id: Int
    let name: String
    let status: String
    let startedAt: String?
    let finishedAt: String?
    let error: String?
    enum CodingKeys: String, CodingKey {
        case id, name, status, error
        case startedAt  = "started_at"
        case finishedAt = "finished_at"
    }
}
