import SwiftUI
import MorrowCore

struct DumpsPane: View {
    @Environment(AppModel.self) private var model
    @State private var projects: [DiagnosticProject] = []
    @State private var requests: [DiagnosticRequest] = []
    @State private var project = ""
    @State private var selected: String?
    @State private var search = ""
    @State private var kind = "all"
    @State private var issue: String?
    @State private var clearing = false
    private var diagnostics: Diagnostics { Diagnostics(store: model.manager.store) }
    private var current: DiagnosticProject? { projects.first { $0.path == project } }
    private var visible: [DiagnosticRequest] {
        requests.filter { request in
            (project.isEmpty || request.project == project) && (search.isEmpty || request.title.localizedCaseInsensitiveContains(search) || request.events.contains { $0.title.localizedCaseInsensitiveContains(search) })
        }
    }
    var body: some View {
        SettingsPane(section: SettingsSection.dumps) {
            SettingsGroup {
                SettingRow(title: "Project capture", subtitle: "Choose the PHP folders you want to inspect.") {
                    Button("Add Folder…", action: addFolder).settingsButton(height: 28).disabled(model.busy)
                }
                if !projects.isEmpty {
                    SettingsDivider()
                    SettingRow(title: "Folder") {
                        SettingsSelect(label: "Capture project", selection: $project, options: [.init(value: "", title: "All projects", symbol: "folder")] + projects.map { .init(value: $0.path, title: URL(fileURLWithPath: $0.path).lastPathComponent, symbol: "folder") })
                    }
                    if let current {
                        SettingsDivider()
                        SettingRow(title: "Capture", subtitle: LocalizedStringKey(current.path)) {
                            Toggle("Capture this project", isOn: Binding(get: { current.enabled }, set: { configure(path: current.path, enabled: $0) })).settingsToggle().disabled(model.busy)
                        }
                    }
                }
            }
            if projects.isEmpty {
                SettingsNote(text: "Inspect dump() and dd() from your PHP projects in Morrow. Laravel 11 and newer also provide queries, logs, views, and queue jobs. Choose a folder to start capturing; your project files stay untouched.")
            } else {
                HStack {
                    SettingsInput(placeholder: "Search requests and events", text: $search, symbol: "magnifyingglass", clearable: true)
                    SettingsSelect(label: "Event type", selection: $kind, options: ["all", "dump", "query", "log", "view", "job", "error"].map { .init(value: $0, title: $0 == "all" ? "All events" : $0.capitalized, symbol: "line.3.horizontal.decrease") })
                    ServiceActionButton(kind: .remove, title: "Clear captured requests") { clearing = true }.disabled(requests.isEmpty)
                }
                SettingsCard {
                    HSplitView {
                        List(selection: $selected) {
                            ForEach(visible) { request in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(request.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                    Text(URL(fileURLWithPath: request.project).lastPathComponent).font(.caption).foregroundStyle(.secondary)
                                    HStack { Text(Date(timeIntervalSince1970: request.time), style: .time); Spacer(); Text("\(request.events.count) events") }.font(.caption2).foregroundStyle(.secondary)
                                }.padding(.vertical, 4).tag(request.id)
                            }
                        }.listStyle(.inset).scrollContentBackground(.hidden).frame(minWidth: 160, idealWidth: 190, maxWidth: 240)
                        ScrollView {
                            if let request = requests.first(where: { $0.id == selected }) {
                                LazyVStack(alignment: .leading, spacing: 14) {
                                    ForEach(request.events.filter { kind == "all" || $0.kind == kind }) { event in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(event.kind.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(event.kind == "error" ? Color.red : Color.secondary)
                                            Text(event.title).font(.system(size: 12, weight: .medium, design: event.kind == "query" ? .monospaced : .default)).textSelection(.enabled)
                                            DiagnosticValueView(value: event.value)
                                            if let file = event.file {
                                                Button("\(URL(fileURLWithPath: file).lastPathComponent):\(event.line ?? 1)") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)]) }.buttonStyle(.link).font(.caption).help(file)
                                            }
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                        Divider()
                                    }
                                }.padding(14)
                            } else { Text(visible.isEmpty ? "No captures yet. Visit your site or run PHP through Morrow." : "Select a request").foregroundStyle(.secondary).padding(24) }
                        }.frame(minWidth: 240, maxWidth: .infinity)
                    }.frame(height: 360)
                }
                SettingsNote(text: "Capture applies to Morrow-hosted PHP sites and new commands run through Morrow’s PHP shim. Laravel event capture requires uncached local configuration. Existing queue workers keep running; they start capturing after their next launch through Morrow. Up to 200 requests per project are kept locally; dumps may contain private application data.")
            }
            if let issue { ErrorCard(message: issue) { self.issue = nil } }
        }
        .task(id: project) {
            repeat {
                await refresh()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            } while !Task.isCancelled
        }
        .onChange(of: project) { _, _ in selected = nil }
        .confirmationDialog(project.isEmpty ? "Clear all captured requests?" : "Clear this project’s captured requests?", isPresented: $clearing, titleVisibility: .visible) {
            Button("Clear Captures", role: .destructive) {
                let diagnostics = diagnostics, path = project.isEmpty ? nil : project
                model.perform("Clearing captures…", operation: { _ in try diagnostics.clear(project: path) }, completion: { selected = nil; requests = [] })
            }
        }
    }
    private func addFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false; panel.prompt = "Enable Capture"
        panel.begin { response in if response == .OK, let url = panel.url { configure(path: url.path, enabled: true) } }
    }
    private func configure(path: String, enabled: Bool) {
        model.perform(enabled ? "Enabling capture…" : "Disabling capture…", operation: { manager in try Diagnostics(store: manager.store).configure(path: path, enabled: enabled, runner: manager.runner) }, completion: { project = path; Task { await refresh() } })
    }
    private func refresh() async {
        let diagnostics = diagnostics, path = project.isEmpty ? nil : project
        do {
            let result = try await Task.detached { (try diagnostics.projects(), try diagnostics.requests(project: path)) }.value
            try Task.checkCancellation(); projects = result.0; requests = result.1; issue = nil
            if selected == nil || !requests.contains(where: { $0.id == selected }) { selected = visible.first?.id }
        } catch { if !Task.isCancelled { issue = error.localizedDescription } }
    }
}

private struct DiagnosticValueView: View {
    let value: DiagnosticValue
    var body: some View {
        switch value {
        case .object(let children):
            ForEach(children.keys.sorted(), id: \.self) { key in
                DisclosureGroup { DiagnosticValueView(value: children[key]!).padding(.leading, 8) } label: { Text(key).font(.system(size: 11, design: .monospaced)) }
            }
        case .array(let children):
            ForEach(children.indices, id: \.self) { index in
                DisclosureGroup { DiagnosticValueView(value: children[index]).padding(.leading, 8) } label: { Text("[\(index)]").font(.system(size: 11, design: .monospaced)) }
            }
        default: Text(value.text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
        }
    }
}
