import SwiftUI

struct AdminInvitesView: View {
    @EnvironmentObject var appState: AppState
    @State private var response: InvitesResponse?
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var copiedCode: String?

    var body: some View {
        ZStack {
            Color.arcticBg.ignoresSafeArea()
            if loading {
                ProgressView().tint(.arcticPrimary)
            } else {
                content
            }
        }
        .navigationTitle("Invites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { Task { await createInvite() } }) {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
    }

    private var content: some View {
        List {
            if let err = errorMsg {
                Text(err).foregroundColor(.red).font(.subheadline)
            }

            if let resp = response {
                // Open registration toggle
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open Registration")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.arcticText)
                            Text("Allow anyone to register without an invite")
                                .font(.caption).foregroundColor(.arcticMuted)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { resp.openRegistration },
                            set: { val in Task { await setOpenReg(val) } }
                        ))
                        .tint(.arcticPrimary)
                    }
                }

                // Invite codes
                Section {
                    if resp.invites.isEmpty {
                        Text("No invite codes yet. Tap + to create one.")
                            .font(.subheadline).foregroundColor(.arcticMuted)
                            .listRowBackground(Color.arcticSurface)
                    } else {
                        ForEach(resp.invites) { invite in
                            InviteRowView(invite: invite, copied: copiedCode == invite.code) {
                                UIPasteboard.general.string = invite.code
                                copiedCode = invite.code
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedCode = nil }
                            } onDelete: {
                                Task { await deleteInvite(invite) }
                            }
                        }
                    }
                } header: {
                    Text("Invite Codes")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func load() async {
        guard let token = appState.token else { return }
        do {
            response = try await APIService.shared.adminInvites(serverURL: appState.serverURL, token: token)
        } catch {
            errorMsg = error.localizedDescription
        }
        loading = false
    }

    private func createInvite() async {
        guard let token = appState.token else { return }
        do {
            let newInvite = try await APIService.shared.createInvite(serverURL: appState.serverURL, token: token)
            if var resp = response {
                let updated = InvitesResponse(openRegistration: resp.openRegistration,
                                              invites: [newInvite] + resp.invites)
                response = updated
            }
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func deleteInvite(_ invite: InviteCode) async {
        guard let token = appState.token else { return }
        do {
            try await APIService.shared.deleteInvite(serverURL: appState.serverURL, token: token, inviteId: invite.id)
            if let resp = response {
                response = InvitesResponse(
                    openRegistration: resp.openRegistration,
                    invites: resp.invites.filter { $0.id != invite.id }
                )
            }
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func setOpenReg(_ enabled: Bool) async {
        guard let token = appState.token else { return }
        do {
            try await APIService.shared.setOpenRegistration(serverURL: appState.serverURL, token: token, enabled: enabled)
            if let resp = response {
                response = InvitesResponse(openRegistration: enabled, invites: resp.invites)
            }
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

private struct InviteRowView: View {
    let invite: InviteCode
    let copied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    private var statusColor: Color {
        if invite.usedBy != nil { return .arcticMuted }
        if invite.expired { return .red }
        return .green
    }

    private var statusLabel: String {
        if let used = invite.usedBy { return "Used by \(used)" }
        if invite.expired { return "Expired" }
        return "Available"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(invite.code)
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundColor(.arcticText)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                }
                Text(statusLabel)
                    .font(.caption).foregroundColor(.arcticMuted)
                if let by = invite.createdBy {
                    Text("Created by \(by)").font(.caption2).foregroundColor(.arcticMuted)
                }
            }

            Spacer()

            if invite.usedBy == nil && !invite.expired {
                Button(action: onCopy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline)
                        .foregroundColor(copied ? .green : .arcticPrimary)
                }
                .buttonStyle(.plain)
            }

            Button(action: onDelete) {
                Image(systemName: "trash").font(.subheadline).foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
