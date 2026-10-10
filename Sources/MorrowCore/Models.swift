import Foundation

public enum DatabaseEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case postgresql, mysql, mariadb, mongodb, redis, valkey, memcached
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .postgresql: return "PostgreSQL"
        case .mysql: return "MySQL"
        case .mariadb: return "MariaDB"
        case .mongodb: return "MongoDB"
        case .redis: return "Redis"
        case .valkey: return "Valkey"
        case .memcached: return "Memcached"
        }
    }
    public var summary: String {
        switch self {
        case .postgresql: return "Relational database for your next project."
        case .mysql: return "A familiar SQL server for local development."
        case .mariadb: return "An open source alternative in the MySQL family."
        case .mongodb: return "Documents, collections, and flexible schemas."
        case .redis: return "Fast data structures, queues, and caching."
        case .valkey: return "An open source in-memory data store."
        case .memcached: return "A lightweight cache for your applications."
        }
    }
    public var defaultPort: Int {
        switch self {
        case .postgresql: return 5432
        case .mysql, .mariadb: return 3306
        case .mongodb: return 27017
        case .redis, .valkey: return 6379
        case .memcached: return 11211
        }
    }
    public var binary: String {
        switch self {
        case .postgresql: return "postgres"
        case .mysql: return "mysqld"
        case .mariadb: return "mariadbd"
        case .mongodb: return "mongod"
        case .redis: return "redis-server"
        case .valkey: return "valkey-server"
        case .memcached: return "memcached"
        }
    }
    public var formulaBase: String { self == .mongodb ? "mongodb-community" : rawValue }
    public var supportsConnections: Bool { [.postgresql, .mysql, .mariadb].contains(self) }
    public var supportsMemory: Bool { [.postgresql, .redis, .valkey, .memcached].contains(self) }
    public static func parse(_ value: String) -> DatabaseEngine? {
        switch value.lowercased() {
        case "pg", "pgsql", "postgres": return .postgresql
        case "mongo": return .mongodb
        default: return DatabaseEngine(rawValue: value.lowercased())
        }
    }
}

public struct Installation: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(engine.rawValue):\(version):\(prefix)" }
    public let engine: DatabaseEngine
    public let formula: String
    public let version: String
    public let prefix: String
    public var executable: String { "\(prefix)/bin/\(engine.binary)" }
    public var packageVersion: String {
        let directory = URL(fileURLWithPath: prefix).lastPathComponent
        if prefix.contains("/Cellar/"), let package = SoftwareVersion(directory),
           package.components == SoftwareVersion(version)?.components { return directory }
        return version
    }
    public var initializationTool: String? {
        if engine == .postgresql { return prefix + "/bin/initdb" }
        if engine == .mariadb {
            return [prefix + "/bin/mariadb-install-db", prefix + "/scripts/mariadb-install-db"]
                .first { FileManager.default.isExecutableFile(atPath: $0) } ?? prefix + "/bin/mariadb-install-db"
        }
        return nil
    }
    public init(engine: DatabaseEngine, formula: String, version: String, prefix: String) {
        self.engine = engine; self.formula = formula; self.version = version; self.prefix = prefix
    }
}

public struct VersionChannel: Codable, Identifiable, Sendable {
    public var id: String { formula }
    public let engine: DatabaseEngine
    public let formula: String
    public let version: String
    public let deprecated: Bool
    public var title: String { formula.hasPrefix("managed:") ? version : formula.split(separator: "/").last.map(String.init) ?? formula }
    public init(engine: DatabaseEngine, formula: String, version: String, deprecated: Bool = false) {
        self.engine = engine; self.formula = formula; self.version = version; self.deprecated = deprecated
    }
}

