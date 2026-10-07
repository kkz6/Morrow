import Foundation
import Darwin

public struct StateStore: Sendable {
    public let root: URL
    private let isolated: Bool
    public init(root: URL? = nil) {
        isolated = root != nil || ProcessInfo.processInfo.environment["MORROW_HOME"] != nil
        if let root { self.root = root }
        else if let override = ProcessInfo.processInfo.environment["MORROW_HOME"] {
            self.root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Morrow", isDirectory: true)
        }
    }
    public func instanceDirectory(_ instance: DatabaseInstance) -> URL {
        root.appendingPathComponent("instances/\(instance.id.uuidString.lowercased())", isDirectory: true)
    }
    public func dataDirectory(_ instance: DatabaseInstance) -> URL { instanceDirectory(instance).appendingPathComponent("data") }
    public func logURL(_ instance: DatabaseInstance) -> URL { instanceDirectory(instance).appendingPathComponent("server.log") }
    public func configURL(_ instance: DatabaseInstance) -> URL { instanceDirectory(instance).appendingPathComponent("server.conf") }
    // Unix socket paths on macOS must stay under 104 bytes, even when the
    // user's home or application support directory has a long name.
    public func socketURL(_ instance: DatabaseInstance) -> URL {
        URL(fileURLWithPath: "/tmp/morrow.\(getuid()).\(instance.id.uuidString.lowercased()).sock")
    }
    public func jobURL(_ instance: DatabaseInstance) -> URL {
        root.appendingPathComponent("jobs/\(instance.label).plist")
    }
    public func loginJobURL(_ instance: DatabaseInstance) -> URL {
        // Isolated stores must never modify the user's real login items.
        let base = isolated
            ? root.appendingPathComponent("LaunchAgents")
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        return base.appendingPathComponent("\(instance.label).plist")
    }
    public func load() throws -> MorrowState { try locked { try readUnlocked() } }
    @discardableResult
    public func update<T>(_ mutate: (inout MorrowState) throws -> T) throws -> T {
        try locked {
            var state = try readUnlocked()
            let value = try mutate(&state)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let file = root.appendingPathComponent("state.json")
            try encoder.encode(state).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return value
        }
    }
    // Serialize long operations across the app and CLI independently of the
    // short metadata lock. A refresh can still read state during an install.
    public func operation<T>(_ body: () throws -> T) throws -> T { try locked(name: "operation.lock", body) }
    private func readUnlocked() throws -> MorrowState {
        let file = root.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return MorrowState() }
        do {
            let state = try JSONDecoder().decode(MorrowState.self, from: Data(contentsOf: file))
            guard state.schemaVersion == 1 else { throw MorrowError.message("This data was saved by a newer Morrow version.") }
            return state
        } catch {
            throw MorrowError.message("Could not read \(file.path). Your data has been preserved. \(error.localizedDescription)")
        }
    }
    private func locked<T>(name: String = "state.lock", _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(root.appendingPathComponent(name).path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw MorrowError.message("Could not open Morrow's state lock.") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw MorrowError.message("Could not lock Morrow's state.") }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
