import SwiftUI
import MorrowCore

struct SyncPane: View {
    var embedded = false
    @Environment(AppModel.self) private var model
    private var folder: URL { model.preferences.syncFolder.isEmpty ? WorkspaceSync.defaultFolder : URL(fileURLWithPath: model.preferences.syncFolder) }
    var body: some View {
        SettingsPane(section: SettingsSection.sync, embedded: embedded) {
            SettingsNote(text: "Keep your workspace setup in iCloud Drive. Enable sync on another Mac to restore database settings, runtime release series, and defaults.")
            SettingsGroup {
                SettingRow(title: "Sync workspace with iCloud Drive") {
                    Toggle("Sync workspace with iCloud Drive", isOn: Binding(get: { model.preferences.iCloudSyncEnabled }, set: { enabled in
                        let selected = folder
                        model.perform(enabled ? "Enabling workspace sync…" : "Disabling workspace sync…", operation: { manager in
                            try WorkspaceSync(store: manager.store, runner: manager.runner).configure(enabled: enabled, folder: selected)
                        }, completion: { if enabled { model.syncNow(retry: true) } })
                    })).settingsToggle()
                }
                SettingsDivider()
                SettingRow(title: "Set up missing services automatically", subtitle: "Recreate the synced setup on this Mac") {
                    Toggle("Set up missing services automatically", isOn: Binding(get: { model.preferences.autoSetupSyncedServices }, set: { enabled in
                        var preferences = model.preferences; preferences.autoSetupSyncedServices = enabled
                        model.savePreferences(preferences)
                        model.syncNow(retry: true)
                    })).settingsToggle()
                }.disabled(!model.preferences.iCloudSyncEnabled)
            }.disabled(model.busy)
            SettingsGroup(header: "iCloud Drive Folder") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(folder.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    Text("Choose a folder inside iCloud Drive on each Mac. iCloud handles file delivery; Morrow checks for changes while it is open.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).settingsCellPadding()
                SettingsDivider()
                SettingsActionRow(title: "Choose iCloud Drive Folder…", symbol: "folder") { chooseFolder() }.disabled(model.busy)
                SettingsDivider()
                SettingsActionRow(title: "Show Sync Folder", symbol: "arrow.up.right.square") { NSWorkspace.shared.open(folder) }.disabled(!FileManager.default.fileExists(atPath: folder.path))
            }
            SettingsGroup(header: "Sync Status") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.syncReport.message).font(.system(size: 13, weight: .medium))
                    if let date = model.syncReport.lastSyncedAt { Text("Last checked: \(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11)).foregroundStyle(.secondary) }
                    ForEach(Array(model.syncReport.details.enumerated()), id: \.offset) { _, detail in Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }
                    ForEach(Array(model.syncReport.failures.enumerated()), id: \.offset) { _, failure in Text(failure).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).settingsCellPadding()
                SettingsDivider()
                SettingsActionRow(title: "Sync and Retry Setup", symbol: "arrow.triangle.2.circlepath") { model.syncNow(retry: true) }
                    .disabled(model.busy || !model.preferences.iCloudSyncEnabled)
            }
            SettingsNote(text: "New database instances start stopped, with their own empty data folders. Occupied ports use the next free port. Existing data and different release series require local review.")
            SettingsNote(text: "Your database contents, logs, credentials, executable paths, and Homebrew location stay on this Mac. Automatic setup and the sync-folder selection are configured separately on each Mac.")
        }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder in iCloud Drive"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.directoryURL = WorkspaceSync.defaultFolder.deletingLastPathComponent()
        panel.prompt = "Choose Folder"
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        var preferences = model.preferences; preferences.syncFolder = selected.path
        model.savePreferences(preferences)
        if preferences.iCloudSyncEnabled { model.syncNow(retry: true) }
    }
}
