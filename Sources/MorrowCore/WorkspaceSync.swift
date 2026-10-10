import Foundation
import CryptoKit

private struct DatabaseRecipe: Codable {
    let id: UUID
    let name: String
    let engine: DatabaseEngine
    let version: String
    let port: Int
    let autoStart: Bool
    let memoryMB: Int
    let maxConnections: Int
}
private struct RuntimeRecipe: Codable {
    let engine: RuntimeEngine
    let version: String
    let isDefault: Bool
    var key: String { engine.rawValue + ":" + WorkspaceSync.runtimeSeries(engine, version: version) }
}
private struct MailRecipe: Codable {
    let id: UUID
    let name: String
    let version: String
    let smtpPort: Int
    let httpPort: Int
    let autoStart: Bool
    var key: String { "mail:" + name.lowercased() }
}
private struct WorkspaceBlueprint: Codable {
    var databases: [DatabaseRecipe]
    var runtimes: [RuntimeRecipe]
    var appearance: String
    var showRunningCount: Bool
    var mail: [MailRecipe]
    init(databases: [DatabaseRecipe], runtimes: [RuntimeRecipe], appearance: String, showRunningCount: Bool, mail: [MailRecipe] = []) {
        self.databases = databases; self.runtimes = runtimes; self.appearance = appearance; self.showRunningCount = showRunningCount; self.mail = mail
    }
    enum CodingKeys: String, CodingKey { case databases, runtimes, appearance, showRunningCount, mail }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        databases = try values.decode([DatabaseRecipe].self, forKey: .databases)
        runtimes = try values.decode([RuntimeRecipe].self, forKey: .runtimes)
        appearance = try values.decode(String.self, forKey: .appearance)
        showRunningCount = try values.decode(Bool.self, forKey: .showRunningCount)
        mail = try values.decodeIfPresent([MailRecipe].self, forKey: .mail) ?? []
    }
}
private struct DeviceSnapshot: Codable {
    let schemaVersion: Int
    let deviceID: UUID
    let revision: Int
    let workspace: WorkspaceBlueprint
}
public struct SyncReport: Codable, Sendable {
    public var lastSyncedAt: Date?
    public var message = "Not synced yet"
    public var details: [String] = []
    public var failures: [String] = []
    public init() {}
}
private struct SyncCache: Codable {
    var deviceID = UUID()
    var localFingerprint: String?
    var appliedFingerprint: String?
    var knownDatabases: Set<String> = []
    var knownRuntimes: Set<String> = []
    var suppressedDatabases: Set<String> = []
    var suppressedRuntimes: Set<String> = []
    var report = SyncReport()
}

