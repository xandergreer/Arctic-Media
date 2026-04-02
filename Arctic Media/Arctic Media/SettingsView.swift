import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var api: APIService
    @State private var serverURLDraft = ""
    @State private var showLogoutConfirm = false
    @State private var scanStatus: ScanStatus?
    @State private var scanPolling: Task<Void, Never>?
    @State private var scanError: String?

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

            if api.isAdmin {
                Section("Libraries") {
                    Button {
                        Task { await triggerScan() }
                    } label: {
                        HStack {
                            Label("Scan Libraries", systemImage: "arrow.clockwise")
                            Spacer()
                            if scanStatus?.scanning == true {
                                ProgressView().scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(scanStatus?.scanning == true)

                    if let status = scanStatus {
                        ForEach(status.libraries) { lib in
                            LibraryScanRow(lib: lib)
                        }
                    }

                    if let err = scanError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    showLogoutConfirm = true
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            serverURLDraft = api.serverURL
            if api.isAdmin { Task { await refreshScanStatus() } }
        }
        .onDisappear { scanPolling?.cancel() }
        .confirmationDialog("Sign out of Arctic Media?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { api.logout() }
        }
    }

    private func triggerScan() async {
        scanError = nil
        do {
            try await api.startScan()
            await pollUntilDone()
        } catch {
            scanError = error.localizedDescription
        }
    }

    private func refreshScanStatus() async {
        scanStatus = try? await api.getScanStatus()
        if scanStatus?.scanning == true {
            await pollUntilDone()
        }
    }

    private func pollUntilDone() async {
        scanPolling?.cancel()
        scanPolling = Task {
            repeat {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                scanStatus = try? await api.getScanStatus()
            } while scanStatus?.scanning == true && !Task.isCancelled
        }
        await scanPolling?.value
    }
}

// MARK: - Library row

private struct LibraryScanRow: View {
    let lib: LibraryScanState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lib.library_name).font(.subheadline)
                Text(lib.status.capitalized)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            Spacer()
            if lib.status == "running" {
                ProgressView().scaleEffect(0.7)
            } else if lib.status == "done" {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if lib.status == "error" {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch lib.status {
        case "running": return .blue
        case "done":    return .green
        case "error":   return .red
        default:        return .secondary
        }
    }
}
