import SwiftUI

struct AdminUsersView: View {
    @EnvironmentObject var appState: AppState
    @State private var users: [AdminUser] = []
    @State private var loading = true
    @State private var confirmDelete: AdminUser?
    @State private var resetResult: ResetPasswordResponse?
    @State private var showCreateUser = false
    @State private var errorMsg: String?

    var body: some View {
        ZStack {
            Color.arcticBg.ignoresSafeArea()
            if loading {
                ProgressView().tint(.arcticPrimary)
            } else {
                userList
            }
        }
        .navigationTitle("Users")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showCreateUser = true } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .task { await load() }
        // Delete confirmation
        .alert("Delete User", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let u = confirmDelete { Task { await deleteUser(u) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let u = confirmDelete {
                Text("Delete \"\(u.username)\"? This cannot be undone.")
            }
        }
        .sheet(isPresented: $showCreateUser) {
            CreateUserSheet { await load() }
        }
        // Reset password result
        .alert("Password Reset", isPresented: Binding(
            get: { resetResult != nil },
            set: { if !$0 { resetResult = nil } }
        )) {
            Button("Copy Password") {
                if let r = resetResult {
                    UIPasteboard.general.string = r.newPassword
                }
                resetResult = nil
            }
            Button("Done", role: .cancel) { resetResult = nil }
        } message: {
            if let r = resetResult {
                Text("\(r.username)'s new password is:\n\n\(r.newPassword)\n\nShare this with the user — they should change it after logging in.")
            }
        }
    }

    private var userList: some View {
        List {
            if let err = errorMsg {
                Text(err).foregroundColor(.red).font(.subheadline)
            }
            ForEach(users) { user in
                UserRowView(user: user) {
                    Task { await toggleSuperuser(user) }
                } onResetPassword: {
                    Task { await resetPassword(user) }
                } onDelete: {
                    confirmDelete = user
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func load() async {
        guard let token = appState.token else { return }
        do {
            let res = try await APIService.shared.adminUsers(serverURL: appState.serverURL, token: token)
            users = res.users
        } catch {
            errorMsg = error.localizedDescription
        }
        loading = false
    }

    private func toggleSuperuser(_ user: AdminUser) async {
        guard let token = appState.token else { return }
        do {
            let updated = try await APIService.shared.toggleSuperuser(
                serverURL: appState.serverURL, token: token, userId: user.id)
            if let idx = users.firstIndex(where: { $0.id == user.id }) {
                users[idx] = AdminUser(
                    id: updated.id, username: updated.username,
                    isSuperuser: updated.isSuperuser, isActive: users[idx].isActive,
                    createdAt: users[idx].createdAt, lastActive: users[idx].lastActive,
                    itemsWatched: users[idx].itemsWatched, watchSeconds: users[idx].watchSeconds,
                    isSelf: users[idx].isSelf
                )
            }
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func resetPassword(_ user: AdminUser) async {
        guard let token = appState.token else { return }
        do {
            let result = try await APIService.shared.resetPassword(
                serverURL: appState.serverURL, token: token, userId: user.id)
            resetResult = result
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func deleteUser(_ user: AdminUser) async {
        guard let token = appState.token else { return }
        do {
            try await APIService.shared.deleteUser(serverURL: appState.serverURL, token: token, userId: user.id)
            users.removeAll { $0.id == user.id }
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

private struct UserRowView: View {
    let user: AdminUser
    let onToggleSuperuser: () -> Void
    let onResetPassword: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(user.isSuperuser ? Color.arcticPrimary : Color.arcticSurface)
                    .frame(width: 44, height: 44)
                Text(String(user.username.prefix(1)).uppercased())
                    .font(.headline.bold())
                    .foregroundColor(user.isSuperuser ? .white : .arcticText)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(user.username)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.arcticText)
                    if user.isSuperuser {
                        Text("Admin")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.arcticPrimary.opacity(0.2))
                            .foregroundColor(.arcticPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text("\(user.itemsWatched) items · \(formatWatchTime(user.watchSeconds))")
                    .font(.caption).foregroundColor(.arcticMuted)
                if let last = user.lastActive {
                    Text("Last active \(timeAgo(last))")
                        .font(.caption2).foregroundColor(.arcticMuted)
                }
            }

            Spacer()

            if !user.isSelf {
                Menu {
                    Button(user.isSuperuser ? "Revoke Admin" : "Make Admin", action: onToggleSuperuser)
                    Button("Reset Password", action: onResetPassword)
                    Divider()
                    Button("Delete User", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.arcticMuted)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatWatchTime(_ secs: Int) -> String {
        let h = secs / 3600
        if h == 0 { return "\((secs % 3600) / 60)m" }
        return "\(h)h"
    }

    private func timeAgo(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return iso
        }
        let secs = Int(-date.timeIntervalSinceNow)
        if secs < 60 { return "just now" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        if secs < 86400 { return "\(secs / 3600)h ago" }
        return "\(secs / 86400)d ago"
    }
}

// MARK: - Create User Sheet

private struct CreateUserSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    var onCreated: () async -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var makeAdmin = false
    @State private var isLoading = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.arcticBg.ignoresSafeArea()
                Form {
                    Section {
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password (min 6 characters)", text: $password)
                            .textContentType(.newPassword)
                        Toggle("Make Admin", isOn: $makeAdmin)
                            .tint(.arcticPrimary)
                    } footer: {
                        if let err = errorMsg {
                            Text(err).foregroundColor(.red)
                        }
                    }
                    .listRowBackground(Color.arcticSurface)

                    Section {
                        Button {
                            Task { await submit() }
                        } label: {
                            if isLoading {
                                HStack { Spacer(); ProgressView().tint(.white); Spacer() }
                            } else {
                                Text("Create User")
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
            .navigationTitle("Create User")
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
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty else { errorMsg = "Username is required."; return }
        guard password.count >= 6 else { errorMsg = "Password must be at least 6 characters."; return }
        guard let token = appState.token else { return }

        isLoading = true
        do {
            let params = "username=\(username.encoded)&password=\(password.encoded)&is_superuser=\(makeAdmin)"
            var req = try URLRequest(url: URL(string: appState.serverURL + "/api/v1/admin/users?\(params)")!)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                errorMsg = "Failed (HTTP \(http.statusCode))."; isLoading = false; return
            }
            await onCreated()
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
        isLoading = false
    }
}
