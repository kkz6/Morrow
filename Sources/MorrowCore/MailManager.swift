import Foundation

public struct MailInstallation: Codable, Equatable, Sendable {
    public let executable: String
    public let version: String
    public let source: String
    public init(executable: String, version: String, source: String) { self.executable = executable; self.version = version; self.source = source }
}
public struct MailService: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var installation: MailInstallation
    public var smtpPort: Int
    public var httpPort: Int
    public var autoStart: Bool
    public var label: String { "dev.morrow.mail.\(id.uuidString.lowercased())" }
    public var inboxURL: URL { URL(string: "http://127.0.0.1:\(httpPort)/")! }
    public var smtpURL: String { "smtp://127.0.0.1:\(smtpPort)" }
    public var appConfiguration: String { "MAIL_MAILER=smtp\nMAIL_HOST=127.0.0.1\nMAIL_PORT=\(smtpPort)\nMAIL_USERNAME=null\nMAIL_PASSWORD=null\nMAIL_SCHEME=null\nMAIL_ENCRYPTION=null" }
    public init(id: UUID = UUID(), name: String, installation: MailInstallation, smtpPort: Int = 1025, httpPort: Int = 8025, autoStart: Bool = false) {
        self.id = id; self.name = name; self.installation = installation; self.smtpPort = smtpPort; self.httpPort = httpPort; self.autoStart = autoStart
    }
}
public struct MailManager: Sendable {
    public let store: StateStore
    public let runner: any CommandRunning
    public init(store: StateStore = StateStore(), runner: any CommandRunning = CommandRunner()) { self.store = store; self.runner = runner }
    private var launchd: LaunchdControl { LaunchdControl(runner: runner) }
    public func directory(_ service: MailService) -> URL { store.root.appendingPathComponent("mail/\(service.id.uuidString.lowercased())") }
    public func logURL(_ service: MailService) -> URL { directory(service).appendingPathComponent("server.log") }
    private func job(_ service: MailService) -> URL { store.root.appendingPathComponent("jobs/\(service.label).plist") }
    private func loginJob(_ service: MailService) -> URL {
        // Reuse StateStore's isolated/normal LaunchAgents location selection.
        let placeholder = DatabaseInstance(id: service.id, name: service.name, installation: Installation(engine: .postgresql, formula: "", version: "", prefix: ""), port: service.smtpPort)
        return store.loginJobURL(placeholder).deletingLastPathComponent().appendingPathComponent(service.label + ".plist")
    }
    public func resolve(_ name: String) throws -> MailService {
        guard let service = try store.load().mailServices.first(where: { $0.name == name || $0.id.uuidString.lowercased() == name.lowercased() }) else { throw MorrowError.message("No mail service named '\(name)'. Run morrow mail list.") }
        return service
    }
    private func current(_ id: UUID) throws -> MailService { try resolve(id.uuidString) }
    public func suggestedPort(_ start: Int, excluding otherPort: Int? = nil) throws -> Int {
        let state = try store.load()
        let used = Set(state.instances.map(\.port) + state.mailServices.flatMap { [$0.smtpPort, $0.httpPort] } + state.webReservedPorts + state.objectStorage.flatMap { [$0.apiPort, $0.consolePort] })
        for port in start..<min(start + 1000, 65536) where port >= 1024 && port != otherPort {
            if !used.contains(port) && DatabaseManager.portAvailable(port) { return port }
        }
        throw MorrowError.message("No available mail service port.")
    }
    public func preflight(name: String, smtpPort: Int, httpPort: Int, excluding: UUID? = nil) throws {
        try DatabaseManager.validate(DatabaseInstance(name: name, installation: Installation(engine: .postgresql, formula: "", version: "", prefix: ""), port: smtpPort))
        guard (1024...65535).contains(httpPort), smtpPort != httpPort else { throw MorrowError.message("SMTP and inbox need different ports between 1024 and 65535.") }
        let state = try store.load()
        let others = state.mailServices.filter { $0.id != excluding }
        guard !others.contains(where: { $0.name.lowercased() == name.lowercased() }) else { throw MorrowError.message("A mail service with that name already exists.") }
        let reserved = Set(state.instances.map(\.port) + others.flatMap { [$0.smtpPort, $0.httpPort] } + state.webReservedPorts + state.objectStorage.flatMap { [$0.apiPort, $0.consolePort] })
        for port in [smtpPort, httpPort] {
            guard !reserved.contains(port), DatabaseManager.portAvailable(port) else { throw MorrowError.message("Port \(port) is in use. Choose another port.") }
        }
    }
    public func installations() throws -> [MailInstallation] {
        var paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":").filter { !$0.isEmpty }.map { $0 + "/mailpit" }
        let brew = HomebrewInstaller(runner: runner, configuredPath: try store.load().preferences.homebrewPath)
        if let binary = brew.executable {
            let cellar = URL(fileURLWithPath: binary).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Cellar/mailpit")
            paths += ((try? FileManager.default.contentsOfDirectory(at: cellar, includingPropertiesForKeys: nil)) ?? []).map { $0.appendingPathComponent("bin/mailpit").path }
        }
        paths += ["/opt/homebrew/bin/mailpit", "/usr/local/bin/mailpit"]
        var seen = Set<String>(), found: [MailInstallation] = []
        for path in paths {
            let executable = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard seen.insert(executable).inserted, let item = try? probe(executable) else { continue }; found.append(item)
        }
        return found.sorted { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
    }
    private func probe(_ executable: String) throws -> MailInstallation {
        guard FileManager.default.isExecutableFile(atPath: executable) else { throw MorrowError.message("Mailpit's executable is missing.") }
        let result = try runner.run(executable, ["version", "--no-release-check"], environment: [:])
        let output: String
        if result.status == 0 { output = result.output }
        else if (result.output + result.errorOutput).contains("unknown flag") {
            // Older Mailpit versions can still report their installed version
            // even if their optional release check fails afterwards.
            output = try runner.run(executable, ["version"], environment: [:]).output
        } else { output = try result.checked() }
        let regex = try NSRegularExpression(pattern: "mailpit(?: version)?\\s+v?([0-9]+(?:\\.[0-9]+)+)", options: .caseInsensitive)
        guard let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)), let range = Range(match.range(at: 1), in: output) else { throw MorrowError.message("The selected executable did not identify itself as Mailpit.") }
        return MailInstallation(executable: executable, version: String(output[range]), source: executable.contains("/Cellar/mailpit/") ? "homebrew" : "external")
    }
    @discardableResult public func provision(name: String, smtpPort: Int, httpPort: Int, autoStart: Bool = false, version: String = "automatic", id: UUID = UUID()) throws -> MailService {
        try store.operation {
            try preflight(name: name, smtpPort: smtpPort, httpPort: httpPort)
            guard ["automatic", "current"].contains(version) || SoftwareVersion(version) != nil else { throw MorrowError.message("Choose a detected Mailpit version or the current Homebrew release.") }
            let found = try installations()
            var installation = found.first { version == "automatic" || $0.version == version }
            if installation == nil {
                let brew = HomebrewInstaller(runner: runner, configuredPath: try store.load().preferences.homebrewPath)
                let package = try brew.package("mailpit")
                guard version == "automatic" || version == "current" || version == package.version else { throw MorrowError.message("Homebrew does not provide that Mailpit version.") }
                installation = found.first { $0.version == package.version }
                if installation == nil {
                    try runner.run(brew.requireExecutable(), ["install", "--formula", "mailpit"], environment: [:]).checked()
                    installation = try installations().first { $0.version == package.version }
                }
            }
            guard let installation else { throw MorrowError.message("Mailpit was not detected after installation.") }
            try preflight(name: name, smtpPort: smtpPort, httpPort: httpPort)
            let service = MailService(id: id, name: name, installation: installation, smtpPort: smtpPort, httpPort: httpPort, autoStart: autoStart)
            guard !FileManager.default.fileExists(atPath: directory(service).path) else { throw MorrowError.message("A mail directory already exists. Its messages have been preserved.") }
            try FileManager.default.createDirectory(at: directory(service), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try writeJobs(service)
            try store.update { $0.mailServices.append(service) }
            return service
        }
    }
    public func status(_ service: MailService) -> InstanceStatus {
        guard let result = try? launchd.inspect(service.label) else { return .unknown }
        let info = LaunchdStatus(result.output), health = ServiceHealth(runner: runner)
        if result.status == 0, let pid = info.pid, health.processAlive(pid) {
            guard health.smtpReady(service.smtpPort), DatabaseManager.portListening(service.httpPort) else { return .starting }
            let web = try? runner.run("/usr/bin/curl", ["--noproxy", "*", "--fail", "--silent", "--max-time", "1", "--output", "/dev/null", service.inboxURL.absoluteString], environment: [:])
            return web?.status == 0 && health.processAlive(pid) ? .running : .starting
        }
        guard FileManager.default.isExecutableFile(atPath: service.installation.executable) else { return .missingBinary }
        if result.status != 0 { return .stopped }
        if info.failed { return .failed }
        return info.exitCode == 0 ? .stopped : .starting
    }
    public func start(_ id: UUID) throws {
        try store.operation {
            let service = try current(id), status = status(service)
            if status == .running || status == .starting { return }
            let actual = try probe(service.installation.executable)
            guard actual.version == service.installation.version else { throw MorrowError.message("Mailpit's version changed. Recreate the service with a detected version.") }
            try preflight(name: service.name, smtpPort: service.smtpPort, httpPort: service.httpPort, excluding: id)
            try launchd.unload(service.label)
            try writeJobs(service); try launchd.bootstrap(job(service))
            for _ in 0..<30 {
                let current = self.status(service)
                if current == .running { return }
                if current == .failed { throw MorrowError.message("\(service.name) could not start. Open Logs for server output.") }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }
    public func stop(_ id: UUID) throws { try store.operation { try launchd.unload(current(id).label) } }
    public func restart(_ id: UUID) throws { try stop(id); try start(id) }
    public func update(_ proposed: MailService) throws {
        try store.operation {
            let existing = try current(proposed.id)
            guard ![.running, .starting].contains(status(existing)) else { throw MorrowError.message("Stop the mail service before changing its settings.") }
            guard proposed.installation == existing.installation else { throw MorrowError.message("Create a separate mail service to select another native version.") }
            try preflight(name: proposed.name, smtpPort: proposed.smtpPort, httpPort: proposed.httpPort, excluding: proposed.id)
            try writeJobs(proposed)
            try store.update { state in if let index = state.mailServices.firstIndex(where: { $0.id == proposed.id }) { state.mailServices[index] = proposed } }
        }
    }
    public func logs(_ service: MailService) throws -> String {
        guard FileManager.default.fileExists(atPath: logURL(service).path) else { return "No mail logs yet." }
        let handle = try FileHandle(forReadingFrom: logURL(service)); defer { try? handle.close() }
        let size = try handle.seekToEnd(); try handle.seek(toOffset: size > 32768 ? size - 32768 : 0)
        return String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
    }
    public func remove(_ id: UUID, deleteMessages: Bool = false) throws {
        try store.operation {
            let service = try current(id)
            try launchd.unload(service.label)
            for path in [job(service), loginJob(service)] where FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
            if FileManager.default.fileExists(atPath: directory(service).path) {
                if deleteMessages { try FileManager.default.removeItem(at: directory(service)) }
                else {
                    let archive = store.root.appendingPathComponent("archives/mail-\(service.id.uuidString.lowercased())")
                    try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: directory(service), to: archive)
                }
            }
            try store.update { $0.mailServices.removeAll { $0.id == id } }
        }
    }
    private func writeJobs(_ service: MailService) throws {
        // env -i prevents inherited Mailpit relay/forwarding settings. This is
        // a loopback mail catcher, with persistent messages per service.
        let arguments = ["/usr/bin/env", "-i", "HOME=" + FileManager.default.homeDirectoryForCurrentUser.path, "PATH=/usr/bin:/bin", "LC_ALL=C", "MP_DISABLE_VERSION_CHECK=true", service.installation.executable,
                         "--listen", "127.0.0.1:\(service.httpPort)", "--smtp", "127.0.0.1:\(service.smtpPort)", "--database", directory(service).appendingPathComponent("messages.db").path]
        let description: [String: Any] = ["Label": service.label, "ProgramArguments": arguments, "RunAtLoad": true, "KeepAlive": false, "WorkingDirectory": directory(service).path, "StandardOutPath": logURL(service).path, "StandardErrorPath": logURL(service).path, "ExitTimeOut": 30]
        try FileManager.default.createDirectory(at: job(service).deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: description, format: .xml, options: 0)
        try data.write(to: job(service), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: job(service).path)
        if service.autoStart {
            try FileManager.default.createDirectory(at: loginJob(service).deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: loginJob(service), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: loginJob(service).path)
        } else if FileManager.default.fileExists(atPath: loginJob(service).path) { try FileManager.default.removeItem(at: loginJob(service)) }
    }
}
