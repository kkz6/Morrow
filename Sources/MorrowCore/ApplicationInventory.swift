import Foundation

public struct ApplicationInventory: Codable, Equatable, Sendable {
    public var updatedAt: Date?
    public var databases: [Installation] = []
    public var runtimes: [RuntimeInstallation] = []
    public var mail: [MailInstallation] = []
    public var channels: [String: [RuntimeChannel]] = [:]
    public init() {}
}
public struct InventoryStore: Sendable {
    public let store: StateStore
    public init(store: StateStore) { self.store = store }
    private var url: URL { store.root.appendingPathComponent("inventory.json") }
    public func load() -> ApplicationInventory {
        guard let data = try? Data(contentsOf: url), var cached = try? JSONDecoder().decode(ApplicationInventory.self, from: data) else { return ApplicationInventory() }
        // nvm's old index advertised releases that may not exist in the hosted
        // catalog. Refresh only that selector after the provider migration;
        // retain the installed inventory and every other cached channel list.
        if cached.channels[RuntimeEngine.node.rawValue]?.contains(where: { $0.formula.hasPrefix("nvm@") }) == true {
            cached.channels.removeValue(forKey: RuntimeEngine.node.rawValue)
        }
        return cached
    }
    public func save(_ inventory: ApplicationInventory) throws {
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(inventory).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
