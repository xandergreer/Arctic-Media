import Foundation

// MARK: - Errors

enum APIError: Error, LocalizedError {
    case unauthorized
    case notFound
    case invalidResponse
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:        return "Invalid credentials"
        case .notFound:            return "Not found"
        case .invalidResponse:     return "Invalid server response"
        case .serverError(let c):  return "Server error (\(c))"
        }
    }
}

// MARK: - Service

@MainActor
final class APIService: ObservableObject {

    static let shared = APIService()

    @Published var token: String? {
        didSet { UserDefaults.standard.set(token, forKey: "auth_token") }
    }
    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "server_url") }
    }

    var isLoggedIn: Bool { token != nil }

    private var base: String {
        serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private init() {
        token     = UserDefaults.standard.string(forKey: "auth_token")
        serverURL = UserDefaults.standard.string(forKey: "server_url") ?? "http://localhost:8000"
    }

    // MARK: - Auth

    func login(username: String, password: String) async throws {
        let url = URL(string: "\(base)/api/v1/auth/token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "username=\(username.urlEncoded)&password=\(password.urlEncoded)"
        req.httpBody = body.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw APIError.serverError(http.statusCode) }

        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        token = auth.access_token
    }

    func logout() {
        token = nil
        UserDefaults.standard.removeObject(forKey: "auth_token")
    }

    // MARK: - Media endpoints

    func getMovies() async throws -> [MediaItem] {
        try await get("/api/v1/media/movies")
    }

    func getShows() async throws -> [MediaItem] {
        try await get("/api/v1/media/shows")
    }

    func getRecentlyAdded() async throws -> MediaList {
        try await get("/api/v1/media/recently-added")
    }

    func getSeasons(showId: Int) async throws -> [MediaItem] {
        try await get("/api/v1/media/shows/\(showId)/seasons")
    }

    func getEpisodes(seasonId: Int) async throws -> [MediaItem] {
        try await get("/api/v1/media/seasons/\(seasonId)/episodes")
    }

    // MARK: - History

    func getProgress(mediaId: Int) async throws -> WatchProgress {
        try await get("/api/v1/history/\(mediaId)")
    }

    func saveProgress(mediaId: Int, position: Double, duration: Double?) async throws {
        struct Body: Encodable { let position_seconds: Double; let duration_seconds: Double? }
        try await post("/api/v1/history/\(mediaId)", body: Body(position_seconds: position, duration_seconds: duration))
    }

    // MARK: - Stream

    func streamURL(mediaId: Int) -> URL? {
        guard let token else { return nil }
        return URL(string: "\(base)/api/v1/stream/\(mediaId)/master.m3u8?token=\(token)")
    }

    // MARK: - Generic helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let token else { throw APIError.unauthorized }
        let url = URL(string: "\(base)\(path)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        default:  throw APIError.serverError(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Encodable>(_ path: String, body: T) async throws {
        guard let token else { throw APIError.unauthorized }
        let url = URL(string: "\(base)\(path)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
