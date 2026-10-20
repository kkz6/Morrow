import Foundation

/// Read-only discovery of existing nvm installations. New Node releases use
/// complete managed distributions and never bootstrap or modify nvm.
public struct NodeVersionManager: Sendable {
    public let store: StateStore
    public let runner: any CommandRunning
    public init(store: StateStore = StateStore(), runner: any CommandRunning = CommandRunner()) { self.store = store; self.runner = runner }
    public var directory: URL {
        let configured = (try? store.load().preferences.nvmDirectory) ?? ""
        if !configured.isEmpty { return URL(fileURLWithPath: configured) }
        if let env = ProcessInfo.processInfo.environment["NVM_DIR"], !env.isEmpty { return URL(fileURLWithPath: env) }
        let existing = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nvm")
        return FileManager.default.fileExists(atPath: existing.path) ? existing : store.root.appendingPathComponent("tools/nvm")
    }
    public func installations() -> [RuntimeInstallation] {
        let root = directory.appendingPathComponent("versions/node")
        return ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).compactMap { folder in
            let version = String(folder.lastPathComponent.drop(while: { $0 == "v" }))
            let binary = folder.appendingPathComponent("bin/node")
            guard SoftwareVersion(version) != nil, FileManager.default.isExecutableFile(atPath: binary.path) else { return nil }
            return RuntimeInstallation(engine: .node, formula: "nvm", version: version, prefix: folder.path, executable: binary.path, source: "nvm")
        }.sorted { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
    }
}
