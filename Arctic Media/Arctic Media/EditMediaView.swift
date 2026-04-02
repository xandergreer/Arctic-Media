import SwiftUI

struct EditMediaView: View {
    let item: MediaItem

    @EnvironmentObject private var api: APIService
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var overview: String = ""
    @State private var posterURL: String = ""
    @State private var tmdbId: String = ""
    @State private var refreshFromTMDB = false
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }

                Section("Overview") {
                    TextEditor(text: $overview)
                        .frame(minHeight: 100)
                }

                Section("Artwork") {
                    TextField("Poster URL", text: $posterURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }

                Section("TMDB") {
                    TextField("TMDB ID", text: $tmdbId)
                        .keyboardType(.numberPad)
                    Toggle("Refresh from TMDB", isOn: $refreshFromTMDB)
                }

                if let err = saveError {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .onAppear { populate() }
        }
    }

    private func populate() {
        title = item.title
        overview = item.overview ?? ""
        posterURL = item.poster_url ?? ""
        tmdbId = item.tmdb_id.map { String($0) } ?? ""
    }

    private func save() async {
        isSaving = true
        saveError = nil
        let update = MediaUpdate(
            title: title.isEmpty ? nil : title,
            overview: overview.isEmpty ? nil : overview,
            poster_url: posterURL.isEmpty ? nil : posterURL,
            tmdb_id: Int(tmdbId),
            refresh_from_tmdb: refreshFromTMDB ? true : nil
        )
        do {
            _ = try await api.updateMedia(id: item.id, update: update)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
