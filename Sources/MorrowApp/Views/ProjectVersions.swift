import SwiftUI
import MorrowCore

struct ProjectVersionsSection: View {
    var preferredEngine = RuntimeEngine.php
    @Environment(AppModel.self) private var model
    @State private var editing: ProjectRuntimeSelection?
    @State private var removing: ProjectRuntimeSelection?
    var body: some View {
        SettingsGroup(header: "Folder Versions") {
            if model.projectRuntimes.isEmpty {
                Text("Choose a folder and select its PHP, Node.js, or other runtime versions.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).settingsCellPadding()
                SettingsDivider()
            }
            ForEach(Array(model.projectRuntimes.enumerated()), id: \.element.id) { index, project in
                HStack(spacing: 12) {
                    IconTile(symbol: "folder.fill", color: .orange, size: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(URL(fileURLWithPath: project.path).lastPathComponent).font(.system(size: 13, weight: .medium))
                        Text(project.runtimes.values.sorted { $0.engine.rawValue < $1.engine.rawValue }.map { "\($0.engine.title) \($0.version)" }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(project.path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    ServiceActionButton(kind: .configuration, title: "Choose folder versions") { editing = project }
                    Menu {
                        Button("Reveal Folder") { NSWorkspace.shared.open(URL(fileURLWithPath: project.path)) }
                        Button("Clear Folder Versions…") { removing = project }
                    } label: { Image(systemName: "ellipsis").frame(width: 16) }.settingsMenuControl()
                }.settingsCellPadding()
                SettingsDivider()
            }
            SettingsActionRow(title: "Choose Folder…", symbol: "folder.badge.plus") {
                let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                guard panel.runModal() == .OK, let path = panel.url?.path else { return }
                editing = model.projectRuntimes.first { $0.path == path } ?? ProjectRuntimeSelection(path: path)
            }
        }
        .disabled(model.busy)
        .feedbackSheet(item: $editing) { ProjectVersionEditor(path: $0.path, initialEngine: preferredEngine).environment(model) }
        .confirmationDialog("Clear folder versions?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let project = removing {
                Button("Clear Versions") {
                    let path = project.path
                    model.perform("Clearing folder versions…", success: "Folder versions cleared; files preserved") { manager in
                        try RuntimeManager(store: manager.store, runner: manager.runner).clearProject(nil, directory: path)
                    }
                    removing = nil
                }
            }
        } message: { Text("The folder and its files stay in place. Parent folder versions or defaults will apply.") }
    }
}

struct ProjectVersionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let path: String
    @State private var engine: RuntimeEngine
    @State private var selection = ""
    @State private var customVersion = ""
    init(path: String, initialEngine: RuntimeEngine = .php) {
        self.path = path; _engine = State(initialValue: initialEngine)
    }
    private var saved: RuntimeInstallation? { model.projectRuntimes.first { $0.path == path }?.runtimes[engine.rawValue] }
    private var versions: [RuntimeInstallation] {
        var seen = Set<String>()
        return (model.inventory.runtimes + model.tools + model.projectRuntimes.flatMap { Array($0.runtimes.values) })
            .filter { $0.engine == engine && seen.insert($0.id).inserted }
    }
    private var options: [SelectOption<String>] {
        let installed = versions.map { SelectOption(value: $0.id, title: $0.version, symbol: engine.symbol) }
        let channels = (model.inventory.channels[engine.rawValue] ?? []).filter { channel in !versions.contains { $0.version == channel.version } }
            .prefix(60).map { SelectOption(value: $0.formula, title: $0.version, symbol: engine.symbol) }
        return [.init(value: "", title: "Inherit Default", symbol: "gearshape")] + installed
            + (engine == .node ? [.init(value: "lts", title: "Latest LTS", symbol: engine.symbol)] : []) + channels
            + [.init(value: "__custom__", title: "Other Version…", symbol: "square.and.pencil")]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Folder Versions").font(.system(size: 18, weight: .semibold))
            Text(path).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
            SettingsGroup {
                SettingRow(title: "Application") {
                    SettingsSelect(label: "Project runtime", selection: $engine, options: RuntimeEngine.allCases.map { .init(value: $0, title: $0.title, symbol: $0.symbol) })
                }
                SettingsDivider()
                SettingRow(title: "Version") {
                    SettingsSelect(label: "Folder runtime version", selection: $selection, options: options)
                }
                if selection == "__custom__" {
                    SettingsDivider()
                    SettingRow(title: "Requested version") {
                        SettingsInput(placeholder: engine == .php ? "8.4" : "Version or release series", text: $customVersion).frame(width: 190)
                    }
                }
            }.disabled(model.busy)
            Text("Applies to this folder and subfolders. PHP hosting and Morrow's Terminal commands use the selected version.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if let project = model.projectRuntimes.first(where: { $0.path == path }) {
                Text(project.runtimes.values.sorted { $0.engine.rawValue < $1.engine.rawValue }.map { "\($0.engine.title) \($0.version)" }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if model.runtimeChannelsLoading.contains(engine.rawValue) { HStack { ProgressView().controlSize(.small); Text("Finding versions…").font(.system(size: 11)) } }
            if let error = model.error { ErrorCard(message: error) { model.error = nil } }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.settingsButton().keyboardShortcut(.cancelAction).disabled(model.busy)
                Button(selection.isEmpty || versions.contains(where: { $0.id == selection }) ? "Save" : "Install & Save") { save() }
                    .settingsButton().disabled(model.busy || selection == (saved?.id ?? "") || selection == "__custom__" && customVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 480)
        .task(id: engine) { selection = saved?.id ?? ""; model.loadRuntimeChannels(engine) }
        .onChange(of: saved?.id) { _, id in selection = id ?? "" }
    }
    private func save() {
        let engine = engine, version = selection == "__custom__" ? customVersion.trimmingCharacters(in: .whitespacesAndNewlines) : selection, path = path, cli = model.cliURL
        model.perform("Saving folder version…", success: "\(engine.title) version saved for this folder") { manager in
            let runtimes = RuntimeManager(store: manager.store, runner: manager.runner)
            if version.isEmpty { try runtimes.clearProject(engine, directory: path) }
            else { _ = try runtimes.useForProject(engine, version: version, directory: path, cli: cli) }
        }
    }
}
