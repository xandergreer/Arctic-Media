import SwiftUI

struct LoginView: View {
    @EnvironmentObject var api: APIService
    @State private var username = ""
    @State private var password = ""
    @State private var serverURL = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingServerField = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.1, green: 0.1, blue: 0.25)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                VStack(spacing: 12) {
                    Image(systemName: "snowflake")
                        .font(.system(size: 60, weight: .ultraLight))
                        .foregroundStyle(.white)
                    Text("Arctic Media")
                        .font(.system(size: 32, weight: .thin, design: .default))
                        .foregroundStyle(.white)
                    Text("Your personal media server")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 48)

                // Form card
                VStack(spacing: 16) {
                    // Server URL toggle
                    HStack {
                        Text("Server")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Button(showingServerField ? "Hide" : "Change") {
                            showingServerField.toggle()
                            if showingServerField { serverURL = api.serverURL }
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }

                    if showingServerField {
                        TextField("http://192.168.1.x:8085", text: $serverURL)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            #endif
                            .padding()
                            .background(.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.white.opacity(0.15), lineWidth: 1)
                            )
                    }

                    // Username
                    TextField("Username", text: $username)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .padding()
                        .background(.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )

                    // Password
                    SecureField("Password", text: $password)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )

                    // Error
                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }

                    // Sign in button
                    Button(action: login) {
                        ZStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Sign In")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(isLoading || username.isEmpty || password.isEmpty)
                }
                .padding(24)
                .background(.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }

    private func login() {
        isLoading = true
        errorMessage = nil

        if showingServerField && !serverURL.isEmpty {
            api.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        Task {
            do {
                try await api.login(username: username, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    LoginView().environmentObject(APIService.shared)
}
