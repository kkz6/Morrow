import Foundation

/// Cleans only Morrow-owned, obsolete launch-agent definitions. macOS controls
/// its historical Login Items records; no global background database is reset.
public struct BackgroundRegistrations: Sendable {
    public let store: StateStore
    public let runner: any CommandRunning
    public init(store: StateStore, runner: any CommandRunning = CommandRunner()) { self.store = store; self.runner = runner }
    public func jobFiles() -> [URL] {
        let fm = FileManager.default
        var values: [URL] = []
        // Search private job folders, skipping large binary and database trees.
        for name in ["jobs", "sites", "mail", "storage"] {
            let root = store.root.appendingPathComponent(name)
            if let files = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
                for case let file as URL in files where file.pathExtension == "plist" { values.append(file) }
            }
        }
        let agents = store.loginAgentURL(label: "unused").deletingLastPathComponent()
        values += ((try? fm.contentsOfDirectory(at: agents, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasPrefix("dev.morrow.") && $0.pathExtension == "plist" }
        return values.filter { owned($0) != nil }
    }
    public func permissionFiles() -> [URL] {
        let loginDirectory = store.loginAgentURL(label: "unused").deletingLastPathComponent().path
        let files = jobFiles().sorted { $0.deletingLastPathComponent().path == loginDirectory && $1.deletingLastPathComponent().path != loginDirectory }
        var seen = Set<String>()
        return files.filter { seen.insert($0.lastPathComponent).inserted }
    }
    private func owned(_ file: URL) -> [String: Any]? {
        guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              let data = try? Data(contentsOf: file), let job = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = job["Label"] as? String, label.hasPrefix("dev.morrow."), file.lastPathComponent == label + ".plist",
              let arguments = job["ProgramArguments"] as? [String], let binary = arguments.first, binary.hasPrefix("/") else { return nil }
        let associated = (job["AssociatedBundleIdentifiers"] as? [String])?.contains("dev.morrow.app") == true
        let working = job["WorkingDirectory"] as? String ?? ""
        let output = job["StandardOutPath"] as? String ?? ""
        let underStore = [working, output].contains { URL(fileURLWithPath: $0).standardizedFileURL.path.hasPrefix(store.root.standardizedFileURL.path + "/") }
        guard associated || underStore else { return nil }
        return job
    }
    public func clean(cli: URL) throws -> String {
        try store.operation {
            guard cli.path.hasSuffix("/Contents/MacOS/morrow") || ["morrow", "morrow-cli"].contains(cli.lastPathComponent), FileManager.default.isExecutableFile(atPath: cli.path) else { throw MorrowError.message("Morrow's service launcher is missing.") }
            let state = try store.load(), launchd = LaunchdControl(runner: runner), fm = FileManager.default
            let sites = SiteManager(store: store, runner: runner)
            let webLabels = (["watch", "caddy", "dns"] + state.web.php.map(sites.phpComponent)).map { sites.label($0, web: state.web) }
            let retained = Set(state.instances.map(\.label) + state.mailServices.map(\.label) + state.objectStorage.map(\.label) + webLabels)
            let archive = store.root.appendingPathComponent("archives/background-\(UUID().uuidString)")
            var removed = 0, updated = 0, active = 0
            for file in jobFiles() {
                guard var job = owned(file), let label = job["Label"] as? String, let arguments = job["ProgramArguments"] as? [String] else { continue }
                if !retained.contains(label) {
                    let inspected = try launchd.inspect(label)
                    if inspected.status == 0 {
                        let status = LaunchdStatus(inspected.output)
                        if status.isRunning || status.isLaunching || status.pid.map({ ServiceHealth(runner: runner).processAlive($0) }) == true { active += 1; continue }
                    }
                    if inspected.status == 0 { try launchd.unload(label) }
                    try fm.createDirectory(at: archive, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    // Preserve separate private and login copies of the same job.
                    try fm.moveItem(at: file, to: archive.appendingPathComponent("\(removed)-" + file.lastPathComponent))
                    removed += 1
                } else {
                    var revised = arguments
                    if arguments.count >= 3, arguments[1] == "service-runner", arguments[2] == "--" { revised[0] = cli.path }
                    else if let binary = arguments.first, !["morrow", "morrow-cli"].contains(URL(fileURLWithPath: binary).lastPathComponent) { revised = [cli.path, "service-runner", "--"] + arguments }
                    else if !revised.isEmpty { revised[0] = cli.path }
                    let associated = job["AssociatedBundleIdentifiers"] as? [String]
                    guard revised != arguments || associated != ManagedServiceRunner.bundleIdentifiers else { continue }
                    job["ProgramArguments"] = revised
                    job["AssociatedBundleIdentifiers"] = ManagedServiceRunner.bundleIdentifiers
                    try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0).write(to: file, options: .atomic)
                    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                    updated += 1
                }
            }
            return "Archived \(removed) unused registrations; updated \(updated) service entries.\(active > 0 ? " Preserved \(active) active orphan entries." : "") macOS may retain older list entries until it refreshes."
        }
    }
}
