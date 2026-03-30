import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var appState: AppState
    let kind: MediaKind

    @State private var items: [MediaItem] = []
    @State private var loading = true
    @State private var error: String?
    @State private var sort: SortOption = .newest
    @State private var showRequest = false

    enum SortOption: String, CaseIterable, Identifiable {
        case newest = "Newly Added"
        case az     = "A → Z"
        case year   = "Year"
        var id: String { rawValue }
    }

    private var sorted: [MediaItem] {
        switch sort {
        case .newest: return items
        case .az:     return items.sorted { ($0.sortTitle ?? $0.title) < ($1.sortTitle ?? $1.title) }
        case .year:   return items.sorted { ($0.year ?? "") > ($1.year ?? "") }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 12)]

    var body: some View {
        ZStack {
            Color.arcticBg.ignoresSafeArea()

            if loading {
                ProgressView().tint(.arcticPrimary)
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundColor(.arcticMuted)
                    Text(error).font(.caption).foregroundColor(.arcticSub)
                    Button("Retry") { Task { await load() } }.foregroundColor(.arcticPrimary)
                }
            } else if sorted.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: kind == .movie ? "film" : "tv")
                        .font(.largeTitle).foregroundColor(.arcticMuted)
                    Text("No \(kind == .movie ? "movies" : "TV shows") found.\nAdd a library in Settings.")
                        .foregroundColor(.arcticSub)
                        .multilineTextAlignment(.center)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(sorted) { item in
                            NavigationLink(destination: MediaDetailView(item: item)) {
                                MediaCardView(item: item, serverURL: appState.serverURL)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle(kind == .movie ? "Movies" : "TV Shows")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.arcticBg, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showRequest = true
                } label: {
                    Label("Request", systemImage: "plus.circle")
                        .foregroundColor(.arcticPrimary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                        .foregroundColor(.arcticPrimary)
                }
            }
        }
        .sheet(isPresented: $showRequest) {
            RequestSheetView(kind: kind)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true; error = nil
        do {
            items = try await (kind == .movie
                ? APIService.shared.movies(serverURL: appState.serverURL, token: appState.token ?? "")
                : APIService.shared.shows(serverURL: appState.serverURL, token: appState.token ?? ""))
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
