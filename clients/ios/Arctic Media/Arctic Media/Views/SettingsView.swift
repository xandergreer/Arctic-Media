import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showChangePassword = false

    var body: some View {
        ZStack {
            Color.arcticBg.ignoresSafeArea()

            List {
                Section {
                    infoRow(label: "Server", value: appState.serverURL)
                    infoRow(label: "User", value: appState.currentUser?.username ?? "—")
                } header: {
                    Text("Connection").foregroundColor(.arcticMuted)
                }
                .listRowBackground(Color.arcticSurface)

                if appState.currentUser?.isSuperuser == true {
                    Section {
                        NavigationLink(destination: AdminView()) {
                            Label("Admin Panel", systemImage: "shield.fill")
                                .foregroundColor(.arcticPrimary)
                        }
                    } header: {
                        Text("Administration").foregroundColor(.arcticMuted)
                    }
                    .listRowBackground(Color.arcticSurface)
                }

                Section {
                    Toggle(isOn: $appState.autoPlayEnabled) {
                        Label("Auto-Play Next Episode", systemImage: "play.circle.fill")
                            .foregroundColor(.arcticText)
                    }
                    .tint(.arcticPrimary)
                } header: {
                    Text("Playback").foregroundColor(.arcticMuted)
                }
                .listRowBackground(Color.arcticSurface)

                Section {
                    Button {
                        showChangePassword = true
                    } label: {
                        Label("Change Password", systemImage: "lock.rotation")
                            .foregroundColor(.arcticText)
                    }
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
                    Text("Account").foregroundColor(.arcticMuted)
                }
                .listRowBackground(Color.arcticSurface)

                Section {
                    infoRow(label: "Version", value: "1.0.0")
                } header: {
                    Text("About").foregroundColor(.arcticMuted)
                }
                .listRowBackground(Color.arcticSurface)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.arcticBg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            guard let token = appState.token else { return }
            do {
                appState.currentUser = try await APIService.shared.me(
                    serverURL: appState.serverURL, token: token
                )
            } catch {}
        }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet()
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

// MARK: - Change Password Sheet

private struct ChangePasswordSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var newPw = ""
    @State private var confirm = ""
    @State private var isLoading = false
    @State private var errorMsg: String?
    @State private var success = false

    var body: some View {
        NavigationStack {
            ZStack { Color.arcticBg.ignoresSafeArea()
                Form {
                    Section {
                        SecureField("Current password", text: $current)
                            .textContentType(.password)
                        SecureField("New password", text: $newPw)
                            .textContentType(.newPassword)
                        SecureField("Confirm new password", text: $confirm)
                            .textContentType(.newPassword)
                    } footer: {
                        if let err = errorMsg {
                            Text(err).foregroundColor(.red)
                        } else if success {
                            Text("Password updated successfully.").foregroundColor(.green)
                        }
                    }
                    .listRowBackground(Color.arcticSurface)

                    Section {
                        Button {
                            Task { await submit() }
                        } label: {
                            if isLoading {
                                HStack {
                                    Spacer()
                                    ProgressView().tint(.white)
                                    Spacer()
                                }
                            } else {
                                Text("Update Password")
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .foregroundColor(.white)
                            }
                        }
                        .disabled(isLoading)
                        .listRowBackground(Color.arcticPrimary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.arcticBg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        errorMsg = nil
        success = false
        guard !current.isEmpty, !newPw.isEmpty, !confirm.isEmpty else {
            errorMsg = "Please fill in all fields."; return
        }
        guard newPw == confirm else {
            errorMsg = "New passwords do not match."; return
        }
        guard newPw.count >= 6 else {
            errorMsg = "New password must be at least 6 characters."; return
        }
        guard let token = appState.token else { return }

        isLoading = true
        do {
            try await APIService.shared.changePassword(
                serverURL: appState.serverURL, token: token,
                currentPassword: current, newPassword: newPw)
            success = true
            current = ""; newPw = ""; confirm = ""
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
        isLoading = false
    }
}
