import RepoBarCore
import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel
    let showsCloseButton: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Account") {
                switch appModel.session.account {
                case .loggedIn(let user):
                    LabeledContent("Signed in as", value: user.username)
                    Button("Sign out") { Task { await appModel.logout() } }
                        .foregroundStyle(.red)
                case .loggingIn:
                    ProgressView("Signing in…")
                case .loggedOut:
                    Button("Sign in") { Task { await appModel.login() } }
                }
            }

            Section("Host") {
                TextField("Enterprise URL", text: enterpriseHostBinding)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Text("Leave empty to use github.com.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display") {
                Stepper(value: $appModel.session.settings.repoList.displayLimit, in: 1 ... 20) {
                    Text("Repo count: \(appModel.session.settings.repoList.displayLimit)")
                }
                Toggle("Show forks", isOn: $appModel.session.settings.repoList.showForks)
                Toggle("Show archived", isOn: $appModel.session.settings.repoList.showArchived)
                Toggle("Contribution header", isOn: $appModel.session.settings.appearance.showContributionHeader)
            }

            Section("Refresh") {
                Picker("Interval", selection: $appModel.session.settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases, id: \.self) { interval in
                        Text(interval.label)
                            .tag(interval)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Heatmap") {
                Picker("Span", selection: $appModel.session.settings.heatmap.span) {
                    ForEach(HeatmapSpan.allCases, id: \.self) { span in
                        Text(span.label).tag(span)
                    }
                }
                .pickerStyle(.menu)
                Picker("Accent", selection: $appModel.session.settings.appearance.accentTone) {
                    ForEach(AccentTone.allCases, id: \.self) { tone in
                        Text(tone.label).tag(tone)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Activity") {
                Picker("Scope", selection: $appModel.session.settings.appearance.activityScope) {
                    ForEach(GlobalActivityScope.allCases, id: \.self) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Diagnostics") {
                Toggle("Enable diagnostics", isOn: $appModel.session.settings.diagnosticsEnabled)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GlassBackground())
        .navigationTitle("Settings")
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .onChange(of: appModel.session.settings) { _, _ in
            appModel.persistSettings()
            appModel.refreshScheduler.configure(interval: appModel.session.settings.refreshInterval.seconds) {
                appModel.requestRefresh()
            }
            Task { await DiagnosticsLogger.shared.setEnabled(appModel.session.settings.diagnosticsEnabled) }
            appModel.updateHeatmapRange()
        }
    }

    private var enterpriseHostBinding: Binding<String> {
        Binding(
            get: { appModel.session.settings.enterpriseHost?.absoluteString ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    appModel.session.settings.enterpriseHost = nil
                } else {
                    let normalized = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
                    if let url = URL(string: normalized) {
                        appModel.session.settings.enterpriseHost = url
                    }
                }
                Task { await appModel.applyHostSettings() }
            }
        )
    }
}