/// Portable workspace recipes live in a user-accessible iCloud Drive folder.
/// Device-specific state, executables and database files always remain local.
public struct WorkspaceSync: Sendable {
    public let store: StateStore
    public let runner: any CommandRunning
    public init(store: StateStore = StateStore(), runner: any CommandRunning = CommandRunner()) { self.store = store; self.runner = runner }
    public static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Morrow")
    }
    private var cacheURL: URL { store.root.appendingPathComponent("sync-state.json") }
    public func report() throws -> SyncReport { try store.syncOperation { try cache().report } }
    public func configure(enabled: Bool, folder: URL? = nil, automatic: Bool? = nil) throws {
        if enabled {
            let configured = try store.load().preferences.syncFolder
            let selected = folder ?? (configured.isEmpty ? Self.defaultFolder : URL(fileURLWithPath: configured))
            guard FileManager.default.fileExists(atPath: selected.deletingLastPathComponent().path) else {
                throw MorrowError.message("iCloud Drive is unavailable. Enable it in System Settings or choose your iCloud Drive folder in Morrow.")
            }
            try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        }
        try store.update { state in
            state.preferences.iCloudSyncEnabled = enabled
            if let folder { state.preferences.syncFolder = folder.path }
            if let automatic { state.preferences.autoSetupSyncedServices = automatic }
        }
    }
    @discardableResult public func synchronize(cli: URL, retry: Bool = false) throws -> SyncReport {
        try store.syncOperation {
            var cache = try cache()
            do {
                let state = try store.load()
                guard state.preferences.iCloudSyncEnabled else { throw MorrowError.message("iCloud workspace sync is disabled on this Mac.") }
                let folder = state.preferences.syncFolder.isEmpty ? Self.defaultFolder : URL(fileURLWithPath: state.preferences.syncFolder)
                guard FileManager.default.fileExists(atPath: folder.path) else { throw MorrowError.message("The sync folder is unavailable. Check iCloud Drive or choose its folder again.") }
                let snapshots = try readSnapshots(folder)
                let latest = snapshots.max { a, b in a.revision == b.revision ? a.deviceID.uuidString < b.deviceID.uuidString : a.revision < b.revision }
                let local = blueprint(state)
                let fingerprint = try digest(local)
                let changedLocally = cache.localFingerprint != nil && cache.localFingerprint != fingerprint
                var chosen = latest
                var report = SyncReport()
                if changedLocally {
                    let names = Set(local.databases.map { $0.name.lowercased() } + local.mail.map(\.key))
                    let tools = Set(local.runtimes.map(\.key))
                    cache.suppressedDatabases.formUnion(cache.knownDatabases.subtracting(names))
                    cache.suppressedRuntimes.formUnion(cache.knownRuntimes.subtracting(tools))
                    cache.suppressedDatabases.subtract(names); cache.suppressedRuntimes.subtract(tools)
                }
                let cloudNames = Set(latest?.workspace.databases.map { $0.name.lowercased() } ?? [])
                let cloudTools = Set(latest?.workspace.runtimes.map(\.key) ?? [])
                let hasInitialAdditions = cache.localFingerprint == nil && latest != nil && (
                    local.databases.contains { !cloudNames.contains($0.name.lowercased()) } || local.runtimes.contains { !cloudTools.contains($0.key) }
                    || local.mail.contains { item in !(latest?.workspace.mail.contains { $0.name.lowercased() == item.name.lowercased() } ?? false) })
                if latest == nil || changedLocally || hasInitialAdditions {
                    // Additive publication retains recipes missing on this Mac.
                    // This avoids deleting another Mac's workspace or publishing
                    // an empty initial setup over an existing cloud blueprint.
                    var merged = merge(local, with: latest?.workspace)
                    if hasInitialAdditions, let previous = latest?.workspace {
                        merged.appearance = previous.appearance; merged.showRunningCount = previous.showRunningCount
                    }
                    let maximum = snapshots.map(\.revision).max() ?? 0
                    guard maximum < Int.max - 1 else { throw MorrowError.message("Invalid sync revision.") }
                    let snapshot = DeviceSnapshot(schemaVersion: 1, deviceID: cache.deviceID, revision: maximum + 1, workspace: merged)
                    try publish(snapshot, folder: folder)
                    chosen = snapshot
                    report.details.append("Saved this Mac's workspace setup to the sync folder.")
                }
                if let chosen {
                    let remoteFingerprint = try digest(chosen.workspace) + ":" + String(state.preferences.autoSetupSyncedServices)
                    if retry || cache.appliedFingerprint != remoteFingerprint {
                        try validate(chosen.workspace)
                        try store.update { state in
                            state.preferences.appearance = chosen.workspace.appearance
                            state.preferences.showRunningCount = chosen.workspace.showRunningCount
                        }
                        if state.preferences.autoSetupSyncedServices {
                            restore(chosen.workspace, cli: cli, cache: cache, report: &report)
                        } else {
                            report.details.append("Service setup is paused on this Mac. Enable automatic setup to install missing services.")
                        }
                        cache.appliedFingerprint = remoteFingerprint
                    } else {
                        report.details = cache.report.details
                        report.failures = cache.report.failures
                    }
                }
                let current = blueprint(try store.load())
                cache.localFingerprint = try digest(current)
                cache.knownDatabases = Set(current.databases.map { $0.name.lowercased() } + current.mail.map(\.key))
                cache.knownRuntimes = Set(current.runtimes.map(\.key))
                report.lastSyncedAt = Date()
                report.message = report.failures.isEmpty ? "Workspace file up to date" : "Some services need attention"
                cache.report = report
                try save(cache)
                return report
            } catch {
                cache.report.message = error.localizedDescription
                try? save(cache)
                throw error
            }
        }
    }
    static func runtimeSeries(_ engine: RuntimeEngine, version: String) -> String {
        let numbers = SoftwareVersion(version)?.components ?? []
        let count = engine == .node ? 1 : 2
        return numbers.prefix(count).map(String.init).joined(separator: ".")
    }
    private func blueprint(_ state: MorrowState) -> WorkspaceBlueprint {
        let databases = state.instances.map { DatabaseRecipe(id: $0.id, name: $0.name, engine: $0.engine, version: $0.installation.version, port: $0.port, autoStart: $0.autoStart, memoryMB: $0.memoryMB, maxConnections: $0.maxConnections) }.sorted { $0.name < $1.name }
        var tools: [String: RuntimeRecipe] = [:]
        for item in state.tools {
            let recipe = RuntimeRecipe(engine: item.engine, version: item.version, isDefault: state.toolDefaults[item.engine.rawValue] == item.id)
            if let existing = tools[recipe.key] {
                if recipe.isDefault || (!existing.isDefault && (SoftwareVersion(recipe.version) ?? SoftwareVersion("0")!) > (SoftwareVersion(existing.version) ?? SoftwareVersion("0")!)) { tools[recipe.key] = recipe }
            } else { tools[recipe.key] = recipe }
        }
        return WorkspaceBlueprint(databases: databases, runtimes: tools.values.sorted { $0.key < $1.key }, appearance: state.preferences.appearance, showRunningCount: state.preferences.showRunningCount, mail: state.mailServices.map { MailRecipe(id: $0.id, name: $0.name, version: $0.installation.version, smtpPort: $0.smtpPort, httpPort: $0.httpPort, autoStart: $0.autoStart) }.sorted { $0.name < $1.name })
    }
    private func merge(_ local: WorkspaceBlueprint, with remote: WorkspaceBlueprint?) -> WorkspaceBlueprint {
        guard let remote else { return local }
        let names = Set(local.databases.map { $0.name.lowercased() }), tools = Set(local.runtimes.map(\.key))
        // The local default for a runtime takes precedence when publishing.
        let defaults = Set(local.runtimes.filter(\.isDefault).map(\.engine))
        let retained = remote.runtimes.filter { !tools.contains($0.key) }.map {
            RuntimeRecipe(engine: $0.engine, version: $0.version, isDefault: $0.isDefault && !defaults.contains($0.engine))
        }
        return WorkspaceBlueprint(databases: (local.databases + remote.databases.filter { !names.contains($0.name.lowercased()) }).sorted { $0.name < $1.name }, runtimes: (local.runtimes + retained).sorted { $0.key < $1.key }, appearance: local.appearance, showRunningCount: local.showRunningCount, mail: (local.mail + remote.mail.filter { item in !local.mail.contains { $0.name.lowercased() == item.name.lowercased() } }).sorted { $0.name < $1.name })
    }
    private func restore(_ workspace: WorkspaceBlueprint, cli: URL, cache: SyncCache, report: inout SyncReport) {
        let databases = DatabaseManager(store: store, runner: runner), runtimes = RuntimeManager(store: store, runner: runner)
        for recipe in workspace.databases {
            if cache.suppressedDatabases.contains(recipe.name.lowercased()) { continue }
            do {
                let local = try store.load().instances
                if let existing = local.first(where: { $0.id == recipe.id || $0.name.lowercased() == recipe.name.lowercased() }) {
                    guard existing.engine == recipe.engine else { throw MorrowError.message("The local instance uses another engine; it was preserved.") }
                    guard let wanted = SoftwareVersion(recipe.version), let current = SoftwareVersion(existing.installation.version), current.isMaintenanceRelease(of: wanted, engine: recipe.engine) else { throw MorrowError.message("The local release series differs; migrate or create another instance manually.") }
                    var settings = existing
                    // Keep a port chosen on this Mac; the blueprint's preferred
                    // port may belong to a different local process.
                    settings.name = recipe.name
                    settings.autoStart = recipe.autoStart; settings.memoryMB = recipe.memoryMB; settings.maxConnections = recipe.maxConnections
                    if settings != existing {
                        let status = databases.status(existing)
                        guard status != .running && status != .starting else { throw MorrowError.message("Stop the local instance to apply its synced settings.") }
                        try databases.update(settings)
                    }
                    report.details.append("\(recipe.name): existing instance preserved on port \(existing.port).")
                    continue
                }
                let series = databaseSeries(recipe.engine, version: recipe.version)
                // Reuse compatible binaries, or resolve an available series
                // before installing. Historical patches may no longer exist.
                let installed = try databases.installer().installations().first { item in
                    item.engine == recipe.engine && BinaryInstaller.matches(item, request: series)
                }
                let formula: String
                if installed != nil { formula = series }
                else {
                    let candidates = try databases.installer().channels().filter { $0.engine == recipe.engine }
                    guard let selected = candidates.first(where: { channel in
                        guard let next = SoftwareVersion(channel.version), let old = SoftwareVersion(recipe.version) else { return false }
                        return next.isMaintenanceRelease(of: old, engine: recipe.engine)
                    }) else { throw MorrowError.message("No configured binary source provides the synced release series \(series).") }
                    formula = selected.formula
                }
                let reserved = Set(local.map(\.port))
                let port = !reserved.contains(recipe.port) && DatabaseManager.portAvailable(recipe.port) ? recipe.port : try databases.suggestedPort(engine: recipe.engine)
                let instance = try databases.provision(engine: recipe.engine, version: formula, name: recipe.name, port: port, autoStart: recipe.autoStart, memoryMB: recipe.memoryMB, maxConnections: recipe.maxConnections, installation: installed, id: recipe.id)
                report.details.append("\(recipe.name): created \(instance.engine.title) \(instance.installation.version) on port \(port).")
            } catch { report.failures.append("\(recipe.name): \(error.localizedDescription)") }
        }
        let mail = MailManager(store: store, runner: runner)
        for recipe in workspace.mail {
            if cache.suppressedDatabases.contains(recipe.key) { continue }
            do {
                let state = try store.load()
                if let existing = state.mailServices.first(where: { $0.id == recipe.id || $0.name.lowercased() == recipe.name.lowercased() }) {
                    guard SoftwareVersion(existing.installation.version)?.components.first == SoftwareVersion(recipe.version)?.components.first else { throw MorrowError.message("The local Mailpit release differs; review its settings locally.") }
                    var settings = existing; settings.name = recipe.name; settings.autoStart = recipe.autoStart
                    if settings != existing { try mail.update(settings) }
                    report.details.append("\(recipe.name): existing mail inbox preserved.")
                    continue
                }
                let found = try mail.installations()
                let series = SoftwareVersion(recipe.version)?.components.prefix(2)
                var version = found.first { SoftwareVersion($0.version)?.components.prefix(2) == series }?.version
                if version == nil {
                    let policy = try databases.installer()
                    let available: String
                    if let release = try policy.managed.release(package: "mailpit", request: "current") { available = release.version }
                    else { available = try policy.package("mailpit").version }
                    guard SoftwareVersion(available)?.components.first == SoftwareVersion(recipe.version)?.components.first else { throw MorrowError.message("The synced Mailpit release is unavailable.") }
                    version = available
                }
                let used = Set(state.instances.map(\.port) + state.mailServices.flatMap { [$0.smtpPort, $0.httpPort] })
                let smtp = !used.contains(recipe.smtpPort) && DatabaseManager.portAvailable(recipe.smtpPort) ? recipe.smtpPort : try mail.suggestedPort(1025)
                let http = smtp != recipe.httpPort && !used.contains(recipe.httpPort) && DatabaseManager.portAvailable(recipe.httpPort) ? recipe.httpPort : try mail.suggestedPort(8025, excluding: smtp)
                let service = try mail.provision(name: recipe.name, smtpPort: smtp, httpPort: http, autoStart: recipe.autoStart, version: version ?? "automatic", id: recipe.id)
                report.details.append("\(service.name): mail server ready to start, SMTP :\(smtp), inbox :\(http).")
            } catch { report.failures.append("\(recipe.name): \(error.localizedDescription)") }
        }
        for recipe in workspace.runtimes {
            if cache.suppressedRuntimes.contains(recipe.key) { continue }
            do {
                let series = Self.runtimeSeries(recipe.engine, version: recipe.version)
                let installed = try runtimes.install(recipe.engine, version: series)
                if recipe.isDefault { try runtimes.use(installed, cli: cli) }
                report.details.append("\(recipe.engine.title): ready with \(installed.version)\(recipe.isDefault ? " as default" : "").")
            } catch { report.failures.append("\(recipe.engine.title): \(error.localizedDescription)") }
        }
    }
    private func databaseSeries(_ engine: DatabaseEngine, version: String) -> String {
        let numbers = SoftwareVersion(version)?.components ?? []
        let count = engine == .postgresql && (numbers.first ?? 0) >= 10 ? 1 : 2
        return numbers.prefix(count).map(String.init).joined(separator: ".")
    }
    private func validate(_ workspace: WorkspaceBlueprint) throws {
        guard workspace.databases.count <= 100, workspace.runtimes.count <= 100, workspace.mail.count <= 100, ["system", "light", "dark"].contains(workspace.appearance) else { throw MorrowError.message("Invalid workspace blueprint.") }
        var ids = Set<UUID>(), names = Set<String>(), tools = Set<String>(), defaults = Set<RuntimeEngine>()
        for item in workspace.databases {
            guard ids.insert(item.id).inserted, names.insert(item.name.lowercased()).inserted, SoftwareVersion(item.version) != nil else { throw MorrowError.message("Invalid database recipe.") }
            let placeholder = Installation(engine: item.engine, formula: "", version: item.version, prefix: "")
            try DatabaseManager.validate(DatabaseInstance(name: item.name, installation: placeholder, port: item.port, memoryMB: item.memoryMB, maxConnections: item.maxConnections))
        }
        var mailNames = Set<String>()
        for item in workspace.mail {
            guard ids.insert(item.id).inserted, mailNames.insert(item.name.lowercased()).inserted, SoftwareVersion(item.version) != nil,
                  (1024...65535).contains(item.smtpPort), (1024...65535).contains(item.httpPort), item.smtpPort != item.httpPort else { throw MorrowError.message("Invalid mail recipe.") }
            try DatabaseManager.validate(DatabaseInstance(name: item.name, installation: Installation(engine: .postgresql, formula: "", version: "", prefix: ""), port: item.smtpPort))
        }
        for item in workspace.runtimes {
            guard SoftwareVersion(item.version) != nil, !Self.runtimeSeries(item.engine, version: item.version).isEmpty, tools.insert(item.key).inserted,
                  !item.isDefault || defaults.insert(item.engine).inserted else { throw MorrowError.message("Invalid runtime recipe.") }
        }
    }
    private func readSnapshots(_ folder: URL) throws -> [DeviceSnapshot] {
        let directory = folder.appendingPathComponent("devices")
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        guard files.count <= 200 else { throw MorrowError.message("Too many sync snapshots. Review the sync folder.") }
        var snapshots: [DeviceSnapshot] = []
        for file in files {
            if file.lastPathComponent.hasSuffix(".icloud") {
                var name = String(file.lastPathComponent.dropLast(".icloud".count))
                if name.hasPrefix(".") { name.removeFirst() }
                try? FileManager.default.startDownloadingUbiquitousItem(at: directory.appendingPathComponent(name))
                throw MorrowError.message("iCloud is downloading workspace settings. Try syncing again shortly.")
            }
            guard file.pathExtension == "json" else { continue }
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1_048_576 else { throw MorrowError.message("A sync snapshot exceeds the allowed size.") }
            var accessError: Error?, coordinatorError: NSError?, snapshot: DeviceSnapshot?
            NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinatorError) { coordinated in
                do {
                    let data = try Data(contentsOf: coordinated)
                    guard data.count <= 1_048_576 else { throw MorrowError.message("A sync snapshot is too large.") }
                    let decoded = try JSONDecoder().decode(DeviceSnapshot.self, from: data)
                    guard decoded.schemaVersion == 1, decoded.revision >= 1, decoded.revision < Int.max - 1 else { throw MorrowError.message("Unsupported sync snapshot.") }
                    try validate(decoded.workspace)
                    snapshot = decoded
                } catch { accessError = error }
            }
            if let error = coordinatorError ?? accessError as NSError? { throw error }
            if let snapshot { snapshots.append(snapshot) }
        }
        return snapshots
    }
    private func publish(_ snapshot: DeviceSnapshot, folder: URL) throws {
        try validate(snapshot.workspace)
        let directory = folder.appendingPathComponent("devices")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(snapshot.deviceID.uuidString.lowercased() + ".json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= 1_048_576 else { throw MorrowError.message("The workspace blueprint is too large to sync.") }
        var accessError: Error?, coordinatorError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { coordinated in
            do { try data.write(to: coordinated, options: .atomic) } catch { accessError = error }
        }
        if let error = coordinatorError ?? accessError as NSError? { throw error }
    }
    private func digest(_ workspace: WorkspaceBlueprint) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(workspace)).map { String(format: "%02x", $0) }.joined()
    }
    private func cache() throws -> SyncCache {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return SyncCache() }
        return try JSONDecoder().decode(SyncCache.self, from: Data(contentsOf: cacheURL))
    }
    private func save(_ cache: SyncCache) throws {
        try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
    }
}
