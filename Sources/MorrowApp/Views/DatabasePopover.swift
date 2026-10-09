import SwiftUI
import MorrowCore

struct DatabasePopover: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettingsWindow) private var openSettings
    private var services: [PopoverService] {
        model.instances.map(PopoverService.database) + model.mailServices.map(PopoverService.mail) + model.objectStorage.map(PopoverService.storage)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Morrow").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(model.runningCount) running").font(.system(size: 10)).foregroundStyle(.secondary)
                Button { model.requestCreation(); openSettings() } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                }.buttonStyle(MenuIconButtonStyle()).help("New instance").accessibilityLabel("New instance").disabled(model.busy)
            }.padding(.horizontal, MenuLayout.horizontalInset).frame(height: MenuLayout.headerHeight)
            if services.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "externaldrive.badge.plus").font(.system(size: 24, weight: .light)).foregroundStyle(.teal)
                    Text("Create your first database").font(.system(size: 12, weight: .medium))
                    Button("Create Instance") { model.requestCreation(); openSettings() }.buttonStyle(MenuActionButtonStyle()).padding(.top, 3)
                }.frame(maxWidth: .infinity).frame(height: MenuLayout.emptyHeight)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                            switch service {
                            case .database(let instance): PopoverInstanceRow(instance: instance)
                            case .mail(let service): PopoverMailRow(service: service)
                            case .storage(let service): PopoverStorageRow(service: service)
                            }
                            if index < services.count - 1 {
                                Divider().frame(height: MenuLayout.separatorHeight)
                                    .padding(.leading, MenuLayout.horizontalInset + MenuLayout.iconSize + MenuLayout.rowSpacing).opacity(0.35)
                            }
                        }
                    }
                }.frame(height: MenuLayout.listHeight(services.count)).scrollBounceBehavior(.basedOnSize)
            }
            if let activity = model.activity {
                HStack(spacing: 6) { ProgressView().controlSize(.mini); Text(activity).font(.system(size: 11)).lineLimit(1); Spacer(minLength: 0) }
                    .padding(.horizontal, MenuLayout.horizontalInset).padding(.vertical, 6).help(activity)
            }
            if let error = model.error { ErrorCard(message: error) { model.error = nil }.lineLimit(3).padding(8) }
            Divider().frame(height: MenuLayout.separatorHeight).opacity(0.35)
            HStack(spacing: 8) {
                Spacer()
                Button { model.selection = .sites; openSettings() } label: { Image(systemName: "globe") }
                    .buttonStyle(MenuIconButtonStyle()).help("Sites and project directories").accessibilityLabel("Sites and project directories")
                Button { openSettings() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(MenuIconButtonStyle()).help("Settings").accessibilityLabel("Settings").keyboardShortcut(",", modifiers: .command)
                Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(MenuIconButtonStyle()).help("Quit Morrow — services stay running").accessibilityLabel("Quit Morrow").disabled(model.busy)
            }.font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.horizontal, MenuLayout.horizontalInset).frame(height: MenuLayout.footerHeight)
        }.frame(width: MenuLayout.width).serviceFeedback(compact: true)
            .task { await model.refresh() }
    }
}

private enum PopoverService: Identifiable {
    case database(DatabaseInstance), mail(MailService), storage(ObjectStorageService)
    var id: String {
        switch self { case .database(let item): return "db:" + item.id.uuidString; case .mail(let item): return "mail:" + item.id.uuidString; case .storage(let item): return "s3:" + item.id.uuidString }
    }
}

