import Foundation
import Darwin

public struct DatabaseManager: Sendable {
    public let store: StateStore
    public let runner: any CommandRunning
    public init(store: StateStore = StateStore(), runner: any CommandRunning = CommandRunner()) {
        self.store = store; self.runner = runner
    }
    public func installer() throws -> HomebrewInstaller {
        HomebrewInstaller(runner: runner, configuredPath: try store.load().preferences.homebrewPath)
    }
    public func install(engine: DatabaseEngine, channel: String) throws -> [Installation] {
        try store.operation { try installer().install(engine: engine, channel: channel) }
    }
    public func resolve(_ name: String) throws -> DatabaseInstance {
        guard let instance = try store.load().instances.first(where: { $0.name == name || $0.id.uuidString.lowercased() == name.lowercased() }) else {
            throw MorrowError.message("No instance named '\(name)'. Run morrow db list to see your instances.")
        }
        return instance
    }
    public func suggestedPort(engine: DatabaseEngine) throws -> Int {
        let used = Set(try store.load().instances.map(\.port))
        for port in engine.defaultPort..<min(engine.defaultPort + 1000, 65536) {
            if !used.contains(port) && Self.portAvailable(port) { return port }
        }
        throw MorrowError.message("Could not find a free local port.")
    }
    public static func validate(_ instance: DatabaseInstance) throws {
        guard instance.name.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,47}$", options: .regularExpression) != nil else {
            throw MorrowError.message("Use 1–48 letters, numbers, dots, underscores, or hyphens for the instance name.")
        }
        guard (1024...65535).contains(instance.port) else { throw MorrowError.message("Choose a port between 1024 and 65535.") }
        guard (16...65536).contains(instance.memoryMB) else { throw MorrowError.message("Memory must be between 16 and 65536 MB.") }
        guard (10...10000).contains(instance.maxConnections) else { throw MorrowError.message("Maximum connections must be between 10 and 10000.") }
    }
    @discardableResult public func create(_ instance: DatabaseInstance) throws -> DatabaseInstance {
        try store.operation { try createUnlocked(instance) }
    }
    public func preflight(name: String, engine: DatabaseEngine, port: Int, memoryMB: Int = 128, maxConnections: Int = 100, excluding: UUID? = nil) throws {
        let placeholder = Installation(engine: engine, formula: "", version: "", prefix: "")
        try Self.validate(DatabaseInstance(name: name, installation: placeholder, port: port, memoryMB: memoryMB, maxConnections: maxConnections))
        let others = try store.load().instances.filter { $0.id != excluding }
        guard !others.contains(where: { $0.name.lowercased() == name.lowercased() }) else { throw MorrowError.message("An instance with that name already exists.") }
        try validatePort(port, excluding: excluding)
    }
    public func validatePort(_ port: Int, excluding: UUID? = nil) throws {
        guard (1024...65535).contains(port) else { throw MorrowError.message("Choose a port between 1024 and 65535.") }
        let others = try store.load().instances.filter { $0.id != excluding }
        guard !others.contains(where: { $0.port == port }), Self.portAvailable(port) else {
            throw MorrowError.message("Port \(port) is already in use. Choose another port.")
        }
    }
    @discardableResult public func provision(engine: DatabaseEngine, version: String = "automatic", name: String,
        port: Int, autoStart: Bool = false, memoryMB: Int = 128, maxConnections: Int = 100,
        installation: Installation? = nil) throws -> DatabaseInstance {
        try store.operation {
            // Reject conflicting ports and duplicate names before downloading
            // software. Recheck after installation and again when starting.
            try preflight(name: name, engine: engine, port: port, memoryMB: memoryMB, maxConnections: maxConnections)
            let chosen: Installation
            if let installation {
                guard installation.engine == engine else { throw MorrowError.message("The selected binary belongs to another database engine.") }
                chosen = try NativeInstallationDetector(runner: runner).validate(installation)
                let expectedVersion = installation.version.components(separatedBy: "_").first ?? installation.version
                guard HomebrewInstaller.matches(chosen, request: expectedVersion) else { throw MorrowError.message("The selected binary's actual version has changed. Refresh the version list before creating this instance.") }
            } else {
                guard let resolved = try installer().install(engine: engine, channel: version).first else { throw MorrowError.message("No compatible server version was found.") }
                chosen = resolved
            }
            let instance = DatabaseInstance(name: name, installation: chosen, port: port, autoStart: autoStart, memoryMB: memoryMB, maxConnections: maxConnections)
            return try createUnlocked(instance)
        }
    }
    private func createUnlocked(_ instance: DatabaseInstance) throws -> DatabaseInstance {
            try Self.validate(instance)
            let state = try store.load()
            guard !state.instances.contains(where: { $0.name.lowercased() == instance.name.lowercased() }) else { throw MorrowError.message("An instance with that name already exists.") }
            guard !state.instances.contains(where: { $0.port == instance.port }), Self.portAvailable(instance.port) else {
                throw MorrowError.message("Port \(instance.port) is already in use. Choose another port.")
            }
            guard FileManager.default.isExecutableFile(atPath: instance.installation.executable) else {
                throw MorrowError.message("The selected database version is not installed.")
            }
            do { try NativeProvider(store: store, runner: runner).initialize(instance) }
            catch { throw MorrowError.message("Initialization failed: \(error.localizedDescription)\nFiles were preserved at \(store.instanceDirectory(instance).path).") }
            try writeJob(instance)
            try syncLoginJob(instance)
            try store.update { $0.instances.append(instance) }
            return instance
    }
    public func start(_ id: UUID) throws {
        try store.operation {
            let instance = try current(id)
            let status = status(instance)
            if status == .running || status == .starting { return }
            guard FileManager.default.isExecutableFile(atPath: instance.installation.executable) else {
                throw MorrowError.message("The native binary for \(instance.installation.version) is missing. Reinstall its channel or create an instance with an installed version.")
            }
            guard Self.portAvailable(instance.port) else { throw MorrowError.message("Port \(instance.port) is occupied by another process.") }
            try unload(instance)
            try NativeProvider(store: store, runner: runner).writeConfiguration(instance)
            try writeJob(instance)
            try syncLoginJob(instance)
            try runner.run("/bin/launchctl", ["bootstrap", domain, store.jobURL(instance).path], environment: [:]).checked()
            // A brief readiness check catches immediate configuration failures.
            // Slower servers remain 'Starting' and are refreshed by the app.
            for _ in 0..<30 {
                let current = self.status(instance)
                if current == .running { return }
                if current == .failed {
                    throw MorrowError.message("\(instance.name) could not start.\n\(try logs(instance))")
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }
    public func stop(_ id: UUID) throws { try store.operation { try unload(current(id)) } }
    public func restart(_ id: UUID) throws { try stop(id); try start(id) }
    public func update(_ proposed: DatabaseInstance) throws {
        try store.operation {
            let existing = try current(proposed.id)
            try Self.validate(proposed)
            let status = status(existing)
            guard status != .running && status != .starting else { throw MorrowError.message("Stop this instance before changing its settings.") }
            guard existing.installation == proposed.installation else { throw MorrowError.message("Create a separate instance to use another database version. Data migration is required between major versions.") }
            let others = try store.load().instances.filter { $0.id != proposed.id }
            guard !others.contains(where: { $0.name.lowercased() == proposed.name.lowercased() }) else { throw MorrowError.message("That name is already in use.") }
            guard !others.contains(where: { $0.port == proposed.port }), Self.portAvailable(proposed.port) else { throw MorrowError.message("That port is already in use.") }
            try NativeProvider(store: store, runner: runner).writeConfiguration(proposed)
            try writeJob(proposed)
            try syncLoginJob(proposed)
            try store.update { state in
                if let index = state.instances.firstIndex(where: { $0.id == proposed.id }) { state.instances[index] = proposed }
            }
        }
    }
    public func setAutoStart(_ id: UUID, enabled: Bool) throws {
        try store.operation {
            var instance = try current(id)
            instance.autoStart = enabled
            try writeJob(instance)
            try syncLoginJob(instance)
            try store.update { state in
                if let index = state.instances.firstIndex(where: { $0.id == id }) { state.instances[index].autoStart = enabled }
            }
        }
    }
    /// Removal preserves native data in an archive unless explicitly requested.
    public func remove(_ id: UUID, deleteData: Bool = false) throws {
        try store.operation {
            let instance = try current(id)
            try unload(instance)
            let fm = FileManager.default
            for file in [store.jobURL(instance), store.loginJobURL(instance)] where fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
            let directory = store.instanceDirectory(instance)
            if fm.fileExists(atPath: directory.path) {
                if deleteData { try fm.removeItem(at: directory) }
                else {
                    let archives = store.root.appendingPathComponent("archives")
                    try fm.createDirectory(at: archives, withIntermediateDirectories: true)
                    try fm.moveItem(at: directory, to: archives.appendingPathComponent(instance.id.uuidString.lowercased()))
                }
            }
            let socket = store.socketURL(instance)
            if fm.fileExists(atPath: socket.path) { try fm.removeItem(at: socket) }
            try store.update { $0.instances.removeAll { $0.id == id } }
        }
    }
    public func status(_ instance: DatabaseInstance) -> InstanceStatus {
        guard let result = try? runner.run("/bin/launchctl", ["print", "\(domain)/\(instance.label)"], environment: [:]) else { return .unknown }
        if result.status == 0 && result.output.contains("state = running") {
            // A process can keep running after an external package cleanup
            // removes its executable. Keep the Stop control available.
            return Self.portListening(instance.port) ? .running : .starting
        }
        guard FileManager.default.isExecutableFile(atPath: instance.installation.executable) else { return .missingBinary }
        guard result.status == 0 else { return .stopped }
        if result.output.contains("last exit code = 0") { return .stopped }
        if result.output.contains("last exit code =") || result.output.contains("last terminating signal =") { return .failed }
        return .starting
    }
    public func logs(_ instance: DatabaseInstance) throws -> String {
        let file = store.logURL(instance)
        guard FileManager.default.fileExists(atPath: file.path) else { return "No logs yet. Start this instance to see server output." }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: size > 32768 ? size - 32768 : 0)
        return String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
    }
    public func jobDescription(_ instance: DatabaseInstance) -> [String: Any] {
        [
            "Label": instance.label,
            "ProgramArguments": NativeProvider(store: store, runner: runner).arguments(instance),
            "RunAtLoad": true,
            "KeepAlive": false,
            "WorkingDirectory": store.instanceDirectory(instance).path,
            "StandardOutPath": store.logURL(instance).path,
            "StandardErrorPath": store.logURL(instance).path,
            "ExitTimeOut": 30,
            "EnvironmentVariables": ["PATH": "\(instance.installation.prefix)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "LC_ALL": "C"],
        ]
    }
    private var domain: String { "gui/\(getuid())" }
    private func current(_ id: UUID) throws -> DatabaseInstance {
        guard let instance = try store.load().instances.first(where: { $0.id == id }) else { throw MorrowError.message("This instance no longer exists.") }
        return instance
    }
    private func writeJob(_ instance: DatabaseInstance) throws {
        let file = store.jobURL(instance)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: jobDescription(instance), format: .xml, options: 0).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    private func syncLoginJob(_ instance: DatabaseInstance) throws {
        let fm = FileManager.default
        let file = store.loginJobURL(instance)
        if instance.autoStart {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: store.jobURL(instance)).write(to: file, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } else if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
    }
    private func unload(_ instance: DatabaseInstance) throws {
        let target = "\(domain)/\(instance.label)"
        let result = try runner.run("/bin/launchctl", ["print", target], environment: [:])
        guard result.status == 0 else { return }
        // Save the managed process's PID before bootout. Do not archive or
        // delete its files until launchd has finished shutting it down.
        let pidLine = result.output.components(separatedBy: .newlines).first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("pid = ") }
        let pid = pidLine?.components(separatedBy: "=").last.flatMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        try runner.run("/bin/launchctl", ["bootout", target], environment: [:]).checked()
        if let pid, pid > 1 {
            for _ in 0..<300 {
                if kill(pid, 0) != 0 { return }
                Thread.sleep(forTimeInterval: 0.1)
            }
            throw MorrowError.message("The server is still shutting down. Its data has been preserved; retry shortly.")
        }
    }
    public static func portAvailable(_ port: Int) -> Bool {
        withSocket(port) { fd, address in
            var reuse: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
            var address = address
            return withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
            }
        }
    }
    public static func portListening(_ port: Int) -> Bool {
        withSocket(port) { fd, address in
            var address = address
            return withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
            }
        }
    }
    private static func withSocket(_ port: Int, _ body: (Int32, sockaddr_in) -> Bool) -> Bool {
        guard (1...65535).contains(port) else { return false }
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return body(fd, address)
    }
}
