import SwiftUI

struct EditMediaView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let item: MediaItem
    var onSave: ((MediaItem) -> Void)?

    @State private var title: String
    @State private var overview: String
    @State private var posterUrl: String
    @State private var tmdbId: String
    @State private var refreshFromTmdb = false
    @State private var saving = false
    @State private var errorMsg: String?

    init(item: MediaItem, onSave: ((MediaItem) -> Void)? = nil) {
        self.item = item
        self.onSave = onSave
        _title = State(initialValue: item.title)
        _overview = State(initialValue: item.overview ?? "")
        _posterUrl = State(initialValue: item.posterUrl ?? "")
        _tmdbId = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.arcticBg.ignoresSafeArea()
                Form {
                    if let err = errorMsg {
                        Section {
                            Text(err).foregroundColor(.red).font(.subheadline)
                        }
                    }

                    Section("Details") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Title").font(.caption).foregroundColor(.arcticMuted)
                            TextField("Title", text: $title)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Overview").font(.caption).foregroundColor(.arcticMuted)
                            TextEditor(text: $overview)
                                .frame(minHeight: 80)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                        }
                    }

                    Section("Images") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Poster URL").font(.caption).foregroundColor(.arcticMuted)
                            TextField("https://...", text: $posterUrl)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    }

                    Section("TMDB") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TMDB ID").font(.caption).foregroundColor(.arcticMuted)
                            TextField("Leave blank to keep current", text: $tmdbId)
                                .keyboardType(.numberPad)
                        }
                        Toggle("Refresh from TMDB after save", isOn: $refreshFromTmdb)
                            .tint(.arcticPrimary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit \(item.kind == .movie ? "Movie" : "Show")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView().tint(.arcticPrimary)
                    } else {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func save() async {
        guard let token = appState.token else { return }
        saving = true
        errorMsg = nil

        var update = MediaUpdate()
        if title != item.title { update.title = title }
        let newOverview = overview.isEmpty ? nil : overview
        if newOverview != item.overview { update.overview = newOverview }
        let newPoster = posterUrl.isEmpty ? nil : posterUrl
        if newPoster != item.posterUrl { update.posterUrl = newPoster }
        if let id = Int(tmdbId), !tmdbId.isEmpty { update.tmdbId = id }
        if refreshFromTmdb { update.refreshFromTmdb = true }

        do {
            let updated = try await APIService.shared.updateMedia(
                serverURL: appState.serverURL, token: token, mediaId: item.id, update: update)
            onSave?(updated)
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
        saving = false
    }
}
