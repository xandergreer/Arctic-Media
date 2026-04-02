import Foundation

// MARK: - Media

struct MediaItem: Codable, Identifiable, Hashable {
    let id: Int
    let kind: String          // "movie" | "show" | "season" | "episode"
    let title: String
    let overview: String?
    let release_date: String?
    let poster_url: String?
    let backdrop_url: String?
    let season_number: Int?
    let episode_number: Int?
    let parent_id: Int?
    let tmdb_id: Int?
    let extra_json: ExtraJSON?

    var year: String? {
        guard let d = release_date, d.count >= 4 else { return nil }
        return String(d.prefix(4))
    }
}

struct ExtraJSON: Codable, Hashable {
    let imdb_id: String?
    let tmdb_id: Int?
}

struct MediaList: Codable {
    let movies: [MediaItem]
    let shows: [MediaItem]
}

struct MediaUpdate: Encodable {
    var title: String?
    var overview: String?
    var poster_url: String?
    var tmdb_id: Int?
    var refresh_from_tmdb: Bool?
}

// MARK: - Auth

struct AuthResponse: Codable {
    let access_token: String
    let token_type: String
}

struct UserInfo: Codable {
    let id: Int
    let username: String
    let is_superuser: Bool
}

// MARK: - Watch progress

struct WatchProgress: Codable {
    let position_seconds: Double
    let duration_seconds: Double?
    let completed: Bool
}

struct ContinueWatchingItem: Codable, Identifiable {
    let media_id: Int
    let title: String
    let poster_url: String?
    let backdrop_url: String?
    let kind: String
    let episode_number: Int?
    let season_number: Int?
    let position_seconds: Double
    let duration_seconds: Double?
    let progress_pct: Int
    var id: Int { media_id }

    var subtitle: String? {
        guard kind == "episode" else { return nil }
        if let s = season_number, let e = episode_number {
            return "S\(s) E\(e)"
        }
        return nil
    }
}

// MARK: - Stream info

struct SubtitleTrack: Codable, Identifiable {
    let index: Int
    let codec: String?
    let language: String?
    let title: String?
    let is_image: Bool
    let is_external: Bool?
    var id: Int { index }

    var displayName: String {
        if let t = title, !t.isEmpty, t != language { return t }
        if let lang = language, !lang.isEmpty, lang != "und" { return lang.uppercased() }
        return "Track \(index + 1)"
    }
}

struct StreamInfo: Codable {
    let subtitle_tracks: [SubtitleTrack]?
    let duration: Double?
}

// MARK: - Scan

struct ScanStatus: Codable {
    let scanning: Bool
    let libraries: [LibraryScanState]
}

struct LibraryScanState: Codable, Identifiable {
    let library_id: Int
    let library_name: String
    let status: String
    let started_at: String?
    let finished_at: String?
    let error: String?
    var id: Int { library_id }
}
