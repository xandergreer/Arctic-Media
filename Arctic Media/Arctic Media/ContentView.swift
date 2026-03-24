import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var api: APIService

    var body: some View {
        if api.isLoggedIn {
            HomeView()
        } else {
            LoginView()
        }
    }
}
