import SwiftUI
import WebKit
import MorrowCore

struct MailInboxSheet: View {
    let service: MailService
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var messages: [MailMessageSummary] = []
    @State private var tags: [String] = []
    @State private var project = ""
    @State private var search = ""
    @State private var selected: String?
    @State private var message: MailMessage?
    @State private var detail = "HTML"
    @State private var source = ""
    @State private var total = 0
    @State private var offset = 0
    @State private var issue: String?
    @State private var deleting = false
    @State private var loading = false
    @State private var groupedInboxes = false
    @State private var supportsGrouping = true
    private var inbox: MailInbox { MailInbox(service: service) }
    private var filterKey: String { "\(project)|\(search)|\(offset)" }
    private var projectNames: [String] { Array(Set(tags + model.web.sites.map(\.domain))).sorted() }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                IconTile(symbol: "tray.fill", color: .orange, size: 28)
                Text(service.name).font(.headline)
                Spacer()
                Button("Copy SMTP Settings") {
                    model.copy((try? service.appConfiguration(project: project)) ?? service.appConfiguration, message: "SMTP settings copied")
                }.settingsButton(height: 28)
                Button("Done") { dismiss() }.settingsButton(height: 28).keyboardShortcut(.cancelAction)
            }
            HStack {
                SettingsInput(placeholder: "Search mail", text: $search, symbol: "magnifyingglass", clearable: true)
                SettingsSelect(label: "Project inbox", selection: $project, options: [.init(value: "", title: "All inboxes", symbol: "tray.full")] + projectNames.map { .init(value: $0, title: $0, symbol: "folder") })
            }
            if let issue { ErrorCard(message: issue) { self.issue = nil } }
            HSplitView {
                VStack(spacing: 0) {
                    List(selection: $selected) {
                        ForEach(messages) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { if !item.Read { Circle().fill(Color.morrowAccent).frame(width: 5, height: 5) }; Text(item.Subject.isEmpty ? "(No subject)" : item.Subject).fontWeight(.medium).lineLimit(1) }
                                Text(item.From.label).font(.caption).lineLimit(1)
                                Text(item.Snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.padding(.vertical, 5).tag(item.ID)
                        }
                    }.listStyle(.inset).scrollContentBackground(.hidden).overlay {
                        if messages.isEmpty { Text(loading ? "Loading mail…" : "No messages").foregroundStyle(.secondary) }
                    }
                    HStack {
                        Button { offset = max(0, offset - 50) } label: { Image(systemName: "chevron.left") }.settingsButton(height: 26).disabled(offset == 0)
                        Text(total == 1 ? "1 message" : "\(total) messages").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { offset += 50 } label: { Image(systemName: "chevron.right") }.settingsButton(height: 26).disabled(offset + messages.count >= total)
                    }.padding(8)
                }.frame(minWidth: 190, idealWidth: 210, maxWidth: 240)
                VStack(alignment: .leading, spacing: 10) {
                    if let message {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.Subject.isEmpty ? "(No subject)" : message.Subject).font(.headline).textSelection(.enabled)
                                Text("From: \(message.From.label)").textSelection(.enabled)
                                Text("To: \((message.To ?? []).map(\.label).joined(separator: ", "))").textSelection(.enabled)
                                if !(message.Cc ?? []).isEmpty { Text("Cc: \((message.Cc ?? []).map(\.label).joined(separator: ", "))") }
                                if !(message.Bcc ?? []).isEmpty { Text("Bcc: \((message.Bcc ?? []).map(\.label).joined(separator: ", "))") }
                                Text(formattedDate(message.Date)).foregroundStyle(.secondary)
                            }.font(.caption)
                            Spacer()
                            ServiceActionButton(kind: .remove, title: "Delete this message") { deleting = true }
                        }
                        HStack {
                            SettingsSelect(label: "Message format", selection: $detail, options: ["HTML", "Text", "Headers", "Raw"].map { .init(value: $0, title: $0, symbol: "doc.text") })
                            Spacer()
                            Menu("Save…") {
                                Button("Original Email (.eml)") { Task { await saveRaw(message) } }
                                ForEach((message.Attachments ?? []) + (message.Inline ?? [])) { attachment in
                                    Button(attachment.FileName.isEmpty ? "Attachment" : attachment.FileName) { Task { await saveAttachment(attachment, message: message) } }
                                }
                            }.menuStyle(.borderlessButton).fixedSize()
                        }
                        if detail == "HTML", !message.HTML.isEmpty {
                            SafeMailHTML(html: message.HTML)
                            Text("Remote images and scripts are blocked.").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            ScrollView { Text(detail == "HTML" || detail == "Text" ? message.Text : source).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                        }
                    } else { Text(selected == nil ? "Select a message" : "Loading message…").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }.padding(12).frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.frame(maxHeight: .infinity)
            HStack {
                Text(!supportsGrouping ? "This Mailpit version does not support project inboxes. Choose a current catalog release to use grouping." : groupedInboxes ? "Select a project and copy its SMTP settings to group new messages. Any test password works." : "Restart this mail server to enable project inboxes. Existing messages are preserved.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                if !groupedInboxes && supportsGrouping {
                    Button("Restart Mail") {
                        model.perform("Restarting mail…", operation: { manager in try MailManager(store: manager.store, runner: manager.runner).restart(service.id) })
                    }.settingsButton(height: 28).disabled(model.busy)
                }
            }
        }.padding(18).frame(width: 680, height: 560)
        .task {
            let manager = model.mail, service = service
            supportsGrouping = (try? await Task.detached { try manager.supportsProjectInboxes(service) }.value) ?? false
        }
        .task(id: filterKey) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            repeat {
                await refresh()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            } while !Task.isCancelled
        }
        .onChange(of: search) { _, _ in offset = 0 }
        .onChange(of: project) { _, _ in offset = 0 }
        .task(id: selected) {
            message = nil; source = ""
            guard let selected else { return }
            do { let value = try await inbox.message(selected); try Task.checkCancellation(); message = value }
            catch { if !Task.isCancelled { issue = error.localizedDescription } }
        }
        .task(id: "\(message?.ID ?? "")|\(detail)") {
            source = ""
            guard let message else { return }
            do {
                let value: String
                if detail == "Raw" { value = String(decoding: try await inbox.raw(message.ID), as: UTF8.self) }
                else if detail == "Headers" { value = try await inbox.headers(message.ID).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.joined(separator: "\n  "))" }.joined(separator: "\n") }
                else { return }
                try Task.checkCancellation(); source = value
            } catch { if !Task.isCancelled { issue = error.localizedDescription } }
        }
        .confirmationDialog("Delete this captured email?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete Message", role: .destructive) {
                guard let selected else { return }
                Task { do { try await inbox.delete([selected]); self.selected = nil; await refresh() } catch { issue = error.localizedDescription } }
            }
        }
    }
    private func refresh() async {
        loading = true; defer { loading = false }
        do {
            let page = try await inbox.messages(search: search, project: project, offset: offset)
            let manager = model.mail, service = service
            let grouped = await Task.detached { manager.projectInboxesEnabled(service) }.value
            try Task.checkCancellation()
            messages = page.messages; total = page.matchingCount; tags = page.tags ?? tags; groupedInboxes = grouped; issue = nil
            if let selected, !messages.contains(where: { $0.ID == selected }) { self.selected = nil }
            if selected == nil { selected = messages.first?.id }
        } catch { if !Task.isCancelled { issue = error.localizedDescription } }
    }
    private func formattedDate(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        return date?.formatted(date: .abbreviated, time: .shortened) ?? raw
    }
    private func saveRaw(_ message: MailMessage) async {
        do { try await save({ try await inbox.raw(message.ID) }, name: "message.eml") } catch { issue = error.localizedDescription }
    }
    private func saveAttachment(_ attachment: MailAttachment, message: MailMessage) async {
        do { try await save({ try await inbox.attachment(attachment.PartID, message: message.ID) }, name: URL(fileURLWithPath: attachment.FileName).lastPathComponent) } catch { issue = error.localizedDescription }
    }
    private func save(_ data: () async throws -> Data, name: String) async throws {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name.isEmpty ? "attachment" : name
        guard await panel.begin() == .OK, let url = panel.url else { return }
        try await data().write(to: url, options: .atomic)
    }
}

/// Email content never receives script execution or network access. Only an
/// explicit click on an HTTP(S) link may leave the preview, in the user's browser.
struct SafeMailHTML: NSViewRepresentable {
    let html: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.html != html else { return }
        context.coordinator.html = html
        view.loadHTMLString("<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'\"><meta name=\"color-scheme\" content=\"light dark\">" + html, baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var html: String?
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url, ["http", "https"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(action.navigationType == .other && action.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
        }
    }
}
