import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var recent: RecentlyAdded?
    @State private var error: String?
    @State private var loading = true

    let cardWidth: CGFloat = 130

    var body: some View {
        ZStack {
                Color.arcticBg.ignoresSafeArea()

                if loading {
                    ProgressView().tint(.arcticPrimary)
                } else if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.arcticMuted)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.arcticSub)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                            .foregroundColor(.arcticPrimary)
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 32) {
                            // Hero greeting
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Recently Added")
                                    .font(.largeTitle.bold())
                                    .foregroundColor(.arcticText)
                                Text("Jump back in or discover something new.")
                                    .font(.subheadline)
                                    .foregroundColor(.arcticSub)
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)

                            if let movies = recent?.movies, !movies.isEmpty {
                                shelf(title: "Movies", items: movies)
                            }

                            if let shows = recent?.shows, !shows.isEmpty {
                                shelf(title: "TV Shows", items: shows)
                            }

                            if (recent?.movies.isEmpty ?? true) && (recent?.shows.isEmpty ?? true) {
                                VStack(spacing: 12) {
                                    Image(systemName: "tray")
                                        .font(.largeTitle)
                                        .foregroundColor(.arcticMuted)
                                    Text("No content yet.\nAdd a library in Settings.")
                                        .font(.body)
                                        .foregroundColor(.arcticSub)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ARCTIC MEDIA")
                    .font(.system(size: 15, weight: .black))
                    .tracking(2)
                    .foregroundColor(.arcticText)
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func shelf(title: String, items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .foregroundColor(.arcticText)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(destination: MediaDetailView(item: item)) {
                            MediaCardView(item: item, serverURL: appState.serverURL)
                                .frame(width: cardWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            recent = try await APIService.shared.recentlyAdded(
                serverURL: appState.serverURL,
                token: appState.token ?? ""
            )
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
