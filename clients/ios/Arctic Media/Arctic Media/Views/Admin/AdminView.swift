import SwiftUI

struct AdminView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Color.arcticBg.ignoresSafeArea()
            List {
                Section {
                    NavigationLink(destination: AdminLiveView()) {
                        Label("Live Viewers", systemImage: "dot.radiowaves.left.and.right")
                    }
                    NavigationLink(destination: AdminServerView()) {
                        Label("Server", systemImage: "server.rack")
                    }
                } header: {
                    Text("Monitoring")
                }

                Section {
                    NavigationLink(destination: AdminUsersView()) {
                        Label("Users", systemImage: "person.2.fill")
                    }
                    NavigationLink(destination: AdminInvitesView()) {
                        Label("Invites", systemImage: "envelope.badge.fill")
                    }
                } header: {
                    Text("Management")
                }

                Section {
                    NavigationLink(destination: AdminHistoryView()) {
                        Label("Watch History", systemImage: "clock.fill")
                    }
                } header: {
                    Text("Analytics")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Admin Panel")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
