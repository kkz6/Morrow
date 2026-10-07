import SwiftUI
import MorrowCore

struct InstancesPane: View {
    @Environment(AppModel.self) private var model
    @State private var editing: DatabaseInstance?
    @State private var query = ""
    private var filtered: [DatabaseInstance] {
        model.instances.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.engine.title.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        SettingsPane(section: SettingsSection.instances) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your local workspace").font(.system(size: 13, weight: .medium))
                    Text("\(model.runningCount) running · \(model.instances.count) instances").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if !model.instances.isEmpty {
                    Button { model.requestCreation() } label: { Label("New Instance", systemImage: "plus") }
                        .settingsButton().disabled(model.busy)
                }
            }
            if model.instances.isEmpty {
                SettingsCard {
                    VStack(spacing: 10) {
                        Image(systemName: "externaldrive.badge.plus").font(.system(size: 28, weight: .light)).foregroundStyle(.teal)
                        Text("No databases yet").font(.system(size: 14, weight: .medium))
                        Text("Create an instance to start your project.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 24)
                    SettingsDivider()
                    SettingsActionRow(title: "Create Instance…", symbol: "plus") { model.requestCreation() }.disabled(model.busy)
                }
            } else {
                SettingsInput(placeholder: "Find an instance", text: $query, symbol: "magnifyingglass", clearable: true)
                SettingsGroup(header: "Local Instances") {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, instance in
                        InstanceRow(instance: instance, edit: { editing = instance }, logs: { model.showLogs(for: instance) })
                        if index < filtered.count - 1 { SettingsDivider() }
                    }
                    if filtered.isEmpty { Text("No matching instances").font(.system(size: 12)).foregroundStyle(.secondary).padding(20) }
                }
            }
            SettingsNote(text: "Each instance has its own port and data directory. Your databases keep running when you close Morrow.")
        }
        .sheet(item: $editing) { InstanceEditor(existing: $0).environment(model) }
    }
}

struct InstanceRow: View {
    @Environment(AppModel.self) private var model
    let instance: DatabaseInstance
    let edit: () -> Void
    let logs: () -> Void
    private var status: InstanceStatus { model.statuses[instance.id] ?? .unknown }
    private var active: Bool { status == .running || status == .starting }
    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: instance.engine.symbol, color: instance.engine.color, size: 30)
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(instance.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                    Text("\(instance.engine.title) \(instance.installation.version) · :\(String(instance.port))").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Instance settings")
            StatusBadge(status: status)
            Button {
                let id = instance.id, shouldStop = active
                model.perform(active ? "Stopping \(instance.name)…" : "Starting \(instance.name)…") { manager in
                    if shouldStop { try manager.stop(id) } else { try manager.start(id) }
                }
            } label: { Image(systemName: active ? "stop.fill" : "play.fill").font(.system(size: 11)) }
                .buttonStyle(SettingsButtonStyle(height: 28, iconOnly: true)).help(active ? "Stop instance" : "Start instance").disabled(model.busy || status == .missingBinary)
            Menu {
                Button("Instance Settings…", action: edit)
                Button("View Logs…", action: logs)
                Button("Copy Connection Address") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(instance.connectionURL, forType: .string) }
                Button("Open Data Folder") { NSWorkspace.shared.open(model.manager.store.dataDirectory(instance)) }
                Divider()
                Button("Restart") { let id = instance.id; model.perform("Restarting \(instance.name)…") { try $0.restart(id) } }.disabled(!active || model.busy)
            } label: { Image(systemName: "ellipsis").frame(width: 16) }.settingsMenuControl()
        }.padding(.horizontal, 12).padding(.vertical, 14)
    }
}

