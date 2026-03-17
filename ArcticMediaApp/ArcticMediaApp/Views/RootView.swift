import SwiftUI

struct RootView: View {
    @EnvironmentObject var api: APIService

    var body: some View {
        Group {
            if api.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: api.isAuthenticated)
    }
}
