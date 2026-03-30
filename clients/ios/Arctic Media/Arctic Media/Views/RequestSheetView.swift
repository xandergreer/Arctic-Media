import SwiftUI

struct RequestSheetView: View {
    let kind: MediaKind

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    @State private var sending = false
    @State private var sent = false
    @State private var errorMsg: String?

    private var kindLabel: String { kind == .movie ? "movie" : "TV show" }
    private var placeholder: String { "Describe the \(kindLabel) you'd like added…" }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.arcticBg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    if sent {
                        sentConfirmation
                    } else {
                        requestForm
                    }
                }
                .padding()
            }
            .navigationTitle("Make a Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.arcticSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.arcticMuted)
                }
                if !sent {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Send") { Task { await submit() } }
                            .foregroundColor(.arcticPrimary)
                            .fontWeight(.semibold)
                            .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var requestForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What \(kindLabel) would you like us to add?")
                .font(.subheadline)
                .foregroundColor(.arcticSub)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.arcticSurface)

                if message.isEmpty {
                    Text(placeholder)
                        .foregroundColor(.arcticMuted)
                        .padding(12)
                }

                TextEditor(text: $message)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(.arcticText)
                    .padding(8)
                    .frame(minHeight: 120, maxHeight: 200)
            }
            .frame(minHeight: 120)

            if let err = errorMsg {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if sending {
                HStack { Spacer(); ProgressView().tint(.arcticPrimary); Spacer() }
            }

            Spacer()
        }
    }

    private var sentConfirmation: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.arcticPrimary)
            Text("Request Sent!")
                .font(.title2.weight(.bold))
                .foregroundColor(.arcticText)
            Text("Your request has been sent to the admin.")
                .font(.subheadline)
                .foregroundColor(.arcticSub)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .padding(.horizontal, 40).padding(.vertical, 12)
                .background(Color.arcticPrimary)
                .foregroundColor(.white)
                .clipShape(Capsule())
                .fontWeight(.semibold)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Submit

    private func submit() async {
        let trimmed = message.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let token = appState.token else { return }
        sending = true
        errorMsg = nil
        do {
            try await APIService.shared.submitRequest(
                serverURL: appState.serverURL, token: token, message: trimmed)
            withAnimation { sent = true }
        } catch {
            errorMsg = error.localizedDescription
        }
        sending = false
    }
}
