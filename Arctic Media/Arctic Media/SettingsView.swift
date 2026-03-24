import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var api: APIService
    @State private var serverURLDraft = ""
    @State private var showLogoutConfirm = false

    var body: some View {
        Form {
            Section("Server") {
                HStack {
                    TextField("Server URL", text: $serverURLDraft)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Button("Save") {
                        api.serverURL = serverURLDraft
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    showLogoutConfirm = true
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear { serverURLDraft = api.serverURL }
        .confirmationDialog("Sign out of Arctic Media?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { api.logout() }
        }
    }
}
