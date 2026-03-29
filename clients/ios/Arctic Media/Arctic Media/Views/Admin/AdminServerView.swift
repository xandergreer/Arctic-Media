import SwiftUI

struct AdminServerView: View {
    @EnvironmentObject var appState: AppState
    @State private var metrics: ServerMetrics?
    @State private var stats: ServerStatsResponse?
    @State private var scanStatus: ScanStatusResponse?
    @State private var loading = true
    @State private var metricsTimer: Timer?
    @State private var scanMessage: String?

    var body: some View {
        ZStack {
            Color.arcticBg.ignoresSafeArea()
            if loading && stats == nil {
                ProgressView().tint(.arcticPrimary)
            } else {
                content
            }
        }
        .navigationTitle("Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { Task { await scanAll() } }) {
                    Label("Scan All", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
        .task {
            await loadAll()
        }
        .onAppear { startMetricsPolling() }
        .onDisappear { stopMetricsPolling() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Live metrics
                if let m = metrics, m.available {
                    liveMetricsSection(m)
                }

                // Scan status
                if let scan = scanStatus, scan.scanning {
                    scanStatusSection(scan)
                }

                // Scan message
                if let msg = scanMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text(msg).font(.subheadline).foregroundColor(.arcticSub)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.arcticSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                }

                // Totals
                if let s = stats {
                    totalsSection(s)
                    librariesSection(s)
                }

                Spacer(minLength: 20)
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func liveMetricsSection(_ m: ServerMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Metrics")
                .font(.caption.weight(.semibold))
                .foregroundColor(.arcticMuted)
                .textCase(.uppercase)
                .padding(.horizontal)

            HStack(spacing: 12) {
                MetricGaugeCard(
                    title: "CPU",
                    value: m.cpuPct ?? 0,
                    max: 100,
                    unit: "%",
                    color: gaugeColor(m.cpuPct ?? 0, warn: 70, crit: 90)
                )
                MetricGaugeCard(
                    title: "RAM",
                    value: m.memPct ?? 0,
                    max: 100,
                    unit: "%",
                    color: gaugeColor(m.memPct ?? 0, warn: 70, crit: 90)
                )
            }
            .padding(.horizontal)

            if let uptime = m.uptimeSeconds {
                HStack {
                    Image(systemName: "clock").foregroundColor(.arcticMuted)
                    Text("Uptime: \(formatUptime(uptime))")
                        .font(.subheadline).foregroundColor(.arcticSub)
                    Spacer()
                    if let cores = m.cpuCoresLogical {
                        Text("\(cores) cores")
                            .font(.caption).foregroundColor(.arcticMuted)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func scanStatusSection(_ scan: ScanStatusResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan in Progress")
                .font(.caption.weight(.semibold))
                .foregroundColor(.arcticMuted)
                .textCase(.uppercase)
                .padding(.horizontal)

            ForEach(scan.libraries) { lib in
                HStack(spacing: 10) {
                    scanIcon(lib.status)
                    Text(lib.name).font(.subheadline).foregroundColor(.arcticText)
                    Spacer()
                    Text(lib.status.capitalized)
                        .font(.caption).foregroundColor(scanColor(lib.status))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.arcticSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private func totalsSection(_ s: ServerStatsResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Library Totals")
                .font(.caption.weight(.semibold))
                .foregroundColor(.arcticMuted)
                .textCase(.uppercase)
                .padding(.horizontal)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTileView(label: "Movies", value: "\(s.totals.movies)", icon: "film.fill")
                StatTileView(label: "Shows", value: "\(s.totals.shows)", icon: "tv.fill")
                StatTileView(label: "Episodes", value: "\(s.totals.episodes)", icon: "play.square.stack.fill")
                StatTileView(label: "Storage", value: formatBytes(s.totals.totalBytes), icon: "internaldrive.fill")
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func librariesSection(_ s: ServerStatsResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Libraries")
                .font(.caption.weight(.semibold))
                .foregroundColor(.arcticMuted)
                .textCase(.uppercase)
                .padding(.horizontal)

            ForEach(s.libraries) { lib in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: lib.type == "movies" ? "film.fill" : "tv.fill")
                            .foregroundColor(.arcticPrimary)
                        Text(lib.name).font(.subheadline.weight(.semibold)).foregroundColor(.arcticText)
                        Spacer()
                        Text(formatBytes(lib.totalBytes))
                            .font(.caption).foregroundColor(.arcticMuted)
                    }

                    HStack(spacing: 16) {
                        if lib.type == "movies" {
                            Text("\(lib.movieCount) movies")
                        } else {
                            Text("\(lib.showCount) shows")
                            Text("\(lib.episodeCount) eps")
                        }
                        Spacer()
                        Text("\(lib.fileCount) files")
                    }
                    .font(.caption).foregroundColor(.arcticSub)

                    if let disk = lib.disk {
                        let pct = Double(disk.usedBytes) / Double(disk.totalBytes)
                        VStack(alignment: .leading, spacing: 3) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(Color.arcticBorder).frame(height: 4)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(pct > 0.9 ? Color.red : pct > 0.75 ? Color.orange : Color.arcticPrimary)
                                        .frame(width: geo.size.width * min(pct, 1.0), height: 4)
                                }
                            }
                            .frame(height: 4)
                            HStack {
                                Text("Disk: \(formatBytes(disk.usedBytes)) / \(formatBytes(disk.totalBytes))")
                                Spacer()
                                Text(String(format: "%.0f%%", pct * 100))
                            }
                            .font(.caption2).foregroundColor(.arcticMuted)
                        }
                    }
                }
                .padding(12)
                .background(Color.arcticSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Actions

    private func scanAll() async {
        guard let token = appState.token else { return }
        scanMessage = nil
        do {
            try await APIService.shared.scanAll(serverURL: appState.serverURL, token: token)
            scanMessage = "Scan started successfully."
            await loadScanStatus()
        } catch {
            scanMessage = "Scan failed: \(error.localizedDescription)"
        }
    }

    private func loadAll() async {
        async let metricsResult = loadMetrics()
        async let statsResult = loadStats()
        async let scanResult = loadScanStatus()
        _ = await (metricsResult, statsResult, scanResult)
        loading = false
    }

    private func loadMetrics() async {
        guard let token = appState.token else { return }
        metrics = try? await APIService.shared.serverMetrics(serverURL: appState.serverURL, token: token)
    }

    private func loadStats() async {
        guard let token = appState.token else { return }
        stats = try? await APIService.shared.serverStats(serverURL: appState.serverURL, token: token)
    }

    private func loadScanStatus() async {
        guard let token = appState.token else { return }
        scanStatus = try? await APIService.shared.scanStatus(serverURL: appState.serverURL, token: token)
    }

    private func startMetricsPolling() {
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { await loadMetrics() }
        }
    }

    private func stopMetricsPolling() {
        metricsTimer?.invalidate()
        metricsTimer = nil
    }

    // MARK: - Helpers

    private func gaugeColor(_ val: Double, warn: Double, crit: Double) -> Color {
        val >= crit ? .red : val >= warn ? .orange : .arcticPrimary
    }

    private func scanColor(_ status: String) -> Color {
        switch status {
        case "done": return .green
        case "scanning": return .arcticPrimary
        case "error": return .red
        default: return .arcticMuted
        }
    }

    @ViewBuilder
    private func scanIcon(_ status: String) -> some View {
        switch status {
        case "done":
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case "scanning":
            ProgressView().scaleEffect(0.7).tint(.arcticPrimary)
        case "error":
            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        default:
            Image(systemName: "clock").foregroundColor(.arcticMuted)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return "\(bytes) B"
    }

    private func formatUptime(_ secs: Int) -> String {
        let d = secs / 86400; let h = (secs % 86400) / 3600; let m = (secs % 3600) / 60
        if d > 0 { return "\(d)d \(h)h \(m)m" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

private struct MetricGaugeCard: View {
    let title: String
    let value: Double
    let max: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.arcticMuted)
                .textCase(.uppercase)

            ZStack {
                Circle()
                    .stroke(Color.arcticBorder, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(value / max))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: value)

                VStack(spacing: 2) {
                    Text(String(format: "%.0f", value))
                        .font(.title3.bold()).foregroundColor(.arcticText)
                    Text(unit).font(.caption2).foregroundColor(.arcticMuted)
                }
            }
            .frame(width: 80, height: 80)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.arcticSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct StatTileView: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.arcticPrimary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.headline).foregroundColor(.arcticText)
                Text(label).font(.caption).foregroundColor(.arcticMuted)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.arcticSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
