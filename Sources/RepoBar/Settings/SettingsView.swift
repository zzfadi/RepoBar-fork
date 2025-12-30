import AppKit
import RepoBarCore
import SwiftUI

struct SettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    var body: some View {
        TabView(selection: self.$session.settingsSelectedTab) {
            GeneralSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)
            RepoSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("Repositories", systemImage: "tray.full") }
                .tag(SettingsTab.repositories)
            AccountSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
            AdvancedSettingsView(session: self.session, appState: self.appState)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.advanced)
            #if DEBUG
                if self.session.settings.debugPaneEnabled {
                    DebugSettingsView(session: self.session, appState: self.appState)
                        .tabItem { Label("Debug", systemImage: "ant.fill") }
                        .tag(SettingsTab.debug)
                }
            #endif
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .tabViewStyle(.automatic)
        .frame(width: 540, height: 605)
        .onChange(of: self.session.settings.debugPaneEnabled) { _, enabled in
            #if DEBUG
                if !enabled, self.session.settingsSelectedTab == .debug {
                    self.session.settingsSelectedTab = .general
                }
            #endif
        }
    }
}

@MainActor
struct AboutSettingsView: View {
    @State private var iconHover = false
    @AppStorage("autoUpdateEnabled") private var autoUpdateEnabled: Bool = true
    @State private var didSyncUpdater = false

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "RepoBar"
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private var buildTimestamp: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RepoBarBuildTimestamp") as? String else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let date = parser.date(from: raw) else { return raw }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: date)
    }

    private var gitCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "RepoBarGitCommit") as? String
    }

    var body: some View {
        VStack(spacing: 8) {
            if let image = NSApplication.shared.applicationIconImage {
                Button {
                    if let url = URL(string: "https://github.com/steipete/RepoBar") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 88, height: 88)
                        .cornerRadius(16)
                        .scaleEffect(self.iconHover ? 1.06 : 1.0)
                        .shadow(color: self.iconHover ? .accentColor.opacity(0.25) : .clear, radius: 6)
                        .padding(.bottom, 4)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        self.iconHover = hovering
                    }
                }
            }

            VStack(spacing: 2) {
                Text(self.appName)
                    .font(.title3).bold()
                Text("Version \(self.versionString)")
                    .foregroundStyle(.secondary)
                if let buildTimestamp {
                    let suffix: String = {
                        if let git = self.gitCommit, !git.isEmpty, git != "unknown" {
                            return " (\(git))"
                        }
                        return ""
                    }()
                    Text("Built \(buildTimestamp)\(suffix)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Menubar glance at GitHub repos: CI, issues/PRs, releases, traffic, and activity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 6) {
                AboutLinkRow(icon: "chevron.left.slash.chevron.right", title: "GitHub", url: "https://github.com/steipete/RepoBar")
                AboutLinkRow(icon: "ant", title: "Issue Tracker", url: "https://github.com/steipete/RepoBar/issues")
                AboutLinkRow(icon: "envelope", title: "Email", url: "mailto:peter@steipete.me")
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)

            if SparkleController.shared.canCheckForUpdates {
                Divider()
                    .padding(.vertical, 6)
                VStack(spacing: 10) {
                    Toggle("Check for updates automatically", isOn: self.$autoUpdateEnabled)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Button("Check for Updates…") {
                        SparkleController.shared.checkForUpdates()
                    }
                }
            } else {
                Text("Updates unavailable in this build.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            Text("© 2025 Peter Steinberger. MIT License.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 6)
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .onAppear {
            guard !self.didSyncUpdater else { return }
            if SparkleController.shared.canCheckForUpdates {
                SparkleController.shared.automaticallyChecksForUpdates = self.autoUpdateEnabled
            }
            self.didSyncUpdater = true
        }
        .onChange(of: self.autoUpdateEnabled) { _, newValue in
            if SparkleController.shared.canCheckForUpdates {
                SparkleController.shared.automaticallyChecksForUpdates = newValue
            }
        }
    }
}

@MainActor
private struct AboutLinkRow: View {
    let icon: String
    let title: String
    let url: String

    @State private var hovering = false

    var body: some View {
        Button {
            if let url = URL(string: self.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: self.icon)
                Text(self.title)
                    .underline(self.hovering, color: .accentColor)
            }
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .onHover { self.hovering = $0 }
    }
}

enum SettingsTab: Hashable {
    case general
    case repositories
    case accounts
    case advanced
    case about
    #if DEBUG
        case debug
    #endif
}

struct GeneralSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            Form {
                Section {
                    Toggle("Launch at login", isOn: self.$session.settings.launchAtLogin)
                        .onChange(of: self.session.settings.launchAtLogin) { _, value in
                            LaunchAtLoginHelper.set(enabled: value)
                            self.appState.persistSettings()
                        }
                } footer: {
                    Text("Automatically opens RepoBar when you start your Mac.")
                }

                Section {
                    Toggle("Show contribution header", isOn: self.$session.settings.appearance.showContributionHeader)
                        .onChange(of: self.session.settings.appearance.showContributionHeader) { _, _ in
                            self.appState.persistSettings()
                        }
                    Picker("Repository heatmap", selection: self.$session.settings.heatmap.display) {
                        ForEach(HeatmapDisplay.allCases, id: \.self) { display in
                            Text(display.label).tag(display)
                        }
                    }
                    .onChange(of: self.session.settings.heatmap.display) { _, _ in
                        self.appState.persistSettings()
                    }
                    Picker("Heatmap window", selection: self.$session.settings.heatmap.span) {
                        ForEach(HeatmapSpan.allCases, id: \.self) { span in
                            Text(span.label).tag(span)
                        }
                    }
                    .onChange(of: self.session.settings.heatmap.span) { _, _ in
                        self.appState.persistSettings()
                        self.appState.updateHeatmapRange(now: Date())
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("Repository heatmaps show recent commit activity for each repository.")
                }

                Section {
                    Picker("Repositories shown", selection: self.$session.settings.repoList.displayLimit) {
                        ForEach([3, 6, 9, 12], id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Menu sort", selection: self.$session.settings.repoList.menuSortKey) {
                        ForEach(RepositorySortKey.settingsCases, id: \.self) { sortKey in
                            Text(sortKey.settingsLabel).tag(sortKey)
                        }
                    }
                    .onChange(of: self.session.settings.repoList.menuSortKey) { _, _ in
                        self.appState.persistSettings()
                    }
                    Toggle("Include forked repositories", isOn: self.$session.settings.repoList.showForks)
                        .onChange(of: self.session.settings.repoList.showForks) { _, _ in
                            self.appState.persistSettings()
                            self.appState.requestRefresh(cancelInFlight: true)
                        }
                    Toggle("Include archived repositories", isOn: self.$session.settings.repoList.showArchived)
                        .onChange(of: self.session.settings.repoList.showArchived) { _, _ in
                            self.appState.persistSettings()
                            self.appState.requestRefresh(cancelInFlight: true)
                        }
                } header: {
                    Text("Repositories")
                } footer: {
                    Text("Filters apply to repo lists and search.")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Quit RepoBar") { NSApp.terminate(nil) }
            }
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func intervalLabel(_ interval: RefreshInterval) -> String {
        switch interval {
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        }
    }
}

struct AdvancedSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    var body: some View {
        Form {
            Section {
                Picker("Refresh interval", selection: self.$session.settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases, id: \.self) { interval in
                        Text(self.intervalLabel(interval)).tag(interval)
                    }
                }
                .onChange(of: self.session.settings.refreshInterval) { _, newValue in
                    LaunchAtLoginHelper.set(enabled: self.session.settings.launchAtLogin)
                    self.appState.persistSettings()
                    Task { @MainActor in
                        self.appState.refreshScheduler.configure(interval: newValue.seconds) { [weak appState] in
                            appState?.requestRefresh()
                        }
                    }
                }
            } header: {
                Text("Refresh")
            } footer: {
                Text("Controls how often RepoBar refreshes GitHub data.")
            }

            Section {
                LabeledContent("Project folder") {
                    HStack(spacing: 8) {
                        Text(self.projectFolderLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(self.projectFolderLabelColor)
                        Button("Choose…") { self.pickProjectFolder() }
                        if self.session.settings.localProjects.rootPath != nil {
                            Button {
                                self.appState.refreshLocalProjects(forceRescan: true)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Rescan local projects")
                            Button {
                                self.clearProjectFolder()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Clear project folder")
                        }
                    }
                }

                if let summary = self.localRepoSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Auto-sync clean repos", isOn: self.$session.settings.localProjects.autoSyncEnabled)
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                    .onChange(of: self.session.settings.localProjects.autoSyncEnabled) { _, _ in
                        self.appState.persistSettings()
                        self.appState.refreshLocalProjects()
                        self.appState.requestRefresh(cancelInFlight: true)
                    }

                HStack {
                    Text("Preferred Terminal")
                    Spacer()
                    Picker("", selection: self.preferredTerminalBinding) {
                        ForEach(TerminalApp.installed, id: \.rawValue) { terminal in
                            HStack {
                                if let icon = terminal.appIcon {
                                    Image(nsImage: icon.resized(to: NSSize(width: 16, height: 16)))
                                }
                                Text(terminal.displayName)
                            }
                            .tag(terminal.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                }

                if self.isGhosttySelected {
                    HStack {
                        Text("Ghostty opens in")
                        Spacer()
                        Picker("", selection: self.ghosttyOpenModeBinding) {
                            ForEach(GhosttyOpenMode.allCases, id: \.self) { mode in
                                Text(mode.label)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(self.session.settings.localProjects.rootPath == nil)
                    }
                }
            } header: {
                Text("Local Projects")
            } footer: {
                Text("Scans two levels deep under the folder and fast-forward pulls clean repos.")
            }

            #if DEBUG
                Section {
                    Toggle("Enable debug tools", isOn: self.$session.settings.debugPaneEnabled)
                        .onChange(of: self.session.settings.debugPaneEnabled) { _, _ in
                            self.appState.persistSettings()
                        }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Developer-only diagnostics and experimental tools.")
                }
            #endif
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear {
            self.ensurePreferredTerminal()
            self.appState.refreshLocalProjects()
        }
    }

    private func intervalLabel(_ interval: RefreshInterval) -> String {
        switch interval {
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        }
    }

    private var projectFolderLabel: String {
        guard let path = self.session.settings.localProjects.rootPath,
              path.isEmpty == false
        else { return "Not set" }
        return PathFormatter.displayString(path)
    }

    private var projectFolderLabelColor: Color {
        self.session.settings.localProjects.rootPath == nil ? .secondary : .primary
    }

    private var localRepoSummary: String? {
        guard self.session.settings.localProjects.rootPath != nil else { return nil }
        if self.session.localProjectsScanInProgress { return "Scanning…" }
        let total = self.session.localDiscoveredRepoCount
        let matched = self.localMatchedRepoCount
        if total == 0 {
            if self.session.localProjectsAccessDenied || self.session.settings.localProjects.rootBookmarkData == nil {
                return "No repositories found yet. Re-choose the folder to grant access."
            }
            return "No repositories found yet."
        }
        if matched > 0 { return "Found \(total) local repos · \(matched) match GitHub data." }
        return "Found \(total) local repos."
    }

    private var localMatchedRepoCount: Int {
        let repos = self.session.repositories.isEmpty
            ? (self.session.menuSnapshot?.repositories ?? [])
            : self.session.repositories
        guard repos.isEmpty == false else { return 0 }
        let fullNames = Set(repos.map(\.fullName))
        let repoByName = Dictionary(grouping: repos, by: \.name)
        var matched = 0
        for status in self.session.localRepoIndex.all {
            if let fullName = status.fullName, fullNames.contains(fullName) {
                matched += 1
            } else if let candidates = repoByName[status.name], candidates.count == 1 {
                matched += 1
            }
        }
        return matched
    }

    private var preferredTerminalBinding: Binding<String> {
        Binding(
            get: {
                self.session.settings.localProjects.preferredTerminal ?? TerminalApp.defaultPreferred.rawValue
            },
            set: { newValue in
                self.session.settings.localProjects.preferredTerminal = newValue
                self.appState.persistSettings()
            }
        )
    }

    private var ghosttyOpenModeBinding: Binding<GhosttyOpenMode> {
        Binding(
            get: { self.session.settings.localProjects.ghosttyOpenMode },
            set: { newValue in
                self.session.settings.localProjects.ghosttyOpenMode = newValue
                self.appState.persistSettings()
            }
        )
    }

    private var isGhosttySelected: Bool {
        TerminalApp.resolve(self.session.settings.localProjects.preferredTerminal) == .ghostty
    }

    private func pickProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let existing = self.session.settings.localProjects.rootPath {
            panel.directoryURL = URL(fileURLWithPath: PathFormatter.expandTilde(existing), isDirectory: true)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            panel.directoryURL = home.appendingPathComponent("Projects", isDirectory: true)
        }
        if panel.runModal() == .OK, let url = panel.url {
            let filePathURL = (url as NSURL).filePathURL ?? url
            let resolvedPath = filePathURL.resolvingSymlinksInPath().path
            self.session.settings.localProjects.rootPath = PathFormatter.abbreviateHome(resolvedPath)
            self.session.settings.localProjects.rootBookmarkData = SecurityScopedBookmark.create(for: url)
            self.appState.persistSettings()
            self.appState.refreshLocalProjects(forceRescan: true)
            self.appState.requestRefresh(cancelInFlight: true)
        }
    }

    private func clearProjectFolder() {
        self.session.settings.localProjects.rootPath = nil
        self.session.settings.localProjects.rootBookmarkData = nil
        self.appState.persistSettings()
        self.appState.refreshLocalProjects(forceRescan: true)
        self.appState.requestRefresh(cancelInFlight: true)
    }

    private func ensurePreferredTerminal() {
        let resolved = TerminalApp.resolve(self.session.settings.localProjects.preferredTerminal).rawValue
        if self.session.settings.localProjects.preferredTerminal != resolved {
            self.session.settings.localProjects.preferredTerminal = resolved
            self.appState.persistSettings()
        }
    }
}

struct AppearanceSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    var body: some View {
        Form {
            Picker("Card density", selection: self.$session.settings.appearance.cardDensity) {
                ForEach(CardDensity.allCases, id: \.self) { density in
                    Text(density.label).tag(density)
                }
            }
            .onChange(of: self.session.settings.appearance.cardDensity) { _, _ in self.appState.persistSettings() }

            Picker("Accent tone", selection: self.$session.settings.appearance.accentTone) {
                ForEach(AccentTone.allCases, id: \.self) { tone in
                    Text(tone.label).tag(tone)
                }
            }
            .onChange(of: self.session.settings.appearance.accentTone) { _, _ in self.appState.persistSettings() }

            Text("GitHub greens keep the classic contribution palette; System accent follows your macOS accent color.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding()
    }
}

struct AccountSettingsView: View {
    @Bindable var session: Session
    let appState: AppState
    @State private var clientID = "Iv23liGm2arUyotWSjwJ"
    @State private var clientSecret = ""
    @State private var enterpriseHost = ""
    @State private var validationError: String?

    var body: some View {
        Form {
            Section("GitHub.com") {
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
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                default:
                    LabeledContent("Client ID") {
                        TextField("", text: self.$clientID)
                    }
                    LabeledContent("Client Secret") {
                        SecureField("", text: self.$clientSecret)
                    }
                    HStack(spacing: 8) {
                        if self.session.account == .loggingIn {
                            ProgressView()
                        }
                        Button(self.session.account == .loggingIn ? "Signing in…" : "Sign in") { self.login() }
                            .disabled(self.session.account == .loggingIn)
                            .buttonStyle(.borderedProminent)
                    }
                    Text("Uses browser-based OAuth. Tokens are stored in the system Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Enterprise (optional)") {
                LabeledContent("Base URL") {
                    TextField("https://host", text: self.$enterpriseHost)
                }
                Text("Trusted TLS only; leave blank if unused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }
        }
    }

    private func login() {
        Task { @MainActor in
            self.session.account = .loggingIn
            let enterpriseURL = self.normalizedEnterpriseHost()

            if let enterpriseURL {
                self.session.settings.enterpriseHost = enterpriseURL
                await self.appState.github.setAPIHost(enterpriseURL.appending(path: "/api/v3"))
                self.session.settings.githubHost = enterpriseURL
                self.validationError = nil
            } else {
                if !self.enterpriseHost.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.validationError = "Enterprise host must be a valid https:// URL with a trusted certificate."
                    self.session.account = .loggedOut
                    return
                }
                await self.appState.github.setAPIHost(URL(string: "https://api.github.com")!)
                self.session.settings.githubHost = URL(string: "https://github.com")!
                self.session.settings.enterpriseHost = nil
                self.validationError = nil
            }
            do {
                try await self.appState.auth.login(
                    clientID: self.clientID,
                    clientSecret: self.clientSecret,
                    host: self.session.settings.enterpriseHost ?? self.session.settings.githubHost,
                    loopbackPort: self.session.settings.loopbackPort
                )
                if let user = try? await appState.github.currentUser() {
                    self.session.account = .loggedIn(user)
                    self.session.lastError = nil
                }
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
}

struct DebugSettingsView: View {
    @Bindable var session: Session
    let appState: AppState
    @State private var diagnostics = DiagnosticsSummary.empty
    @State private var gitExecutableInfo = LocalProjectsService.gitExecutableInfo()

    var body: some View {
        Form {
            Section("Debug") {
                Button("Clear cache") {
                    Task {
                        await self.appState.clearCaches()
                        await self.loadDiagnosticsIfEnabled()
                    }
                }
                Button("Clear contribution heatmap cache") {
                    self.appState.clearContributionCache()
                }
                Button("Clear release cache") {
                    Task {
                        await self.appState.github.clearCache()
                        self.appState.requestRefresh(cancelInFlight: true)
                    }
                }
                Button("Force refresh") {
                    self.appState.requestRefresh(cancelInFlight: true)
                }
                Toggle("Show diagnostics overlay", isOn: self.$session.settings.diagnosticsEnabled)
                    .onChange(of: self.session.settings.diagnosticsEnabled) { _, newValue in
                        self.appState.persistSettings()
                        Task {
                            await DiagnosticsLogger.shared.setEnabled(newValue)
                            await self.loadDiagnosticsIfEnabled()
                        }
                    }
            }

            Section("Diagnostics") {
                LabeledContent("Git binary") {
                    Text(self.gitExecutableInfo.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("Git version") {
                    Text(self.gitExecutableInfo.version ?? "—")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("Git sandboxed") {
                    Text(self.gitExecutableInfo.isSandboxed ? "Yes" : "No")
                }
                if let error = self.gitExecutableInfo.error, !error.isEmpty {
                    LabeledContent("Git error") {
                        Text(error)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("API host") {
                    Text(self.diagnostics.apiHost.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("REST rate limit") {
                    Text(
                        self.diagnostics.restRateLimit.map(self.formatRate)
                            ?? "— (not fetched yet)"
                    )
                }
                LabeledContent("GraphQL rate limit") {
                    Text(
                        self.diagnostics.graphQLRateLimit.map(self.formatRate)
                            ?? "— (not fetched yet)"
                    )
                }
                if let reset = diagnostics.rateLimitReset {
                    LabeledContent("Rate limit resets") {
                        Text(RelativeFormatter.string(from: reset, relativeTo: Date()))
                    }
                }
                if let error = diagnostics.lastRateLimitError {
                    LabeledContent("Last API notice") { Text(error).foregroundStyle(.red) }
                }
                LabeledContent("Backoff entries") { Text("\(self.diagnostics.backoffEntries)") }
                LabeledContent("ETag entries") { Text("\(self.diagnostics.etagEntries)") }
                Button("Refresh diagnostics") { Task { await self.loadDiagnosticsIfEnabled() } }
            }
            .opacity(self.session.settings.diagnosticsEnabled ? 1 : 0.4)
            .disabled(!self.session.settings.diagnosticsEnabled)
        }
        .padding()
        .task {
            self.gitExecutableInfo = LocalProjectsService.gitExecutableInfo()
            await self.loadDiagnosticsIfEnabled()
        }
    }

    private func loadDiagnosticsIfEnabled() async {
        guard self.session.settings.diagnosticsEnabled else {
            self.diagnostics = .empty
            return
        }
        self.diagnostics = await self.appState.diagnostics()
    }

    private func formatRate(_ snapshot: RateLimitSnapshot) -> String {
        var parts: [String] = []
        if let resource = snapshot.resource?.uppercased() {
            parts.append(resource)
        }
        if let remaining = snapshot.remaining, let limit = snapshot.limit {
            parts.append("\(remaining)/\(limit) left")
        } else if let remaining = snapshot.remaining {
            parts.append("\(remaining) remaining")
        } else if let limit = snapshot.limit {
            parts.append("limit \(limit)")
        }
        if let used = snapshot.used {
            parts.append("\(used) used")
        }
        if let reset = snapshot.reset {
            parts.append("resets \(RelativeFormatter.string(from: reset, relativeTo: Date()))")
        }
        let text = parts.joined(separator: " • ")
        return text.isEmpty ? "—" : text
    }
}
