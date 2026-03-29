import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var serverURL: String
    @Published var token: String?
    @Published var currentUser: UserInfo?

    init() {
        self.serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        self.token = KeychainService.getToken()
    }

    var isConfigured: Bool { !serverURL.isEmpty }
    var isAuthenticated: Bool { token != nil }

    func setServer(_ url: String) {
        var clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasSuffix("/") { clean = String(clean.dropLast()) }
        serverURL = clean
        UserDefaults.standard.set(serverURL, forKey: "serverURL")
    }

    func login(token: String) {
        self.token = token
        KeychainService.saveToken(token)
    }

    func logout() {
        token = nil
        currentUser = nil
        KeychainService.deleteToken()
    }
}
