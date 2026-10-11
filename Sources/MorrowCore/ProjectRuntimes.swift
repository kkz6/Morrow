import Foundation

public struct ProjectRuntimeSelection: Codable, Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public var runtimes: [String: RuntimeInstallation]
    public init(path: String, runtimes: [String: RuntimeInstallation] = [:]) {
        self.path = path; self.runtimes = runtimes
    }
}

/// Separate metadata keeps older running directory watchers from discarding
/// folder preferences when they save the shared workspace's existing schema.
public struct ProjectRuntimeStore: Sendable {
    public let store: StateStore
    public init(store: StateStore = StateStore()) { self.store = store }
    private var url: URL { store.root.appendingPathComponent("project-runtimes.json") }
    private struct Document: Codable { let schemaVersion: Int; let projects: [ProjectRuntimeSelection] }
    public static func directory(_ path: String, allowRoot: Bool = false) throws -> String {
        let directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        guard (allowRoot || directory.path != "/"), (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw MorrowError.message("Choose an existing project folder.")
        }
        return directory.path
    }
    public func load() throws -> [ProjectRuntimeSelection] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Preserve older per-site PHP choices as folder selections.
            let web = try store.load().web
            let grouped = Dictionary(grouping: web.sites.filter { $0.phpID != nil }, by: \.path)
            return grouped.compactMap { path, sites in
                let ids = Set(sites.compactMap(\.phpID))
                guard ids.count == 1, let item = web.php.first(where: { $0.id == ids.first }) else { return nil }
                return ProjectRuntimeSelection(path: path, runtimes: [RuntimeEngine.php.rawValue: item])
            }.sorted { $0.path < $1.path }
        }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 2_097_152 else { throw MorrowError.message("Project runtime settings are too large.") }
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.schemaVersion == 1, document.projects.count <= 1000 else { throw MorrowError.message("Unsupported project runtime settings.") }
            var paths = Set<String>()
            for project in document.projects {
                guard project.path.hasPrefix("/"), project.path != "/", paths.insert(project.path).inserted,
                      project.runtimes.allSatisfy({ RuntimeEngine(rawValue: $0.key) == $0.value.engine }) else {
                    throw MorrowError.message("Invalid project runtime settings.")
                }
            }
            return document.projects.sorted { $0.path < $1.path }
        } catch { throw MorrowError.message("Could not read project runtime settings. They were preserved. \(error.localizedDescription)") }
    }
    /// The caller holds StateStore.operation while applying and saving choices.
    func save(_ projects: [ProjectRuntimeSelection]) throws {
        let data = try JSONEncoder().encode(Document(schemaVersion: 1, projects: projects.sorted { $0.path < $1.path }))
        guard projects.count <= 1000, data.count <= 2_097_152 else { throw MorrowError.message("Too many project runtime settings. Existing choices were preserved.") }
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func selection(_ engine: RuntimeEngine, directory: String, projects: [ProjectRuntimeSelection]) -> RuntimeInstallation? {
        projects.filter { directory == $0.path || directory.hasPrefix($0.path + "/") }
            .sorted { $0.path.count > $1.path.count }
            .compactMap { $0.runtimes[engine.rawValue] }.first
    }
    public func selection(_ engine: RuntimeEngine, directory: String) throws -> RuntimeInstallation? {
        Self.selection(engine, directory: try Self.directory(directory, allowRoot: true), projects: try load())
    }
}
