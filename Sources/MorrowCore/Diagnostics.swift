import Foundation
import CryptoKit

public struct DiagnosticProject: Codable, Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public var enabled: Bool
    public init(path: String, enabled: Bool) { self.path = path; self.enabled = enabled }
}

public indirect enum DiagnosticValue: Codable, Sendable {
    case object([String: DiagnosticValue]), array([DiagnosticValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let v = try decoder.singleValueContainer()
        if v.decodeNil() { self = .null }
        else if let x = try? v.decode(Bool.self) { self = .bool(x) }
        else if let x = try? v.decode(Double.self) { self = .number(x) }
        else if let x = try? v.decode(String.self) { self = .string(x) }
        else if let x = try? v.decode([DiagnosticValue].self) { self = .array(x) }
        else { self = .object(try v.decode([String: DiagnosticValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var v = encoder.singleValueContainer()
        switch self { case .null: try v.encodeNil(); case .bool(let x): try v.encode(x); case .number(let x): try v.encode(x); case .string(let x): try v.encode(x); case .array(let x): try v.encode(x); case .object(let x): try v.encode(x) }
    }
    public var text: String {
        switch self { case .string(let x): return x; case .number(let x): return String(x); case .bool(let x): return String(x); case .null: return "null"; case .array(let x): return "Array (\(x.count))"; case .object(let x): return "Object (\(x.count))" }
    }
}

public struct DiagnosticEvent: Codable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let time: Double
    public let title: String
    public let value: DiagnosticValue
    public let file: String?
    public let line: Int?
}

public struct DiagnosticRequest: Identifiable, Sendable {
    public let id: String
    public let project: String
    public let events: [DiagnosticEvent]
    public var title: String { events.first?.title ?? "Request" }
    public var time: Double { events.first?.time ?? 0 }
}

/// Separate metadata avoids older directory watchers losing capture choices.
/// Each request writes its own bounded JSON-lines file; no listener or daemon.
public struct Diagnostics: Sendable {
    public let store: StateStore
    public init(store: StateStore = StateStore()) { self.store = store }
    public var root: URL { store.root.appendingPathComponent("diagnostics") }
    private var settings: URL { root.appendingPathComponent("projects.json") }
    public func projects() throws -> [DiagnosticProject] {
        guard FileManager.default.fileExists(atPath: settings.path) else { return [] }
        let data = try Data(contentsOf: settings)
        guard data.count <= 1_048_576 else { throw MorrowError.message("Capture settings exceed the supported size.") }
        return try JSONDecoder().decode([DiagnosticProject].self, from: data)
    }
    public func directory(_ path: String) -> URL {
        root.appendingPathComponent(SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined())
    }
    public func prepend(for folder: String) throws -> URL? {
        let folder = (try? ProjectRuntimeStore.directory(folder, allowRoot: true)) ?? folder
        guard let project = try projects().filter({ $0.enabled && (folder == $0.path || folder.hasPrefix($0.path + "/")) }).max(by: { $0.path.count < $1.path.count }) else { return nil }
        return directory(project.path).appendingPathComponent("prepend.php")
    }
    public func configure(path: String, enabled: Bool, runner: any CommandRunning = CommandRunner()) throws {
        let path = enabled ? try ProjectRuntimeStore.directory(path) : URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        try store.operation {
            var all = try projects()
            let previous = all
            if enabled {
                let state = try store.load()
                var runtimes: [RuntimeInstallation] = []
                if try ProjectRuntimeStore(store: store).selection(.php, directory: path) != nil || state.toolDefaults["php"] != nil {
                    runtimes.append(try RuntimeManager(store: store, runner: runner).resolve(.php, directory: path))
                }
                for site in state.web.sites where site.path == path && site.mode == .php {
                    if let php = state.web.php.first(where: { $0.id == (site.phpID ?? state.web.defaultPHPID) }), !runtimes.contains(php) { runtimes.append(php) }
                }
                guard !runtimes.isEmpty else { throw MorrowError.message("Select PHP for this folder or choose a default PHP version first.") }
                for runtime in runtimes {
                    guard let php = runtime.command("php") else { throw MorrowError.message("Select PHP for this folder first.") }
                    let existing = try runner.run(php, ["-r", "echo ini_get('auto_prepend_file');"], environment: runtime.environment).checked().trimmingCharacters(in: .whitespacesAndNewlines)
                    guard existing.isEmpty else { throw MorrowError.message("PHP \(runtime.version) already uses auto_prepend_file. Capture was not enabled, so its existing bootstrap stays intact.") }
                }
                // A directory-specific prepend would otherwise silently replace it.
                let paths = Set([path, path + "/public"] + state.web.sites.filter { $0.path == path }.map(\.documentRoot))
                for folder in paths {
                    if let ini = try? String(contentsOfFile: folder + "/.user.ini", encoding: .utf8), ini.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("auto_prepend_file") }) {
                        throw MorrowError.message("\(folder)/.user.ini already defines auto_prepend_file. Keep that bootstrap or remove the setting before enabling capture.")
                    }
                }
                try installAgent(path: path)
            }
            all.removeAll { $0.path == path }; all.append(DiagnosticProject(path: path, enabled: enabled))
            try write(JSONEncoder().encode(all), to: settings)
            do { try SiteManager(store: store, runner: runner).reloadDiagnosticsRoutes() }
            catch { try write(JSONEncoder().encode(previous), to: settings); try? SiteManager(store: store, runner: runner).reloadDiagnosticsRoutes(); throw error }
        }
    }
    func installAgent(path: String) throws {
        let folder = directory(path)
        let events = folder.appendingPathComponent("requests")
        try FileManager.default.createDirectory(at: events, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try write(Data(PHPDiagnosticsAgent.source.utf8), to: root.appendingPathComponent("agent.php"))
        // JSON escaping handles arbitrary Mac folder names without PHP evaluation.
        let config = try JSONSerialization.data(withJSONObject: ["project": path, "output": events.path, "settings": settings.path])
        let payload = config.base64EncodedString()
        let agent = root.appendingPathComponent("agent.php").path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        try write(Data("<?php\n// Morrow local diagnostics. Generated; project files are untouched.\n$__morrow = json_decode(base64_decode('\(payload)'), true);\nrequire_once '\(agent)';\n".utf8), to: folder.appendingPathComponent("prepend.php"))
    }
    public func requests(project: String? = nil) throws -> [DiagnosticRequest] {
        let projects = try projects().filter { project == nil || $0.path == project }
        var candidates: [(URL, String)] = []
        for item in projects {
            let folder = directory(item.path).appendingPathComponent("requests")
            let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])) ?? [])
                .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent > $1.lastPathComponent }.prefix(200)
            candidates += files.map { ($0, item.path) }
        }
        var result: [DiagnosticRequest] = [], bytesRemaining = 16 * 1024 * 1024
        for (file, path) in candidates.sorted(by: { $0.0.lastPathComponent > $1.0.lastPathComponent }).prefix(200) {
            guard let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { continue }
            let size = info.fileSize ?? 0
            guard info.isRegularFile == true, info.isSymbolicLink != true, size <= 1_048_576, size <= bytesRemaining else { continue }
            // A live request can be pruned or cleared between listing and reading.
            guard let data = try? Data(contentsOf: file) else { continue }
            bytesRemaining -= data.count
            let lines = data.split(separator: 10, omittingEmptySubsequences: true)
            let events = lines.prefix(500).compactMap { try? JSONDecoder().decode(DiagnosticEvent.self, from: Data($0)) }
            if !events.isEmpty { result.append(DiagnosticRequest(id: directory(path).lastPathComponent + ":" + file.lastPathComponent, project: path, events: events)) }
        }
        return result.sorted { $0.time > $1.time }
    }

    public func clear(project: String? = nil) throws {
        try store.operation {
            for item in try projects() where project == nil || item.path == project {
                let folder = directory(item.path).appendingPathComponent("requests")
                for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "jsonl" {
                    try FileManager.default.removeItem(at: file)
                }
            }
        }
    }
    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