struct InstanceEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let existing: DatabaseInstance?
    @State private var engine: DatabaseEngine
    @State private var installationID = ""
    @State private var name: String
    @State private var port: String
    @State private var memory: String
    @State private var connections: String
    @State private var autoStart: Bool
    @State private var startAfterCreate = true
    @State private var validationError: String?
    @State private var confirmRemoval = false
    @State private var portIssue: String?
    private var versions: [Installation] { model.installations.filter { $0.engine == engine } }
    private var chosen: Installation? { versions.first { $0.id == installationID } }
    private var versionOptions: [SelectOption<String>] {
        var result = versions.map { SelectOption(value: $0.id, title: $0.version, symbol: "square.stack.3d.up") }
        result += model.channels.filter { channel in channel.engine == engine && !versions.contains { HomebrewInstaller.matches($0, request: channel.formula) } }
            .map { .init(value: $0.formula, title: $0.title, symbol: "square.stack.3d.up") }
        if result.isEmpty { result.append(.init(value: "automatic", title: "Automatic version", symbol: "square.stack.3d.up")) }
        if !installationID.isEmpty && !result.contains(where: { $0.value == installationID }) && HomebrewInstaller.isAllowedFormula(installationID, engine: engine) {
            result.append(.init(value: installationID, title: installationID.components(separatedBy: "/").last ?? installationID, symbol: "square.stack.3d.up"))
        }
        return result
    }
    private var isRunning: Bool { existing.map { [.running, .starting].contains(model.statuses[$0.id] ?? .unknown) } ?? false }
    init(existing: DatabaseInstance? = nil, installation: Installation? = nil, engine: DatabaseEngine? = nil, version: String? = nil) {
        self.existing = existing
        _engine = State(initialValue: existing?.engine ?? installation?.engine ?? engine ?? .postgresql)
        _name = State(initialValue: existing?.name ?? "")
        _port = State(initialValue: String(existing?.port ?? installation?.engine.defaultPort ?? engine?.defaultPort ?? 5432))
        _memory = State(initialValue: String(existing?.memoryMB ?? 128))
        _connections = State(initialValue: String(existing?.maxConnections ?? 100))
        _autoStart = State(initialValue: existing?.autoStart ?? false)
        _installationID = State(initialValue: existing?.installation.id ?? installation?.id ?? version ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconTile(symbol: engine.symbol, color: engine.color, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(existing == nil ? "New Instance" : "Instance Settings").font(.system(size: 18, weight: .semibold))
                    Text(existing?.name ?? "Give your project a database of its own.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            SettingsCard {
                if existing == nil {
                    SettingRow(title: "Database") {
                        SettingsSelect(label: "Database", selection: $engine, options:
                            DatabaseEngine.allCases.map { .init(value: $0, title: $0.title, symbol: $0.symbol) })
                    }
                    SettingsDivider()
                    SettingRow(title: "Version") {
                        SettingsSelect(label: "Version", selection: $installationID, options: versionOptions)
                            .frame(maxWidth: 220, alignment: .trailing)
                    }
                } else {
                    SettingRow(title: "Version") { Text(existing!.installation.version).font(.system(size: 13)).foregroundStyle(.secondary) }
                }
                SettingsDivider()
                SettingRow(title: "Instance name") { SettingsInput(placeholder: "Instance name", text: $name).frame(width: 200) }
                SettingsDivider()
                SettingRow(title: "Port") { SettingsInput(placeholder: "Port", text: $port).frame(width: 130) }
                if engine.supportsMemory {
                    SettingsDivider()
                    SettingRow(title: engine == .postgresql ? "Shared buffers (MB)" : "Memory limit (MB)") {
                        SettingsInput(placeholder: "Memory in MB", text: $memory).frame(width: 130)
                    }
                }
                if engine.supportsConnections {
                    SettingsDivider()
                    SettingRow(title: "Maximum connections") { SettingsInput(placeholder: "Maximum connections", text: $connections).frame(width: 130) }
                }
                SettingsDivider()
                SettingRow(title: "Start at macOS login") { Toggle("Start at macOS login", isOn: $autoStart).settingsToggle() }
                if existing == nil {
                    SettingsDivider()
                    SettingRow(title: "Start after creating") { Toggle("Start after creating", isOn: $startAfterCreate).settingsToggle() }
                }
            }.disabled(isRunning || model.busy)
            if let portIssue { Text(portIssue).font(.system(size: 12)).foregroundStyle(.red) }
            if isRunning { Text("Stop this instance to edit its settings.").font(.system(size: 12)).foregroundStyle(.orange) }
            Text("Local development: connects on 127.0.0.1 with no password. \(engine == .postgresql ? "User: postgres." : (engine == .mysql || engine == .mariadb) ? "User: root." : "")")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let existing {
                Text(existing.connectionURL).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                Text("Version changes use a new instance and data migration.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let error = validationError ?? model.error { ErrorCard(message: error) { validationError = nil; model.error = nil } }
            if let activity = model.activity { HStack { ProgressView().controlSize(.small); Text(activity).font(.system(size: 12)) } }
            HStack {
                if let existing {
                    Button("Remove…", role: .destructive) { confirmRemoval = true }.settingsButton().disabled(model.busy || isRunning)
                    Button("Open Data") { NSWorkspace.shared.open(model.manager.store.dataDirectory(existing)) }.settingsButton()
                }
                Spacer()
                Button("Cancel") { dismiss() }.settingsButton().keyboardShortcut(.cancelAction).disabled(model.busy)
                Button(existing == nil ? "Create Instance" : "Save Changes", action: save)
                    .settingsButton().keyboardShortcut(.defaultAction)
                    .disabled(model.busy || isRunning || portIssue != nil)
            }
        }.padding(20).frame(width: 470)
        .onAppear {
            chooseVersion(resetPort: true)
            if existing == nil && model.homebrewAvailable { model.loadChannels() }
        }
        .onChange(of: engine) { _, _ in chooseVersion(resetPort: true) }
        .onChange(of: model.channels.map(\.id)) { _, _ in chooseVersion() }
        .onChange(of: model.installations.map(\.id)) { _, _ in chooseVersion() }
        .onChange(of: model.homebrewAvailable) { _, available in
            if existing == nil && available { model.loadChannels() }
        }
        .task(id: "\(port):\(isRunning)") {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !model.preview else { return }
            guard !isRunning else { portIssue = nil; return }
            guard let value = Int(port) else { portIssue = "Enter a numeric port between 1024 and 65535."; return }
            do { try model.manager.validatePort(value, excluding: existing?.id); portIssue = nil }
            catch { portIssue = error.localizedDescription }
        }
        .confirmationDialog("Remove \(existing?.name ?? "instance")?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Remove and Preserve Data") {
                guard let existing else { return }; let id = existing.id
                model.perform("Removing \(existing.name)…", operation: { try $0.remove(id) }, completion: { dismiss() })
            }
            Button("Delete Instance and Data", role: .destructive) {
                guard let existing else { return }; let id = existing.id
                model.perform("Deleting \(existing.name)…", operation: { try $0.remove(id, deleteData: true) }, completion: { dismiss() })
            }
        } message: { Text("Preserved data is moved into Morrow’s archives folder.") }
    }
    private func chooseVersion(resetPort: Bool = false) {
        guard existing == nil else { return }
        if !versionOptions.contains(where: { $0.value == installationID }) { installationID = versionOptions.first?.value ?? "automatic" }
        if resetPort && !model.preview { port = String((try? model.manager.suggestedPort(engine: engine)) ?? engine.defaultPort) }
    }
    private func save() {
        guard let port = Int(port), let memory = Int(memory), let connections = Int(connections) else {
            validationError = "Enter valid numeric settings."; return
        }
        let selected = existing?.installation ?? chosen
        let placeholder = selected ?? Installation(engine: engine, formula: "", version: "", prefix: "")
        let instance = DatabaseInstance(id: existing?.id ?? UUID(), name: name, installation: placeholder, port: port,
            autoStart: autoStart, memoryMB: memory, maxConnections: connections, createdAt: existing?.createdAt ?? Date())
        do { try model.manager.preflight(name: name, engine: engine, port: port, memoryMB: memory, maxConnections: connections, excluding: existing?.id) }
        catch { validationError = error.localizedDescription; return }
        let creating = existing == nil
        let start = startAfterCreate
        let selectedEngine = engine, requestedVersion = installationID
        let result = ProvisionResult()
        model.perform(creating ? "Creating \(name)…" : "Saving \(name)…", operation: { manager in
            if creating {
                result.instance = try manager.provision(engine: selectedEngine, version: requestedVersion, name: instance.name,
                    port: instance.port, autoStart: instance.autoStart, memoryMB: instance.memoryMB, maxConnections: instance.maxConnections, installation: selected)
            }
            else { try manager.update(instance) }
        }, completion: {
            dismiss()
            if creating && start, let created = result.instance { model.perform("Starting \(created.name)…") { try $0.start(created.id) } }
        })
    }
}

// Written once by the provisioning operation, read after its awaited completion.
private final class ProvisionResult: @unchecked Sendable { var instance: DatabaseInstance? }
