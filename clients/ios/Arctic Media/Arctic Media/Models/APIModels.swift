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
