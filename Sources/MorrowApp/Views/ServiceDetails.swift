import SwiftUI
import MorrowCore

struct ServiceLogRequest: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let url: URL
}
struct ConfigurationRequest: Identifiable {
    let id = UUID()
    let title: String
    let files: [ConfigurationFile]
}

/// The same viewer can be embedded in a card or shown as its own service sheet.
struct ServiceLogViewer: View {
    @Environment(AppModel.self) private var model
    let url: URL
    var height: CGFloat = 300
    @State private var viewer = LogViewerModel()
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                SettingsInput(placeholder: "Search logs", text: $viewer.query, symbol: "magnifyingglass", clearable: true)
                Toggle("Live", isOn: $viewer.follow).toggleStyle(.switch).controlSize(.small)
                ServiceActionButton(kind: .refresh, title: "Refresh logs") { Task { await viewer.refresh() } }
                ServiceActionButton(kind: .copy, title: "Copy displayed logs") { model.copy(viewer.visibleOutput, message: "Logs copied") }.disabled(viewer.visibleOutput.isEmpty)
            }
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(viewer.visibleOutput.isEmpty ? viewer.query.isEmpty ? "No output yet." : "No matching lines." : viewer.visibleOutput)
                            .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: true, vertical: true).padding(12)
                        Color.clear.frame(height: 1).id("last-line")
                    }.frame(minWidth: 470, alignment: .leading)
                }.frame(height: height).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: DS.Radius.action))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.action).strokeBorder(DS.borderColor, lineWidth: 0.5))
                .onChange(of: viewer.visibleOutput) { _, _ in if viewer.follow { proxy.scrollTo("last-line", anchor: .bottomLeading) } }
            }
            HStack { Text(viewer.truncated ? "Latest 128 KB" : viewer.follow ? "Live output" : "Paused"); Spacer(); if viewer.loading { ProgressView().controlSize(.mini) } }.font(.system(size: 10)).foregroundStyle(.secondary)
            if let error = viewer.error { ErrorCard(message: error) { viewer.error = nil } }
        }
        .task(id: url) {
            if model.preview { viewer.previewOutput(); return }
            viewer.configure(url: url); await viewer.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                if viewer.follow { await viewer.refresh() }
            }
        }
    }
}
struct ServiceLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: ServiceLogRequest
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) { Text(request.title + " Logs").font(.system(size: 18, weight: .semibold)); Text(request.subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }
                Spacer()
                Button("Done") { dismiss() }.settingsButton().keyboardShortcut(.cancelAction)
            }
            ServiceLogViewer(url: request.url)
        }.padding(20).frame(width: 620).serviceFeedback()
    }
}
struct ConfigurationEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ConfigurationRequest
    @State private var selected = ""
    @State private var original = ""
    @State private var text = ""
    @State private var issue: String?
    private var file: ConfigurationFile? { request.files.first { $0.id == selected } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.title + " Configuration").font(.system(size: 18, weight: .semibold))
            SettingsSelect(label: "Configuration file", selection: $selected, options: request.files.map { .init(value: $0.id, title: $0.title, symbol: "doc.text") })
            if let file {
                Text(file.url.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                if !file.editable { Text(file.readOnlyReason).font(.system(size: 12)).foregroundStyle(.secondary) }
                TextEditor(text: $text).font(.system(size: 12, design: .monospaced)).scrollContentBackground(.hidden)
                    .padding(8).frame(height: 300).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: DS.Radius.action))
                    .disabled(!file.editable)
            }
            if let issue { ErrorCard(message: issue) { self.issue = nil } }
            HStack {
                ServiceActionButton(kind: .refresh, title: "Reload configuration from disk") { reload() }
                if let file { Button("Open in Editor") { NSWorkspace.shared.open(file.url) }.settingsButton() }
                Spacer(); Button("Done") { dismiss() }.settingsButton().keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let file else { return }
                    do { try ConfigurationAccess(store: model.manager.store, runner: model.manager.runner).save(file, text: text, original: original); original = text; model.notify("Configuration saved. Restart the affected service to apply it.") }
                    catch { issue = error.localizedDescription }
                }.settingsButton().disabled(file?.editable != true || text == original)
            }
        }.padding(20).frame(width: 620).serviceFeedback()
        .onAppear { selected = request.files.first?.id ?? "" }
        .onChange(of: selected) { _, _ in
            reload()
        }
    }
    private func reload() {
        guard let file else { return }
        do { original = try String(contentsOf: file.url, encoding: .utf8); text = original; issue = nil }
        catch { issue = error.localizedDescription }
    }
}
