import SwiftUI

struct AdminHistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var stats: HistoryStats?
    @State private var loading = true

    var body: some View {
        ZStack {
            Color.arcticBg.ignoresSafeArea()
            if loading {
                ProgressView().tint(.arcticPrimary)
            } else if let s = stats {
                content(s)
            }
        }
        .navigationTitle("Watch History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ s: HistoryStats) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                totalsSection(s.totals)
                mostWatchedSection(s)
                usersSection(s.users)
                Spacer(minLength: 20)
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func totalsSection(_ t: HistoryTotals) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Overview")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                HistoryStatTile(label: "Total Watch Time", value: formatTime(t.totalSeconds), icon: "clock.fill")
                HistoryStatTile(label: "Total Plays", value: "\(t.totalPlays)", icon: "play.fill")
                HistoryStatTile(label: "Completed", value: "\(t.totalCompleted)", icon: "checkmark.circle.fill")
                HistoryStatTile(label: "Watchers", value: "\(t.uniqueWatchers)", icon: "person.2.fill")
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func mostWatchedSection(_ s: HistoryStats) -> some View {
        if !s.mostWatchedMovies.isEmpty || !s.mostWatchedShows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Most Watched")

                if !s.mostWatchedMovies.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Movies")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.arcticMuted)
                            .padding(.horizontal)
                        ForEach(s.mostWatchedMovies.prefix(5)) { item in
                            TopItemRow(
                                title: item.title,
                                posterUrl: item.posterUrl,
                                badge: "\(item.playCount) plays"
                            )
                        }
                    }
                }

                if !s.mostWatchedShows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TV Shows")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.arcticMuted)
                            .padding(.horizontal)
                        ForEach(s.mostWatchedShows.prefix(5)) { show in
                            TopItemRow(
                                title: show.title,
                                posterUrl: show.posterUrl,
                                badge: "\(show.epCount) eps"
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func usersSection(_ users: [UserHistory]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Per-User History")
            ForEach(users) { userHist in
                UserHistoryCard(userHistory: userHist)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(.arcticMuted)
            .textCase(.uppercase)
            .padding(.horizontal)
    }

    private func load() async {
        guard let token = appState.token else { return }
        stats = try? await APIService.shared.adminHistory(serverURL: appState.serverURL, token: token)
        loading = false
    }

    private func formatTime(_ secs: Int) -> String {
        let h = secs / 3600
        if h < 1 { return "\((secs % 3600) / 60)m" }
        if h < 24 { return "\(h)h" }
        return "\(h / 24)d \(h % 24)h"
    }
}

private struct HistoryStatTile: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3).foregroundColor(.arcticPrimary).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.headline).foregroundColor(.arcticText)
                Text(label).font(.caption).foregroundColor(.arcticMuted).lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.arcticSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct TopItemRow: View {
    @EnvironmentObject var appState: AppState
    let title: String
    let posterUrl: String?
    let badge: String

    var body: some View {
        HStack(spacing: 10) {
            PosterImageView(url: posterUrl, serverURL: appState.serverURL)
                .frame(width: 36, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(title)
                .font(.subheadline).foregroundColor(.arcticText).lineLimit(2)
            Spacer()
            Text(badge)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.arcticPrimary.opacity(0.15))
                .foregroundColor(.arcticPrimary)
                .clipShape(Capsule())
        }
        .padding(.horizontal)
    }
}

private struct UserHistoryCard: View {
    @EnvironmentObject var appState: AppState
    let userHistory: UserHistory
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }) {
                HStack {
                    ZStack {
                        Circle().fill(Color.arcticPrimary.opacity(0.15)).frame(width: 40, height: 40)
                        Text(String(userHistory.username.prefix(1)).uppercased())
                            .font(.headline.bold()).foregroundColor(.arcticPrimary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(userHistory.username)
                            .font(.subheadline.weight(.semibold)).foregroundColor(.arcticText)
                        Text("\(userHistory.itemCount) items · \(formatTime(userHistory.totalSeconds))")
                            .font(.caption).foregroundColor(.arcticMuted)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundColor(.arcticMuted)
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().background(Color.arcticBorder)
                VStack(spacing: 0) {
                    ForEach(userHistory.history.prefix(10)) { item in
                        HistoryItemRow(item: item)
                        if item.id != userHistory.history.prefix(10).last?.id {
                            Divider().background(Color.arcticBorder).padding(.leading, 58)
                        }
                    }
                }
            }
        }
        .background(Color.arcticSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    private func formatTime(_ secs: Int) -> String {
        let h = secs / 3600
        if h < 1 { return "\((secs % 3600) / 60)m" }
        return "\(h)h"
    }
}

private struct HistoryItemRow: View {
    @EnvironmentObject var appState: AppState
    let item: HistoryItem

    var body: some View {
        HStack(spacing: 10) {
            PosterImageView(url: item.posterUrl, serverURL: appState.serverURL)
                .frame(width: 46, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(.caption.weight(.semibold)).foregroundColor(.arcticText).lineLimit(1)
                    if let ep = item.epLabel {
                        Text(ep).font(.caption2).foregroundColor(.arcticPrimary)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1).fill(Color.arcticBorder).frame(height: 2)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(item.completed ? Color.green : Color.arcticPrimary)
                            .frame(width: geo.size.width * CGFloat(item.progressPct) / 100, height: 2)
                    }
                }
                .frame(height: 2)
            }

            Spacer()

            if item.completed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption).foregroundColor(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
