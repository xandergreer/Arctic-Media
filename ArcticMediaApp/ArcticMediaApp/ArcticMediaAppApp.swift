import SwiftUI

@main
struct ArcticMediaAppApp: App {
    @StateObject private var api = APIService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(api)
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        #endif
    }
}
