import SwiftUI

struct AdminLiveView: View {
    @EnvironmentObject var appState: AppState
    @State private var response: LiveViewerResponse?
    @State private var loading = true
    @State private var error: String?
    @State private var refreshTimer: Timer?

    var body: some View {
        ZStack {
            Color.arcticBg.ignoresSafeArea()
            Group {
                if loading && response == nil {
                    ProgressView().tint(.arcticPrimary)
                } else if let err = error {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.slash").font(.largeTitle).foregroundColor(.arcticMuted)
                        Text(err).foregroundColor(.arcticSub).multilineTextAlignment(.center).padding(.horizontal)
                    }
                } else {
                    content
                }
            }
        }
        .navigationTitle("Live Viewers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Active count header
                let viewers = response?.viewers ?? []
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(viewers.count) Active")
                            .font(.title2.bold()).foregroundColor(.arcticText)
                        Text("Updates every 10s")
                            .font(.caption).foregroundColor(.arcticMuted)
                    }
                    Spacer()
                    Circle()
                        .fill(viewers.isEmpty ? Color.arcticMuted : Color.green)
                        .frame(width: 10, height: 10)
                        .overlay(
                            viewers.isEmpty ? nil :
                            Circle().stroke(Color.green.opacity(0.4), lineWidth: 4)
                        )
                }
                .padding(.horizontal)
                .padding(.top, 8)

                if viewers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tv.slash").font(.largeTitle).foregroundColor(.arcticMuted)
                        Text("No one is watching right now").foregroundColor(.arcticSub)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(viewers) { viewer in
                        LiveViewerCard(viewer: viewer)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func load() async {
        guard let token = appState.token else { return }
        do {
            response = try await APIService.shared.liveViewers(serverURL: appState.serverURL, token: token)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { await load() }
        }
    }

    private func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

private struct LiveViewerCard: View {
    @EnvironmentObject var appState: AppState
    let viewer: LiveViewer

    var body: some View {
        HStack(spacing: 12) {
            PosterImageView(url: viewer.posterUrl, serverURL: appState.serverURL)
                .frame(width: 56, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(viewer.username)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.arcticText)
                    Spacer()
                    Text(viewer.secondsAgo < 60 ? "\(viewer.secondsAgo)s ago" : "\(viewer.secondsAgo / 60)m ago")
                        .font(.caption2).foregroundColor(.arcticMuted)
                }

                Text(viewer.displayTitle)
                    .font(.subheadline).foregroundColor(.arcticText).lineLimit(1)

                if let ep = viewer.epLabel {
                    Text(ep).font(.caption).foregroundColor(.arcticPrimary)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.arcticBorder).frame(height: 4)
                        RoundedRectangle(cornerRadius: 2).fill(Color.arcticPrimary)
                            .frame(width: geo.size.width * CGFloat(viewer.progressPct) / 100, height: 4)
                    }
                }
                .frame(height: 4)

                HStack(spacing: 4) {
                    Text(viewer.positionFmt)
                    if let dur = viewer.durationFmt { Text("/ \(dur)") }
                    Spacer()
                    Image(systemName: deviceIcon(viewer.device.type))
                        .font(.caption2)
                    Text(viewer.device.label).font(.caption2)
                }
                .foregroundColor(.arcticMuted)
                .font(.caption2)
            }
        }
        .padding(12)
        .background(Color.arcticSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func deviceIcon(_ type: String) -> String {
        switch type {
        case "tv": return "tv"
        case "mobile": return "iphone"
        case "tablet": return "ipad"
        default: return "desktopcomputer"
        }
    }
}
