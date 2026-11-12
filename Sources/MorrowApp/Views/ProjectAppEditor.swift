import SwiftUI
import MorrowCore

struct ProjectAppEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let site: LocalSite
    let initialRuntime: RuntimeEngine
    @State private var runtime = RuntimeEngine.rust
    @State private var executable = "cargo"
    @State private var arguments = "run"
    @State private var port = ""
    @State private var issue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("App Command").font(.system(size: 18, weight: .semibold))
            Text(site.domain).font(.system(size: 12)).foregroundStyle(.secondary)
            SettingsGroup {
                SettingRow(title: "Runtime") {
                    SettingsSelect(label: "App runtime", selection: Binding(get: { runtime }, set: { select($0) }),
                                   options: RuntimeEngine.allCases.map { .init(value: $0, title: $0.title, symbol: $0.symbol) })
                }
                SettingsDivider()
                SettingRow(title: "Command") {
                    SettingsSelect(label: "App command", selection: $executable,
                                   options: runtime.commands.map { .init(value: $0, title: $0, symbol: "terminal") })
                }
                SettingsDivider()
                SettingRow(title: "Arguments") {
                    SettingsInput(placeholder: "One argument per line", text: $arguments, axis: .vertical).frame(width: 255)
                }
                SettingsDivider()
                SettingRow(title: "Local port") {
                    SettingsInput(placeholder: "3000", text: $port).frame(width: 100)
                }
            }.disabled(model.busy)
            SettingsNote(text: "Enter one argument per line. The command runs in the project folder. Set the app to listen on 127.0.0.1 using PORT or an explicit port argument.")
            if let error = issue ?? model.error { ErrorCard(message: error) { issue = nil; model.error = nil } }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.settingsButton().keyboardShortcut(.cancelAction)
                Button("Save") { save(start: false) }.settingsButton()
                Button("Save & Start") { save(start: true) }.settingsButton().keyboardShortcut(.defaultAction)
                    .disabled(port.isEmpty || site.isIgnoredForHosting)
            }.disabled(model.busy)
        }.padding(20).frame(width: 490)
            .onAppear {
                port = site.proxyPort.map(String.init) ?? ""
                if let command = model.webStatus?.applications[site.id]?.command {
                    runtime = command.runtime; executable = command.executable; arguments = command.arguments.joined(separator: "\n")
                } else { select(initialRuntime) }
            }
    }

    private func select(_ selected: RuntimeEngine) {
        runtime = selected
        executable = selected == .rust ? "cargo" : selected == .node ? "npm" : selected.commands[0]
        arguments = selected == .rust ? "run" : selected == .node ? "run\ndev" : ""
    }

    private func save(start: Bool) {
        guard let port = Int(port), (1...65_535).contains(port) else {
            issue = "Enter a local port between 1 and 65535."
            return
        }
        issue = nil
        let id = site.id
        let command = ProjectAppCommand(runtime: runtime, executable: executable,
                                        arguments: arguments.components(separatedBy: .newlines).filter { !$0.isEmpty })
        model.perform(start ? "Starting project app…" : "Saving app command…", operation: { manager in
            let apps = ProjectApps(store: manager.store, runner: manager.runner)
            try apps.configure(id, command: command, port: port)
            if start { try apps.start(id) }
        }, completion: { dismiss() })
    }
}
