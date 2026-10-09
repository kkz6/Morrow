import SwiftUI
import Observation
import MorrowCore

struct InstanceCreationRequest: Identifiable {
    let id = UUID()
    var installation: Installation? = nil
    var engine: DatabaseEngine? = nil
    var version: String? = nil
}

@MainActor @Observable
final class AppModel {
    var instances: [DatabaseInstance] = []
    var installations: [Installation] = []
    var inventory = ApplicationInventory()
    var inventoryLoading = false
    var runtimeChannelsLoading: Set<String> = []
    var objectStorage: [ObjectStorageService] = []
    var storageStatuses: [UUID: InstanceStatus] = [:]
    var buckets: [UUID: [String]] = [:]
    var bucketsLoading: Set<UUID> = []
    var toast: ToastNotice?
    var logRequest: ServiceLogRequest?
    var configurationRequest: ConfigurationRequest?
    var httpsMessage = ""
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    var statuses: [UUID: InstanceStatus] = [:]
    var channels: [VersionChannel] = []
    var web = WebWorkspace()
    var webStatus: WebStatus?
    var mailServices: [MailService] = []
    var mailStatuses: [UUID: InstanceStatus] = [:]
    var tools: [RuntimeInstallation] = []
    var toolDefaults: [String: String] = [:]
    var databaseUpdates: [DatabaseUpdate] = []
    var runtimeUpdates: [RuntimeUpdate] = []
    var upgradeRequest: DatabaseUpdate?
    var syncReport = SyncReport()
    var preferences = AppPreferences()
    var error: String?
    var activity: String?
    var channelActivity = false
    var homebrewAvailable = false
    var selection: SettingsSection = .instances {
        didSet {
            guard !preview else { return }
            preferences.lastSettingsSection = selection.rawValue
            try? manager.store.update { $0.preferences.lastSettingsSection = selection.rawValue }
        }
    }
    var creationRequest: InstanceCreationRequest?
    var logInstanceID: UUID?
    var logSiteID: UUID?
    @ObservationIgnored let manager: DatabaseManager
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var lastSyncAttempt = Date.distantPast
    @ObservationIgnored let preview: Bool

