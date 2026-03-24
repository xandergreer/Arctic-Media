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

    var year: String? {
        guard let d = release_date, d.count >= 4 else { return nil }
        return String(d.prefix(4))
    }
}

struct MediaList: Codable {
    let movies: [MediaItem]
    let shows: [MediaItem]
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
