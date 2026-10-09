import Foundation

/// nvm is a shell function. Only fixed scripts are evaluated; versions and
/// paths travel as positional arguments, never interpolated shell source.
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
    public func channels() throws -> [RuntimeChannel] {
        let output = try runner.run("/usr/bin/curl", ["--fail", "--silent", "--show-error", "--max-time", "20", "--max-filesize", "5242880", "https://nodejs.org/dist/index.json"], environment: [:]).checked()
        guard let data = output.data(using: .utf8), let releases = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw MorrowError.message("Could not read Node's official release catalog.") }
        return releases.compactMap { release in
            guard let raw = release["version"] as? String, raw.hasPrefix("v"), let files = release["files"] as? [String], files.contains(where: { $0.hasPrefix("osx-") }) else { return nil }
            let version = String(raw.dropFirst())
            guard SoftwareVersion(version) != nil else { return nil }
            return RuntimeChannel(engine: .node, formula: "nvm@" + version, version: version)
        }
    }
    private func script() throws -> String {
        let candidates = [directory.appendingPathComponent("nvm.sh").path, "/opt/homebrew/opt/nvm/nvm.sh", "/usr/local/opt/nvm/nvm.sh"]
        if let script = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            return script
        }
        let staging = store.root.appendingPathComponent(".nvm-install-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try runner.run("/usr/bin/git", ["clone", "--depth", "1", "--branch", "v0.40.8", "https://github.com/nvm-sh/nvm.git", staging.path], environment: [:]).checked()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for name in ["nvm.sh", "nvm-exec", "bash_completion", "LICENSE.md"] {
            let target = directory.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: target.path) else { throw MorrowError.message("An existing nvm file was preserved. Choose a complete nvm directory in General.") }
            try FileManager.default.copyItem(at: staging.appendingPathComponent(name), to: target)
        }
        return directory.appendingPathComponent("nvm.sh").path
    }
    @discardableResult public func install(_ requested: String) throws -> RuntimeInstallation {
        let version = requested.replacingOccurrences(of: "nvm@", with: "").replacingOccurrences(of: "node@", with: "")
        guard ["automatic", "current", "latest", "lts"].contains(version) || SoftwareVersion(version) != nil else { throw MorrowError.message("Use an exact Node version, a release series, current, or lts.") }
        let selector = ["automatic", "current", "latest"].contains(version) ? "node" : version
        let manager = try script()
        let source = "export NVM_DIR=\"$1\"; . \"$2\" --no-use || exit $?; if [ \"$3\" = lts ]; then nvm install --lts >&2 || exit $?; else nvm install \"$3\" >&2 || exit $?; fi; nvm which current"
        let output = try runner.run("/bin/bash", ["--noprofile", "--norc", "-c", source, "morrow-nvm", directory.path, manager, selector], environment: ["NVM_NO_COLORS": "1", "NVM_NO_PROGRESS": "1"]).checked()
        let path = output.components(separatedBy: .newlines).last { $0.hasPrefix(directory.path + "/versions/node/") } ?? ""
        guard let item = installations().first(where: { $0.executable == path }) else { throw MorrowError.message("nvm completed but the installed Node executable was not detected.") }
        return item
    }
    public func selectDefault(_ item: RuntimeInstallation) throws {
        guard item.source == "nvm" else { return }
        let source = "export NVM_DIR=\"$1\"; . \"$2\" --no-use || exit $?; nvm alias default \"$3\""
        try runner.run("/bin/bash", ["--noprofile", "--norc", "-c", source, "morrow-nvm", directory.path, try script(), item.version], environment: ["NVM_NO_COLORS": "1"]).checked()
    }
}
