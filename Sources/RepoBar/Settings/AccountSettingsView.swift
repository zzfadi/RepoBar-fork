import RepoBarCore
import SwiftUI

struct AccountSettingsView: View {
    @Bindable var session: Session
    let appState: AppState
    @State private var clientID = "Iv23liGm2arUyotWSjwJ"
    @State private var clientSecret = ""
    @State private var enterpriseHost = ""
    @State private var hostMode: HostMode = .githubCom
    @State private var validationError: String?
    @State private var tokenValidation: TokenValidationState = .unknown

    var body: some View {
        Form {
            Section("Account") {
                Picker("Host", selection: self.$hostMode) {
                    ForEach(HostMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch self.session.account {
                case let .loggedIn(user):
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Signed in")
                                        .font(.headline)
                                    Text("\(user.username) · \(user.host.host ?? "github.com")")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Log out") {
                                Task {
                                    await self.appState.auth.logout()
                                    self.session.account = .loggedOut
                                    self.session.hasStoredTokens = false
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        if let status = self.tokenStatusText {
                            HStack(spacing: 8) {
                                if self.tokenValidation == .checking {
                                    ProgressView()
                                }
                                Text(status)
                                    .font(.caption)
                                    .foregroundStyle(self.tokenStatusColor)
                            }
                        }
                        HStack(spacing: 8) {
                            Button("Check token") {
                                Task { await self.validateToken() }
                            }
                            .disabled(self.tokenValidation == .checking)
                            Button("Refresh token") {
                                Task { await self.refreshToken() }
                            }
                            .disabled(self.tokenValidation == .checking)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                default:
                    if self.hostMode == .enterprise {
                        LabeledContent("Enterprise Base URL") {
                            TextField("https://ghe.example.com", text: self.$enterpriseHost)
                        }
                        LabeledContent("Client ID") {
                            TextField("", text: self.$clientID)
                        }
                        LabeledContent("Client Secret") {
                            SecureField("", text: self.$clientSecret)
                        }
                        Text("Create an OAuth App in your enterprise server. Callback URL: http://127.0.0.1:53682/callback")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Uses the built-in GitHub.com OAuth app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        if self.session.account == .loggingIn {
                            ProgressView()
                        }
                        Button(self.session.account == .loggingIn ? "Signing in…" : self.hostMode == .enterprise ? "Sign in to Enterprise" : "Sign in to GitHub.com") {
                            self.login()
                        }
                        .disabled(self.session.account == .loggingIn)
                        .buttonStyle(.borderedProminent)
                    }
                    Text("Uses browser-based OAuth. Tokens are stored in the system Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear {
            if let enterprise = self.session.settings.enterpriseHost {
                self.enterpriseHost = enterprise.absoluteString
                self.hostMode = .enterprise
            }
            if self.session.settings.enterpriseHost == nil {
                self.hostMode = .githubCom
                if self.clientID.isEmpty {
                    self.clientID = RepoBarAuthDefaults.clientID
                }
                if self.clientSecret.isEmpty {
                    self.clientSecret = RepoBarAuthDefaults.clientSecret
                }
            }
        }
        .task(id: self.session.account) {
            guard case .loggedIn = self.session.account else {
                self.tokenValidation = .unknown
                return
            }
            await self.validateToken()
        }
    }

    private func login() {
        Task { @MainActor in
            self.session.account = .loggingIn
            let enterpriseURL = self.hostMode == .enterprise ? self.normalizedEnterpriseHost() : nil

            if self.hostMode == .enterprise, let enterpriseURL {
                self.session.settings.enterpriseHost = enterpriseURL
                await self.appState.github.setAPIHost(enterpriseURL.appending(path: "/api/v3"))
                self.session.settings.githubHost = enterpriseURL
                self.validationError = nil
            } else {
                if self.hostMode == .enterprise {
                    self.validationError = "Enterprise Base URL must be a valid https:// URL with a trusted certificate."
                    self.session.account = .loggedOut
                    return
                }
                await self.appState.github.setAPIHost(URL(string: "https://api.github.com")!)
                self.session.settings.githubHost = URL(string: "https://github.com")!
                self.session.settings.enterpriseHost = nil
                self.validationError = nil
            }
            let usingEnterprise = self.session.settings.enterpriseHost != nil
            let effectiveClientID = self.clientID.isEmpty && !usingEnterprise
                ? RepoBarAuthDefaults.clientID
                : self.clientID
            let effectiveClientSecret = self.clientSecret.isEmpty && !usingEnterprise
                ? RepoBarAuthDefaults.clientSecret
                : self.clientSecret
            if usingEnterprise, effectiveClientID.isEmpty || effectiveClientSecret.isEmpty {
                self.validationError = "Client ID and Client Secret are required for enterprise login."
                self.session.account = .loggedOut
                return
            }
            do {
                try await self.appState.auth.login(
                    clientID: effectiveClientID,
                    clientSecret: effectiveClientSecret,
                    host: self.session.settings.enterpriseHost ?? self.session.settings.githubHost,
                    loopbackPort: self.session.settings.loopbackPort
                )
                self.session.hasStoredTokens = true
                if let user = try? await appState.github.currentUser() {
                    self.session.account = .loggedIn(user)
                    self.session.lastError = nil
                } else {
                    self.session.account = .loggedIn(UserIdentity(username: "", host: self.session.settings.githubHost))
                }
                await self.appState.refresh()
            } catch {
                self.session.account = .loggedOut
                self.session.lastError = error.userFacingMessage
            }
        }
    }

    private func normalizedEnterpriseHost() -> URL? {
        guard !self.enterpriseHost.isEmpty else { return nil }
        guard var components = URLComponents(string: enterpriseHost) else { return nil }
        if components.scheme == nil { components.scheme = "https" }
        guard components.scheme?.lowercased() == "https", components.host != nil else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private func validateToken() async {
        guard case .loggedIn = self.session.account else { return }
        if self.tokenValidation == .checking { return }
        self.tokenValidation = .checking
        do {
            let user = try await self.appState.github.currentUser()
            self.session.account = .loggedIn(user)
            self.session.lastError = nil
            self.tokenValidation = .valid
        } catch {
            if error.isAuthenticationFailure {
                await self.appState.handleAuthenticationFailure(error)
                return
            }
            self.tokenValidation = .invalid(error.userFacingMessage)
        }
    }

    private func refreshToken() async {
        guard case .loggedIn = self.session.account else { return }
        if self.tokenValidation == .checking { return }
        self.tokenValidation = .checking
        do {
            let refreshed = try await self.appState.auth.refreshIfNeeded(force: true)
            guard refreshed != nil else {
                throw URLError(.userAuthenticationRequired)
            }
            await self.validateToken()
        } catch {
            if error.isAuthenticationFailure {
                await self.appState.handleAuthenticationFailure(error)
                return
            }
            self.tokenValidation = .invalid(error.userFacingMessage)
        }
    }

    private var tokenStatusText: String? {
        switch self.tokenValidation {
        case .unknown:
            "Token status not checked yet."
        case .checking:
            "Checking token…"
        case .valid:
            "Token is valid."
        case let .invalid(message):
            "Token invalid: \(message)"
        }
    }

    private var tokenStatusColor: Color {
        switch self.tokenValidation {
        case .valid:
            .green
        case .invalid:
            .red
        default:
            .secondary
        }
    }
}

private enum TokenValidationState: Equatable {
    case unknown
    case checking
    case valid
    case invalid(String)
}

private enum HostMode: String, CaseIterable {
    case githubCom
    case enterprise

    var label: String {
        switch self {
        case .githubCom:
            "GitHub.com"
        case .enterprise:
            "Enterprise"
        }
    }
}
