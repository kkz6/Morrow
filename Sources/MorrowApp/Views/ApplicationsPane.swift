import SwiftUI
import MorrowCore

struct ApplicationsPane: View {
    @Environment(AppModel.self) private var model
    @State private var engine = RuntimeEngine.php
    @State private var selection = ""
    @State private var pendingUpdate: RuntimeInstallation?
    @State private var pendingRemoval: RuntimeInstallation?
    private var selectedInstallation: RuntimeInstallation? { versions.first { $0.id == selection } }
    private var isSelectedDefault: Bool { selectedInstallation.map { model.toolDefaults[engine.rawValue] == $0.id } ?? false }
    private var versions: [RuntimeInstallation] {
        var seen = Set<String>()
        return (model.inventory.runtimes + model.tools).filter { $0.engine == engine && seen.insert($0.id).inserted }
    }
    private var options: [SelectOption<String>] {
        let existing = versions.map { SelectOption(value: $0.id, title: $0.version, symbol: "square.stack.3d.up") }
        let missing = (model.inventory.channels[engine.rawValue] ?? []).filter { channel in !versions.contains { $0.formula == channel.formula || $0.version == channel.version } }
            .map { SelectOption(value: $0.formula, title: "\($0.version) · \($0.formula)", symbol: "square.stack.3d.up") }
        return (engine == .node ? [SelectOption(value: "lts", title: "Latest LTS · nvm", symbol: "morrow.node")] : []) + existing + missing
    }
    var body: some View {
        SettingsPane(section: SettingsSection.applications) {
            SettingsNote(text: "Install a runtime or choose an installed version as the default for Morrow commands.")
            SettingsGroup(header: "Add Runtime") {
                SettingRow(title: "Application") {
                    SettingsSelect(label: "Application", selection: $engine, options: RuntimeEngine.allCases.map { .init(value: $0, title: $0.title, symbol: $0.symbol) })
                }
                SettingsDivider()
                SettingRow(title: "Version") {
                    if options.isEmpty { Text(model.runtimeChannelsLoading.contains(engine.rawValue) ? "Loading…" : "No versions available").font(.system(size: 12)).foregroundStyle(.secondary) }
                    else {
                        HStack(spacing: 8) {
                            SettingsSelect(label: "Version", selection: $selection, options: options)
                            if isSelectedDefault { Text("Default").font(.system(size: 11)).foregroundStyle(.secondary) }
                            else {
                                Button(selectedInstallation == nil ? "Install" : "Set Default") { selectVersion() }.settingsButton(height: 28).disabled(model.busy || selection.isEmpty)
                            }
                        }
                    }
                }
            }
            if model.runtimeChannelsLoading.contains(engine.rawValue) { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Finding versions…").font(.system(size: 12)).foregroundStyle(.secondary) } }
            HStack {
                Text("Your Runtimes").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                ServiceActionButton(kind: .refresh, title: "Refresh installed versions and channels") { Task { await model.loadInventory(force: true); model.loadRuntimeChannels(engine, force: true) } }.disabled(model.busy || model.inventoryLoading)
                Button("Check Updates") { model.checkUpdates() }.settingsButton().disabled(model.busy)
            }
            if model.tools.isEmpty {
                SettingsCard { Text("Select a version above to add your first application.").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(16) }
            } else {
                SettingsGroup {
                    ForEach(Array(model.tools.enumerated()), id: \.element.id) { index, item in
                        runtimeRow(item)
                        if index < model.tools.count - 1 { SettingsDivider() }
                    }
                }
            }
            SettingsGroup(header: "Terminal Setup") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Run morrow tool shell and add its output to your shell configuration to use selected versions in Terminal.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("morrow tool exec \(engine.rawValue) -- \(engine == .go ? "version" : "--version")")
                        .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading).settingsCellPadding()
            }
            if engine == .flutter { SettingsNote(text: "Homebrew provides the current Flutter release. Selected SDKs are retained separately in Morrow. Target platforms may require Xcode, Android SDK, or other Flutter prerequisites.") }
            if engine == .node {
                Text("nvm: " + NodeVersionManager(store: model.manager.store).directory.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            SettingsNote(text: "Version selection applies to Morrow commands and its optional PATH setup. Homebrew may update shared dependencies during installation.")
        }
        .onAppear { engine = RuntimeEngine.parse(model.preferences.lastRuntime) ?? .php }
        .task(id: "\(engine.rawValue):\(model.tools.map(\.id).joined()):\(model.inventory.channels[engine.rawValue]?.count ?? 0)") { await loadVersions() }
        .onChange(of: engine) { _, value in var preferences = model.preferences; preferences.lastRuntime = value.rawValue; model.savePreferences(preferences); selection = "" }
        .confirmationDialog("Update \(pendingUpdate?.engine.title ?? "Application")?", isPresented: Binding(get: { pendingUpdate != nil }, set: { if !$0 { pendingUpdate = nil } }), titleVisibility: .visible) {
            if let item = pendingUpdate {
                Button("Update") {
                    let cli = model.cliURL
                    model.perform("Updating \(item.engine.title)…", operation: { manager in
                        _ = try RuntimeManager(store: manager.store, runner: manager.runner).upgrade(item, cli: cli)
                    }, completion: { model.checkUpdates(refresh: false) })
                    pendingUpdate = nil
                }
            }
        } message: { Text(pendingUpdate?.engine == .node ? "nvm will install the latest Node release in this series, keeping the existing version. If this is your selected version, Morrow will select the new release." : "Homebrew will update this channel and may update shared dependencies. If this is your selected version, Morrow will select the new release.") }
        .confirmationDialog("Remove from Morrow?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), titleVisibility: .visible) {
            if let item = pendingRemoval {
                Button("Remove Selection", role: .destructive) {
                    model.perform("Removing \(item.engine.title)…") { manager in try RuntimeManager(store: manager.store, runner: manager.runner).forget(item) }
                    pendingRemoval = nil
                }
            }
        } message: { Text("Runtime files are preserved. Removing the default requires selecting another version before using Morrow's commands.") }
    }
    private func runtimeRow(_ item: RuntimeInstallation) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: item.engine.symbol, color: item.engine.color, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.engine.title).font(.system(size: 13, weight: .semibold))
                Text(item.version + " · " + item.source).font(.system(size: 11)).foregroundStyle(.secondary)
                if let update = model.runtimeUpdates.first(where: { $0.id == item.id }) {
                    Text(update.canUpgrade ? "Update available: \(update.availableVersion ?? "")" : update.message)
                        .font(.system(size: 11)).foregroundStyle(update.canUpgrade ? .orange : .secondary).lineLimit(2)
                }
            }
            Spacer()
            if model.toolDefaults[item.engine.rawValue] == item.id { Text("Default").font(.system(size: 11)).foregroundStyle(.teal) }
            else {
                Button("Set Default") {
                    let cli = model.cliURL
                    model.perform("Selecting \(item.engine.title)…") { manager in try RuntimeManager(store: manager.store, runner: manager.runner).use(item, cli: cli) }
                }.settingsButton(height: 28).disabled(model.busy)
            }
            if let log = model.sites.runtimeLogURL(item), FileManager.default.fileExists(atPath: log.path) {
                ServiceActionButton(kind: .logs, title: "Open PHP-FPM logs") { model.logRequest = ServiceLogRequest(title: item.engine.title + " " + item.version, subtitle: "PHP-FPM", url: log) }
            }
            ServiceActionButton(kind: .configuration, title: "Edit runtime configuration") { model.showConfiguration(item) }
            Menu {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.executable)]) }
                if model.runtimeUpdates.contains(where: { $0.id == item.id && $0.canUpgrade }) { Button("Update…") { pendingUpdate = item } }
                Button("Remove from Morrow…", role: .destructive) { pendingRemoval = item }
            } label: { Image(systemName: "ellipsis").frame(width: 16) }.settingsMenuControl().disabled(model.busy)
        }.settingsCellPadding()
    }
    private func selectVersion() {
        guard options.contains(where: { $0.value == selection }) else { return }
        let selectedEngine = engine, version = selection
        let existing = versions.first { $0.id == version }, cli = model.cliURL
        model.perform(existing == nil ? "Installing \(engine.title)…" : "Selecting \(engine.title)…", success: "\(engine.title) is ready") { manager in
            let runtimes = RuntimeManager(store: manager.store, runner: manager.runner)
            let item = try existing ?? runtimes.install(selectedEngine, version: version)
            try runtimes.use(item, cli: cli)
        }
    }
    private func loadVersions() async {
        model.loadRuntimeChannels(engine)
        let selected = model.toolDefaults[engine.rawValue]
        if !options.contains(where: { $0.value == selection }) { selection = selected.flatMap { id in options.first { $0.value == id }?.value } ?? options.first?.value ?? "" }
    }

}

