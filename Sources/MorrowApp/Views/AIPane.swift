import SwiftUI
import MorrowCore

struct AIPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var settings = AISettings()
    @State private var added: Set<AIClient> = []
    @State private var issue: String?
    @State private var message: String?
    private var integration: AIIntegration { AIIntegration(store: model.manager.store) }
    private var configuration: AIClientConfiguration {
        AIClientConfiguration(executable: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/morrow").path)
    }
    var body: some View {
        SettingsPane(section: SettingsSection.ai) {
            SettingsGroup {
                SettingRow(icon: "sparkles", iconColor: .indigo, title: "Connect AI apps", subtitle: "Let your assistant inspect your local workspace") {
                    Toggle("Connect AI apps", isOn: preference(\.enabled)).settingsToggle()
                }
            }
            SettingsGroup(header: "Access") {
                SettingRow(title: "Projects and services", subtitle: "Status, versions, and project health") {
                    Text("Read only").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                SettingsDivider()
                SettingRow(title: "Debug data", subtitle: "Service logs, PHP dumps, and request insights") {
                    Toggle("Debug data", isOn: preference(\.includeDebugData)).settingsToggle()
                }
                SettingsDivider()
                SettingRow(title: "Mail", subtitle: "Captured test messages and email source") {
                    Toggle("Mail", isOn: preference(\.includeMail)).settingsToggle()
                }
            }.disabled(!settings.enabled)
            SettingsGroup(header: "AI Apps") {
                ForEach(Array(AIClient.allCases.enumerated()), id: \.element.id) { index, client in
                    if index > 0 { SettingsDivider() }
                    SettingRow(title: LocalizedStringKey(client.title)) {
                        HStack(spacing: 10) {
                            if added.contains(client) { Text("Added").font(.system(size: 11)).foregroundStyle(.secondary) }
                            Button(added.contains(client) ? "Remove" : "Add") { configure(client) }
                                .settingsButton().disabled(model.preview || (!settings.enabled && !added.contains(client)))
                        }
                    }
                }
                SettingsDivider()
                SettingRow(title: "Other apps") {
                    Menu("Copy Setup") {
                        Button("Codex Command") { copy(configuration.codexCommand) }
                        Button("Claude Code Command") { copy(configuration.claudeCommand) }
                        Divider()
                        Button("MCP Configuration") { do { copy(try configuration.json()) } catch { issue = error.localizedDescription } }
                        Button("VS Code Configuration") { do { copy(try configuration.json(for: .vscode)) } catch { issue = error.localizedDescription } }
                    }.settingsMenuControl(iconOnly: false)
                }
            }
            if let issue {
                Text(issue).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled)
            } else if let message {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                SettingsNote(text: "Your AI app starts Morrow’s MCP connection when needed. Information you allow may be sent to that app’s AI provider.")
            }
        }
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }
    private func preference(_ key: WritableKeyPath<AISettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: key] }, set: { value in
            if model.preview { settings[keyPath: key] = value; return }
            do { settings = try integration.update { $0[keyPath: key] = value }; issue = nil; message = nil }
            catch { issue = error.localizedDescription }
        })
    }
    private func configure(_ client: AIClient) {
        do {
            let adding = !added.contains(client)
            try configuration.setAdded(adding, to: client)
            refresh()
            message = adding ? "Added to \(client.title). Restart that app and approve Morrow’s tools to connect." : "Removed from \(client.title). Restart that app to close its connection."
        } catch { issue = error.localizedDescription }
    }
    private func refresh() {
        if model.preview { return }
        do {
            settings = try integration.settings()
            // Unsupported client files stay untouched; Add reports actionable details.
            added = Set(AIClient.allCases.filter { (try? configuration.isAdded(to: $0)) == true })
            issue = nil
        } catch { issue = error.localizedDescription }
    }
    private func copy(_ value: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        issue = nil; message = "Setup copied. Add it in your AI app, then approve Morrow’s tools."
    }
}
