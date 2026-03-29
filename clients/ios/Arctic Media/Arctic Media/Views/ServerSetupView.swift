import SwiftUI

struct ServerSetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var urlInput = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 80)

                // Logo
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.arcticPrimary.opacity(0.15))
                            .frame(width: 80, height: 80)
                        Image(systemName: "snowflake")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundColor(.arcticPrimary)
                    }
                    Text("ARCTIC MEDIA")
                        .font(.system(size: 26, weight: .black))
                        .tracking(4)
                        .foregroundColor(.arcticText)
                }

                Spacer().frame(height: 48)

                // Card
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect to Server")
                            .font(.title3.bold())
                            .foregroundColor(.arcticText)
                        Text("Enter your Arctic Media server address.")
                            .font(.subheadline)
                            .foregroundColor(.arcticSub)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("SERVER URL")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.arcticMuted)
                            .tracking(1)

                        TextField("http://192.168.1.x:8085", text: $urlInput)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(Color.arcticBg)
                            .foregroundColor(.arcticText)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.arcticBorder, lineWidth: 1)
                            )
                            .tint(.arcticPrimary)
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Button(action: connect) {
                        Text("Connect")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.arcticPrimary)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: Color.arcticPrimary.opacity(0.35), radius: 10, y: 4)
                    }
                }
                .padding(24)
                .background(Color.arcticSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.arcticBorder, lineWidth: 1)
                )
                .padding(.horizontal, 24)

                Spacer().frame(height: 48)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.arcticBg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    private func connect() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Please enter a server URL."
            return
        }
        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            error = "URL must start with http:// or https://"
            return
        }
        error = nil
        appState.setServer(trimmed)
    }
}
