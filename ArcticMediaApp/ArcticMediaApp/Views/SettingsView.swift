import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var api: APIService
    @State private var serverURLDraft = ""
    @State private var showingLogoutConfirm = false
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                // Server
                Section("Server") {
                    HStack {
                        Text("URL")
                        Spacer()
                        TextField("http://192.168.1.x:8085", text: $serverURLDraft)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            #endif
                    }

                    Button(action: saveServerURL) {
                        Text("Save Server URL")
                    }

                    Button(action: testConnection) {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            } else if let result = testResult {
                                Image(systemName: result == "ok" ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result == "ok" ? .green : .red)
                            }
                        }
                    }
                }

                // Account
                if let user = api.currentUser {
                    Section("Account") {
                        LabeledContent("Username", value: user.username)
                        LabeledContent("Role", value: user.is_superuser ? "Administrator" : "User")
                    }
                }

                // About
                Section("About") {
                    LabeledContent("App", value: "Arctic Media")
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Platform") {
                        #if os(iOS)
                        Text("iOS")
                        #else
                        Text("macOS")
                        #endif
                    }
                }

                // Logout
                Section {
                    Button(role: .destructive) {
                        showingLogoutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear { serverURLDraft = api.serverURL }
            .confirmationDialog("Sign Out", isPresented: $showingLogoutConfirm) {
                Button("Sign Out", role: .destructive) { api.logout() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }

    private func saveServerURL() {
        let trimmed = serverURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        api.serverURL = trimmed
        testResult = nil
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                try await api.fetchCurrentUser()
                testResult = "ok"
            } catch {
                testResult = "fail"
            }
            isTesting = false
        }
    }
}
