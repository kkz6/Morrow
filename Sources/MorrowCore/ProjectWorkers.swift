import Foundation
import Darwin

/// Explicitly adopted user launch agents. Original registrations stay private
/// and recoverable; importing never bootouts, bootstraps, or signals a worker.
public struct ProjectWorkers: Sendable {
    public struct Worker: Sendable {
        public let label: String
        public let directory: String
    }
    private struct Registration: Codable {
        let label: String
        let directory: String
        let original: Data
        let permissions: Int
        var managed: Data
        var previous: Data?
        func accepts(_ data: Data) -> Bool { data == original || data == managed || data == previous }
    }
    public let store: StateStore
    public init(store: StateStore) { self.store = store }
    private var registry: URL { store.root.appendingPathComponent("project-workers.json") }
    private func load() throws -> [Registration] {
        guard FileManager.default.fileExists(atPath: registry.path) else { return [] }
        return try JSONDecoder().decode([Registration].self, from: Data(contentsOf: registry))
    }
    private func save(_ records: [Registration]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: registry, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registry.path)
    }
    public func workers() throws -> [Worker] {
        try load().map { Worker(label: $0.label, directory: $0.directory) }
    }
    public func managedFiles() throws -> [URL] {
        try load().compactMap { record in
            let file = store.loginAgentURL(label: record.label)
            guard let (data, _, _) = try? read(file), data == record.managed || (data == record.previous && data != record.original) else { return nil }
            return file
        }
    }
    private func read(_ file: URL) throws -> (Data, [String: Any], Int) {
        let fm = FileManager.default, directory = store.loginAgentURL(label: "unused").deletingLastPathComponent().standardizedFileURL
        let file = file.standardizedFileURL
        guard file.deletingLastPathComponent() == directory,
              directory.resolvingSymlinksInPath() == directory else {
            throw MorrowError.message("Choose a worker registration in your own Library/LaunchAgents folder.")
        }
        let attributes = try fm.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1_048_576 else {
            throw MorrowError.message("Worker registrations must be regular files owned by your Mac account.")
        }
        let data = try Data(contentsOf: file)
        guard let job = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = job["Label"] as? String,
              label.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil,
              !label.hasPrefix("com.apple."), !label.hasPrefix("dev.morrow."),
              file.lastPathComponent == label + ".plist" else {
            throw MorrowError.message("Choose an independent project worker; system and existing Morrow jobs cannot be imported.")
        }
        return (data, job, (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o600)
    }
    private func wrapped(_ original: Data, launcher: URL) throws -> Data {
        guard var job = try PropertyListSerialization.propertyList(from: original, format: nil) as? [String: Any],
              let arguments = job["ProgramArguments"] as? [String], let binary = arguments.first,
              binary.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: binary),
              job["Program"] == nil || job["Program"] as? String == binary,
              job["BundleProgram"] == nil, job["UserName"] == nil, job["GroupName"] == nil,
              job["AssociatedBundleIdentifiers"] == nil,
              let directory = job["WorkingDirectory"] as? String, directory.hasPrefix("/"),
              (try? URL(fileURLWithPath: directory).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              binary != launcher.path else {
            throw MorrowError.message("Import needs an independent user worker with an existing executable and project folder. Its command and folder are preserved.")
        }
        job.removeValue(forKey: "Program")
        job["ProgramArguments"] = [launcher.path, "service-runner", "--"] + arguments
        job["AssociatedBundleIdentifiers"] = ManagedServiceRunner.bundleIdentifiers
        return try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
    }
    private func verify(_ launcher: URL) throws {
        let attribution = BackgroundAttribution(launcher: launcher)
        guard attribution.ready else { throw MorrowError.message("Import project workers from the installed, signed Morrow app.") }
        try attribution.registerApp()
    }
    public func adopt(_ file: URL, launcher: URL) throws -> String {
        try verify(launcher)
        return try adoptVerified(file, launcher: launcher)
    }
    // Kept separate for testing file transactions without distributing test keys.
    func adoptVerified(_ file: URL, launcher: URL) throws -> String {
        try store.operation {
            let (data, job, permissions) = try read(file)
            let label = job["Label"] as! String
            var records = try load()
            if let index = records.firstIndex(where: { $0.label == label }) {
                guard records[index].accepts(data) else { throw changed(label) }
                let managed = try wrapped(records[index].original, launcher: launcher)
                if data == managed { return label }
                records[index].previous = data
                records[index].managed = managed
            } else {
                let managed = try wrapped(data, launcher: launcher)
                records.append(Registration(label: label, directory: job["WorkingDirectory"] as! String,
                                            original: data, permissions: permissions, managed: managed, previous: data))
            }
            let record = records.first { $0.label == label }!
            // Persist both old and new bytes first. An interrupted write can be
            // retried or undone without losing the original registration.
            try save(records)
            try write(record.managed, to: file, permissions: permissions)
            return label
        }
    }
    private func changed(_ label: String) -> MorrowError {
        .message("\(label) was changed outside Morrow. Its file was preserved; review it before importing or restoring it.")
    }
    private func write(_ data: Data, to file: URL, permissions: Int) throws {
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
    }
    public func restore(_ label: String) throws {
        try store.operation {
            var records = try load()
            guard let index = records.firstIndex(where: { $0.label == label }) else { throw MorrowError.message("No imported worker named \(label).") }
            let record = records[index], file = store.loginAgentURL(label: label)
            let (data, _, _) = try read(file)
            guard record.accepts(data) else { throw changed(label) }
            try write(record.original, to: file, permissions: record.permissions)
            records.remove(at: index)
            try save(records)
        }
    }
    /// Repair only explicitly imported, unchanged registrations. Their original
    /// labels remain valid, and cleanup never treats them as orphan Morrow jobs.
    public func repair(launcher: URL) throws -> Int {
        try verify(launcher)
        var count = 0
        for worker in try workers() {
            let file = store.loginAgentURL(label: worker.label)
            // Missing/externally edited jobs must not be recreated or overwritten.
            guard let (data, _, _) = try? read(file),
                  let record = try load().first(where: { $0.label == worker.label }), record.accepts(data) else { continue }
            let desired = try wrapped(record.original, launcher: launcher)
            if data != desired { _ = try adoptVerified(file, launcher: launcher); count += 1 }
        }
        return count
    }
}
