import Foundation
import Darwin

public struct SiteManager: Sendable {
    public let store: StateStore
    public let runner: any CommandRunning
    public init(store: StateStore = StateStore(), runner: any CommandRunning = CommandRunner()) { self.store = store; self.runner = runner }
    private var launchd: LaunchdControl { LaunchdControl(runner: runner) }
    public static func domain(for folder: String, suffix: String) throws -> String {
        let slug = URL(fileURLWithPath: folder).lastPathComponent.lowercased()
            .replacingOccurrences(of: "[^a-z0-9-]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !slug.isEmpty, slug.count <= 63 else { throw MorrowError.message("Choose a domain for this folder; its name cannot form a DNS label.") }
        return slug + "." + (try SiteSystemSetup.validateSuffix(suffix))
    }
    public static func validateDomain(_ value: String, web: WebWorkspace) throws -> String {
        let domain = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard domain.count <= 253, domain.range(of: "^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$", options: .regularExpression) != nil,
              web.suffixes.contains(where: { domain.hasSuffix("." + $0) }) else {
            throw MorrowError.message("Use a valid hostname inside \(web.suffixes.map { "." + $0 }.joined(separator: ", ")).")
        }
        return domain
    }
    public func resolve(_ domain: String) throws -> LocalSite {
        guard let site = try store.load().web.sites.first(where: { $0.domain == domain.lowercased() || $0.id.uuidString.lowercased() == domain.lowercased() }) else { throw MorrowError.message("No site named '\(domain)'. Run morrow site list.") }; return site
    }
    private func folder(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw MorrowError.message("Choose an existing project directory.") }
        _ = try Self.quote(url.path); return url
    }
    public func park(_ path: String) throws {
        try store.operation {
            let url = try folder(path)
            var web = try store.load().web
            guard !web.directories.contains(where: { $0.path == url.path }) else { throw MorrowError.message("This project directory is already parked.") }
            web.directories.append(ProjectDirectory(path: url.path))
            web = try discovered(web)
            try saveAndApply(web)
        }
    }
    public func unpark(_ path: String) throws {
        try store.operation {
            let path = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
            var web = try store.load().web
            guard let item = web.directories.first(where: { $0.path == path || $0.id.uuidString == path }) else { throw MorrowError.message("That directory is not parked.") }
            web.directories.removeAll { $0.id == item.id }
            web.sites.removeAll { $0.directoryID == item.id }
            try saveAndApply(web)
        }
    }
    public func setDirectory(_ id: UUID, enabled: Bool) throws {
        try store.operation {
            var web = try store.load().web
            guard let index = web.directories.firstIndex(where: { $0.id == id }) else { throw MorrowError.message("This directory was removed.") }
            web.directories[index].enabled = enabled
            try saveAndApply(discovered(web))
        }
    }
    @discardableResult public func link(path: String, port: Int? = nil, domain: String? = nil, https: Bool? = nil, phpID: String? = nil) throws -> LocalSite {
        try store.operation {
            let url = try folder(path)
            var web = try store.load().web
            if let port { try validateProxyPort(port, web: web) }
            let name = try domain.map { try Self.validateDomain($0.contains(".") ? $0 : $0 + "." + web.suffix, web: web) } ?? Self.domain(for: url.path, suffix: web.suffix)
            if let other = web.sites.first(where: { $0.domain == name && $0.path != url.path }) { throw MorrowError.message("\(name) already belongs to \(other.path). Choose another domain.") }
            let existing = web.sites.first { $0.domain == name && $0.path == url.path }
            var site = try existing ?? detected(url, domain: name, web: web)
            site = LocalSite(id: site.id, domain: name, path: url.path, documentRoot: site.documentRoot, mode: port == nil ? site.mode : .proxy,
                             proxyPort: port ?? site.proxyPort, https: https ?? site.https, phpID: phpID ?? site.phpID, directoryID: nil, issue: port == nil ? site.issue : nil, automaticDomain: domain == nil)
            web.sites.removeAll { $0.domain == name }; web.sites.append(site)
            try saveAndApply(web)
            return site
        }
    }
    public func unlink(_ id: UUID) throws {
        try store.operation {
            var web = try store.load().web
            guard let site = web.sites.first(where: { $0.id == id }), site.directoryID == nil else { throw MorrowError.message("Remove or disable the parked directory to remove automatically discovered routes.") }
            web.sites.removeAll { $0.id == id }; try saveAndApply(web)
        }
    }
    public func update(_ proposed: LocalSite) throws {
        try store.operation {
            var web = try store.load().web
            guard let index = web.sites.firstIndex(where: { $0.id == proposed.id }) else { throw MorrowError.message("This site was removed.") }
            var site = proposed
            site.domain = try Self.validateDomain(site.domain, web: web)
            guard !web.sites.contains(where: { $0.id != site.id && $0.domain == site.domain && $0.issue == nil }) else { throw MorrowError.message("That hostname belongs to another project.") }
            let root = try folder(site.documentRoot)
            guard root.path == site.path || root.path.hasPrefix(site.path + "/") else { throw MorrowError.message("The document root must stay inside the project folder.") }
            if site.mode == .proxy { guard let port = site.proxyPort else { throw MorrowError.message("Enter the app's local port.") }; try validateProxyPort(port, web: web) }
            if let id = site.phpID, !web.php.contains(where: { $0.id == id }) { throw MorrowError.message("Select a registered PHP-FPM runtime.") }
            if site.domain != web.sites[index].domain { site.automaticDomain = false }
            site.issue = nil; web.sites[index] = site; try saveAndApply(web)
        }
    }
    public func configure(suffix: String? = nil, defaultHTTPS: Bool? = nil, http: Int? = nil, https: Int? = nil, dns: Int? = nil, autoStart: Bool? = nil) throws {
        try store.operation {
            var web = try store.load().web
            if let suffix {
                let value = try SiteSystemSetup.validateSuffix(suffix)
                if value != web.suffix {
                    if web.sites.contains(where: { !$0.automaticDomain && $0.domain.hasSuffix("." + web.suffix) }) { web.additionalSuffixes.append(web.suffix) }
                    web.suffix = value
                    for index in web.sites.indices where web.sites[index].automaticDomain { web.sites[index].domain = try Self.domain(for: web.sites[index].path, suffix: value) }
                }
            }
            if let defaultHTTPS { web.defaultHTTPS = defaultHTTPS }
            if let autoStart { web.autoStart = autoStart }
            if (http ?? web.httpPort) != web.httpPort || (https ?? web.httpsPort) != web.httpsPort || (dns ?? web.dnsPort) != web.dnsPort {
                guard !web.enabled else { throw MorrowError.message("Stop Sites before changing listener ports.") }
                web.httpPort = http ?? web.httpPort; web.httpsPort = https ?? web.httpsPort; web.dnsPort = dns ?? web.dnsPort
            }
            try SiteSystemSetup.validatePorts(http: web.httpPort, https: web.httpsPort, dns: web.dnsPort)
            guard !web.sites.contains(where: { $0.mode == .proxy && [web.httpPort, web.httpsPort, web.dnsPort].contains($0.proxyPort ?? 0) }) else {
                throw MorrowError.message("Listener ports must differ from linked application ports.")
            }
            try saveAndApply(discovered(web))
        }
    }
    public func availablePHP() throws -> [RuntimeInstallation] {
        try RuntimeManager(store: store, runner: runner).installations().filter { $0.engine == .php && Self.fpmExecutable($0) != nil }
    }
    public func installPHP() throws {
        let found = try availablePHP()
        if let item = found.first { try selectPHP(item); return }
        let brew = HomebrewInstaller(runner: runner, configuredPath: try store.load().preferences.homebrewPath)
        _ = try store.operation { try runner.run(brew.requireExecutable(), ["install", "--formula", "php"], environment: [:]).checked() }
        guard let item = try availablePHP().first else { throw MorrowError.message("Homebrew completed but PHP-FPM was not detected.") }
        try selectPHP(item)
    }
    public func selectPHP(_ item: RuntimeInstallation) throws { try registerPHP(item, asDefault: true) }
    public func registerPHP(_ item: RuntimeInstallation, asDefault: Bool = false) throws {
        try store.operation {
            guard item.engine == .php, let binary = Self.fpmExecutable(item) else { throw MorrowError.message("This installation has no PHP-FPM executable. Select a complete Homebrew PHP installation.") }
            let reported = try runner.run(binary, ["--version"], environment: [:]).checked()
            guard let version = SoftwareVersion(item.version), reported.contains("PHP " + version.components.map(String.init).joined(separator: ".")) else { throw MorrowError.message("PHP-FPM reports a different version than the selected runtime.") }
            var web = try store.load().web
            let candidate = base.appendingPathComponent(phpComponent(item) + ".conf")
            try writeFile(fpmConfiguration(item, web: web), to: candidate)
            try runner.run(binary, ["--test", "--fpm-config", candidate.path], environment: [:]).checked()
            if !web.php.contains(where: { $0.id == item.id }) { web.php.append(item) }
            if asDefault { web.defaultPHPID = item.id }
            try saveAndApply(web)
        }
    }
    public func refreshProjects(force: Bool = false) throws {
        try store.operation {
            let previous = try store.load().web
            let next = try discovered(previous)
            if next != previous || (force && next.enabled) { try saveAndApply(next) }
            else if next.enabled { try recoverServices(next) }
        }
    }
    private func detected(_ path: URL, domain: String, web: WebWorkspace, directory: UUID? = nil) throws -> LocalSite {
        let fm = FileManager.default
        let laravel = fm.fileExists(atPath: path.appendingPathComponent("artisan").path)
        let publicRoot = path.appendingPathComponent("public")
        let root = (try? publicRoot.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? publicRoot : path
        let php = fm.fileExists(atPath: root.appendingPathComponent("index.php").path)
        let serverApp = fm.fileExists(atPath: path.appendingPathComponent("package.json").path) || fm.fileExists(atPath: path.appendingPathComponent("go.mod").path)
        let mode: SiteMode = php || laravel ? .php : serverApp ? .proxy : .files
        let issue = laravel && root == path ? "Laravel's public directory is missing." : mode == .proxy ? "Link the development server port with morrow site link --port <port>." : nil
        return LocalSite(domain: domain, path: path.path, documentRoot: root.path, mode: mode, https: web.defaultHTTPS, directoryID: directory, issue: issue)
    }
    private func discovered(_ previous: WebWorkspace) throws -> WebWorkspace {
        var web = previous
        var next = previous.sites.filter { $0.directoryID == nil }
        var names = Set(next.map(\.domain))
        for directory in previous.directories where !directory.enabled {
            next += previous.sites.filter { $0.directoryID == directory.id }.map { site in var site = site; site.issue = "Project directory is disabled."; return site }
        }
        for directory in previous.directories where directory.enabled {
            let root = URL(fileURLWithPath: directory.path)
            let children: [URL]
            do { children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) }
            catch {
                next += previous.sites.filter { $0.directoryID == directory.id }.map { site in var site = site; site.issue = "Cannot read the parked directory."; return site }; continue
            }
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard !["node_modules", "vendor", "build", "dist"].contains(child.lastPathComponent), (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let canonical = child.resolvingSymlinksInPath()
                let generated = try Self.domain(for: child.path, suffix: web.suffix)
                let existing = previous.sites.first { $0.directoryID == directory.id && $0.path == canonical.path }
                var site = try existing ?? detected(canonical, domain: generated, web: web, directory: directory.id)
                if site.automaticDomain { site.domain = generated }
                if site.issue == "Cannot read the parked directory." || site.issue == "Project directory is disabled." {
                    site.issue = site.mode == .proxy && site.proxyPort == nil ? "Link the development server port with morrow site link --port <port>." : nil
                }
                if next.contains(where: { $0.directoryID == nil && $0.path == site.path && $0.domain == site.domain }) { continue }
                if !names.insert(site.domain).inserted { site.issue = "This domain is claimed by another project directory. Set a unique domain." }
                else if site.issue == "This domain is claimed by another project directory. Set a unique domain." { site.issue = nil }
                next.append(site)
            }
        }
        web.sites = next.sorted { $0.domain == $1.domain ? $0.path < $1.path : $0.domain < $1.domain }
        return web
    }
    private func validateProxyPort(_ port: Int, web: WebWorkspace) throws {
        guard (1...65535).contains(port), ![web.httpPort, web.httpsPort, web.dnsPort, 80, 443].contains(port) else { throw MorrowError.message("Choose an application port distinct from Morrow's HTTP, HTTPS, and DNS listeners.") }
    }
    private func saveAndApply(_ proposed: WebWorkspace) throws {
        var web = proposed
        if web.defaultPHPID == nil && web.sites.contains(where: { $0.mode == .php && $0.issue == nil }), let php = try availablePHP().first {
            if !web.php.contains(where: { $0.id == php.id }) { web.php.append(php) }
            web.defaultPHPID = php.id
        }
        if web.enabled { try apply(web) }
        try store.update { $0.web = web }
        if web.enabled { try writeWatcher(web) }
    }
    private func nativeTool(_ name: String, preferred: String? = nil) throws -> String {
        let candidates = [preferred, "/opt/homebrew/bin/" + name, "/opt/homebrew/sbin/" + name, "/usr/local/bin/" + name, "/usr/local/sbin/" + name].compactMap { $0 }
        if let binary = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return URL(fileURLWithPath: binary).resolvingSymlinksInPath().path }
        let brew = HomebrewInstaller(runner: runner, configuredPath: try store.load().preferences.homebrewPath)
        try runner.run(brew.requireExecutable(), ["install", "--formula", name], environment: [:]).checked()
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw MorrowError.message("The installed \(name) executable was not detected.") }
        return URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
    }
    public func start(cli: URL) throws {
        try store.operation {
            var web = try discovered(store.load().web)
            try validateListeners(web)
            web.cliPath = cli.resolvingSymlinksInPath().path
            guard FileManager.default.isExecutableFile(atPath: web.cliPath!) else { throw MorrowError.message("The morrow CLI is missing.") }
            web.caddyPath = try nativeTool("caddy", preferred: web.caddyPath)
            web.dnsmasqPath = try nativeTool("dnsmasq", preferred: web.dnsmasqPath)
            if web.sites.contains(where: { $0.mode == .php && $0.issue == nil }) && web.defaultPHPID == nil {
                let php = try RuntimeManager(store: store, runner: runner).installations().first { $0.engine == .php && Self.fpmExecutable($0) != nil }
                if let php { web.php.append(php); web.defaultPHPID = php.id }
                // Other routes can run while PHP projects show 'PHP unavailable'.
            }
            web.enabled = true
            do { try apply(web); try store.update { $0.web = web }; try writeWatcher(web) }
            catch {
                for component in ["caddy", "dns", "watch"] + web.php.map(phpComponent) { try? launchd.unload(label(component, web: web)) }
                throw error
            }
        }
    }
    public func stop() throws {
        try store.operation {
            var web = try store.load().web; web.enabled = false
            for component in ["watch", "caddy", "dns"] + web.php.map(phpComponent) {
                try launchd.unload(label(component, web: web))
                let login = store.loginAgentURL(label: label(component, web: web))
                if FileManager.default.fileExists(atPath: login.path) { try FileManager.default.removeItem(at: login) }
            }
            try store.update { $0.web = web }
        }
    }
    private func validateListeners(_ web: WebWorkspace) throws {
        try SiteSystemSetup.validatePorts(http: web.httpPort, https: web.httpsPort, dns: web.dnsPort)
        let state = try store.load()
        let reserved = Set(state.instances.map(\.port) + state.mailServices.flatMap { [$0.smtpPort, $0.httpPort] })
        for (port, component) in [(web.httpPort, "caddy"), (web.httpsPort, "caddy"), (web.dnsPort, "dns")] {
            if live(component, web: web) { continue }
            guard !reserved.contains(port), DatabaseManager.portAvailable(port) else { throw MorrowError.message("Port \(port) is unavailable. Choose another Sites listener port.") }
        }
    }
    private func apply(_ web: WebWorkspace) throws {
        guard let caddy = web.caddyPath, let dns = web.dnsmasqPath else { throw MorrowError.message("Start Sites to install its native dependencies.") }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let caddyText = try caddyConfiguration(web)
        let candidate = base.appendingPathComponent("Caddyfile.next")
        try writeFile(caddyText, to: candidate)
        try runner.run(caddy, ["validate", "--config", candidate.path, "--adapter", "caddyfile"], environment: [:]).checked()
        try startPHP(web)
        try writeFile(caddyText, to: configurationURL)
        try writeJob("caddy", web: web, arguments: [caddy, "run", "--config", configurationURL.path, "--adapter", "caddyfile"], output: logURL)
        if live("caddy", web: web) {
            try runner.run(caddy, ["reload", "--config", configurationURL.path, "--adapter", "caddyfile", "--address", "unix/" + adminSocket(web)], environment: [:]).checked()
        } else {
            try launchd.unload(label("caddy", web: web)); try launchd.bootstrap(job("caddy", web: web))
            try waitFor("caddy", web: web, port: web.httpPort)
        }
        let dnsText = dnsConfiguration(web)
        let changed = (try? String(contentsOf: dnsConfigurationURL, encoding: .utf8)) != dnsText
        try writeFile(dnsText, to: dnsConfigurationURL)
        try writeJob("dns", web: web, arguments: [dns, "--keep-in-foreground", "--conf-file=" + dnsConfigurationURL.path], output: dnsLogURL)
        if changed || !live("dns", web: web) {
            try runner.run(dns, ["--test", "--conf-file=" + dnsConfigurationURL.path], environment: [:]).checked()
            try launchd.unload(label("dns", web: web)); try launchd.bootstrap(job("dns", web: web))
            try waitFor("dns", web: web, port: web.dnsPort)
        }
    }
    private func startPHP(_ web: WebWorkspace) throws {
        let used = Set(web.sites.filter { $0.mode == .php && $0.issue == nil }.compactMap { $0.phpID ?? web.defaultPHPID })
        for item in web.php where !used.contains(item.id) {
            try launchd.unload(label(phpComponent(item), web: web))
            let login = store.loginAgentURL(label: label(phpComponent(item), web: web))
            if FileManager.default.fileExists(atPath: login.path) { try FileManager.default.removeItem(at: login) }
        }
        for item in web.php where used.contains(item.id) {
            guard let executable = Self.fpmExecutable(item) else { throw MorrowError.message("PHP-FPM for \(item.version) is missing.") }
            let component = phpComponent(item)
            let configuration = base.appendingPathComponent(component + ".conf")
            try writeFile(fpmConfiguration(item, web: web), to: configuration)
            try runner.run(executable, ["--test", "--fpm-config", configuration.path], environment: [:]).checked()
            try writeJob(component, web: web, arguments: [executable, "--nodaemonize", "--fpm-config", configuration.path], output: base.appendingPathComponent(component + ".log"))
            if !live(component, web: web) { try launchd.unload(label(component, web: web)); try launchd.bootstrap(job(component, web: web)) }
        }
    }
    private func writeWatcher(_ web: WebWorkspace) throws {
        guard let cli = web.cliPath else { return }
        try writeJob("watch", web: web, arguments: [cli, "site", "watch"], output: watcherLogURL)
        if !live("watch", web: web) { try launchd.unload(label("watch", web: web)); try launchd.bootstrap(job("watch", web: web)) }
    }
    private func recoverServices(_ web: WebWorkspace) throws {
        // A scan after login rebuilds routes and recovers missing managed jobs.
        let changed = (try? String(contentsOf: configurationURL, encoding: .utf8)) != (try caddyConfiguration(web))
        if !live("caddy", web: web) || !live("dns", web: web) || changed { try apply(web) }
        else { try startPHP(web) }
    }
    private func waitFor(_ component: String, web: WebWorkspace, port: Int) throws {
        for _ in 0..<30 {
            if live(component, web: web) && DatabaseManager.portListening(port) { return }
            if let result = try? launchd.inspect(label(component, web: web)), LaunchdStatus(result.output).failed { throw MorrowError.message("The \(component) service failed. Open its Sites log.") }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw MorrowError.message("The \(component) listener did not become ready. Open its Sites log.")
    }
    func live(_ component: String, web: WebWorkspace) -> Bool {
        guard let result = try? launchd.inspect(label(component, web: web)), result.status == 0, let pid = LaunchdStatus(result.output).pid else { return false }
        return ServiceHealth(runner: runner).processAlive(pid)
    }
    private func componentStatus(_ name: String, web: WebWorkspace, port: Int) -> InstanceStatus {
        if live(name, web: web) { return DatabaseManager.portListening(port) ? .running : .starting }
        let binary = name == "caddy" ? web.caddyPath : web.dnsmasqPath
        if let binary, !FileManager.default.isExecutableFile(atPath: binary) { return .missingBinary }
        guard let result = try? launchd.inspect(label(name, web: web)), result.status == 0 else { return .stopped }
        let job = LaunchdStatus(result.output)
        if job.failed { return .failed }
        return job.exitCode == 0 ? .stopped : .starting
    }
    public func status() throws -> WebStatus {
        let web = try store.load().web
        let proxyStatus = componentStatus("caddy", web: web, port: web.httpPort)
        let dnsStatus = componentStatus("dns", web: web, port: web.dnsPort)
        let proxy = proxyStatus == .running
        let configured = SiteSystemSetup.isConfigured(http: web.httpPort, https: web.httpsPort, dns: web.dnsPort, suffixes: web.suffixes)
        let message = configured ? "Local domain routing is installed." : SiteSystemSetup.setupIssue(suffixes: web.suffixes) ?? "Enable Local Domains to use URLs without listener ports."
        var statuses: [UUID: SiteStatus] = [:]
        for site in web.sites {
            if !FileManager.default.fileExists(atPath: site.path) { statuses[site.id] = .missingFolder }
            else if site.issue != nil { statuses[site.id] = .configurationIssue }
            else if !proxy { statuses[site.id] = .stopped }
            else if site.mode == .proxy && !(site.proxyPort.map(DatabaseManager.portListening) ?? false) { statuses[site.id] = .waitingForApp }
            else if site.mode == .php {
                if let item = web.php.first(where: { $0.id == (site.phpID ?? web.defaultPHPID) }), live(phpComponent(item), web: web), FileManager.default.fileExists(atPath: phpSocket(item, web: web)) { statuses[site.id] = .serving }
                else { statuses[site.id] = .needsPHP }
            } else { statuses[site.id] = .serving }
        }
        return WebStatus(proxy: proxyStatus, dns: dnsStatus, systemConfigured: configured, setupMessage: message, sites: statuses)
    }
    public func setupCommand(cli: URL) throws -> String {
        let web = try store.load().web
        func shell(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return shell(cli.resolvingSymlinksInPath().path) + " site setup --user \(getuid()) --http-port \(web.httpPort) --https-port \(web.httpsPort) --dns-port \(web.dnsPort) --suffixes " + shell(web.suffixes.joined(separator: ","))
    }
    public func trustCertificate() throws {
        guard FileManager.default.fileExists(atPath: certificateURL.path) else { throw MorrowError.message("Enable HTTPS on a site and start Sites first to create its local certificate authority.") }
        let keychain = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Keychains/login.keychain-db")
        try runner.run("/usr/bin/security", ["add-trusted-cert", "-r", "trustRoot", "-k", keychain.path, certificateURL.path], environment: [:]).checked()
    }
}
