import Foundation
import Darwin
import CLaunch

/// The one administrator operation is intentionally separate from normal
/// hosting: only Morrow's resolver files and socket-activated gateway are owned.
public enum SiteSystemSetup {
    public static let resolverAddress = "127.0.0.1"
    private static let legacyResolverAddress = "192.0.2.53"
    private static let marker = "# Managed by Morrow local sites"
    private static let root = URL(fileURLWithPath: "/Library/Application Support/Morrow Network")
    private static let daemon = URL(fileURLWithPath: "/Library/LaunchDaemons/dev.morrow.network.plist")
    private static let backupRoot = URL(fileURLWithPath: "/Library/Application Support/Morrow Network Backups")
    private struct Ownership: Codable {
        let uid: UInt32
        let http: Int
        let https: Int
        let dns: Int
        let suffixes: [String]
        var resolverBackups: [String: String] = [:]
        var transport = "sockets"
        enum CodingKeys: String, CodingKey { case uid, http, https, dns, suffixes, resolverBackups, transport }
        init(uid: UInt32, http: Int, https: Int, dns: Int, suffixes: [String], resolverBackups: [String: String] = [:]) {
            self.uid = uid; self.http = http; self.https = https; self.dns = dns; self.suffixes = suffixes; self.resolverBackups = resolverBackups
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            uid = try values.decode(UInt32.self, forKey: .uid); http = try values.decode(Int.self, forKey: .http)
            https = try values.decode(Int.self, forKey: .https); dns = try values.decode(Int.self, forKey: .dns)
            suffixes = try values.decode([String].self, forKey: .suffixes)
            resolverBackups = try values.decodeIfPresent([String: String].self, forKey: .resolverBackups) ?? [:]
            transport = try values.decodeIfPresent(String.self, forKey: .transport) ?? "pf"
        }
    }
    private struct ResolverBackup: Codable { let data: Data; let permissions: Int }
    public static func validateSuffix(_ text: String) throws -> String {
        let value = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard value.count <= 190, value.range(of: "^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$", options: .regularExpression) != nil,
              ["test", "internal", "localhost"].contains(value.components(separatedBy: ".").last ?? "") else {
            throw MorrowError.message("Use test, internal, localhost, or a namespace such as morrow.test.")
        }
        return value
    }
    public static func isConfigured(http: Int, https: Int, dns: Int, suffixes: [String]) -> Bool {
        guard !FileManager.default.fileExists(atPath: root.appendingPathComponent("pending.json").path),
              let data = try? Data(contentsOf: root.appendingPathComponent("ownership.json")),
              let owner = try? JSONDecoder().decode(Ownership.self, from: data),
              owner.uid == getuid(), owner.http == http, owner.https == https, owner.dns == dns,
              owner.suffixes.sorted() == suffixes.sorted(), owner.transport == "sockets",
              let gateway = try? CommandRunner().run("/bin/launchctl", ["print", "system/dev.morrow.network"]),
              let pid = LaunchdStatus(gateway.output).pid, ServiceHealth(runner: CommandRunner()).processAlive(pid),
              DatabaseManager.portListening(80), DatabaseManager.portListening(443), DatabaseManager.portListening(53) else { return false }
        return suffixes.allSatisfy { suffix in
            (try? String(contentsOfFile: "/etc/resolver/" + suffix, encoding: .utf8)) == resolver(suffix: suffix, port: dns)
        }
    }
    public static func setupIssue(suffixes: [String]) -> String? {
        for suffix in suffixes {
            guard (try? validateSuffix(suffix)) != nil else { return "Invalid development suffix." }
            let file = URL(fileURLWithPath: "/etc/resolver/" + suffix)
            if FileManager.default.fileExists(atPath: file.path),
               (try? String(contentsOf: file, encoding: .utf8).hasPrefix(marker + "\n")) != true {
                return "Another tool manages /etc/resolver/\(suffix). Remove that tool's resolver configuration or choose another suffix before enabling Morrow."
            }
        }
        return nil
    }
    public static func install(http: Int, https: Int, dns: Int, suffixes: [String], uid: UInt32, replaceResolvers: Bool = false, runner: any CommandRunning = CommandRunner()) throws {
        guard geteuid() == 0 else { throw MorrowError.message("Local domain setup needs administrator authorization. Use Set Up in Sites, or sudo morrow site setup.") }
        try validatePorts(http: http, https: https, dns: dns)
        let zones = try Array(Set(suffixes.map(validateSuffix))).sorted()
        guard !zones.isEmpty, zones.count <= 20, uid > 0 else { throw MorrowError.message("Invalid system setup parameters.") }
        if !replaceResolvers, let issue = setupIssue(suffixes: zones) { throw MorrowError.message(issue) }
        let fm = FileManager.default
        var replacements: [String: ResolverBackup] = [:]
        for suffix in zones {
            let url = URL(fileURLWithPath: "/etc/resolver/" + suffix)
            guard fm.fileExists(atPath: url.path) else { continue }
            guard (try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])).isSymbolicLink != true,
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw MorrowError.message("The resolver is not a regular file. It was preserved.") }
            let data = try Data(contentsOf: url)
            guard data.count <= 65_536 else { throw MorrowError.message("The existing resolver is too large to replace safely.") }
            if !String(decoding: data, as: UTF8.self).hasPrefix(marker + "\n") {
                guard replaceResolvers else { throw MorrowError.message("An existing resolver needs explicit replacement authorization.") }
                let permissions = (try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
                replacements[suffix] = ResolverBackup(data: data, permissions: permissions)
            }
        }
        var previousOwner: Ownership?
        if fm.fileExists(atPath: root.path) {
            try ensureRootDirectory(root, mode: 0o755)
            guard (try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  let data = (try? Data(contentsOf: root.appendingPathComponent("pending.json"))) ?? (try? Data(contentsOf: root.appendingPathComponent("ownership.json"))), let existing = try? JSONDecoder().decode(Ownership.self, from: data), existing.uid == uid else {
                throw MorrowError.message("The existing network setup belongs to another user or tool.")
            }
            previousOwner = existing
        }
        guard let account = getpwuid(uid) else { throw MorrowError.message("The selected Mac user does not exist.") }
        let username = String(cString: account.pointee.pw_name)
        var pathSize: UInt32 = 4096, pathBytes = [CChar](repeating: 0, count: 4096)
        guard _NSGetExecutablePath(&pathBytes, &pathSize) == 0 else { throw MorrowError.message("Could not locate the running setup helper.") }
        let executable = URL(fileURLWithPath: String(cString: pathBytes)).resolvingSymlinksInPath().path
        guard fm.isExecutableFile(atPath: executable) else { throw MorrowError.message("The gateway CLI is missing.") }
        if previousOwner?.transport == "sockets" {
            _ = try runner.run("/bin/launchctl", ["bootout", "system/dev.morrow.network"], environment: [:])
        }
        guard DatabaseManager.portAvailable(80), DatabaseManager.portAvailable(443), DatabaseManager.portAvailable(53), udpDNSAvailable() else {
            throw MorrowError.message("Port 80, 443, or DNS 53 belongs to another service. Stop that service before setting up Morrow.")
        }
        try ensureRootDirectory(root, mode: 0o755)
        let gateway = root.appendingPathComponent("morrow-gateway")
        if executable != gateway.path {
            if fm.fileExists(atPath: gateway.path) { try fm.removeItem(at: gateway) }
            try fm.copyItem(at: URL(fileURLWithPath: executable), to: gateway)
        }
        try fm.setAttributes([.posixPermissions: 0o755, .ownerAccountID: 0], ofItemAtPath: gateway.path)
        var backups = previousOwner?.resolverBackups ?? [:]
        let ownershipURL = root.appendingPathComponent("pending.json")
        let staged = Ownership(uid: uid, http: http, https: https, dns: dns, suffixes: zones, resolverBackups: backups)
        try JSONEncoder().encode(staged).write(to: ownershipURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0], ofItemAtPath: ownershipURL.path)
        for (suffix, backup) in replacements {
            try ensureRootDirectory(backupRoot, mode: 0o700)
            let name = "\(uid)-\(UUID().uuidString.lowercased()).json"
            let target = backupRoot.appendingPathComponent(name)
            try JSONEncoder().encode(backup).write(to: target, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600, .ownerAccountID: 0], ofItemAtPath: target.path)
            backups[suffix] = name
        }
        let newOwner = Ownership(uid: uid, http: http, https: https, dns: dns, suffixes: zones, resolverBackups: backups)
        // Mark the created directory even if a later privileged step fails;
        // a retry can then safely finish this same user's staged setup.
        try JSONEncoder().encode(newOwner).write(to: ownershipURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0], ofItemAtPath: ownershipURL.path)
        try fm.createDirectory(atPath: "/etc/resolver", withIntermediateDirectories: true)
        for suffix in zones {
            let file = URL(fileURLWithPath: "/etc/resolver/" + suffix)
            guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw MorrowError.message("A resolver file is a symbolic link. It was preserved.") }
            if let original = replacements[suffix] {
                guard (try? Data(contentsOf: file)) == original.data else { throw MorrowError.message("The existing resolver changed during setup. Its backup was retained; retry setup.") }
            } else if fm.fileExists(atPath: file.path), !(try String(contentsOf: file, encoding: .utf8)).hasPrefix(marker + "\n") {
                throw MorrowError.message("Another tool changed the resolver during setup. It was preserved.")
            }
            try resolver(suffix: suffix, port: dns).write(to: file, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0], ofItemAtPath: file.path)
        }
        if let previousOwner {
            for old in previousOwner.suffixes where !zones.contains(old) {
                let oldURL = URL(fileURLWithPath: "/etc/resolver/" + old)
                if (try? String(contentsOf: oldURL, encoding: .utf8)) == resolver(suffix: old, port: previousOwner.dns, legacy: previousOwner.transport == "pf") { try restoreResolver(oldURL, suffix: old, owner: previousOwner) }
            }
        }
        func socketDescription(_ port: Int, datagram: Bool = false) -> [String: Any] {
            ["SockFamily": "IPv4", "SockType": datagram ? "dgram" : "stream", "SockProtocol": datagram ? "UDP" : "TCP", "SockNodeName": "127.0.0.1", "SockServiceName": String(port), "SockPassive": true]
        }
        let description: [String: Any] = ["Label": "dev.morrow.network", "UserName": username,
            "AssociatedBundleIdentifiers": ManagedServiceRunner.bundleIdentifiers,
            "ProgramArguments": [gateway.path, "site", "gateway", "--http-port", String(http), "--https-port", String(https), "--dns-port", String(dns)],
            "Sockets": ["http": socketDescription(80), "https": socketDescription(443), "dnsTCP": socketDescription(53), "dnsUDP": socketDescription(53, datagram: true)],
            "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 5,
            "StandardOutPath": "/var/log/dev.morrow.network.log", "StandardErrorPath": "/var/log/dev.morrow.network.log"]
        let log = URL(fileURLWithPath: "/var/log/dev.morrow.network.log")
        if !fm.fileExists(atPath: log.path) { fm.createFile(atPath: log.path, contents: Data(), attributes: [.posixPermissions: 0o600]) }
        guard (try log.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])).isRegularFile == true,
              (try log.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw MorrowError.message("The gateway log is not a regular file.") }
        try fm.setAttributes([.posixPermissions: 0o600, .ownerAccountID: uid], ofItemAtPath: log.path)
        try PropertyListSerialization.data(fromPropertyList: description, format: .xml, options: 0).write(to: daemon, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0], ofItemAtPath: daemon.path)
        _ = try runner.run("/bin/launchctl", ["bootout", "system/dev.morrow.network"], environment: [:])
        try runner.run("/bin/launchctl", ["bootstrap", "system", daemon.path], environment: [:]).checked()
        if previousOwner?.transport == "pf" || fm.fileExists(atPath: root.appendingPathComponent("pf.rules").path) || fm.fileExists(atPath: "/var/run/dev.morrow.pf-token") { try removeLegacyForwarding(runner: runner) }
        var ready = false
        for _ in 0..<50 {
            if let job = try? runner.run("/bin/launchctl", ["print", "system/dev.morrow.network"], environment: [:]),
               let pid = LaunchdStatus(job.output).pid, ServiceHealth(runner: runner).processAlive(pid) { ready = true; break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard ready else { throw MorrowError.message("The localhost gateway could not start. Setup remains pending; inspect its gateway log before retrying.") }
        let committed = root.appendingPathComponent("ownership.json")
        try JSONEncoder().encode(newOwner).write(to: committed, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0], ofItemAtPath: committed.path)
        try fm.removeItem(at: ownershipURL)
        _ = try runner.run("/usr/bin/dscacheutil", ["-flushcache"], environment: [:])
        _ = try runner.run("/usr/bin/killall", ["-HUP", "mDNSResponder"], environment: [:])
    }
    public static func remove(runner: any CommandRunning = CommandRunner()) throws {
        guard geteuid() == 0 else { throw MorrowError.message("Removing system routing needs administrator authorization.") }
        let data: Data
        if let committed = try? Data(contentsOf: root.appendingPathComponent("ownership.json")) { data = committed }
        else { data = try Data(contentsOf: root.appendingPathComponent("pending.json")) }
        let owner = try JSONDecoder().decode(Ownership.self, from: data)
        _ = try runner.run("/bin/launchctl", ["bootout", "system/dev.morrow.network"], environment: [:])
        if owner.transport == "pf" || FileManager.default.fileExists(atPath: root.appendingPathComponent("pf.rules").path) || FileManager.default.fileExists(atPath: "/var/run/dev.morrow.pf-token") { try removeLegacyForwarding(runner: runner) }
        for suffix in owner.suffixes {
            let url = URL(fileURLWithPath: "/etc/resolver/" + suffix)
            if (try? String(contentsOf: url, encoding: .utf8)) == resolver(suffix: suffix, port: owner.dns, legacy: owner.transport == "pf") { try restoreResolver(url, suffix: suffix, owner: owner) }
        }
        if FileManager.default.fileExists(atPath: daemon.path) { try FileManager.default.removeItem(at: daemon) }
        try FileManager.default.removeItem(at: root)
        _ = try runner.run("/usr/bin/dscacheutil", ["-flushcache"], environment: [:])
        _ = try runner.run("/usr/bin/killall", ["-HUP", "mDNSResponder"], environment: [:])
    }
    private static func udpDNSAvailable() -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, 0); guard fd >= 0 else { return false }; defer { Darwin.close(fd) }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(53).bigEndian; address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 } }
    }
    private static func removeLegacyForwarding(runner: any CommandRunning) throws {
        try runner.run("/sbin/pfctl", ["-a", "com.apple/dev.morrow", "-F", "all"], environment: [:]).checked()
        let tokenURL = URL(fileURLWithPath: "/var/run/dev.morrow.pf-token")
        if let token = try? String(contentsOf: tokenURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), UInt64(token) != nil {
            try runner.run("/sbin/pfctl", ["-X", token], environment: [:]).checked(); try FileManager.default.removeItem(at: tokenURL)
        }
        if aliasInterface() == "lo0" { try runner.run("/sbin/ifconfig", ["lo0", "-alias", legacyResolverAddress], environment: [:]).checked() }
        for name in ["apply.sh", "pf.rules"] { let file = root.appendingPathComponent(name); if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) } }
    }
    private static func ensureRootDirectory(_ url: URL, mode: Int) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            let attributes = try fm.attributesOfItem(atPath: url.path)
            guard values.isSymbolicLink != true, values.isDirectory == true,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0,
                  ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o022 == 0 else {
                throw MorrowError.message("The existing system setup directory is not protected and root-owned. It was preserved.")
            }
        } else { try fm.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: mode, .ownerAccountID: 0]) }
    }
    private static func restoreResolver(_ url: URL, suffix: String, owner: Ownership) throws {
        guard let name = owner.resolverBackups[suffix] else { try FileManager.default.removeItem(at: url); return }
        guard name.range(of: "^[0-9]+-[a-f0-9-]{36}\\.json$", options: .regularExpression) != nil else { throw MorrowError.message("Invalid resolver backup reference. Backups were preserved.") }
        try ensureRootDirectory(backupRoot, mode: 0o700)
        let backup = try JSONDecoder().decode(ResolverBackup.self, from: Data(contentsOf: backupRoot.appendingPathComponent(name)))
        try backup.data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: backup.permissions, .ownerAccountID: 0], ofItemAtPath: url.path)
    }
    private static func resolver(suffix: String, port: Int, legacy: Bool = false) -> String { "\(marker)\ndomain \(suffix)\nnameserver \(legacy ? legacyResolverAddress : resolverAddress)\nport 53\n" }
    private static func aliasInterface() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var next = list
        while let entry = next {
            if let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) {
                let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
                if value == inet_addr(legacyResolverAddress) { return String(cString: entry.pointee.ifa_name) }
            }
            next = entry.pointee.ifa_next
        }
        return nil
    }
    public static func validatePorts(http: Int, https: Int, dns: Int) throws {
        let ports = [http, https, dns]
        guard ports.allSatisfy({ (1024...65535).contains($0) }), Set(ports).count == 3 else { throw MorrowError.message("Use three different unprivileged ports between 1024 and 65535.") }
    }
}
