import Foundation
import Darwin

/// The one administrator operation is intentionally separate from normal
/// hosting: only Morrow's resolver files, PF subanchor, and boot job are owned.
public enum SiteSystemSetup {
    public static let resolverAddress = "192.0.2.53"
    private static let marker = "# Managed by Morrow local sites"
    private static let root = URL(fileURLWithPath: "/Library/Application Support/Morrow Network")
    private static let daemon = URL(fileURLWithPath: "/Library/LaunchDaemons/dev.morrow.network.plist")
    private struct Ownership: Codable {
        let uid: UInt32
        let http: Int
        let https: Int
        let dns: Int
        let suffixes: [String]
    }
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
              owner.suffixes.sorted() == suffixes.sorted(), aliasInterface() == "lo0" else { return false }
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
    public static func install(http: Int, https: Int, dns: Int, suffixes: [String], uid: UInt32, runner: any CommandRunning = CommandRunner()) throws {
        guard geteuid() == 0 else { throw MorrowError.message("Local domain setup needs administrator authorization. Use Enable Local Domains in Sites, or sudo morrow site setup.") }
        try validatePorts(http: http, https: https, dns: dns)
        let zones = try Array(Set(suffixes.map(validateSuffix))).sorted()
        guard !zones.isEmpty, zones.count <= 20, uid > 0 else { throw MorrowError.message("Invalid system setup parameters.") }
        if let issue = setupIssue(suffixes: zones) { throw MorrowError.message(issue) }
        let fm = FileManager.default
        var previousOwner: Ownership?
        if fm.fileExists(atPath: root.path) {
            guard (try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
                  let data = (try? Data(contentsOf: root.appendingPathComponent("ownership.json"))) ?? (try? Data(contentsOf: root.appendingPathComponent("pending.json"))), let existing = try? JSONDecoder().decode(Ownership.self, from: data), existing.uid == uid else {
                throw MorrowError.message("The existing network setup belongs to another user or tool.")
            }
            previousOwner = existing
        } else { try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755]) }
        let newOwner = Ownership(uid: uid, http: http, https: https, dns: dns, suffixes: zones)
        let ownershipURL = root.appendingPathComponent("pending.json")
        // Mark the created directory even if a later privileged step fails;
        // a retry can then safely finish this same user's staged setup.
        try JSONEncoder().encode(newOwner).write(to: ownershipURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0], ofItemAtPath: ownershipURL.path)
        guard (try? String(contentsOfFile: "/etc/pf.conf", encoding: .utf8).contains("rdr-anchor \"com.apple/*\"")) == true else {
            throw MorrowError.message("The macOS PF configuration has no standard Apple redirect anchor. Morrow preserved it; use custom-port site URLs or configure forwarding manually.")
        }
        // An existing listener must not be redirected away from another tool.
        guard DatabaseManager.portAvailable(80), DatabaseManager.portAvailable(443) else {
            throw MorrowError.message("Ports 80 or 443 are already owned by another web server. Stop that server before enabling Morrow's domain routing.")
        }
        if let interface = aliasInterface(), interface != "lo0" || previousOwner == nil {
            throw MorrowError.message("The local DNS alias address is already used by another network configuration.")
        }
        let rules = "\(marker)\nrdr pass on lo0 inet proto { tcp udp } from any to \(resolverAddress) port 53 -> 127.0.0.1 port \(dns)\nrdr pass on lo0 inet proto tcp from any to 127.0.0.1 port 80 -> 127.0.0.1 port \(http)\nrdr pass on lo0 inet proto tcp from any to 127.0.0.1 port 443 -> 127.0.0.1 port \(https)\n"
        let ruleURL = root.appendingPathComponent("pf.rules")
        try rules.write(to: ruleURL, atomically: true, encoding: .utf8)
        try runner.run("/sbin/pfctl", ["-n", "-a", "com.apple/dev.morrow", "-f", ruleURL.path], environment: [:]).checked()
        let scriptURL = root.appendingPathComponent("apply.sh")
        let token = "/var/run/dev.morrow.pf-token"
        let script = """
        #!/bin/sh
        \(marker)
        set -eu
        if ! /sbin/ifconfig lo0 | /usr/bin/grep -q 'inet \(resolverAddress) '; then
            /sbin/ifconfig lo0 alias \(resolverAddress) netmask 255.255.255.255
        fi
        /sbin/pfctl -a com.apple/dev.morrow -f '/Library/Application Support/Morrow Network/pf.rules'
        if [ ! -s '\(token)' ]; then
            output=$(/sbin/pfctl -E 2>&1)
            token=$(printf '%s\\n' "$output" | /usr/bin/awk '/Token/{print $NF}')
            if [ -z "$token" ]; then printf '%s\\n' "$output" >&2; exit 1; fi
            printf '%s\\n' "$token" > '\(token)'
            /bin/chmod 600 '\(token)'
        fi
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        for file in [scriptURL, ruleURL] { try fm.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0], ofItemAtPath: file.path) }
        try runner.run("/bin/sh", [scriptURL.path], environment: [:]).checked()
        try fm.createDirectory(atPath: "/etc/resolver", withIntermediateDirectories: true)
        for suffix in zones {
            let file = URL(fileURLWithPath: "/etc/resolver/" + suffix)
            guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw MorrowError.message("A resolver file is a symbolic link. It was preserved.") }
            try resolver(suffix: suffix, port: dns).write(to: file, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0], ofItemAtPath: file.path)
        }
        if let previousOwner {
            for old in previousOwner.suffixes where !zones.contains(old) {
                let oldURL = URL(fileURLWithPath: "/etc/resolver/" + old)
                if (try? String(contentsOf: oldURL, encoding: .utf8)) == resolver(suffix: old, port: previousOwner.dns) { try fm.removeItem(at: oldURL) }
            }
        }
        let description: [String: Any] = ["Label": "dev.morrow.network", "ProgramArguments": ["/bin/sh", scriptURL.path], "RunAtLoad": true, "KeepAlive": false,
            "StandardOutPath": "/var/log/dev.morrow.network.log", "StandardErrorPath": "/var/log/dev.morrow.network.log"]
        try PropertyListSerialization.data(fromPropertyList: description, format: .xml, options: 0).write(to: daemon, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0], ofItemAtPath: daemon.path)
        _ = try runner.run("/bin/launchctl", ["bootout", "system/dev.morrow.network"], environment: [:])
        try runner.run("/bin/launchctl", ["bootstrap", "system", daemon.path], environment: [:]).checked()
        let committed = root.appendingPathComponent("ownership.json")
        try JSONEncoder().encode(newOwner).write(to: committed, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0], ofItemAtPath: committed.path)
        try fm.removeItem(at: ownershipURL)
    }
    public static func remove(runner: any CommandRunning = CommandRunner()) throws {
        guard geteuid() == 0 else { throw MorrowError.message("Removing system routing needs administrator authorization.") }
        let data: Data
        if let committed = try? Data(contentsOf: root.appendingPathComponent("ownership.json")) { data = committed }
        else { data = try Data(contentsOf: root.appendingPathComponent("pending.json")) }
        let owner = try JSONDecoder().decode(Ownership.self, from: data)
        _ = try runner.run("/bin/launchctl", ["bootout", "system/dev.morrow.network"], environment: [:])
        try runner.run("/sbin/pfctl", ["-a", "com.apple/dev.morrow", "-F", "all"], environment: [:]).checked()
        let tokenURL = URL(fileURLWithPath: "/var/run/dev.morrow.pf-token")
        if let token = try? String(contentsOf: tokenURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), UInt64(token) != nil {
            _ = try runner.run("/sbin/pfctl", ["-X", token], environment: [:]); try FileManager.default.removeItem(at: tokenURL)
        }
        if aliasInterface() == "lo0" { _ = try runner.run("/sbin/ifconfig", ["lo0", "-alias", resolverAddress], environment: [:]) }
        for suffix in owner.suffixes {
            let url = URL(fileURLWithPath: "/etc/resolver/" + suffix)
            if (try? String(contentsOf: url, encoding: .utf8)) == resolver(suffix: suffix, port: owner.dns) { try FileManager.default.removeItem(at: url) }
        }
        if FileManager.default.fileExists(atPath: daemon.path) { try FileManager.default.removeItem(at: daemon) }
        try FileManager.default.removeItem(at: root)
    }
    private static func resolver(suffix: String, port: Int) -> String { "\(marker)\ndomain \(suffix)\nnameserver \(resolverAddress)\nport 53\n" }
    private static func aliasInterface() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var next = list
        while let entry = next {
            if let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) {
                let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
                if value == inet_addr(resolverAddress) { return String(cString: entry.pointee.ifa_name) }
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