    init(manager: DatabaseManager = DatabaseManager(), preview: Bool = false) {
        self.manager = manager; self.preview = preview
        if !preview {
            inventory = InventoryStore(store: manager.store).load()
            installations = inventory.databases
            if let state = try? manager.store.load() {
                preferences = state.preferences
                instances = state.instances; tools = state.tools; toolDefaults = state.toolDefaults
                web = state.web; mailServices = state.mailServices; objectStorage = state.objectStorage
                selection = SettingsSection(rawValue: preferences.lastSettingsSection) ?? .instances
                if selection == .logs { selection = .instances }
            }
        }
        if preview {
            homebrewAvailable = true
            let pg = Installation(engine: .postgresql, formula: "postgresql@17", version: "17.6", prefix: "/opt/homebrew/Cellar/postgresql@17/17.6")
            let mysql = Installation(engine: .mysql, formula: "mysql@8.4", version: "8.4.6", prefix: "/opt/homebrew/Cellar/mysql@8.4/8.4.6")
            let mongo = Installation(engine: .mongodb, formula: "mongodb/brew/mongodb-community@8.0", version: "8.0.13", prefix: "/opt/homebrew/Cellar/mongodb-community@8.0/8.0.13")
            let redis = Installation(engine: .redis, formula: "redis", version: "8.0.0", prefix: "/opt/homebrew/Cellar/redis/8.0.0")
            let valkey = Installation(engine: .valkey, formula: "valkey", version: "8.0.0", prefix: "/opt/homebrew/Cellar/valkey/8.0.0")
            installations = [pg, mysql, mongo, redis, valkey]
            instances = [DatabaseInstance(name: "studio", installation: pg, port: 5432, autoStart: true),
                         DatabaseInstance(name: "local-mysql", installation: mysql, port: 3306),
                         DatabaseInstance(name: "playground", installation: mongo, port: 27017),
                         DatabaseInstance(name: "cache", installation: redis, port: 6379),
                         DatabaseInstance(name: "valkey-cache", installation: valkey, port: 6380)]
            statuses = [instances[0].id: .running, instances[1].id: .stopped, instances[2].id: .running, instances[3].id: .running, instances[4].id: .stopped]
        }
    }
    var busy: Bool { activity != nil }
    var databaseRunningCount: Int { statuses.values.filter { $0 == .running }.count }
    var runningCount: Int { databaseRunningCount + mailStatuses.values.filter { $0 == .running }.count + storageStatuses.values.filter { $0 == .running }.count }
    var unconfiguredInstallations: [Installation] {
        let used = Set(instances.map { $0.installation.id })
        return installations.filter { !used.contains($0.id) }
    }
    func requestCreation(installation: Installation? = nil, engine: DatabaseEngine? = nil, version: String? = nil) {
        guard !busy else { return }
        selection = .instances
        creationRequest = InstanceCreationRequest(installation: installation, engine: engine, version: version)
    }
    func showLogs(for instance: DatabaseInstance) {
        logRequest = ServiceLogRequest(title: instance.name, subtitle: instance.engine.title, url: manager.store.logURL(instance))
    }
    var colorScheme: ColorScheme? {
        switch preferences.appearance { case "light": return .light; case "dark": return .dark; default: return nil }
    }
    func startMonitoring() {
        guard monitor == nil, !preview else { return }
        monitor = Task { [weak self] in
            await self?.refresh()
            await self?.loadInventory()
            while !Task.isCancelled {
                await self?.refresh()
                await self?.syncIfDue()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
    func refresh() async {
        guard !preview, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let manager = manager, readSyncReport = !syncing
        do {
            let snapshot = try await Task.detached {
                let state = try manager.store.load()
                let installer = try manager.installer()
                let installations = state.instances.map(\.installation)
                let statuses = Dictionary(uniqueKeysWithValues: state.instances.map { ($0.id, manager.status($0)) })
                let mail = MailManager(store: manager.store, runner: manager.runner)
                let mailStatuses = Dictionary(uniqueKeysWithValues: state.mailServices.map { ($0.id, mail.status($0)) })
                let report = readSyncReport ? try? WorkspaceSync(store: manager.store, runner: manager.runner).report() : nil
                let webStatus = try SiteManager(store: manager.store, runner: manager.runner).status()
                let storage = ObjectStorageManager(store: manager.store, runner: manager.runner)
                let storageStatuses = Dictionary(uniqueKeysWithValues: state.objectStorage.map { ($0.id, storage.status($0)) })
                return (state, installations, statuses, installer.executable != nil, report, mailStatuses, webStatus, storageStatuses)
            }.value
            instances = snapshot.0.instances
            preferences = snapshot.0.preferences
            web = snapshot.0.web
            webStatus = snapshot.6
            mailServices = snapshot.0.mailServices
            mailStatuses = snapshot.5
            tools = snapshot.0.tools
            toolDefaults = snapshot.0.toolDefaults
            let previousInventory = inventory
            for item in snapshot.1 where !inventory.databases.contains(where: { $0.id == item.id }) { inventory.databases.append(item) }
            for item in snapshot.0.web.php where !inventory.runtimes.contains(where: { $0.id == item.id }) { inventory.runtimes.append(item) }
            for item in snapshot.0.tools where !inventory.runtimes.contains(where: { $0.id == item.id }) { inventory.runtimes.append(item) }
            installations = inventory.databases
            objectStorage = snapshot.0.objectStorage; storageStatuses = snapshot.7
            if previousInventory != inventory { try? InventoryStore(store: manager.store).save(inventory) }
            statuses = snapshot.2
            homebrewAvailable = snapshot.3
            if let report = snapshot.4 { syncReport = report }
        } catch { self.error = error.localizedDescription }
    }
    func perform(_ title: String, success: String? = nil, operation: @escaping @Sendable (DatabaseManager) throws -> Void, completion: (() -> Void)? = nil) {
        guard !busy, !preview else { return }
        activity = title; error = nil
        let manager = manager
        Task {
            do {
                try await Task.detached { try operation(manager) }.value
                await refresh()
                activity = nil
                if let success { notify(success) }
                completion?()
            } catch {
                await refresh()
                self.error = error.localizedDescription
                notify(error.localizedDescription, error: true)
            }
            if activity == title { activity = nil }
        }
    }
    func loadChannels(force: Bool = false) {
        guard !preview, !channelActivity, channels.isEmpty || force else { return }
        channelActivity = true
        let manager = manager
        Task {
            do { channels = try await Task.detached { try manager.installer().channels() }.value }
            catch { self.error = error.localizedDescription }
            channelActivity = false
        }
    }
    func notify(_ text: String, error: Bool = false) {
        toastTask?.cancel(); toast = ToastNotice(text: text, error: error)
        toastTask = Task { do { try await Task.sleep(for: .seconds(error ? 8 : 3)) } catch { return }; toast = nil }
    }
    func copy(_ value: String, message: String = "Copied") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string); notify(message) }
    func loadInventory(force: Bool = false) async {
        guard !preview, !inventoryLoading else { return }
        if !force, let date = inventory.updatedAt, Date().timeIntervalSince(date) < 86400 { return }
        inventoryLoading = true
        let manager = manager
        do {
            let value = try await Task.detached {
                var value = ApplicationInventory()
                value.databases = try manager.installer().installations()
                value.runtimes = try RuntimeManager(store: manager.store, runner: manager.runner).installations()
                value.mail = try MailManager(store: manager.store, runner: manager.runner).installations()
                value.updatedAt = Date(); return value
            }.value
            var cached = value; cached.channels = inventory.channels
            inventory = cached; installations = cached.databases
            try InventoryStore(store: manager.store).save(cached)
        } catch { notify(error.localizedDescription, error: true) }
        inventoryLoading = false
    }
    func loadRuntimeChannels(_ engine: RuntimeEngine, force: Bool = false) {
        guard !preview, !runtimeChannelsLoading.contains(engine.rawValue), force || inventory.channels[engine.rawValue] == nil else { return }
        runtimeChannelsLoading.insert(engine.rawValue)
        let runtimes = runtimes
        Task {
            do {
                let channels = try await Task.detached { try runtimes.channels(engine) }.value
                inventory.channels[engine.rawValue] = channels
                try InventoryStore(store: manager.store).save(inventory)
            } catch { notify(error.localizedDescription, error: true) }
            runtimeChannelsLoading.remove(engine.rawValue)
        }
    }
    func showSiteLogs() { logRequest = ServiceLogRequest(title: "Sites", subtitle: "Caddy routing", url: sites.logURL) }
    func showStorageLogs(_ service: ObjectStorageService) { logRequest = ServiceLogRequest(title: service.name, subtitle: "MinIO", url: storage.logURL(service)) }
    func loadBuckets(_ service: ObjectStorageService, force: Bool = false) {
        guard !bucketsLoading.contains(service.id), force || buckets[service.id] == nil else { return }
        bucketsLoading.insert(service.id)
        let storage = storage
        Task {
            defer { bucketsLoading.remove(service.id) }
            do { buckets[service.id] = try await Task.detached { try storage.buckets(service) }.value }
            catch { notify(error.localizedDescription, error: true) }
        }
    }
    var storage: ObjectStorageManager { ObjectStorageManager(store: manager.store, runner: manager.runner) }
    func showConfiguration(_ runtime: RuntimeInstallation) {
        guard !busy, !preview else { return }
        let manager = manager
        activity = "Finding configuration…"
        Task {
            defer { activity = nil }
            do {
                let files = try await Task.detached { try ConfigurationAccess(store: manager.store, runner: manager.runner).files(runtime) }.value
                if files.isEmpty { notify("This runtime has no shared configuration file; use its project settings.") }
                else { configurationRequest = ConfigurationRequest(title: runtime.engine.title + " " + runtime.version, files: files) }
            } catch { notify(error.localizedDescription, error: true) }
        }
    }
    func trustHTTPS() {
        perform("Trusting local HTTPS…", operation: { manager in try SiteManager(store: manager.store, runner: manager.runner).trustCertificate() }, completion: { [self] in
            checkHTTPS()
        })
    }
    func checkHTTPS() {
        guard !busy, !preview else { return }
        activity = "Checking HTTPS…"; error = nil
        let sites = sites
        Task {
            defer { activity = nil }
            do { httpsMessage = try await Task.detached { try sites.httpsSummary() }.value; notify(httpsMessage) }
            catch { httpsMessage = error.localizedDescription; self.error = error.localizedDescription; notify(httpsMessage, error: true) }
        }
    }
    var sites: SiteManager { SiteManager(store: manager.store, runner: manager.runner) }
    func installSiteSystemSetup() {
        let cli = cliURL
        perform("Configuring local domains…", operation: { manager in
            let sites = SiteManager(store: manager.store, runner: manager.runner)
            let web = try manager.store.load().web
            if let issue = SiteSystemSetup.setupIssue(suffixes: web.suffixes) { throw MorrowError.message(issue) }
            let command = try sites.setupCommand(cli: cli)
            let script = "do shell script " + Self.appleScriptString(command) + " with administrator privileges"
            try manager.runner.run("/usr/bin/osascript", ["-e", script], environment: [:]).checked()
            try sites.refreshProjects(force: true)
        })
    }
    private nonisolated static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    var mail: MailManager { MailManager(store: manager.store, runner: manager.runner) }
    func showMailLogs(_ service: MailService) { logRequest = ServiceLogRequest(title: service.name, subtitle: "Mailpit", url: mail.logURL(service)) }
    var runtimes: RuntimeManager { RuntimeManager(store: manager.store, runner: manager.runner) }
    var cliURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/morrow") }
    func checkUpdates(refresh: Bool = true) {
        guard !busy, !preview else { return }
        activity = refresh ? "Refreshing Homebrew and checking updates…" : "Checking updates…"
        error = nil
        let manager = manager
        Task {
            do {
                let results = try await Task.detached {
                    if refresh { try manager.installer().refreshMetadata() }
                    return (try manager.databaseUpdates(), try RuntimeManager(store: manager.store, runner: manager.runner).updates())
                }.value
                databaseUpdates = results.0; runtimeUpdates = results.1
            } catch { self.error = error.localizedDescription }
            activity = nil
        }
    }
    func syncNow(retry: Bool = false) { Task { await runSync(retry: retry) } }
    private func syncIfDue() async {
        guard preferences.iCloudSyncEnabled, Date().timeIntervalSince(lastSyncAttempt) >= 30 else { return }
        await runSync(retry: false)
    }
    private func runSync(retry: Bool) async {
        guard !busy, !syncing, !preview, preferences.iCloudSyncEnabled else { return }
        syncing = true; lastSyncAttempt = Date(); activity = "Syncing workspace setup…"
        let manager = manager, cli = cliURL
        do {
            syncReport = try await Task.detached { try WorkspaceSync(store: manager.store, runner: manager.runner).synchronize(cli: cli, retry: retry) }.value
        } catch {
            syncReport.message = error.localizedDescription
        }
        syncing = false; activity = nil
        await refresh()
    }
    func savePreferences(_ new: AppPreferences) {
        guard !preview else { preferences = new; return }
        do { try manager.store.update { $0.preferences = new }; preferences = new }
        catch { self.error = error.localizedDescription }
    }
    func preference<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(get: { self.preferences[keyPath: keyPath] }, set: { value in
            var preferences = self.preferences; preferences[keyPath: keyPath] = value
            self.savePreferences(preferences)
        })
    }
}

extension DatabaseEngine {
    var symbol: String { "morrow." + rawValue }
    var color: Color {
        switch self {
        case .postgresql: return .blue
        case .mysql: return .orange
        case .mariadb: return .indigo
        case .mongodb: return .green
        case .redis: return .red
        case .valkey: return .teal
        case .memcached: return .purple
        }
    }
}

struct StatusBadge: View {
    let status: InstanceStatus
    var body: some View { ServiceStatusView(status: status) }
}

extension RuntimeEngine {
    var symbol: String { "morrow." + rawValue }
    var color: Color {
        switch self { case .php: return .indigo; case .go: return .cyan; case .flutter: return .blue; case .node: return .green; case .python: return .yellow; case .ruby: return .red }
    }
}