public struct DatabaseInstance: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var installation: Installation
    public var port: Int
    public var autoStart: Bool
    public var memoryMB: Int
    public var maxConnections: Int
    public let createdAt: Date
    public var engine: DatabaseEngine { installation.engine }
    public var label: String { "dev.morrow.database.\(id.uuidString.lowercased())" }
    public init(id: UUID = UUID(), name: String, installation: Installation, port: Int,
                autoStart: Bool = false, memoryMB: Int = 128, maxConnections: Int = 100,
                createdAt: Date = Date()) {
        self.id = id; self.name = name; self.installation = installation; self.port = port
        self.autoStart = autoStart; self.memoryMB = memoryMB; self.maxConnections = maxConnections
        self.createdAt = createdAt
    }
    public var connectionURL: String {
        switch engine {
        case .postgresql: return "postgresql://postgres@127.0.0.1:\(port)/postgres"
        case .mysql, .mariadb: return "mysql://root@127.0.0.1:\(port)"
        case .mongodb: return "mongodb://127.0.0.1:\(port)"
        case .redis, .valkey: return "redis://127.0.0.1:\(port)"
        case .memcached: return "127.0.0.1:\(port)"
        }
    }
}

public enum InstanceStatus: String, Sendable {
    case running, starting, stopped, failed, missingBinary, unknown
    public var title: String {
        switch self {
        case .missingBinary: return "Version missing"
        default: return rawValue.capitalized
        }
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var showRunningCount = true
    public var appearance = "system"
    public var homebrewPath = ""
    public var allowHomebrewFallback = false
    public var binaryCatalogURL = ""
    public var iCloudSyncEnabled = false
    public var autoSetupSyncedServices = false
    public var syncFolder = ""
    public var nvmDirectory = ""
    public var lastSettingsSection = "instances"
    public var lastRuntime = "php"
    public var onboardingCompleted = false
    public init() {}
    enum CodingKeys: String, CodingKey { case showRunningCount, appearance, homebrewPath, allowHomebrewFallback, binaryCatalogURL, iCloudSyncEnabled, autoSetupSyncedServices, syncFolder, nvmDirectory, lastSettingsSection, lastRuntime, onboardingCompleted }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        showRunningCount = try values.decodeIfPresent(Bool.self, forKey: .showRunningCount) ?? true
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
        homebrewPath = try values.decodeIfPresent(String.self, forKey: .homebrewPath) ?? ""
        allowHomebrewFallback = try values.decodeIfPresent(Bool.self, forKey: .allowHomebrewFallback) ?? false
        binaryCatalogURL = try values.decodeIfPresent(String.self, forKey: .binaryCatalogURL) ?? ""
        iCloudSyncEnabled = try values.decodeIfPresent(Bool.self, forKey: .iCloudSyncEnabled) ?? false
        autoSetupSyncedServices = try values.decodeIfPresent(Bool.self, forKey: .autoSetupSyncedServices) ?? false
        syncFolder = try values.decodeIfPresent(String.self, forKey: .syncFolder) ?? ""
        nvmDirectory = try values.decodeIfPresent(String.self, forKey: .nvmDirectory) ?? ""
        lastSettingsSection = try values.decodeIfPresent(String.self, forKey: .lastSettingsSection) ?? "instances"
        lastRuntime = try values.decodeIfPresent(String.self, forKey: .lastRuntime) ?? "php"
        // Existing installations keep their workspace; new preferences start
        // with the assistant enabled through the property default above.
        onboardingCompleted = try values.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? true
    }
}

public struct MorrowState: Codable, Sendable {
    public var schemaVersion = 1
    public var instances: [DatabaseInstance] = []
    public var preferences = AppPreferences()
    public var objectStorage: [ObjectStorageService] = []
    public var web = WebWorkspace()
    public var mailServices: [MailService] = []
    public var tools: [RuntimeInstallation] = []
    public var toolDefaults: [String: String] = [:]
    public init() {}
    enum CodingKeys: String, CodingKey { case schemaVersion, instances, preferences, objectStorage, web, mailServices, tools, toolDefaults }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        instances = try values.decodeIfPresent([DatabaseInstance].self, forKey: .instances) ?? []
        preferences = try values.decodeIfPresent(AppPreferences.self, forKey: .preferences) ?? AppPreferences()
        objectStorage = try values.decodeIfPresent([ObjectStorageService].self, forKey: .objectStorage) ?? []
        web = try values.decodeIfPresent(WebWorkspace.self, forKey: .web) ?? WebWorkspace()
        mailServices = try values.decodeIfPresent([MailService].self, forKey: .mailServices) ?? []
        tools = try values.decodeIfPresent([RuntimeInstallation].self, forKey: .tools) ?? []
        toolDefaults = try values.decodeIfPresent([String: String].self, forKey: .toolDefaults) ?? [:]
    }
}

public enum MorrowError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}