struct DatabaseUpgradeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let update: DatabaseUpdate
    private var recovering: Bool { model.manager.needsUpdateRecovery(update.instanceID) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(recovering ? "Recover \(update.name)" : "Update \(update.name)").font(.system(size: 18, weight: .semibold))
            if !recovering { Text("\(update.currentVersion) → \(update.availableVersion ?? "")").font(.system(size: 13)).foregroundStyle(.secondary) }
            Text(recovering ? "Recover the interrupted operation. Failed updates restore the saved instance; completed updates finish their setup. Files from failed updates are preserved separately." : "Morrow will stop this instance, back up its files, apply the maintenance update, and restart it if it was running. Homebrew may also update shared dependencies.")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Text("Backups are kept in Morrow’s backups folder. Linked data or external tablespaces require a manual upgrade.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if let error = model.error { ErrorCard(message: error) { model.error = nil } }
            if let activity = model.activity { HStack { ProgressView().controlSize(.small); Text(activity).font(.system(size: 12)) } }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.settingsButton().keyboardShortcut(.cancelAction).disabled(model.busy)
                Button(recovering ? "Recover" : "Back Up and Update") {
                    let id = update.instanceID, expected = update.availableVersion, recovery = recovering
                    model.perform(recovery ? "Recovering \(update.name)…" : "Updating \(update.name)…", operation: { manager in
                        if recovery { try manager.recoverUpdate(id) } else { _ = try manager.upgrade(id, expectedVersion: expected) }
                    }, completion: { dismiss(); model.checkUpdates(refresh: false) })
                }.settingsButton().keyboardShortcut(.defaultAction).disabled(model.busy)
            }
        }.padding(20).frame(width: 440)
    }
}
