import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            ZStack {
                Color.arcticBg.ignoresSafeArea()

                List {
                    Section {
                        infoRow(label: "Server", value: appState.serverURL)
                        infoRow(label: "User", value: appState.currentUser?.username ?? "—")
                    } header: {
                        Text("Connection")
                            .foregroundColor(.arcticMuted)
                    }
                    .listRowBackground(Color.arcticSurface)

                    Section {
                        Button(role: .destructive) {
                            appState.logout()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }

                        Button {
                            appState.setServer("")
                            appState.logout()
                        } label: {
                            Label("Change Server", systemImage: "server.rack")
                                .foregroundColor(.arcticSub)
                        }
                    } header: {
                        Text("Account")
                            .foregroundColor(.arcticMuted)
                    }
                    .listRowBackground(Color.arcticSurface)

                    Section {
                        infoRow(label: "Version", value: "1.0.0")
                    } header: {
                        Text("About")
                            .foregroundColor(.arcticMuted)
                    }
                    .listRowBackground(Color.arcticSurface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.arcticBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            guard let token = appState.token else { return }
            do {
                appState.currentUser = try await APIService.shared.me(
                    serverURL: appState.serverURL, token: token
                )
            } catch {}
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.arcticSub)
            Spacer()
            Text(value)
                .foregroundColor(.arcticMuted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
