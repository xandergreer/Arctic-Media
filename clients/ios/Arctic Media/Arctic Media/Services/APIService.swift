import Foundation

enum APIError: LocalizedError {
    case invalidURL, unauthorized, serverError(Int), decodingError(Error), networkError(Error)
    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Invalid server URL."
        case .unauthorized:        return "Invalid credentials."
        case .serverError(let c):  return "Server error (\(c))."
        case .decodingError(let e): return "Unexpected response: \(e.localizedDescription)"
        case .networkError(let e): return e.localizedDescription
        }
    }
}

class APIService {
    static let shared = APIService()
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    // MARK: - Auth

    func login(serverURL: String, username: String, password: String) async throws -> TokenResponse {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/auth/token", method: "POST")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "username=\(username.encoded)&password=\(password.encoded)".data(using: .utf8)
        return try await send(req)
    }

    func me(serverURL: String, token: String) async throws -> UserInfo {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/auth/me")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    // MARK: - Media

    func recentlyAdded(serverURL: String, token: String, limit: Int = 12) async throws -> RecentlyAdded {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/media/recently-added?limit=\(limit)")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func movies(serverURL: String, token: String, skip: Int = 0, limit: Int = 200) async throws -> [MediaItem] {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/media/movies?skip=\(skip)&limit=\(limit)")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func shows(serverURL: String, token: String, skip: Int = 0, limit: Int = 200) async throws -> [MediaItem] {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/media/shows?skip=\(skip)&limit=\(limit)")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func mediaItem(serverURL: String, token: String, id: Int) async throws -> MediaItem {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/media/\(id)")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func seasons(serverURL: String, token: String, showId: Int) async throws -> [MediaItem] {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/media/shows/\(showId)/seasons")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func episodes(serverURL: String, token: String, seasonId: Int) async throws -> [MediaItem] {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/media/seasons/\(seasonId)/episodes")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func search(serverURL: String, token: String, query: String) async throws -> SearchResult {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/media/search?q=\(q)")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func streamInfo(serverURL: String, token: String, mediaId: Int) async throws -> StreamInfo {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/stream/\(mediaId)/info?token=\(token)")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    // MARK: - Watch History

    func watchProgress(serverURL: String, token: String, mediaId: Int) async throws -> WatchProgress {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/history/\(mediaId)")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func updateProgress(serverURL: String, token: String, mediaId: Int, position: Double, duration: Double) async {
        guard var req = try? makeRequest(serverURL: serverURL, path: "/api/v1/history/\(mediaId)", method: "POST") else { return }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "position_seconds": position,
            "duration_seconds": duration
        ])
        _ = try? await session.data(for: req)
    }

    // MARK: - Media Requests

    func submitRequest(serverURL: String, token: String, message: String) async throws {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/requests", method: "POST")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["message": message])
        _ = try await session.data(for: req)
    }

    func adminRequests(serverURL: String, token: String) async throws -> [MediaRequest] {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/admin/requests")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func updateRequestStatus(serverURL: String, token: String, requestId: Int, status: String) async throws -> MediaRequest {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/admin/requests/\(requestId)", method: "PATCH")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["status": status])
        return try await send(req)
    }

    // MARK: - Stream URL (not a network call — just constructs the URL)

    func hlsURL(serverURL: String, token: String, mediaId: Int, audioIndex: Int = 0) -> URL? {
        URL(string: "\(serverURL)/api/v1/stream/\(mediaId)/master.m3u8?token=\(token)&aidx=\(audioIndex)")
    }

    // MARK: - Media Edit

    func updateMedia(serverURL: String, token: String, mediaId: Int, update: MediaUpdate) async throws -> MediaItem {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/media/\(mediaId)", method: "PATCH")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONEncoder().encode(update)
        return try await send(req)
    }

    // MARK: - Admin: Live Viewers

    func liveViewers(serverURL: String, token: String) async throws -> LiveViewerResponse {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/admin/live")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    // MARK: - Admin: Server

    func serverMetrics(serverURL: String, token: String) async throws -> ServerMetrics {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/admin/server/metrics")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func serverStats(serverURL: String, token: String) async throws -> ServerStatsResponse {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/admin/server")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    // MARK: - Admin: Scan

    func scanStatus(serverURL: String, token: String) async throws -> ScanStatusResponse {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/scan/status")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func scanAll(serverURL: String, token: String) async throws {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/scan/run", method: "POST")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await session.data(for: req)
    }

    // MARK: - Admin: Users

    func adminUsers(serverURL: String, token: String) async throws -> AdminUsersResponse {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/admin/users")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func toggleSuperuser(serverURL: String, token: String, userId: Int) async throws -> AdminUser {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/admin/users/\(userId)/superuser", method: "PATCH")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func deleteUser(serverURL: String, token: String, userId: Int) async throws {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/admin/users/\(userId)", method: "DELETE")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await session.data(for: req)
    }

    // MARK: - Admin: Invites

    func adminInvites(serverURL: String, token: String) async throws -> InvitesResponse {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/admin/invites")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func createInvite(serverURL: String, token: String) async throws -> InviteCode {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/admin/invites", method: "POST")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    func deleteInvite(serverURL: String, token: String, inviteId: Int) async throws {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/admin/invites/\(inviteId)", method: "DELETE")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await session.data(for: req)
    }

    func setOpenRegistration(serverURL: String, token: String, enabled: Bool) async throws {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/admin/invites/settings?open_registration=\(enabled)", method: "PATCH")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await session.data(for: req)
    }

    // MARK: - Admin: History

    func adminHistory(serverURL: String, token: String) async throws -> HistoryStats {
        var req = try makeRequest(serverURL: serverURL, path: "/api/v1/admin/history")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req)
    }

    // MARK: - Internals

    private func makeRequest(serverURL: String, path: String, method: String = "GET") throws -> URLRequest {
        guard let url = URL(string: serverURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        return req
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 { throw APIError.unauthorized }
                if http.statusCode >= 400  { throw APIError.serverError(http.statusCode) }
            }
            let decoder = JSONDecoder()
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.networkError(error)
        }
    }
}

private extension String {
    var encoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
