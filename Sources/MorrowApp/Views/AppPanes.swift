import SwiftUI
import ServiceManagement
import MorrowCore

struct CommandLinePane: View {
    var embedded = false
    @Environment(AppModel.self) private var model
    @State private var installed = false
    private var source: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/morrow") }
    var body: some View {
        SettingsPane(section: SettingsSection.commandLine, embedded: embedded) {
            SettingsNote(text: "Manage the same databases and runtimes from Terminal. The app and CLI share your configuration, versions, and data.")
            SettingsGroup {
                SettingsActionRow(title: installed ? "CLI Installed" : "Install Command Line Tool…", symbol: "terminal", detail: "morrow") {
                    do { try CLIInstaller.install(source: source); installed = true }
                    catch { model.error = error.localizedDescription }
                }.disabled(installed || model.preview)
            }
            Text(CLIInstaller.defaultDestination.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            SettingsGroup(header: "Terminal Setup") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add your local bin directory to PATH in ~/.zshrc:").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("export PATH=\"$HOME/.local/bin:$PATH\"").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }.settingsCellPadding()
            }
            SettingsGroup(header: "Example") {
                Text("morrow db create postgresql my-app --start\nmorrow db list\nmorrow db logs my-app")
                    .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).settingsCellPadding()
            }
        }.onAppear {
            installed = (try? FileManager.default.destinationOfSymbolicLink(atPath: CLIInstaller.defaultDestination.path)) == source.path
        }
    }
}

struct GeneralOptionsPane: View {
    var embedded = false
    @Environment(AppModel.self) private var model
    @State private var brewPath = ""
    @State private var catalogURL = ""
    @State private var nvmPath = ""
    var body: some View {
        SettingsPane(section: SettingsSection.general, embedded: embedded) {
            SettingsGroup {
                SettingRow(title: "Launch Morrow at login", subtitle: model.loginPermission == .needsApproval ? "Login permission needs approval in System Settings" : "Keep your database controls close by") {
                    Toggle("Launch Morrow at login", isOn: Binding(get: { model.loginPermission == .allowed }, set: { value in
                        if model.preview { model.loginPermission = value ? .allowed : .notRegistered; return }
                        do {
                            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            model.refreshPermissions()
                            if value, model.loginPermission == .needsApproval { NativeSetupController.openApprovalSettings() }
                        } catch { model.error = error.localizedDescription }
                    })).settingsToggle()
                }
                SettingsDivider()
                SettingRow(title: "Background access", subtitle: LocalizedStringKey(model.blockedBackgroundItems.isEmpty ? "Local domain setup: \(model.setupPermission.title.lowercased())" : "\(model.blockedBackgroundItems.count) service permissions need attention")) {
                    HStack(spacing: 8) {
                        Text(model.setupPermission.title).font(.system(size: 11)).foregroundStyle(model.setupPermission == .allowed ? Color.secondary : Color.orange)
                        Menu {
                            Button("Review Permissions…") { NativeSetupController.openApprovalSettings() }
                            Button("Clean Up Old Registrations") { model.cleanupBackgroundItems() }
                        } label: { Image(systemName: "ellipsis").frame(width: 16) }.settingsMenuControl().help("Background permissions and cleanup").disabled(model.busy)
                    }
                }
            }
            SettingsGroup(header: "Binary Downloads") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Binary catalog URL").font(.system(size: 13))
                    HStack {
                        SettingsInput(placeholder: "https://…/catalog.json (optional)", text: $catalogURL)
                        Button("Save") {
                            let url = catalogURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            model.perform("Saving binary source…", success: "Binary source saved", operation: { manager in
                                try ManagedBinaryStore(store: manager.store, runner: manager.runner).configure(url: url)
                            }, completion: {
                                model.inventory.channels = [:]
                                model.channels = []
                                model.loadChannels()
                                model.loadRuntimeChannels(RuntimeEngine(rawValue: model.preferences.lastRuntime) ?? .php, force: true)
                            })
                        }.settingsButton().disabled(model.busy)
                    }
                    Text("Reuse installed software, or download verified distributions. Go is available directly; other packages need a catalog or optional Homebrew compatibility.").font(.system(size: 12)).foregroundStyle(.secondary)
                }.settingsCellPadding()
                SettingsDivider()
                SettingRow(title: "Homebrew compatibility", subtitle: "Allow Homebrew for packages missing from the catalog") {
                    Toggle("Homebrew compatibility", isOn: Binding(get: { model.preferences.allowHomebrewFallback }, set: { value in
                        var preferences = model.preferences; preferences.allowHomebrewFallback = value
                        model.savePreferences(preferences)
                        try? BinaryInstaller(store: model.manager.store, runner: model.manager.runner).setHomebrewCompatibility(value)
                        model.inventory.channels = [:]; model.channels = []
                        model.loadChannels(); model.loadRuntimeChannels(RuntimeEngine(rawValue: model.preferences.lastRuntime) ?? .php, force: true)
                    })).settingsToggle()
                }.disabled(model.busy)
            }
            if model.preferences.allowHomebrewFallback {
                SettingsGroup(header: "Homebrew Location") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Homebrew executable").font(.system(size: 13))
                        HStack {
                            SettingsInput(placeholder: "Automatic (/opt/homebrew/bin/brew)", text: $brewPath)
                            Button("Save") {
                                let path = brewPath.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard path.isEmpty || FileManager.default.isExecutableFile(atPath: path) else { model.error = "Choose an executable Homebrew path."; return }
                                var preferences = model.preferences; preferences.homebrewPath = path
                                model.savePreferences(preferences)
                                Task { await model.refresh() }
                            }.settingsButton(height: ControlLayout.height).disabled(model.busy)
                        }
                    }.settingsCellPadding()
                }
            }
            SettingsGroup(header: "Node Version Manager") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("nvm directory").font(.system(size: 13))
                    HStack {
                        SettingsInput(placeholder: "Automatic (existing nvm or Morrow-managed)", text: $nvmPath)
                        Button("Save") {
                            let path = nvmPath.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard path.isEmpty || path.hasPrefix("/") else { model.notify("Choose an absolute nvm directory path.", error: true); return }
                            var preferences = model.preferences; preferences.nvmDirectory = path
                            model.savePreferences(preferences); model.notify("nvm directory saved")
                            Task { await model.loadInventory(force: true) }
                        }.settingsButton().disabled(model.busy)
                    }
                }.settingsCellPadding()
            }
            SettingsNote(text: "Database startup is configured per instance. Morrow uses macOS launchd so services continue running independently of the menu bar app.")
            SettingsGroup {
                SettingsActionRow(title: "Open Setup Assistant…", symbol: "wand.and.stars") { model.onboardingPresented = true }
            }
        }.onAppear {
            model.refreshPermissions()
            brewPath = model.preferences.homebrewPath
            catalogURL = model.preferences.binaryCatalogURL
            nvmPath = model.preferences.nvmDirectory
        }
    }
}

