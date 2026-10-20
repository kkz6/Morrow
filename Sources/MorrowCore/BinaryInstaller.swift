import Foundation

/// Installation policy shared by app, CLI and workspace sync. Existing native
/// copies are always reused; all new installs use complete portable packages.
public struct BinaryInstaller: Sendable {
    public let store: StateStore
    public let runner: any CommandRunning
    public init(store: StateStore, runner: any CommandRunning) { self.store = store; self.runner = runner }
    public var managed: ManagedBinaryStore { ManagedBinaryStore(store: store, runner: runner) }
    var brew: HomebrewInstaller { HomebrewInstaller(runner: runner, configuredPath: (try? store.load().preferences.homebrewPath) ?? "") }
    public var executable: String? { brew.executable }
    public var allowsHomebrew: Bool { false }
    public func setHomebrewCompatibility(_ enabled: Bool) throws {
        guard !enabled else { throw MorrowError.message("Homebrew installation has been removed. Morrow downloads complete native packages automatically.") }
        try store.update { $0.preferences.allowHomebrewFallback = false }
        var inventory = InventoryStore(store: store).load(); inventory.channels = [:]
        try InventoryStore(store: store).save(inventory)
    }
    public func installations() throws -> [Installation] {
        let managed = self.managed.installations().compactMap { item -> Installation? in
            guard let engine = DatabaseEngine(rawValue: item.release.package) else { return nil }
            return Installation(engine: engine, formula: item.release.channel, version: item.release.version, prefix: item.prefix)
        }
        let tracked = try store.load().instances.map(\.installation).filter { FileManager.default.isExecutableFile(atPath: $0.executable) }
        var seen = Set<String>()
        return (managed + tracked + (try brew.installations())).filter { seen.insert($0.id).inserted }
            .sorted { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
    }
    public func channels() throws -> [VersionChannel] {
        let channels = try managed.releases().compactMap { release -> VersionChannel? in
            guard let engine = DatabaseEngine(rawValue: release.package) else { return nil }
            return VersionChannel(engine: engine, formula: release.channel, version: release.version)
        }
        return channels
    }
    public func install(engine: DatabaseEngine, channel: String) throws -> [Installation] {
        let found = try installations().filter { $0.engine == engine }
        if let existing = found.first(where: { channel == "automatic" || Self.matches($0, request: channel) }) {
            let valid = try NativeInstallationDetector(runner: runner).validate(existing)
            guard channel == "automatic" || Self.matches(valid, request: channel) else { throw MorrowError.message("The existing server reports another version. No second copy was installed.") }
            return [valid]
        }
        if let release = try managed.release(package: engine.rawValue, request: channel) {
            let installed = try managed.install(release)
            let valid = try NativeInstallationDetector(runner: runner).validate(Installation(engine: engine, formula: release.channel, version: release.version, prefix: installed.prefix))
            guard valid.version == release.version else { throw MorrowError.message("The downloaded server reports an unexpected version. It was not attached to an instance.") }
            return [valid]
        }
        guard !channel.hasPrefix("managed:") else { throw MorrowError.message("This exact managed release is no longer in the catalog. No other version was substituted.") }
        throw MorrowError.message("No compatible \(engine.title) distribution is published for this request. Refresh available versions or select an existing installation.")
    }
    public static func matches(_ item: Installation, request: String) -> Bool {
        if request.hasPrefix("managed:") { return ManagedBinaryStore.matches(item.version, request: request, package: item.engine.rawValue) }
        return item.formula == request || ManagedBinaryStore.matches(item.version, request: request, package: item.engine.rawValue) || HomebrewInstaller.matches(item, request: request)
    }
    public func refreshMetadata() throws {
        _ = try managed.releases(refresh: true)
        try? FileManager.default.removeItem(at: store.root.appendingPathComponent("go-releases.json"))
    }
    /// Auxiliary services consume the same catalog as database/runtime setup.
    public func auxiliary(_ name: String, request: String = "automatic", preferred: String? = nil) throws -> String {
        let managed = self.managed.installations().filter { $0.release.package == name && (request == "automatic" || ManagedBinaryStore.matches($0.release.version, request: request, package: name)) }
        var candidates = [preferred].compactMap { $0 } + managed.map { $0.prefix + "/bin/" + name }
        candidates += (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":").filter { !$0.isEmpty }.map { $0 + "/" + name }
        candidates += ["/opt/homebrew/bin/" + name, "/opt/homebrew/sbin/" + name, "/usr/local/bin/" + name, "/usr/local/sbin/" + name]
        if request == "automatic", let existing = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return URL(fileURLWithPath: existing).resolvingSymlinksInPath().path }
        if let release = try self.managed.release(package: name, request: request) {
            let installed = try self.managed.install(release)
            let executable = installed.prefix + "/bin/" + name
            guard FileManager.default.isExecutableFile(atPath: executable) else { throw MorrowError.message("The distribution needs bin/\(name).") }
            return executable
        }
        throw MorrowError.message("No compatible \(name) distribution is published for this request. Existing installations were preserved.")
    }
}
