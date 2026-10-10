import SwiftUI
import MorrowCore

struct StoragePane: View {
    @Environment(AppModel.self) private var model
    @State private var creating = false
    @State private var editing: ObjectStorageService?
    @State private var bucketService: ObjectStorageService?
    @State private var bucketName = ""
    @State private var addingBucket = false
    @State private var deletingBucket: String?
    @State private var removing: ObjectStorageService?
    var body: some View {
        SettingsPane(section: SettingsSection.storage) {
            HStack {
                Text("Local S3 storage").font(.system(size: 13, weight: .medium)); Spacer()
                if !model.objectStorage.isEmpty { Button("New Server") { creating = true }.settingsButton().disabled(model.busy) }
            }
            if model.objectStorage.isEmpty {
                SettingsCard {
                    VStack(spacing: 10) {
                        IconTile(symbol: "morrow.minio", color: .red, size: 36)
                        Text("S3 for your development apps").font(.system(size: 14, weight: .medium))
                        Text("Run MinIO locally and manage buckets here.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(24)
                    SettingsDivider()
                    SettingsActionRow(title: "Create S3 Server…", symbol: "plus") { creating = true }.disabled(model.busy)
                }
            }
            ForEach(model.objectStorage) { service in
                SettingsGroup(header: LocalizedStringKey(service.name)) {
                    HStack(spacing: 12) {
                        IconTile(symbol: "morrow.minio", color: .red, size: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("MinIO").font(.system(size: 13, weight: .semibold))
                            Text(service.endpoint.absoluteString).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer(); ServiceStatusView(status: model.storageStatuses[service.id] ?? .unknown)
                        ServiceActionButton(kind: [.running, .starting].contains(model.storageStatuses[service.id] ?? .unknown) ? .stop : .start, title: [.running, .starting].contains(model.storageStatuses[service.id] ?? .unknown) ? "Stop S3 server" : "Start S3 server") {
                            let stop = [.running, .starting].contains(model.storageStatuses[service.id] ?? .unknown)
                            model.perform(stop ? "Stopping S3…" : "Starting S3…", success: stop ? "S3 server stopped" : "S3 server started") { manager in
                                let storage = ObjectStorageManager(store: manager.store, runner: manager.runner)
                                if stop { try storage.stop(service.id) } else { try storage.start(service.id) }
                            }
                        }.disabled(model.busy)
                        ServiceActionButton(kind: .logs, title: "Open MinIO logs") { model.showStorageLogs(service) }
                        ServiceActionButton(kind: .configuration, title: "S3 server settings") { editing = service }
                    }.settingsCellPadding()
                    SettingsDivider()
                    HStack {
                        Text("Buckets").font(.system(size: 12, weight: .medium)); Spacer()
                        if model.bucketsLoading.contains(service.id) { ProgressView().controlSize(.mini) }
                        ServiceActionButton(kind: .refresh, title: "Refresh buckets") { model.loadBuckets(service, force: true) }.disabled(model.storageStatuses[service.id] != .running || model.bucketsLoading.contains(service.id))
                        Button("Create Bucket") { bucketName = ""; bucketService = service; addingBucket = true }.settingsButton(height: 28).disabled(model.storageStatuses[service.id] != .running)
                    }.settingsCellPadding()
                    if model.storageStatuses[service.id] == .running {
                        ForEach(model.buckets[service.id] ?? [], id: \.self) { bucket in
                            HStack {
                                Image(systemName: "archivebox").foregroundStyle(.secondary); Text(bucket).font(.system(size: 12)); Spacer()
                                ServiceActionButton(kind: .copy, title: "Copy bucket app configuration") {
                                    do { model.copy(try model.storage.configuration(service, bucket: bucket), message: "S3 bucket configuration copied") } catch { model.notify(error.localizedDescription, error: true) }
                                }
                                ServiceActionButton(kind: .remove, title: "Delete empty bucket") { bucketService = service; deletingBucket = bucket }
                            }.padding(.horizontal, SettingsLayout.cardHorizontalInset).padding(.bottom, SettingsLayout.cardVerticalInset)
                        }
                        if model.buckets[service.id]?.isEmpty == true && !model.bucketsLoading.contains(service.id) { Text("No buckets yet. Create one for your application.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, SettingsLayout.cardHorizontalInset).padding(.bottom, SettingsLayout.cardVerticalInset) }
                    } else { Text("Start the S3 server to view its buckets.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, SettingsLayout.cardHorizontalInset).padding(.bottom, SettingsLayout.cardVerticalInset) }
                    SettingsDivider()
                    SettingsActionGroup {
                        Button("Open Console") { NSWorkspace.shared.open(service.consoleURL) }.disabled(model.storageStatuses[service.id] != .running)
                        Button("Copy App Settings") { do { model.copy(try model.storage.configuration(service), message: "S3 configuration copied") } catch { model.notify(error.localizedDescription, error: true) } }
                        Button("Remove…", role: .destructive) { removing = service }
                    }
                }.task(id: model.storageStatuses[service.id]) { if model.storageStatuses[service.id] == .running { model.loadBuckets(service) } }
            }
            SettingsNote(text: "S3 and its console listen on loopback. Server data and generated credentials stay on this Mac. Removing a server archives its data; deleting a bucket requires it to be empty.")
        }
        .sheet(isPresented: $creating) { ObjectStorageEditor().environment(model) }
        .sheet(item: $editing) { ObjectStorageEditor(existing: $0).environment(model) }
        .alert("Create Bucket", isPresented: $addingBucket) {
            TextField("Bucket name", text: $bucketName)
            Button("Create") { guard let service = bucketService else { return }; let name = bucketName
                model.perform("Creating bucket…", success: "Bucket created", operation: { try ObjectStorageManager(store: $0.store, runner: $0.runner).createBucket(name, service: service) }, completion: { model.loadBuckets(service, force: true) }); bucketService = nil
            }
            Button("Cancel", role: .cancel) { bucketService = nil }
        } message: { Text("Use lowercase letters, numbers, dots, or hyphens.") }
        .confirmationDialog("Delete empty bucket?", isPresented: Binding(get: { deletingBucket != nil }, set: { if !$0 { deletingBucket = nil; bucketService = nil } }), titleVisibility: .visible) {
            if let bucket = deletingBucket, let service = bucketService {
                Button("Delete \(bucket)", role: .destructive) { model.perform("Deleting bucket…", success: "Empty bucket deleted", operation: { try ObjectStorageManager(store: $0.store, runner: $0.runner).deleteBucket(bucket, service: service) }, completion: { model.loadBuckets(service, force: true) }); deletingBucket = nil; bucketService = nil }
            }
        }
        .confirmationDialog("Remove S3 server and archive its data?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let service = removing { Button("Remove and Preserve Data", role: .destructive) { model.perform("Removing S3 server…", success: "Server removed; data archived") { try ObjectStorageManager(store: $0.store, runner: $0.runner).remove(service.id) }; removing = nil } }
        }
    }
}

private struct ObjectStorageEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let existing: ObjectStorageService?
    @State private var name = "local-s3"
    @State private var api = "9000"
    @State private var console = "9001"
    @State private var autoStart = false
    @State private var start = true
    @State private var issue: String?
    private var running: Bool { existing.map { [.running, .starting].contains(model.storageStatuses[$0.id] ?? .unknown) } ?? false }
    init(existing: ObjectStorageService? = nil) { self.existing = existing }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existing == nil ? "New S3 Server" : "S3 Server Settings").font(.system(size: 18, weight: .semibold))
            SettingsGroup {
                SettingRow(title: "Name") { SettingsInput(placeholder: "local-s3", text: $name).frame(width: 210) }
                SettingsDivider()
                SettingRow(title: "S3 API port") { SettingsInput(placeholder: "9000", text: $api).frame(width: 110) }
                SettingsDivider()
                SettingRow(title: "Console port") { SettingsInput(placeholder: "9001", text: $console).frame(width: 110) }
                SettingsDivider()
                SettingRow(title: "Start at login") { Toggle("Start at login", isOn: $autoStart).settingsToggle() }
                if existing == nil { SettingsDivider(); SettingRow(title: "Start after creating") { Toggle("Start after creating", isOn: $start).settingsToggle() } }
            }.disabled(model.busy || running)
            if let existing {
                SettingsActionGroup {
                    Button("Copy Access Key") { do { model.copy(try model.storage.credentials(existing).accessKey, message: "Access key copied") } catch { issue = error.localizedDescription } }
                    Button("Copy Secret Key") { do { model.copy(try model.storage.credentials(existing).secretKey, message: "Secret key copied") } catch { issue = error.localizedDescription } }
                }
                Text("Stop this server before editing its settings.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let error = issue ?? model.error { ErrorCard(message: error) { issue = nil; model.error = nil } }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }.settingsButton().keyboardShortcut(.cancelAction).disabled(model.busy)
                Button(existing == nil ? "Create Server" : "Save") {
                    guard let api = Int(api), let console = Int(console) else { issue = "Enter numeric ports."; return }
                    let name = name, auto = autoStart, start = start, existing = existing
                    model.perform(existing == nil ? "Creating S3 server…" : "Saving S3 settings…", operation: { manager in
                        let storage = ObjectStorageManager(store: manager.store, runner: manager.runner)
                        if var service = existing { service.name = name; service.apiPort = api; service.consolePort = console; service.autoStart = auto; try storage.update(service) }
                        else { let service = try storage.create(name: name, api: api, console: console, autoStart: auto); if start { try storage.start(service.id) } }
                    }, completion: { dismiss() })
                }.settingsButton().keyboardShortcut(.defaultAction).disabled(model.busy || running)
            }
        }.padding(20).frame(width: 480).serviceFeedback().onAppear {
            if let existing { name = existing.name; api = String(existing.apiPort); console = String(existing.consolePort); autoStart = existing.autoStart }
            else if let ports = try? model.storage.suggestedPorts() { api = String(ports.0); console = String(ports.1) }
        }
    }
}
