import SwiftUI

struct AdminRequestsView: View {
    @EnvironmentObject var appState: AppState

    @State private var requests: [MediaRequest] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.arcticBg.ignoresSafeArea()

            if loading {
                ProgressView().tint(.arcticPrimary)
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.arcticMuted)
                    Text(error).font(.caption).foregroundColor(.arcticSub)
                    Button("Retry") { Task { await load() } }.foregroundColor(.arcticPrimary)
                }
            } else if requests.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.largeTitle).foregroundColor(.arcticMuted)
                    Text("No requests yet.").foregroundColor(.arcticSub)
                }
            } else {
                List {
                    ForEach(requests) { req in
                        RequestRowView(request: req) { newStatus in
                            await updateStatus(req, status: newStatus)
                        }
                        .listRowBackground(Color.arcticSurface)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Requests")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        loading = true; error = nil
        do {
            requests = try await APIService.shared.adminRequests(
                serverURL: appState.serverURL, token: appState.token ?? "")
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func updateStatus(_ req: MediaRequest, status: String) async {
        guard let token = appState.token else { return }
        do {
            let updated = try await APIService.shared.updateRequestStatus(
                serverURL: appState.serverURL, token: token,
                requestId: req.id, status: status)
            if let idx = requests.firstIndex(where: { $0.id == req.id }) {
                requests[idx] = updated
            }
        } catch {}
    }
}

// MARK: - Row

private struct RequestRowView: View {
    let request: MediaRequest
    let onStatusChange: (String) async -> Void

    private var statusColor: Color {
        switch request.status {
        case "acknowledged": return .orange
        case "fulfilled":    return .green
        default:             return .arcticMuted
        }
    }

    private var statusLabel: String {
        switch request.status {
        case "acknowledged": return "Acknowledged"
        case "fulfilled":    return "Fulfilled"
        default:             return "Pending"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(request.username)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.arcticPrimary)
                Spacer()
                Text(statusLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            Text(request.message)
                .font(.subheadline)
                .foregroundColor(.arcticText)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(formattedDate(request.createdAt))
                    .font(.caption2)
                    .foregroundColor(.arcticMuted)
                Spacer()
                if request.status == "pending" {
                    Button("Acknowledge") { Task { await onStatusChange("acknowledged") } }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                } else if request.status == "acknowledged" {
                    Button("Mark Fulfilled") { Task { await onStatusChange("fulfilled") } }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ??
              ISO8601DateFormatter().date(from: iso) else { return iso }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .full
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
