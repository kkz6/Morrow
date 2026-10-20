import Foundation

public struct HomebrewInstaller: Sendable {
    public let runner: any CommandRunning
    public let configuredPath: String
    public init(runner: any CommandRunning = CommandRunner(), configuredPath: String = "") {
        self.runner = runner; self.configuredPath = configuredPath
    }
    public var executable: String? {
        let candidates = configuredPath.isEmpty ? ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] : [configuredPath]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    /// Legacy discovery reads existing files without executing a package manager.
    public var searchPrefixes: [URL] {
        let paths = configuredPath.isEmpty ? ["/opt/homebrew", "/usr/local"]
            : [URL(fileURLWithPath: configuredPath).deletingLastPathComponent().deletingLastPathComponent().path]
        return paths.map { URL(fileURLWithPath: $0) }
    }
    public func installations() throws -> [Installation] {
        var result: [Installation] = []
        let fm = FileManager.default
        for prefix in searchPrefixes {
            let cellar = prefix.appendingPathComponent("Cellar")
            for folder in (try? fm.contentsOfDirectory(at: cellar, includingPropertiesForKeys: nil)) ?? [] {
                guard let engine = DatabaseEngine.allCases.first(where: { folder.lastPathComponent == $0.formulaBase || folder.lastPathComponent.hasPrefix($0.formulaBase + "@") }) else { continue }
                for version in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                    guard fm.isExecutableFile(atPath: version.appendingPathComponent("bin/" + engine.binary).path) else { continue }
                    result.append(Installation(engine: engine, formula: folder.lastPathComponent, version: version.lastPathComponent, prefix: version.path))
                }
            }
        }
        return NativeInstallationDetector(runner: runner).discover(existing: result)
    }
    public func channels() throws -> [VersionChannel] { [] }
    public func install(engine: DatabaseEngine, channel: String) throws -> [Installation] {
        let found = try installations().filter { $0.engine == engine }
        if let existing = found.first(where: { Self.matches($0, request: channel) }) {
            return [try NativeInstallationDetector(runner: runner).validate(existing)]
        }
        throw MorrowError.message("New installations use Morrow's portable distribution catalog.")
    }
    public static func matches(_ installation: Installation, request: String) -> Bool {
        if request == "automatic" { return true }
        let requested = request.replacingOccurrences(of: "mongodb/brew/", with: "")
        let formula = installation.formula.replacingOccurrences(of: "mongodb/brew/", with: "")
        let series = requested.contains("@") ? requested.components(separatedBy: "@").last! : requested
        guard series.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil else { return formula == requested }
        let version = installation.version.components(separatedBy: "_").first ?? installation.version
        return version == series || version.hasPrefix(series + ".")
    }
    public static func isAllowedFormula(_ formula: String, engine: DatabaseEngine) -> Bool {
        let name = formula.replacingOccurrences(of: "mongodb/brew/", with: "")
        guard formula == name || (engine == .mongodb && formula == "mongodb/brew/" + name) else { return false }
        return name.range(of: "^\(engine.formulaBase)(@[0-9]+(\\.[0-9]+)*)?$", options: .regularExpression) != nil
    }
}
