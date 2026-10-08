import SwiftUI
import MorrowCore

struct LogsPane: View {
    @Environment(AppModel.self) private var model
    @State private var viewer = LogViewerModel()
    private struct LogSource: Identifiable {
        let id: UUID
        let name: String
        let detail: String
        let symbol: String
        let url: URL
        let status: InstanceStatus
    }
    private var sources: [LogSource] {
        model.instances.map { LogSource(id: $0.id, name: $0.name, detail: "\($0.engine.title) \($0.installation.version)", symbol: $0.engine.symbol, url: model.manager.store.logURL($0), status: model.statuses[$0.id] ?? .unknown) }
        + (model.web.caddyPath == nil ? [] : [LogSource(id: model.web.id, name: "Sites", detail: "Caddy routing", symbol: "globe", url: model.sites.logURL, status: model.webStatus?.proxy ?? .unknown)])
        + model.mailServices.map { LogSource(id: $0.id, name: $0.name, detail: "Mailpit \($0.installation.version)", symbol: "envelope.fill", url: model.mail.logURL($0), status: model.mailStatuses[$0.id] ?? .unknown) }
    }
    private var selected: LogSource? { sources.first { $0.id == (model.logSiteID ?? model.logInstanceID) } ?? sources.first }
    var body: some View {
        SettingsPane(section: SettingsSection.logs) {
            if let instance = selected {
                SettingsGroup {
                    SettingRow(title: "Instance") {
                        SettingsSelect(label: "Instance",
                            selection: Binding(get: { selected?.id }, set: { model.logSiteID = nil; model.logInstanceID = $0 }),
                            options: sources.map { .init(value: Optional($0.id), title: $0.name, symbol: $0.symbol) })
                            .frame(maxWidth: 210, alignment: .trailing)
                    }
                }
                HStack(spacing: 8) {
                    Text(instance.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    StatusBadge(status: instance.status)
                }
                HStack(spacing: 8) {
                    SettingsInput(placeholder: "Search logs", text: $viewer.query, symbol: "magnifyingglass", clearable: true)
                    Toggle("Live", isOn: $viewer.follow).toggleStyle(.switch).controlSize(.small)
                    ControlIconButton(symbol: "arrow.clockwise", help: "Refresh logs") { Task { await viewer.refresh() } }.disabled(viewer.loading)
                    ControlIconButton(symbol: "doc.on.doc", help: "Copy displayed logs") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewer.visibleOutput, forType: .string)
                    }.disabled(viewer.visibleOutput.isEmpty)
                }.controlSize(.small)
                logContent
                HStack {
                    Text(viewer.truncated ? "Showing the most recent 128 KB" : viewer.follow ? "Following new output" : "Live updates paused")
                    Spacer()
                    if viewer.loading { ProgressView().controlSize(.mini) }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                if let error = viewer.error { ErrorCard(message: error) { viewer.error = nil } }
            } else {
                SettingsCard {
                    VStack(spacing: 10) {
                        Image(systemName: "terminal").font(.system(size: 30)).foregroundStyle(.secondary)
                        Text("No instance logs yet").font(.system(size: 15, weight: .semibold))
                        Text("Create a database instance to view its output here.").font(.system(size: 12)).foregroundStyle(.secondary)
                        Button("Go to Databases") { model.selection = .instances }.settingsButton(expands: true)
                            .padding(.horizontal, 28).padding(.top, 6)
                    }.frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
        }
        .task(id: selected?.id) {
            guard let instance = selected else { return }
            if model.preview { viewer.previewOutput(); return }
            viewer.configure(url: instance.url)
            await viewer.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                if viewer.follow { await viewer.refresh() }
            }
        }
        .onChange(of: viewer.follow) { _, live in if live { Task { await viewer.refresh() } } }
    }
    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    if viewer.output.isEmpty {
                        Text(viewer.loading ? "Loading logs…" : "No output yet. Start this instance to see its logs.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).padding(14)
                    } else if viewer.visibleOutput.isEmpty {
                        Text("No lines match your search.").font(.system(size: 12)).foregroundStyle(.secondary).padding(14)
                    } else {
                        Text(viewer.visibleOutput).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true).padding(12)
                    }
                    Color.clear.frame(height: 1).id("log-bottom")
                }.frame(minWidth: 480, alignment: .topLeading)
            }
            .frame(height: 340)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DS.borderColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onChange(of: viewer.visibleOutput) { _, _ in
                if viewer.follow { proxy.scrollTo("log-bottom", anchor: .bottomLeading) }
            }
            .onChange(of: viewer.follow) { _, live in
                if live { proxy.scrollTo("log-bottom", anchor: .bottomLeading) }
            }
        }
    }
}
