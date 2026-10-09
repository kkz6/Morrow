import Foundation
import CryptoKit
import Darwin

extension SiteManager {
    public var base: URL { store.root.appendingPathComponent("web") }
    public var logURL: URL { base.appendingPathComponent("caddy.log") }
    public var dnsLogURL: URL { base.appendingPathComponent("dns.log") }
    public var watcherLogURL: URL { base.appendingPathComponent("watch.log") }
    public var certificateURL: URL { base.appendingPathComponent("caddy-data/pki/authorities/local/root.crt") }
    var configurationURL: URL { base.appendingPathComponent("Caddyfile") }
    var dnsConfigurationURL: URL { base.appendingPathComponent("dnsmasq.conf") }
    func label(_ component: String, web: WebWorkspace) -> String { "dev.morrow.web.\(web.id.uuidString.lowercased()).\(component)" }
    func adminSocket(_ web: WebWorkspace) -> String { "/tmp/morrow.\(getuid()).\(web.id.uuidString.lowercased()).caddy.sock" }
    func phpSocket(_ item: RuntimeInstallation, web: WebWorkspace) -> String {
        let hash = SHA256.hash(data: Data(item.id.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "/tmp/morrow.\(getuid()).\(web.id.uuidString.lowercased()).\(hash).sock"
    }
    func phpComponent(_ item: RuntimeInstallation) -> String { "php." + SHA256.hash(data: Data(item.id.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined() }
    public func url(_ site: LocalSite, web: WebWorkspace? = nil) -> URL {
        let web = web ?? (try? store.load().web) ?? WebWorkspace()
        let installed = SiteSystemSetup.isConfigured(http: web.httpPort, https: web.httpsPort, dns: web.dnsPort, suffixes: web.suffixes)
        let port = installed ? (site.https ? 443 : 80) : (site.https ? web.httpsPort : web.httpPort)
        return URL(string: "\(site.https ? "https" : "http")://\(site.domain)\((port == 80 && !site.https) || (port == 443 && site.https) ? "" : ":\(port)")/")!
    }
    static func quote(_ value: String) throws -> String {
        guard !value.contains(where: { $0.isNewline || $0 == "\0" }) else { throw MorrowError.message("Project paths must not contain line breaks or null bytes.") }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    func caddyConfiguration(_ web: WebWorkspace) throws -> String {
        var result = """
        {
            admin unix/\(adminSocket(web))
            skip_install_trust
            auto_https disable_redirects
            http_port \(web.httpPort)
            https_port \(web.httpsPort)
            storage file_system {
                root \(try Self.quote(base.appendingPathComponent("caddy-data").path))
            }
            pki {
                ca local {
                    name "Morrow Development CA"
                }
            }
        }

        http://127.0.0.1:\(web.httpPort) {
            bind 127.0.0.1
            respond "Morrow local sites" 200
        }

        """
        for site in web.sites where site.issue == nil && !site.ignored {
            let secure = site.https
            result += "\(secure ? "https" : "http")://\(site.domain):\(secure ? web.httpsPort : web.httpPort) {\n    bind 127.0.0.1\n"
            if secure { result += "    tls internal\n" }
            // Bind each hostname explicitly; unknown folders are never served.
            result += "    log\n"
            if site.mode == .proxy {
                guard let port = site.proxyPort else { throw MorrowError.message("A proxy site needs an application port.") }
                result += "    reverse_proxy 127.0.0.1:\(port)\n"
            } else {
                result += "    root * \(try Self.quote(site.documentRoot))\n"
                result += "    @private path /.env* /.git* */.env* */.git* /composer.* /package*.json /*.lock /node_modules/* /vendor/* /morrow.json\n    respond @private 404\n"
                if site.mode == .php {
                    if let php = web.php.first(where: { $0.id == (site.phpID ?? web.defaultPHPID) }), Self.fpmExecutable(php) != nil {
                        result += "    php_fastcgi unix/\(phpSocket(php, web: web))\n"
                    } else { result += "    respond \"Select a PHP-FPM version in Morrow\" 503\n" }
                } else {
                    result += "    @phpSource path *.php\n    respond @phpSource 404\n"
                }
                result += "    file_server\n"
            }
            result += "}\n\n"
            if secure {
                let cleanPorts = SiteSystemSetup.isConfigured(http: web.httpPort, https: web.httpsPort, dns: web.dnsPort, suffixes: web.suffixes)
                let destination = "https://\(site.domain)\(cleanPorts ? "" : ":\(web.httpsPort)"){uri}"
                result += "http://\(site.domain):\(web.httpPort) {\n    bind 127.0.0.1\n    redir \(destination) 308\n}\n\n"
            }
        }
        return result
    }
    func dnsConfiguration(_ web: WebWorkspace) -> String {
        "port=\(web.dnsPort)\nlisten-address=127.0.0.1\nbind-interfaces\nno-resolv\nno-hosts\n" + web.suffixes.map { "local=/\($0)/\naddress=/\($0)/127.0.0.1\n" }.joined() + "pid-file=\((try? Self.quote(base.appendingPathComponent("dns.pid").path)) ?? "")\n"
    }
    static func fpmExecutable(_ item: RuntimeInstallation) -> String? {
        [item.prefix + "/sbin/php-fpm", item.prefix + "/bin/php-fpm"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    func fpmConfiguration(_ item: RuntimeInstallation, web: WebWorkspace) -> String {
        let user = getpwuid(getuid()).map { String(cString: $0.pointee.pw_name) } ?? NSUserName()
        let group = getgrgid(getgid()).map { String(cString: $0.pointee.gr_name) } ?? "staff"
        return """
        [global]
        daemonize = no
        error_log = \(base.appendingPathComponent(phpComponent(item) + ".log").path)
        [morrow]
        user = \(user)
        group = \(group)
        listen = \(phpSocket(item, web: web))
        listen.mode = 0600
        pm = ondemand
        pm.max_children = 5
        pm.process_idle_timeout = 10s
        catch_workers_output = yes
        clear_env = no
        security.limit_extensions = .php
        """
    }
    func writeFile(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(text.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func job(_ component: String, web: WebWorkspace) -> URL { store.root.appendingPathComponent("jobs/\(label(component, web: web)).plist") }
    func writeJob(_ component: String, web: WebWorkspace, arguments: [String], output: URL) throws {
        var environment = store.workerEnvironment
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["LC_ALL"] = "C"
        let description: [String: Any] = ["Label": label(component, web: web), "ProgramArguments": arguments, "WorkingDirectory": base.path,
            "RunAtLoad": true, "KeepAlive": component == "watch" ? ["SuccessfulExit": false] as Any : false as Any, "StandardOutPath": output.path, "StandardErrorPath": output.path, "ExitTimeOut": 30, "EnvironmentVariables": environment]
        let data = try PropertyListSerialization.data(fromPropertyList: description, format: .xml, options: 0)
        let file = job(component, web: web)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let login = store.loginAgentURL(label: label(component, web: web))
        if web.autoStart && web.enabled {
            try FileManager.default.createDirectory(at: login.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: login, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: login.path)
        } else if FileManager.default.fileExists(atPath: login.path) { try FileManager.default.removeItem(at: login) }
    }
}
