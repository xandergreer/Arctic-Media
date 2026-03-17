import Foundation

// MARK: - API Models

struct LoginResponse: Codable {
    let access_token: String
    let token_type: String
}

struct UserResponse: Codable {
    let id: Int
    let username: String
    let is_superuser: Bool
}

struct MediaItem: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let sort_title: String?
    let kind: String
    let overview: String?
    let release_date: String?
    let year: Int?
    let poster_url: String?
    let backdrop_url: String?
    let tmdb_id: Int?
    let library_id: Int?
    let parent_id: Int?
    let season_number: Int?
    let episode_number: Int?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool { lhs.id == rhs.id }
}

struct MediaFile: Codable, Identifiable {
    let id: Int
    let media_item_id: Int
    let path: String
    let size_bytes: Int?
    let duration_seconds: Double?
}

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
    let is_image: Bool?
    let is_external: Bool?
    var id: Int { index }
}

struct StreamInfo: Codable {
    let audio_tracks: [AudioTrack]
    let subtitle_tracks: [SubtitleTrack]
    let can_direct_play: Bool?
    let duration: Double?
}

struct LibraryItem: Codable, Identifiable {
    let id: Int
    let name: String
    let path: String
    let type: String
}

struct MediaPage: Codable {
    let items: [MediaItem]
    let total: Int?
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int, String)
    case decodingError(Error)
    case networkError(Error)
    case noToken

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .unauthorized: return "Invalid username or password"
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        case .decodingError(let e): return "Decode error: \(e.localizedDescription)"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .noToken: return "Not authenticated"
        }
    }
}

// MARK: - APIService

@MainActor
class APIService: ObservableObject {
    static let shared = APIService()

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }
    @Published var token: String? {
        didSet { UserDefaults.standard.set(token, forKey: "authToken") }
    }
    @Published var currentUser: UserResponse?

    var isAuthenticated: Bool { token != nil }

    private var baseURL: URL? { URL(string: serverURL) }

    init() {
        self.serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://localhost:8085"
        self.token = UserDefaults.standard.string(forKey: "authToken")
    }

    // MARK: - Request Builder

    private func request(_ path: String, method: String = "GET", body: Data? = nil, requiresAuth: Bool = true) throws -> URLRequest {
        guard let base = baseURL, let url = URL(string: path, relativeTo: base) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30

        if requiresAuth {
            guard let tok = token else { throw APIError.noToken }
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    private func perform<T: Decodable>(_ req: URLRequest) async throws -> T {
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.networkError(URLError(.badServerResponse))
            }
            if http.statusCode == 401 { throw APIError.unauthorized }
            if http.statusCode >= 400 {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.serverError(http.statusCode, msg)
            }
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Auth

    func login(username: String, password: String) async throws {
        guard let base = baseURL else { throw APIError.invalidURL }
        var req = URLRequest(url: base.appendingPathComponent("api/v1/auth/token"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "username=\(username.urlEncoded)&password=\(password.urlEncoded)"
        req.httpBody = body.data(using: .utf8)

        let resp: LoginResponse = try await perform(req)
        token = resp.access_token
        try await fetchCurrentUser()
    }

    func logout() {
        token = nil
        currentUser = nil
    }

    func fetchCurrentUser() async throws {
        let req = try request("api/v1/auth/me")
        currentUser = try await perform(req)
    }

    // MARK: - Media

    func fetchMovies(skip: Int = 0, limit: Int = 50) async throws -> [MediaItem] {
        let req = try request("api/v1/media/movies?skip=\(skip)&limit=\(limit)")
        return try await perform(req)
    }

    func fetchShows(skip: Int = 0, limit: Int = 50) async throws -> [MediaItem] {
        let req = try request("api/v1/media/shows?skip=\(skip)&limit=\(limit)")
        return try await perform(req)
    }

    func fetchRecentlyAdded() async throws -> [MediaItem] {
        let req = try request("api/v1/media/recently-added")
        return try await perform(req)
    }

    func fetchMediaItem(_ id: Int) async throws -> MediaItem {
        let req = try request("api/v1/media/\(id)")
        return try await perform(req)
    }

    func fetchSeasons(showId: Int) async throws -> [MediaItem] {
        let req = try request("api/v1/media/shows/\(showId)/seasons")
        return try await perform(req)
    }

    func fetchEpisodes(seasonId: Int) async throws -> [MediaItem] {
        let req = try request("api/v1/media/seasons/\(seasonId)/episodes")
        return try await perform(req)
    }

    func fetchMediaFiles(_ mediaId: Int) async throws -> [MediaFile] {
        let req = try request("api/v1/media/\(mediaId)/files")
        return try await perform(req)
    }

    func search(query: String) async throws -> [MediaItem] {
        let encoded = query.urlEncoded
        let req = try request("api/v1/media/search?q=\(encoded)")
        return try await perform(req)
    }

    // MARK: - Streaming

    func fetchStreamInfo(_ mediaId: Int, fileId: Int? = nil) async throws -> StreamInfo {
        var path = "api/v1/stream/\(mediaId)/info"
        if let fid = fileId { path += "?file_id=\(fid)" }
        let req = try request(path)
        return try await perform(req)
    }

    func streamURL(mediaId: Int, fileId: Int? = nil, audioIndex: Int? = nil, subtitleIndex: Int? = nil) -> URL? {
        guard let base = baseURL, let tok = token else { return nil }
        var comps = URLComponents(url: base.appendingPathComponent("api/v1/stream/\(mediaId)/master.m3u8"), resolvingAgainstBaseURL: true)
        var items: [URLQueryItem] = [URLQueryItem(name: "token", value: tok)]
        if let fid = fileId { items.append(URLQueryItem(name: "file_id", value: "\(fid)")) }
        if let aidx = audioIndex { items.append(URLQueryItem(name: "aidx", value: "\(aidx)")) }
        if let sidx = subtitleIndex { items.append(URLQueryItem(name: "sidx", value: "\(sidx)")) }
        comps?.queryItems = items
        return comps?.url
    }

    // MARK: - Image URLs

    func posterURL(for item: MediaItem) -> URL? {
        guard let path = item.poster_url else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return baseURL?.appendingPathComponent(path)
    }

    func backdropURL(for item: MediaItem) -> URL? {
        guard let path = item.backdrop_url else { return nil }
        if path.hasPrefix("http") { return URL(string: path) }
        return baseURL?.appendingPathComponent(path)
    }
}

// MARK: - String Extension

extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
