import Foundation

public struct ProjectAppCommand: Codable, Equatable, Sendable {
    public let runtime: RuntimeEngine
    public let executable: String
    public let arguments: [String]

    public init(runtime: RuntimeEngine, executable: String, arguments: [String]) {
        self.runtime = runtime; self.executable = executable; self.arguments = arguments
    }

    func validate() throws {
        guard runtime.commands.contains(executable), arguments.count <= 128,
              arguments.allSatisfy({ $0.utf8.count <= 4096 && !$0.contains("\0") }) else {
            throw MorrowError.message("Choose a command provided by the runtime and use at most 128 arguments.")
        }
    }
}

public struct ProjectAppState: Sendable {
    public let command: ProjectAppCommand
    public let status: InstanceStatus
    public var canStop: Bool { status == .running || status == .starting }
}

/// User-approved foreground commands run as user launchd jobs, independently
/// of the app window. Each site owns its command, job label, and log.
public struct ProjectApps: Sendable {
    public let store: StateStore
    public let runner: any CommandRunning
    public init(store: StateStore, runner: any CommandRunning = CommandRunner()) {
        self.store = store; self.runner = runner
    }

    private var launchd: LaunchdControl { LaunchdControl(runner: runner) }
    func label(_ id: UUID) -> String { "dev.morrow.project-app." + id.uuidString.lowercased() }
    private func directory(_ id: UUID) -> URL { store.root.appendingPathComponent("project-apps/" + id.uuidString.lowercased()) }
    private func commandURL(_ id: UUID) -> URL { directory(id).appendingPathComponent("command.json") }
    public func logURL(_ id: UUID) -> URL { directory(id).appendingPathComponent("application.log") }
    private func jobURL(_ id: UUID) -> URL { store.root.appendingPathComponent("jobs/" + label(id) + ".plist") }

    public func command(_ id: UUID) throws -> ProjectAppCommand? {
        let file = commandURL(id)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 2_097_152 else {
            throw MorrowError.message("The saved app command is invalid.")
        }
        let value = try JSONDecoder().decode(ProjectAppCommand.self, from: Data(contentsOf: file))
        try value.validate()
        return value
    }

    public func state(_ site: LocalSite) -> ProjectAppState? {
        guard let command = try? command(site.id) else { return nil }
        return ProjectAppState(command: command, status: status(site))
    }

    private func status(_ site: LocalSite) -> InstanceStatus {
        guard let job = try? launchd.inspect(label(site.id)) else { return .unknown }
        guard job.status == 0 else { return .stopped }
        let current = LaunchdStatus(job.output)
        if current.isRunning {
            return site.proxyPort.map(DatabaseManager.portListening) == true ? .running : .starting
        }
        if current.isLaunching { return .starting }
        return current.failed ? .failed : .stopped
    }

    public func configure(_ id: UUID, command: ProjectAppCommand, port: Int? = nil) throws {
        try store.operation {
            var site = try site(id, state: store.load())
            try command.validate()
            try requireStopped(site)
            let previous = try self.command(id), file = commandURL(id)
            try write(JSONEncoder().encode(command), to: file)
            if let port, port != site.proxyPort {
                site.proxyPort = port
                do { try SiteManager(store: store, runner: runner).updateUnderOperationLock(site) }
                catch {
                    let savedPort = try? store.load().web.sites.first(where: { $0.id == id })?.proxyPort
                    if savedPort != port {
                        if let previous { try write(JSONEncoder().encode(previous), to: file) }
                        else { try FileManager.default.removeItem(at: file) }
                    }
                    throw error
                }
            }
        }
    }

    public func start(_ id: UUID) throws {
        try store.operation {
            guard geteuid() != 0 else { throw MorrowError.message("Start project apps from your normal Mac account.") }
            let state = try store.load(), site = try site(id, state: state)
            guard !site.isIgnoredForHosting, site.issue == nil, let port = site.proxyPort else {
                throw MorrowError.message("Include this site and set its application port in Project Settings first.")
            }
            guard let command = try command(id) else { throw MorrowError.message("Configure this project's app command first.") }
            let current = status(site)
            if current == .running || current == .starting { return }
            guard current != .unknown else { throw MorrowError.message("Could not check the project's background job.") }
            let reserved = state.instances.map(\.port)
                + state.mailServices.flatMap { [$0.smtpPort, $0.httpPort] }
                + state.objectStorage.flatMap { [$0.apiPort, $0.consolePort] }
                + [state.web.httpPort, state.web.httpsPort, state.web.dnsPort, 80, 443]
            let occupied = state.web.sites.contains { other in
                other.id != id && other.proxyPort == port && self.state(other)?.canStop == true
            }
            guard !reserved.contains(port), !occupied, DatabaseManager.portAvailable(port) else {
                throw MorrowError.message("Port \(port) is in use. Stop the other app or choose another project port.")
            }
            let folder = try ProjectRuntimeStore.directory(site.path)
            let runtimes = RuntimeManager(store: store, runner: runner)
            let runtime = try runtimes.resolve(command.runtime, directory: folder)
            guard let executable = runtime.command(command.executable), FileManager.default.isExecutableFile(atPath: executable) else {
                throw MorrowError.message("The selected \(runtime.engine.title) version does not include \(command.executable).")
            }
            let environment = runtimes.commandEnvironment(runtime, base: [
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
                "PORT": String(port), "HOST": "127.0.0.1"
            ])
            let log = logURL(id)
            if !FileManager.default.fileExists(atPath: log.path) { try write(Data(), to: log) }
            guard try FileManager.default.attributesOfItem(atPath: log.path)[.type] as? FileAttributeType == .typeRegular else {
                throw MorrowError.message("The project log must be a regular file.")
            }
            let definition: [String: Any] = [
                "Label": label(id), "ProgramArguments": ManagedServiceRunner.arguments([executable] + command.arguments),
                "AssociatedBundleIdentifiers": ManagedServiceRunner.bundleIdentifiers,
                "WorkingDirectory": folder, "EnvironmentVariables": environment,
                "RunAtLoad": true, "KeepAlive": false, "ExitTimeOut": 10,
                "StandardOutPath": log.path, "StandardErrorPath": log.path
            ]
            let job = jobURL(id)
            try launchd.unload(label(id))
            try write(PropertyListSerialization.data(fromPropertyList: definition, format: .xml, options: 0), to: job)
            try launchd.bootstrap(job)
        }
    }

    public func stop(_ id: UUID) throws {
        try store.operation { try stopOwned(id) }
    }

    public func logs(_ id: UUID) throws -> String {
        let url = logURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return "No project app output yet." }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        try handle.seek(toOffset: end > 32_768 ? end - 32_768 : 0)
        return String(decoding: try handle.read(upToCount: 32_768) ?? Data(), as: UTF8.self)
    }

    func stopOwned(_ id: UUID) throws {
        guard FileManager.default.fileExists(atPath: jobURL(id).path) else { return }
        try launchd.unload(label(id))
    }

    func requireStopped(_ site: LocalSite) throws {
        guard FileManager.default.fileExists(atPath: jobURL(site.id).path) else { return }
        let current = status(site)
        guard current == .stopped || current == .failed else {
            throw MorrowError.message("Stop the project's app before changing its command or port.")
        }
    }

    private func site(_ id: UUID, state: MorrowState) throws -> LocalSite {
        guard let site = state.web.sites.first(where: { $0.id == id }), site.mode == .proxy else {
            throw MorrowError.message("Choose a site using app-port hosting.")
        }
        return site
    }

    private func write(_ data: Data, to file: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
