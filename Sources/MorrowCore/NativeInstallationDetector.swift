import Foundation

public struct NativeInstallationDetector: Sendable {
    public let runner: any CommandRunning
    public init(runner: any CommandRunning = CommandRunner()) { self.runner = runner }

    public func discover(existing: [Installation], directories: [String]? = nil) -> [Installation] {
        let search = directories ?? (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
            + ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin", "/usr/bin"]
            + Self.applicationDirectories()
        var result = existing
        var seen = Set(existing.map { URL(fileURLWithPath: $0.executable).resolvingSymlinksInPath().path })
        for engine in DatabaseEngine.allCases {
            for directory in search where !directory.isEmpty {
                let binary = URL(fileURLWithPath: directory).appendingPathComponent(engine.binary).resolvingSymlinksInPath()
                guard FileManager.default.isExecutableFile(atPath: binary.path), !seen.contains(binary.path) else { continue }
                let prefix = binary.deletingLastPathComponent().deletingLastPathComponent().path
                let candidate = Installation(engine: engine, formula: "external", version: "", prefix: prefix)
                if let validated = try? probe(candidate) { seen.insert(binary.path); result.append(validated) }
            }
        }
        return result.sorted { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
    }
    public func validate(_ installation: Installation) throws -> Installation {
        guard FileManager.default.isExecutableFile(atPath: installation.executable) else { throw MorrowError.message("The selected server executable is missing.") }
        if let helper = installation.initializationTool {
            guard FileManager.default.isExecutableFile(atPath: helper) else {
                throw MorrowError.message("\(installation.engine.title) is present but its required \(URL(fileURLWithPath: helper).lastPathComponent) tool is missing. Morrow has not installed a second copy.")
            }
        }
        return try probe(installation)
    }
    private static func applicationDirectories() -> [String] {
        let fm = FileManager.default
        let herd = URL(fileURLWithPath: "/Users/Shared/Herd/services")
        var paths: [String] = []
        for service in (try? fm.contentsOfDirectory(at: herd, includingPropertiesForKeys: nil)) ?? [] {
            for version in (try? fm.contentsOfDirectory(at: service, includingPropertiesForKeys: nil)) ?? [] {
                paths.append(version.appendingPathComponent("bin").path)
            }
        }
        let postgres = URL(fileURLWithPath: "/Applications/Postgres.app/Contents/Versions")
        for version in (try? fm.contentsOfDirectory(at: postgres, includingPropertiesForKeys: nil)) ?? [] {
            paths.append(version.appendingPathComponent("bin").path)
        }
        return paths
    }
    private func probe(_ installation: Installation) throws -> Installation {
        let args = [.mysql, .mariadb].contains(installation.engine) ? ["--no-defaults", "--version"] : installation.engine == .memcached ? ["-V"] : ["--version"]
        let output = try runner.run(installation.executable, args, environment: [:]).checked()
        guard let version = Self.version(from: output, engine: installation.engine) else {
            throw MorrowError.message("The executable at \(installation.executable) did not identify itself as a compatible \(installation.engine.title) server.")
        }
        return Installation(engine: installation.engine, formula: installation.formula, version: version, prefix: installation.prefix)
    }
    public static func version(from output: String, engine: DatabaseEngine) -> String? {
        let lower = output.lowercased()
        let identifies: Bool
        switch engine {
        case .postgresql: identifies = lower.contains("postgresql")
        case .mysql: identifies = lower.contains("mysqld") && !lower.contains("mariadb")
        case .mariadb: identifies = lower.contains("mariadb")
        case .mongodb: identifies = lower.contains("db version")
        case .redis: identifies = lower.contains("redis server")
        case .valkey: identifies = lower.contains("valkey server")
        case .memcached: identifies = lower.contains("memcached")
        }
        guard identifies,
              let regex = try? NSRegularExpression(pattern: "(?:PostgreSQL\\)\\s*|Ver\\s+|db version v|v=|memcached\\s+)([0-9]+(?:\\.[0-9]+){1,3})", options: .caseInsensitive),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else { return nil }
        return String(output[range])
    }
}
