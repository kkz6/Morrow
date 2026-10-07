import SwiftUI
import MorrowCore

struct MailPane: View {
    @Environment(AppModel.self) private var model
    @State private var creating = false
    @State private var editing: MailService?
    @State private var removing: MailService?
    var body: some View {
        SettingsPane(section: SettingsSection.mail) {
            HStack {
                Text("SMTP for your local apps").font(.system(size: 13, weight: .medium))
                Spacer()
                if !model.mailServices.isEmpty { Button("New Mail Server") { creating = true }.settingsButton().disabled(model.busy) }
            }
            if model.mailServices.isEmpty {
                SettingsCard {
                    VStack(spacing: 10) {
                        IconTile(symbol: "envelope.fill", color: .orange, size: 36)
                        Text("Your test inbox").font(.system(size: 14, weight: .medium))
                        Text("Send SMTP messages from your apps and inspect them in Mailpit.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(24)
                    SettingsDivider()
                    SettingsActionRow(title: "Create Mail Server…", symbol: "plus") { creating = true }.disabled(model.busy)
                }
            } else {
                ForEach(model.mailServices) { service in
                    SettingsGroup(header: LocalizedStringKey(service.name)) {
                        SettingRow(title: "Mailpit", subtitle: LocalizedStringKey(service.installation.version)) {
                            HStack {
                                StatusBadge(status: model.mailStatuses[service.id] ?? .unknown)
                                Button([.running, .starting].contains(model.mailStatuses[service.id] ?? .unknown) ? "Stop" : "Start") {
                                    let stop = [.running, .starting].contains(model.mailStatuses[service.id] ?? .unknown)
                                    model.perform(stop ? "Stopping mail…" : "Starting mail…") { manager in
                                        let mail = MailManager(store: manager.store, runner: manager.runner)
                                        if stop { try mail.stop(service.id) } else { try mail.start(service.id) }
                                    }
                                }.settingsButton(height: 28).disabled(model.busy)
                            }
                        }
                        SettingsDivider()
                        SettingRow(title: "SMTP", subtitle: LocalizedStringKey(service.smtpURL)) {
                            Button("Copy Settings") { copy(service.appConfiguration) }.settingsButton(height: 28)
                        }
                        SettingsDivider()
                        SettingsActionRow(title: "Open Inbox", symbol: "tray", detail: ":\(service.httpPort)") { NSWorkspace.shared.open(service.inboxURL) }
                            .disabled(model.mailStatuses[service.id] != .running)
                        SettingsDivider()
                        HStack {
                            Button("Settings…") { editing = service }.settingsButton(height: 28)
                            Button("Logs") { model.showMailLogs(service) }.settingsButton(height: 28)
                            Spacer()
                            Button("Remove…", role: .destructive) { removing = service }.settingsButton(height: 28)
                        }.padding(12).disabled(model.busy)
                    }
                }
            }
            SettingsNote(text: "SMTP and the inbox listen on 127.0.0.1. Use no authentication and no TLS in your app's development mail settings. Captured messages remain in this Mac's local inbox.")
        }
        .sheet(isPresented: $creating) { MailEditor().environment(model) }
        .sheet(item: $editing) { MailEditor(existing: $0).environment(model) }
        .confirmationDialog("Remove mail server?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let service = removing {
                Button("Remove and Preserve Messages") { model.perform("Removing mail server…") { try MailManager(store: $0.store, runner: $0.runner).remove(service.id) }; removing = nil }
                Button("Delete Server and Messages", role: .destructive) { model.perform("Deleting mail server…") { try MailManager(store: $0.store, runner: $0.runner).remove(service.id, deleteMessages: true) }; removing = nil }
            }
        }
    }
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}

private struct MailEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let existing: MailService?
    @State private var name: String
    @State private var smtp: String
    @State private var http: String
    @State private var autoStart: Bool
    @State private var startAfterCreating = true
    @State private var version = "automatic"
    @State private var versions: [MailInstallation] = []
    @State private var issue: String?
    private var active: Bool { existing.map { [.running, .starting].contains(model.mailStatuses[$0.id] ?? .unknown) } ?? false }
    init(existing: MailService? = nil) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "local-mail")
        _smtp = State(initialValue: String(existing?.smtpPort ?? 1025))
        _http = State(initialValue: String(existing?.httpPort ?? 8025))
        _autoStart = State(initialValue: existing?.autoStart ?? false)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { IconTile(symbol: "envelope.fill", color: .orange, size: 30); Text(existing == nil ? "New Mail Server" : "Mail Server Settings").font(.system(size: 18, weight: .semibold)); Spacer() }
            SettingsGroup {
                SettingRow(title: "Name") { SettingsInput(placeholder: "local-mail", text: $name).frame(width: 220) }
                SettingsDivider()
                if existing == nil {
                    SettingRow(title: "Version") {
                        SettingsSelect(label: "Mailpit version", selection: $version, options: [.init(value: "automatic", title: "Automatic", symbol: "square.stack.3d.up")] + versions.map { .init(value: $0.version, title: $0.version, symbol: "square.stack.3d.up") } + [.init(value: "current", title: "Current Homebrew release", symbol: "square.stack.3d.up")])
                    }
                    SettingsDivider()
                }
                SettingRow(title: "SMTP port") { SettingsInput(placeholder: "1025", text: $smtp).frame(width: 130) }
                SettingsDivider()
                SettingRow(title: "Inbox port") { SettingsInput(placeholder: "8025", text: $http).frame(width: 130) }
                SettingsDivider()
                SettingRow(title: "Start at macOS login") { Toggle("Start at macOS login", isOn: $autoStart).settingsToggle() }
                if existing == nil {
                    SettingsDivider()
                    SettingRow(title: "Start after creating") { Toggle("Start after creating", isOn: $startAfterCreating).settingsToggle() }
                }
            }.disabled(model.busy || active)
            if active { Text("Stop this mail server to edit its settings.").font(.system(size: 12)).foregroundStyle(.secondary) }
            if let error = issue ?? model.error { ErrorCard(message: error) { issue = nil; model.error = nil } }
            if let activity = model.activity { HStack { ProgressView().controlSize(.small); Text(activity).font(.system(size: 12)) } }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.settingsButton().keyboardShortcut(.cancelAction).disabled(model.busy)
                Button(existing == nil ? "Create Mail Server" : "Save Changes", action: save).settingsButton().keyboardShortcut(.defaultAction).disabled(model.busy || active || issue != nil)
            }
        }.padding(20).frame(width: 470)
        .task {
            guard !model.preview else { return }
            if existing == nil {
                smtp = String((try? model.mail.suggestedPort(1025)) ?? 1025)
                http = String((try? model.mail.suggestedPort(8025, excluding: Int(smtp))) ?? 8025)
                let mail = model.mail
                versions = (try? await Task.detached { try mail.installations() }.value) ?? []
            }
        }
        .task(id: "\(name):\(smtp):\(http):\(active)") {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !model.preview, !active else { issue = nil; return }
            guard let smtp = Int(smtp), let http = Int(http) else { issue = "Enter numeric ports."; return }
            do { try model.mail.preflight(name: name, smtpPort: smtp, httpPort: http, excluding: existing?.id); issue = nil }
            catch { issue = error.localizedDescription }
        }
    }
    private func save() {
        guard let smtp = Int(smtp), let http = Int(http) else { issue = "Enter numeric ports."; return }
        let name = name, auto = autoStart, version = version, start = startAfterCreating, existing = existing
        model.perform(existing == nil ? "Creating mail server…" : "Saving mail settings…", operation: { manager in
            let mail = MailManager(store: manager.store, runner: manager.runner)
            if var service = existing { service.name = name; service.smtpPort = smtp; service.httpPort = http; service.autoStart = auto; try mail.update(service) }
            else { let service = try mail.provision(name: name, smtpPort: smtp, httpPort: http, autoStart: auto, version: version); if start { try mail.start(service.id) } }
        }, completion: { dismiss() })
    }
}
