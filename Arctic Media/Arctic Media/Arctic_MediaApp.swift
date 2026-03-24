import SwiftUI

@main
struct Arctic_MediaApp: App {
    @StateObject private var api = APIService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(api)
        }
    }
}
