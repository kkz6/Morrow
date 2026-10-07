import SwiftUI
import ServiceManagement
import MorrowCore

struct CommandLinePane: View {
    @Environment(AppModel.self) private var model
    @State private var installed = false
    private var source: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/morrow") }
    var body: some View {
        SettingsPane(section: SettingsSection.commandLine) {
            SettingsNote(text: "Manage the same databases from Terminal. The app and CLI share your configuration, versions, and data.")
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
                }.padding(12)
            }
            SettingsGroup(header: "Example") {
                Text("morrow db create postgresql my-app --start\nmorrow db list\nmorrow db logs my-app")
                    .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        }.onAppear {
            installed = (try? FileManager.default.destinationOfSymbolicLink(atPath: CLIInstaller.defaultDestination.path)) == source.path
        }
    }
}

struct GeneralPane: View {
    @Environment(AppModel.self) private var model
    @State private var loginEnabled = false
    @State private var brewPath = ""
    var body: some View {
        SettingsPane(section: SettingsSection.general) {
            SettingsGroup {
                SettingRow(title: "Launch Morrow at login", subtitle: "Keep your database controls close by") {
                    Toggle("Launch Morrow at login", isOn: Binding(get: { loginEnabled }, set: { value in
                        if model.preview { loginEnabled = value; return }
                        do {
                            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginEnabled = value
                        } catch { model.error = error.localizedDescription }
                    })).settingsToggle()
                }
                SettingsDivider()
                SettingRow(title: "Homebrew", subtitle: model.homebrewAvailable ? "Native installer is available" : "Installer not found") {
                    Image(systemName: model.homebrewAvailable ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(model.homebrewAvailable ? .green : .orange)
                }
            }
            SettingsGroup(header: "Installer Location") {
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
                }.padding(12)
            }
            SettingsNote(text: "Database startup is configured per instance. Morrow uses macOS launchd so services continue running independently of the menu bar app.")
        }.onAppear {
            loginEnabled = model.preview ? false : SMAppService.mainApp.status == .enabled
            brewPath = model.preferences.homebrewPath
        }
    }
}

struct MenuBarPane: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        SettingsPane(section: SettingsSection.menuBar) {
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
    @Environment(AppModel.self) private var model
    var body: some View {
        SettingsPane(section: SettingsSection.appearance) {
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

struct StoragePane: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        SettingsPane(section: SettingsSection.storage) {
            SettingsGroup(header: "Local Storage") {
                SettingsActionRow(title: "Open Morrow Data…", symbol: "folder") { NSWorkspace.shared.open(model.manager.store.root) }
                SettingsDivider()
                SettingsActionRow(title: "Open Preserved Data…", symbol: "archivebox") {
                    let path = model.manager.store.root.appendingPathComponent("archives")
                    do { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true); NSWorkspace.shared.open(path) }
                    catch { model.error = error.localizedDescription }
                }
            }
            Text(model.manager.store.root.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            SettingsNote(text: "Removing an instance preserves its files by default. View server output in Logs, or open an instance’s data folder below.")
            if !model.instances.isEmpty {
                SettingsGroup(header: "Instance Folders") {
                    ForEach(Array(model.instances.enumerated()), id: \.element.id) { index, instance in
                        SettingRow(title: LocalizedStringKey(instance.name), subtitle: LocalizedStringKey(instance.engine.title)) {
                            HStack {
                                Button("Logs") { model.showLogs(for: instance) }.settingsButton(height: 30)
                                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([model.manager.store.instanceDirectory(instance)]) }.settingsButton(height: 30)
                            }
                        }
                        if index < model.instances.count - 1 { SettingsDivider() }
                    }
                }
            }
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
