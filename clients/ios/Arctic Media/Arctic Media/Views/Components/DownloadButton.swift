import SwiftUI

/// Reusable download button.
/// compact=true → icon only (for episode rows)
/// compact=false → full-width labeled button (for movie detail)
struct DownloadButton: View {
    let mediaId: Int
    let title: String
    let posterUrl: String?
    let kind: String
    let episodeLabel: String?
    var compact: Bool = true

    @EnvironmentObject var appState: AppState
    @ObservedObject private var dm = DownloadManager.shared

    @State private var showAlert = false
    @State private var estimatedBytes: Int64 = 0
    @State private var availableBytes: Int64 = 0
    @State private var isFetching = false

    // MARK: - Body

    var body: some View {
        Button(action: handleTap) {
            if dm.isDownloading(mediaId) {
                downloadingIndicator
            } else if dm.isDownloaded(mediaId) {
                downloadedIndicator
            } else {
                idleIndicator
            }
        }
        .buttonStyle(.plain)
        .disabled(isFetching)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Download") { confirmDownload() }
        } message: {
            Text(alertBody)
        }
        // Show download errors inline
        .onChange(of: dm.activeErrors[mediaId]) { _, err in
            if err != nil { dm.activeErrors.removeValue(forKey: mediaId) }
        }
    }

    // MARK: - Indicator views

    @ViewBuilder
    private var downloadingIndicator: some View {
        let progress = dm.activeProgress[mediaId] ?? 0
        if compact {
            ZStack {
                Circle().stroke(Color.arcticBorder, lineWidth: 2).frame(width: 26, height: 26)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Color.arcticPrimary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 26, height: 26)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.arcticMuted)
            }
        } else {
            HStack(spacing: 12) {
                ProgressView(value: progress).tint(.arcticPrimary).frame(maxWidth: .infinity)
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.arcticMuted)
                    .frame(width: 36)
                Image(systemName: "xmark.circle.fill").foregroundColor(.arcticMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(Color.arcticSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.arcticBorder, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var downloadedIndicator: some View {
        if compact {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(.green)
        } else {
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity).padding(14)
                .background(Color.arcticSurface)
                .foregroundColor(.green)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.4), lineWidth: 1))
        }
    }

    @ViewBuilder
    private var idleIndicator: some View {
        if compact {
            Image(systemName: isFetching ? "hourglass" : "arrow.down.circle")
                .font(.system(size: 22))
                .foregroundColor(isFetching ? .arcticMuted : .arcticPrimary)
        } else {
            Label(isFetching ? "Checking…" : "Download",
                  systemImage: isFetching ? "hourglass" : "arrow.down.circle")
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity).padding(14)
                .background(Color.arcticSurface)
                .foregroundColor(isFetching ? .arcticMuted : .arcticText)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.arcticBorder, lineWidth: 1))
        }
    }

    // MARK: - Actions

    private func handleTap() {
        if dm.isDownloading(mediaId) {
            dm.cancelDownload(mediaId)
        } else if !dm.isDownloaded(mediaId) {
            Task { await startDownloadFlow() }
        }
        // If already downloaded, do nothing (delete via Downloads tab swipe)
    }

    private func startDownloadFlow() async {
        guard let token = appState.token else { return }
        isFetching = true
        let info = try? await APIService.shared.streamInfo(
            serverURL: appState.serverURL, token: token, mediaId: mediaId)
        isFetching = false

        let duration = info?.duration ?? 5400.0   // fallback: 90 min
        estimatedBytes = DownloadManager.estimatedBytes(durationSeconds: duration)
        availableBytes = DownloadManager.availableStorageBytes()
        showAlert = true
    }

    private func confirmDownload() {
        guard let token = appState.token,
              let url = APIService.shared.hlsURL(
                serverURL: appState.serverURL, token: token, mediaId: mediaId)
        else { return }
        DownloadManager.shared.startDownload(
            mediaId: mediaId, title: title, posterUrl: posterUrl,
            kind: kind, episodeLabel: episodeLabel, hlsURL: url)
    }

    // MARK: - Alert strings

    private var alertTitle: String { "Download \"\(title)\"?" }

    private var alertBody: String {
        let est = DownloadManager.formatBytes(estimatedBytes)
        let avail = DownloadManager.formatBytes(availableBytes)
        var msg = "Estimated size: ~\(est)\nAvailable storage: \(avail)"
        if estimatedBytes > availableBytes {
            msg += "\n\n⚠️ You may not have enough free space."
        }
        return msg
    }
}
