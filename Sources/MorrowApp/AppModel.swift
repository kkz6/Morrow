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
    @ObservationIgnored let preview: Bool

    init(manager: DatabaseManager = DatabaseManager(), preview: Bool = false) {
        self.manager = manager; self.preview = preview
        if preview {
            homebrewAvailable = true
            let pg = Installation(engine: .postgresql, formula: "postgresql@17", version: "17.6", prefix: "/opt/homebrew/Cellar/postgresql@17/17.6")
            let mysql = Installation(engine: .mysql, formula: "mysql@8.4", version: "8.4.6", prefix: "/opt/homebrew/Cellar/mysql@8.4/8.4.6")
            let mongo = Installation(engine: .mongodb, formula: "mongodb/brew/mongodb-community@8.0", version: "8.0.13", prefix: "/opt/homebrew/Cellar/mongodb-community@8.0/8.0.13")
            installations = [pg, mysql, mongo]
            instances = [DatabaseInstance(name: "studio", installation: pg, port: 5432, autoStart: true),
                         DatabaseInstance(name: "local-mysql", installation: mysql, port: 3306),
                         DatabaseInstance(name: "playground", installation: mongo, port: 27017)]
            statuses = [instances[0].id: .running, instances[1].id: .stopped, instances[2].id: .running]
        }
    }
    var busy: Bool { activity != nil }
    var runningCount: Int { statuses.values.filter { $0 == .running }.count }
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
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
    func refresh() async {
        guard !preview, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let manager = manager
        do {
            let snapshot = try await Task.detached {
                let state = try manager.store.load()
                let installer = try manager.installer()
                let installations = try installer.installations()
                let statuses = Dictionary(uniqueKeysWithValues: state.instances.map { ($0.id, manager.status($0)) })
                return (state, installations, statuses, installer.executable != nil)
            }.value
            instances = snapshot.0.instances
            preferences = snapshot.0.preferences
            installations = snapshot.1
            statuses = snapshot.2
            homebrewAvailable = snapshot.3
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
        case .redis, .valkey: return "square.stack.3d.up.fill"
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
