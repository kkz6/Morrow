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
    var statuses: [UUID: InstanceStatus] = [:]
    var channels: [VersionChannel] = []
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
    var selection: SettingsSection = .instances
    var creationRequest: InstanceCreationRequest?
    var logInstanceID: UUID?
    @ObservationIgnored let manager: DatabaseManager
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var lastSyncAttempt = Date.distantPast
    @ObservationIgnored let preview: Bool

    init(manager: DatabaseManager = DatabaseManager(), preview: Bool = false) {
        self.manager = manager; self.preview = preview
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
    var runningCount: Int { databaseRunningCount + mailStatuses.values.filter { $0 == .running }.count }
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
        creationRequest = nil
        logInstanceID = instance.id
        selection = .logs
    }
    var colorScheme: ColorScheme? {
        switch preferences.appearance { case "light": return .light; case "dark": return .dark; default: return nil }
    }
    func startMonitoring() {
        guard monitor == nil, !preview else { return }
        monitor = Task { [weak self] in
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
                let installations = try installer.installations()
                let statuses = Dictionary(uniqueKeysWithValues: state.instances.map { ($0.id, manager.status($0)) })
                let mail = MailManager(store: manager.store, runner: manager.runner)
                let mailStatuses = Dictionary(uniqueKeysWithValues: state.mailServices.map { ($0.id, mail.status($0)) })
                let report = readSyncReport ? try? WorkspaceSync(store: manager.store, runner: manager.runner).report() : nil
                return (state, installations, statuses, installer.executable != nil, report, mailStatuses)
            }.value
            instances = snapshot.0.instances
            preferences = snapshot.0.preferences
            mailServices = snapshot.0.mailServices
            mailStatuses = snapshot.5
            tools = snapshot.0.tools
            toolDefaults = snapshot.0.toolDefaults
            installations = snapshot.1
            statuses = snapshot.2
            homebrewAvailable = snapshot.3
            if let report = snapshot.4 { syncReport = report }
        } catch { self.error = error.localizedDescription }
    }
    func perform(_ title: String, operation: @escaping @Sendable (DatabaseManager) throws -> Void, completion: (() -> Void)? = nil) {
        guard !busy, !preview else { return }
        activity = title; error = nil
        let manager = manager
        Task {
            do {
                try await Task.detached { try operation(manager) }.value
                await refresh()
                activity = nil
                completion?()
            } catch {
                await refresh()
                self.error = error.localizedDescription
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
    var mail: MailManager { MailManager(store: manager.store, runner: manager.runner) }
    func showMailLogs(_ service: MailService) { logInstanceID = service.id; selection = .logs }
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
    var symbol: String {
        switch self {
        case .postgresql: return "cylinder.split.1x2.fill"
        case .mysql, .mariadb: return "externaldrive.fill"
        case .mongodb: return "leaf.fill"
        case .redis: return "morrow.redis"
        case .valkey: return "morrow.valkey"
        case .memcached: return "bolt.fill"
        }
    }
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
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(status.title).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.09), in: Capsule())
        .accessibilityElement(children: .combine)
    }
    var color: Color {
        switch status {
        case .running: return .green
        case .starting: return .orange
        case .failed, .missingBinary: return .red
        case .stopped, .unknown: return .secondary
        }
    }
}
