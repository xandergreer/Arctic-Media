import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var loading = false

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
                        Text("Welcome back")
                            .font(.title3.bold())
                            .foregroundColor(.arcticText)
                        Text("Sign in to your Arctic Media account.")
                            .font(.subheadline)
                            .foregroundColor(.arcticSub)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("USERNAME")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.arcticMuted)
                            .tracking(1)
                        TextField("", text: $username)
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PASSWORD")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.arcticMuted)
                            .tracking(1)
                        SecureField("", text: $password)
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

                    Button(action: login) {
                        Group {
                            if loading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Sign In")
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.arcticPrimary)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: Color.arcticPrimary.opacity(0.35), radius: 10, y: 4)
                    }
                    .disabled(loading)

                    Button("Change Server") {
                        appState.setServer("")
                    }
                    .font(.footnote)
                    .foregroundColor(.arcticMuted)
                    .frame(maxWidth: .infinity)
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

    private func login() {
        guard !username.isEmpty, !password.isEmpty else {
            error = "Please enter your username and password."
            return
        }
        error = nil
        loading = true
        Task {
            do {
                let resp = try await APIService.shared.login(
                    serverURL: appState.serverURL,
                    username: username,
                    password: password
                )
                await MainActor.run {
                    appState.login(token: resp.accessToken)
                    loading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    loading = false
                }
            }
        }
    }
}
