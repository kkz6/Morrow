import SwiftUI
import ServiceManagement
import MorrowCore

struct OnboardingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var launchAtLogin = false
    @State private var installCLI = true
    @State private var localDomains = true
    @State private var issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage()).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(step == 0 ? "Welcome to Morrow" : "Local Workspace Setup").font(.system(size: 20, weight: .semibold))
                    Text(step == 0 ? "Choose how you'd like to get started." : "Approve Morrow once for local domain setup.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            if step == 0 {
                SettingsGroup {
                    SettingRow(title: "Launch at login") { Toggle("Launch at login", isOn: $launchAtLogin).settingsToggle() }
                    SettingsDivider()
                    SettingRow(title: "Install command line tool", subtitle: "Manage your workspace with morrow") { Toggle("Install CLI", isOn: $installCLI).settingsToggle() }
                    SettingsDivider()
                    SettingRow(title: "Set up local project domains", subtitle: "Use .test addresses with HTTP and HTTPS") { Toggle("Local domains", isOn: $localDomains).settingsToggle() }
                }
                SettingsNote(text: "Database and runtime controls work without administrator access. Local domains use an approved Morrow helper. Your password is never stored.")
            } else {
                SettingsGroup {
                    SettingRow(title: "Morrow setup helper", subtitle: "Local DNS and ports 80/443") {
                        if model.domainActivity != nil { ProgressView().controlSize(.small) }
                        else { Text(model.domainApprovalNeeded ? "Approval needed" : model.domainFailure ? "Needs attention" : "Ready").font(.system(size: 11)).foregroundStyle(.secondary) }
                    }
                    if model.domainApprovalNeeded {
                        SettingsDivider()
                        SettingsActionRow(title: "Approve Morrow in System Settings…", symbol: "lock.shield") { model.openSetupApproval() }
                    }
                }
                Text(model.domainActivity ?? model.httpsMessage).font(.system(size: 12)).foregroundStyle(model.domainFailure ? Color.orange : Color.secondary).textSelection(.enabled)
                if model.domainFailure { Button("Retry Setup") { model.installSiteSystemSetup(replaceResolvers: SiteSystemSetup.setupIssue(suffixes: model.web.suffixes) != nil, repair: true) }.settingsButton() }
            }
            if let issue { ErrorCard(message: issue) { self.issue = nil } }
            HStack {
                Button(step == 0 ? "Set Up Later" : "Finish Later") { finish() }.settingsButton().disabled(model.busy)
                Spacer()
                if step == 0 {
                    Button("Continue") { begin() }.settingsButton().keyboardShortcut(.defaultAction).disabled(model.busy)
                } else {
                    Button("Finish") { finish() }.settingsButton().keyboardShortcut(.defaultAction).disabled(model.busy || model.domainApprovalNeeded || model.domainFailure)
                }
            }
        }.padding(24).frame(width: 500).serviceFeedback().interactiveDismissDisabled()
    }
    private func begin() {
        do {
            if installCLI { try CLIInstaller.install(source: model.cliURL) }
            if launchAtLogin { try SMAppService.mainApp.register() }
            if localDomains {
                step = 1
                model.installSiteSystemSetup(replaceResolvers: SiteSystemSetup.setupIssue(suffixes: model.web.suffixes) != nil)
            } else { finish() }
        } catch { issue = error.localizedDescription }
    }
    private func finish() {
        var preferences = model.preferences; preferences.onboardingCompleted = true
        model.savePreferences(preferences); model.onboardingPresented = false; dismiss()
    }
}