struct MenuBarPane: View {
    var embedded = false
    @Environment(AppModel.self) private var model
    var body: some View {
        SettingsPane(section: SettingsSection.menuBar, embedded: embedded) {
            SettingsGroup {
                SettingRow(title: "Show running count", subtitle: "Display active instances beside the icon") {
                    Toggle("Show running count", isOn: model.preference(\.showRunningCount)).settingsToggle()
                }
            }
            SettingsGroup(header: "Preview") {
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive.fill")
                    if model.preferences.showRunningCount { Text("\(model.runningCount)").monospacedDigit() }
                    Spacer()
                    Text("Morrow in your menu bar").font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(16)
            }
            SettingsNote(text: "Click the menu bar icon to start or stop instances, copy a connection address, or open Settings.")
        }
    }
}

struct AppearancePane: View {
    var embedded = false
    @Environment(AppModel.self) private var model
    var body: some View {
        SettingsPane(section: SettingsSection.appearance, embedded: embedded) {
            SettingsGroup {
                SettingRow(title: "Appearance") {
                    SettingsSelect(label: "Appearance", selection: model.preference(\.appearance), options: [
                        .init(value: "system", title: "System", symbol: "circle.lefthalf.filled"),
                        .init(value: "light", title: "Light", symbol: "sun.max.fill"),
                        .init(value: "dark", title: "Dark", symbol: "moon.fill"),
                    ])
                }
            }
            SettingsNote(text: "System follows your Mac’s appearance. Native materials adapt across the menu bar and Settings.")
        }
    }
}

struct AboutPane: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
    var body: some View {
        SettingsPane(section: SettingsSection.about) {
            VStack(spacing: 8) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable().frame(width: 56, height: 56)
                Text("Morrow").font(.system(size: 22, weight: .medium))
                Text("Version \(version)").font(.system(size: 12)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 20)
            SettingsGroup(header: "Resources") {
                SettingsActionRow(title: "Documentation", symbol: "book") {
                    NSWorkspace.shared.open(URL(string: "https://kkz6.github.io/Morrow/")!)
                }
                SettingsDivider()
                SettingsActionRow(title: "Source Code", symbol: "chevron.left.forwardslash.chevron.right") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/kkz6/Morrow")!)
                }
                SettingsDivider()
                SettingsActionRow(title: "Report a Problem", symbol: "bubble.left") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/kkz6/Morrow/issues/new")!)
                }
            }
        }
    }
}

struct GeneralPane: View {
    var body: some View {
        SettingsPane(section: SettingsSection.general) {
            GeneralOptionsPane(embedded: true)
            SectionHeader(title: "Appearance")
            AppearancePane(embedded: true)
            SectionHeader(title: "Menu Bar")
            MenuBarPane(embedded: true)
            SectionHeader(title: "Command Line")
            CommandLinePane(embedded: true)
            SectionHeader(title: "iCloud Sync")
            SyncPane(embedded: true)
        }
    }
}
