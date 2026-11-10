import SwiftUI
import MorrowCore

struct MailInboxView: View {
    let service: MailService
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var messages: [MailMessageSummary] = []
    @State private var tags: [String] = []
    @State private var project = ""
    @State private var search = ""
    @State private var selected: String?
    @State private var message: MailMessage?
    @State private var format = "HTML"
    @State private var source = ""
    @State private var total = 0
    @State private var offset = 0
    @State private var refreshIssue: String?
    @State private var detailIssue: String?
    @State private var actionIssue: String?
    @State private var deletion: MailMessage?
    @State private var loading = false
    @State private var loadingSource = false
    @State private var refreshed: Date?
    @State private var refreshID = 0
    @State private var groupedInboxes = false
    @State private var supportsGrouping = true
    @State private var showSetup = false
    @State private var showDetails = false
    @State private var copiedSettings = false
    @State private var zoom = 1.0
    private var inbox: MailInbox { MailInbox(service: service) }
    private var filterKey: String { "\(project)|\(search)|\(offset)|\(refreshID)" }
    private var projectNames: [String] { Array(Set(tags + model.web.sites.map(\.domain))).sorted() }
    private var issue: String? { actionIssue ?? detailIssue ?? refreshIssue }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            SettingsDivider()
            if let issue {
                ErrorCard(message: issue) { actionIssue = nil; detailIssue = nil; refreshIssue = nil }.padding(DS.Spacing.sm)
            }
            HSplitView {
                messageList.frame(minWidth: 250, idealWidth: 290, maxWidth: 380)
                reader.frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            SettingsDivider()
            statusBar
        }
        .background(DS.Surface.canvas)
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
            message = nil; source = ""; detailIssue = nil; showDetails = false
            guard let selected else { return }
            do {
                let value = try await inbox.message(selected)
                try Task.checkCancellation()
                message = value
                if value.HTML.isEmpty { format = "Text" }
            } catch { if !Task.isCancelled { detailIssue = error.localizedDescription } }
        }
        .task(id: "\(message?.ID ?? "")|\(format)") { await loadSource() }
        .confirmationDialog("Delete this captured email?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            if let deletion {
                Button("Delete Message", role: .destructive) {
                    Task {
                        do {
                            try await inbox.delete([deletion.ID])
                            if selected == deletion.ID { selected = nil }
                            refreshID += 1
                        } catch { actionIssue = error.localizedDescription }
                    }
                    self.deletion = nil
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: DS.Spacing.md) {
            IconTile(symbol: "tray.fill", color: .orange, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text("Local mail inbox").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: DS.Spacing.sm) {
                SettingsMenuPicker(label: "Project inbox", selection: $project, options: [.init(value: "", title: "All inboxes", symbol: "tray.full")] + projectNames.map { .init(value: $0, title: $0, symbol: "folder") })
                    .frame(maxWidth: 220, alignment: .trailing)
                Button("SMTP Settings") { copiedSettings = false; showSetup.toggle() }.settingsButton(height: ControlLayout.height)
                    .popover(isPresented: $showSetup, arrowEdge: .bottom) { smtpSetup }
                ControlIconButton(symbol: "arrow.clockwise", help: "Refresh inbox (⌘R)") { refreshID += 1 }
                    .keyboardShortcut("r", modifiers: .command)
            }.frame(height: ControlLayout.height)
                .environment(\.morrowToolbarActions, true)
        }.padding(.horizontal, DS.Spacing.lg).padding(.vertical, DS.Spacing.md)
    }

    private var messageList: some View {
        VStack(spacing: 0) {
            SettingsInput(placeholder: "Search mail", text: $search, symbol: "magnifyingglass", clearable: true)
                .padding(DS.Spacing.md)
            List(selection: $selected) {
                ForEach(messages) { item in
                    MailMessageRow(message: item).tag(item.ID)
                }
            }.listStyle(.inset).scrollContentBackground(.hidden)
                .overlay {
                    if messages.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(.tertiary)
                            Text(loading ? "Loading mail…" : search.isEmpty ? "No messages yet" : "No matching messages").font(.system(size: 13, weight: .medium))
                            if !loading && search.isEmpty {
                                Button("View SMTP Settings") { showSetup = true }.settingsButton(height: 28)
                            }
                        }.foregroundStyle(.secondary)
                    }
                }
            SettingsDivider()
            HStack(spacing: 8) {
                ServiceActionButton(kind: .open, title: "Open browser inbox", compact: true) { NSWorkspace.shared.open(service.inboxURL) }
                Spacer()
                Text(total == 0 ? "0 messages" : "\(offset + 1)–\(min(offset + messages.count, total)) of \(total)")
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button { offset = max(0, offset - 50) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(MenuIconButtonStyle()).help("Previous page").accessibilityLabel("Previous page").disabled(offset == 0)
                Button { offset += 50 } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(MenuIconButtonStyle()).help("Next page").accessibilityLabel("Next page").disabled(offset + messages.count >= total)
            }.padding(.horizontal, DS.Spacing.md).frame(height: 34)
        }
    }

    @ViewBuilder private var reader: some View {
        if let message {
            VStack(alignment: .leading, spacing: 0) {
                messageHeader(message)
                SettingsDivider()
                if format == "HTML", !message.HTML.isEmpty {
                    SafeMailHTML(html: message.HTML, zoom: zoom).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if loadingSource {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let text = format == "HTML" || format == "Text" ? message.Text : source
                    ScrollView([.vertical, .horizontal]) {
                        Text(text.isEmpty ? "No content in this format." : text)
                            .font(.system(size: CGFloat(13 * zoom), design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading).padding(DS.Spacing.lg)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "envelope.open").font(.system(size: 36)).foregroundStyle(.tertiary)
                Text(selected == nil ? "Your app’s mail, all in one place" : "Loading message…").font(.system(size: 17, weight: .medium))
                Text("Select an email to preview it, inspect its source, or save attachments.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 330)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func messageHeader(_ message: MailMessage) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(message.Subject.isEmpty ? "(No subject)" : message.Subject)
                .font(.system(size: 16, weight: .semibold)).lineLimit(2).textSelection(.enabled).help(message.Subject)
            HStack(alignment: .firstTextBaseline) {
                Text(message.From.label).font(.system(size: 12, weight: .medium)).lineLimit(1).help(message.From.label)
                Spacer(minLength: 8)
                Text(MailDate.full(message.Date)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text("To: \((message.To ?? []).map(\.label).joined(separator: ", "))")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Button("Details") { showDetails.toggle() }.settingsButton(height: 24)
                    .popover(isPresented: $showDetails) { messageDetails(message) }
            }
            HStack(spacing: 10) {
                SettingsTabs(title: "Message format", selection: $format, options: ["HTML", "Text", "Headers", "Raw"].map { .init(value: $0, title: $0, symbol: "doc.text") })
                    .frame(maxWidth: 310)
                Spacer(minLength: 0)
                SettingsZoomControl(zoom: $zoom)
                Menu {
                    Button("Save Original Email…") { Task { await saveRaw(message) } }
                    Button("Copy Message ID") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.ID, forType: .string) }
                } label: { Image(systemName: "ellipsis").frame(width: 16) }.settingsMenuControl().help("Message actions")
                ServiceActionButton(kind: .remove, title: "Delete this message") { deletion = message }
            }
            let attachments = (message.Attachments ?? []) + (message.Inline ?? [])
            if !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(attachments) { attachment in
                            Button { Task { await saveAttachment(attachment, message: message) } } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "paperclip")
                                    Text(attachment.FileName.isEmpty ? "Attachment" : attachment.FileName).lineLimit(1)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.Size), countStyle: .file)).foregroundStyle(.secondary)
                                }.font(.system(size: 11))
                            }.settingsButton(height: 28).help("Save attachment")
                        }
                    }.padding(.vertical, 2)
                }.scrollIndicators(.automatic)
            }
        }.padding(DS.Spacing.lg)
    }

    private func messageDetails(_ message: MailMessage) -> some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                detailRow("From", message.From.label)
                detailRow("To", (message.To ?? []).map(\.label).joined(separator: ", "))
                if !(message.Cc ?? []).isEmpty { detailRow("Cc", (message.Cc ?? []).map(\.label).joined(separator: ", ")) }
                if !(message.Bcc ?? []).isEmpty { detailRow("Bcc", (message.Bcc ?? []).map(\.label).joined(separator: ", ")) }
                detailRow("Received", MailDate.full(message.Date))
                detailRow("Message ID", message.ID)
            }.font(.system(size: 12)).textSelection(.enabled).padding(20)
        }.frame(width: 480, height: 240)
    }
    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow(alignment: .top) { Text(title).foregroundStyle(.secondary); Text(value).frame(maxWidth: .infinity, alignment: .leading) }
    }

    private var smtpSetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect your app").font(.system(size: 16, weight: .semibold))
            Text(project.isEmpty ? "Capture mail from your local application." : "Route new messages to \(project).")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text((try? service.appConfiguration(project: project)) ?? service.appConfiguration)
                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            Button(copiedSettings ? "Copied" : "Copy SMTP Settings") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString((try? service.appConfiguration(project: project)) ?? service.appConfiguration, forType: .string)
                copiedSettings = true
            }.settingsButton(height: 30)
            Text(!supportsGrouping ? "This Mailpit version does not support project inboxes. Choose a current catalog release to use grouping." : groupedInboxes ? "Choose a project inbox to copy its username. Any test password works; keep local SMTP encryption disabled." : "Restart this mail server to enable project inboxes. Existing messages are preserved.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if !groupedInboxes && supportsGrouping {
                Button("Restart Mail") { model.perform("Restarting mail…") { try MailManager(store: $0.store, runner: $0.runner).restart(service.id) } }
                    .settingsButton(height: 28).disabled(model.busy)
            }
        }.padding(20).frame(width: 360)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if loading && messages.isEmpty { ProgressView().controlSize(.mini) }
            Text("\(total) \(total == 1 ? "message" : "messages")").monospacedDigit()
            if !groupedInboxes && supportsGrouping {
                Button("Project inbox setup") { showSetup = true }.settingsButton(height: 24)
            }
            Spacer()
            if let refreshed { Text("Updated \(refreshed.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary) }
            Image(systemName: "lock.shield").foregroundStyle(.secondary).help("Email previews block scripts and remote resources. Links open only when clicked.")
                .accessibilityLabel("Remote content blocked")
        }.font(.system(size: 11)).padding(.horizontal, DS.Spacing.lg).frame(height: 28)
    }

    private func refresh() async {
        loading = true; defer { loading = false }
        do {
            let page = try await inbox.messages(search: search, project: project, offset: offset)
            let manager = model.mail, service = service
            let grouped = await Task.detached { manager.projectInboxesEnabled(service) }.value
            try Task.checkCancellation()
            if offset > 0 && page.messages.isEmpty {
                offset = max(0, ((max(1, page.matchingCount) - 1) / 50) * 50)
                return
            }
            messages = page.messages; total = page.matchingCount; tags = page.tags ?? tags
            groupedInboxes = grouped; refreshIssue = nil; refreshed = Date()
            if let selected, !messages.contains(where: { $0.ID == selected }) { self.selected = nil }
            if selected == nil { selected = messages.first?.id }
        } catch { if !Task.isCancelled { refreshIssue = error.localizedDescription } }
    }
    private func loadSource() async {
        source = ""; loadingSource = false
        guard let message, ["Raw", "Headers"].contains(format) else { return }
        loadingSource = true
        defer { loadingSource = false }
        do {
            let value: String
            if format == "Raw" { value = String(decoding: try await inbox.raw(message.ID), as: UTF8.self) }
            else { value = try await inbox.headers(message.ID).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.joined(separator: "\n  "))" }.joined(separator: "\n") }
            try Task.checkCancellation(); source = value; detailIssue = nil
        } catch { if !Task.isCancelled { detailIssue = error.localizedDescription } }
    }
    private func saveRaw(_ message: MailMessage) async {
        do { try await save({ try await inbox.raw(message.ID) }, name: "message.eml") } catch { actionIssue = error.localizedDescription }
    }
    private func saveAttachment(_ attachment: MailAttachment, message: MailMessage) async {
        do { try await save({ try await inbox.attachment(attachment.PartID, message: message.ID) }, name: URL(fileURLWithPath: attachment.FileName).lastPathComponent) } catch { actionIssue = error.localizedDescription }
    }
    private func save(_ data: () async throws -> Data, name: String) async throws {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name.isEmpty ? "attachment" : name
        guard await panel.begin() == .OK, let url = panel.url else { return }
        try await data().write(to: url, options: .atomic)
    }
}

private struct MailMessageRow: View {
    let message: MailMessageSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(message.From.Name.isEmpty ? message.From.Address : message.From.Name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 6)
                Text(MailDate.short(message.Created)).font(.system(size: 10)).foregroundStyle(.secondary)
                if !message.Read {
                    Circle().fill(Color.morrowAccent).frame(width: 5, height: 5).accessibilityLabel("Unread")
                }
            }
            Text(message.Subject.isEmpty ? "(No subject)" : message.Subject).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            Text(message.Snippet).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 6) {
                Text(message.Tags?.first ?? "Untagged").lineLimit(1)
                Spacer()
                if let count = message.Attachments, count > 0 { Label(String(count), systemImage: "paperclip") }
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(.vertical, 4).help(message.Subject)
    }
}

private enum MailDate {
    static func date(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
    static func full(_ raw: String) -> String { date(raw)?.formatted(date: .abbreviated, time: .shortened) ?? raw }
    static func short(_ raw: String) -> String {
        guard let date = date(raw) else { return raw }
        return Calendar.current.isDateInToday(date) ? date.formatted(date: .omitted, time: .shortened) : date.formatted(.dateTime.month(.abbreviated).day())
    }
}
