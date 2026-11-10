import Foundation
import Darwin

/// Local-only access preferences, separate from the portable workspace settings.
public struct AISettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var includeDebugData = false
    public var includeMail = false
    public init() {}
}

public struct AIIntegration: Sendable {
    public let store: StateStore
    public init(store: StateStore = StateStore()) { self.store = store }
    private var file: URL { store.root.appendingPathComponent("ai/settings.json") }
    public func settings() throws -> AISettings {
        guard FileManager.default.fileExists(atPath: file.path) else { return AISettings() }
        return try JSONDecoder().decode(AISettings.self, from: Data(contentsOf: file))
    }
    @discardableResult public func update(_ change: (inout AISettings) -> Void) throws -> AISettings {
        // AI preference changes must not wait behind a long service installation.
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(file.deletingLastPathComponent().appendingPathComponent("settings.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw MorrowError.message("Could not open AI preferences.") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw MorrowError.message("Could not lock AI preferences.") }
        defer { flock(fd, LOCK_UN) }
        var value = try settings(); change(&value)
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return value
    }
}

public enum AIClient: String, CaseIterable, Identifiable, Sendable {
    case claudeDesktop = "claude-desktop", cursor, vscode, windsurf
    public var id: String { rawValue }
    public var title: String {
        switch self { case .claudeDesktop: return "Claude Desktop"; case .cursor: return "Cursor"; case .vscode: return "VS Code"; case .windsurf: return "Windsurf" }
    }
    public func file(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let path: String
        switch self {
        case .claudeDesktop: path = "Library/Application Support/Claude/claude_desktop_config.json"
        case .cursor: path = ".cursor/mcp.json"
        case .vscode: path = "Library/Application Support/Code/User/mcp.json"
        case .windsurf: path = ".codeium/windsurf/mcp_config.json"
        }
        return home.appendingPathComponent(path)
    }
    var key: String { self == .vscode ? "servers" : "mcpServers" }
}

/// Updates only the named Morrow entry. Existing entries and malformed files are preserved.
public struct AIClientConfiguration {
    public let executable: String
    public let home: URL
    public init(executable: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.executable = executable; self.home = home
    }
    public func entry(for client: AIClient? = nil) -> [String: Any] {
        var entry: [String: Any] = ["command": executable, "args": ["mcp", "serve"]]
        if client == .vscode { entry["type"] = "stdio" }
        return entry
    }
    public func json(for client: AIClient? = nil) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [client?.key ?? "mcpServers": ["morrow": entry(for: client)]], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
    public func isAdded(to client: AIClient) throws -> Bool {
        let document = try read(client.file(home: home)).document
        guard let servers = document[client.key] as? [String: Any], let current = servers["morrow"] as? [String: Any] else { return false }
        return NSDictionary(dictionary: current).isEqual(to: entry(for: client))
    }
    public func setAdded(_ added: Bool, to client: AIClient) throws {
        guard !added || FileManager.default.isExecutableFile(atPath: executable) else { throw MorrowError.message("Install Morrow before connecting an AI app.") }
        let file = client.file(home: home).resolvingSymlinksInPath()
        let original = try read(file)
        var document = original.document
        guard document[client.key] == nil || document[client.key] is [String: Any] else { throw MorrowError.message("This app's MCP configuration uses an unsupported format. Use manual setup instead.") }
        var servers = document[client.key] as? [String: Any] ?? [:]
        if let current = servers["morrow"], !NSDictionary(dictionary: ["entry": current]).isEqual(to: ["entry": entry(for: client)]) {
            throw MorrowError.message("A different Morrow connection already exists. Review it in \(client.title); its settings have been preserved.")
        }
        if added { servers["morrow"] = entry(for: client) } else { servers.removeValue(forKey: "morrow") }
        if original.data == nil && !added { return }
        document[client.key] = servers
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let fm = FileManager.default
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Do not replace changes made by an editor while preparing this update.
        guard (try? Data(contentsOf: file)) == original.data else { throw MorrowError.message("The AI app changed its settings. Try again.") }
        if let previous = original.data {
            let backup = file.appendingPathExtension("morrow-backup-" + UUID().uuidString)
            try previous.write(to: backup, options: .withoutOverwriting)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try data.write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    private func read(_ file: URL) throws -> (document: [String: Any], data: Data?) {
        guard FileManager.default.fileExists(atPath: file.path) else { return ([:], nil) }
        let data = try Data(contentsOf: file)
        guard data.count <= 2 * 1024 * 1024, let object = try? JSONSerialization.jsonObject(with: data), let document = object as? [String: Any] else {
            throw MorrowError.message("This configuration contains comments or invalid JSON. Use manual setup; the file has been preserved.")
        }
        return (document, data)
    }
    public var codexCommand: String { "codex mcp add morrow -- " + shellQuote(executable) + " mcp serve" }
    public var claudeCommand: String { "claude mcp add --transport stdio --scope user morrow -- " + shellQuote(executable) + " mcp serve" }
    private func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
