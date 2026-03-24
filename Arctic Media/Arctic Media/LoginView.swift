import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var api: APIService

    @State private var serverURL = ""
    @State private var username  = ""
    @State private var password  = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("http://192.168.1.x:8000", text: $serverURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Account") {
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $password)
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Sign In")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isLoading || username.isEmpty || password.isEmpty || serverURL.isEmpty)
                }
            }
            .navigationTitle("Arctic Media")
            .onAppear { serverURL = api.serverURL }
        }
    }

    private func signIn() async {
        isLoading = true
        error = nil
        api.serverURL = serverURL
        do {
            try await api.login(username: username, password: password)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