private struct PopoverInstanceRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettingsWindow) private var openSettings
    let instance: DatabaseInstance
    private var status: InstanceStatus { model.statuses[instance.id] ?? .unknown }
    private var active: Bool { [.running, .starting].contains(status) }
    var body: some View {
        MenuServiceRow(title: instance.name, subtitle: "\(instance.engine.title) · :\(String(instance.port))", symbol: instance.engine.symbol, color: instance.engine.color, status: status) {
            ServiceActionButton(kind: active ? .stop : .start, title: active ? "Stop database" : "Start database", compact: true) {
                let id = instance.id, shouldStop = active
                model.perform(active ? "Stopping \(instance.name)…" : "Starting \(instance.name)…", success: active ? "Database stopped" : "Database started") { manager in
                    if shouldStop { try manager.stop(id) } else { try manager.start(id) }
                }
            }.disabled(model.busy || status == .missingBinary)
            Button { model.showLogs(for: instance); openSettings() } label: { Image(systemName: "terminal").font(.system(size: 11)) }
                .buttonStyle(MenuIconButtonStyle()).help("View database logs").accessibilityLabel("View database logs")
            Button { model.copy(instance.connectionURL, message: "Connection address copied") } label: { Image(systemName: "doc.on.doc").font(.system(size: 11)) }
                .buttonStyle(MenuIconButtonStyle()).help("Copy connection address").accessibilityLabel("Copy connection address")
        }
    }
}

private struct PopoverStorageRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettingsWindow) private var openSettings
    let service: ObjectStorageService
    private var status: InstanceStatus { model.storageStatuses[service.id] ?? .unknown }
    private var active: Bool { [.running, .starting].contains(status) }
    var body: some View {
        MenuServiceRow(title: service.name, subtitle: "S3 · :\(String(service.apiPort))", symbol: "morrow.minio", color: .red, status: status) {
            ServiceActionButton(kind: active ? .stop : .start, title: active ? "Stop S3 server" : "Start S3 server", compact: true) {
                let stop = active
                model.perform(stop ? "Stopping S3…" : "Starting S3…", success: stop ? "S3 server stopped" : "S3 server started") { manager in
                    let storage = ObjectStorageManager(store: manager.store, runner: manager.runner)
                    if stop { try storage.stop(service.id) } else { try storage.start(service.id) }
                }
            }.disabled(model.busy)
            Button { NSWorkspace.shared.open(service.consoleURL) } label: { Image(systemName: "arrow.up.right.square").font(.system(size: 11)) }
                .buttonStyle(MenuIconButtonStyle()).help("Open S3 console").accessibilityLabel("Open S3 console").disabled(status != .running)
            Button { model.showStorageLogs(service); openSettings() } label: { Image(systemName: "terminal").font(.system(size: 11)) }
                .buttonStyle(MenuIconButtonStyle()).help("View MinIO logs").accessibilityLabel("View MinIO logs")
        }
    }
}

private struct PopoverMailRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettingsWindow) private var openSettings
    let service: MailService
    private var status: InstanceStatus { model.mailStatuses[service.id] ?? .unknown }
    private var active: Bool { [.running, .starting].contains(status) }
    var body: some View {
        MenuServiceRow(title: service.name, subtitle: "SMTP · :\(String(service.smtpPort))", symbol: "envelope.fill", color: .orange, status: status) {
            ServiceActionButton(kind: active ? .stop : .start, title: active ? "Stop mail server" : "Start mail server", compact: true) {
                let id = service.id, stop = active
                model.perform(stop ? "Stopping mail…" : "Starting mail…", success: stop ? "Mail server stopped" : "Mail server started") { manager in
                    let mail = MailManager(store: manager.store, runner: manager.runner)
                    if stop { try mail.stop(id) } else { try mail.start(id) }
                }
            }.disabled(model.busy)
            Button { NSWorkspace.shared.open(service.inboxURL) } label: { Image(systemName: "tray").font(.system(size: 11)) }
                .buttonStyle(MenuIconButtonStyle()).help("Open test inbox").accessibilityLabel("Open test inbox").disabled(status != .running)
            Button { model.showMailLogs(service); openSettings() } label: { Image(systemName: "terminal").font(.system(size: 11)) }
                .buttonStyle(MenuIconButtonStyle()).help("View mail logs").accessibilityLabel("View mail logs")
        }
    }
}
