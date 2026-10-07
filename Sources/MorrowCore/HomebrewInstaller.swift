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
    public func requireExecutable() throws -> String {
        guard let executable else {
            throw MorrowError.message("Install Homebrew from brew.sh, or set its executable path in Settings → General.")
        }
        return executable
    }
    public func installations() throws -> [Installation] {
        NativeInstallationDetector(runner: runner).discover(existing: try cellarInstallations())
    }
    private func cellarInstallations() throws -> [Installation] {
        guard let executable else { return [] }
        let prefix = URL(fileURLWithPath: executable).deletingLastPathComponent().deletingLastPathComponent()
        let cellar = prefix.appendingPathComponent("Cellar")
        guard FileManager.default.fileExists(atPath: cellar.path) else { return [] }
        var installations: [Installation] = []
        for directory in try FileManager.default.contentsOfDirectory(at: cellar, includingPropertiesForKeys: nil) {
            guard let engine = DatabaseEngine.allCases.first(where: {
                directory.lastPathComponent == $0.formulaBase || directory.lastPathComponent.hasPrefix($0.formulaBase + "@")
            }) else { continue }
            for version in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                let binary = version.appendingPathComponent("bin/\(engine.binary)")
                guard FileManager.default.isExecutableFile(atPath: binary.path) else { continue }
                let formula = engine == .mongodb ? "mongodb/brew/\(directory.lastPathComponent)" : directory.lastPathComponent
                installations.append(Installation(engine: engine, formula: formula, version: version.lastPathComponent, prefix: version.path))
            }
        }
        return installations.sorted { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
    }
    public func channels() throws -> [VersionChannel] {
        let brew = try requireExecutable()
        let output = try runner.run(brew, ["search", "--formula", "/^(postgresql|mysql|mariadb|redis|valkey|memcached)(@[0-9.]+)?$/"], environment: [:]).checked()
        let names = output.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var channels: [VersionChannel] = names.compactMap { name in
            guard let engine = DatabaseEngine.allCases.first(where: { name == $0.formulaBase || name.hasPrefix($0.formulaBase + "@") }),
                  Self.isAllowedFormula(name, engine: engine) else { return nil }
            return VersionChannel(engine: engine, formula: name, version: name.components(separatedBy: "@").dropFirst().first ?? "Current")
        }
        // Homebrew search includes disabled historical formulae. Read current
        // metadata so the UI only offers channels that can still be installed.
        if !channels.isEmpty {
            let metadata = try runner.run(brew, ["info", "--json=v2", "--formula"] + channels.map(\.formula), environment: [:]).checked()
            if let data = metadata.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let formulae = json["formulae"] as? [[String: Any]] {
                channels = formulae.compactMap { item in
                    guard item["disabled"] as? Bool != true, let name = item["name"] as? String,
                          let channel = channels.first(where: { $0.formula == name }) else { return nil }
                    let version = (item["versions"] as? [String: Any])?["stable"] as? String ?? channel.version
                    return VersionChannel(engine: channel.engine, formula: name, version: version, deprecated: item["deprecated"] as? Bool ?? false)
                }
            }
        }
        // MongoDB's official tap is added only when the user installs MongoDB.
        // Query its public formula listing without mutating Homebrew's taps.
        if let url = URL(string: "https://api.github.com/repos/mongodb/homebrew-brew/contents/Formula"),
           let data = try? Data(contentsOf: url),
           let files = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for file in files {
                guard let filename = file["name"] as? String, filename.hasSuffix(".rb") else { continue }
                let name = String(filename.dropLast(3))
                guard Self.isAllowedFormula(name, engine: .mongodb) else { continue }
                channels.append(VersionChannel(engine: .mongodb, formula: "mongodb/brew/\(name)",
                    version: name.components(separatedBy: "@").dropFirst().first ?? "Current"))
            }
        }
        if !channels.contains(where: { $0.engine == .mongodb }) {
            channels.append(VersionChannel(engine: .mongodb, formula: "mongodb/brew/mongodb-community", version: "Current"))
        }
        return channels.sorted {
            if $0.engine != $1.engine { return $0.engine.rawValue < $1.engine.rawValue }
            return $0.version.localizedStandardCompare($1.version) == .orderedDescending
        }
    }
    public func install(engine: DatabaseEngine, channel: String) throws -> [Installation] {
        guard ["automatic", "current", "latest"].contains(channel) || Self.isAllowedFormula(channel, engine: engine)
            || channel.range(of: "^[0-9]+(\\.[0-9]+)*$", options: .regularExpression) != nil else {
            throw MorrowError.message("Invalid version channel: \(channel).")
        }
        let found = try installations().filter { $0.engine == engine }
        if channel == "automatic", let existing = found.first {
            return [try NativeInstallationDetector(runner: runner).validate(existing)]
        }
        if channel != "current" && channel != "latest" && channel != "automatic",
           let existing = found.first(where: { Self.matches($0, request: channel) }) {
            let validated = try NativeInstallationDetector(runner: runner).validate(existing)
            guard Self.matches(validated, request: channel) else { throw MorrowError.message("The existing binary reports a different version than requested. No duplicate was installed.") }
            return [validated]
        }
        let brew = try requireExecutable()
        let formula: String
        if channel == "current" || channel == "latest" || channel == "automatic" { formula = engine.formulaBase }
        else if channel.hasPrefix(engine.formulaBase) || channel.hasPrefix("mongodb/brew/") { formula = channel }
        else { formula = engine.formulaBase + "@" + channel }
        guard Self.isAllowedFormula(formula, engine: engine) else { throw MorrowError.message("Invalid version channel: \(channel).") }
        // Resolve Homebrew aliases and current release channels before deciding
        // whether an install is needed (postgresql may resolve to postgresql@18).
        let target = engine == .mongodb && !formula.contains("/") ? "mongodb/brew/\(formula)" : formula
        if engine == .mongodb {
            try runner.run(brew, ["tap", "mongodb/brew"], environment: [:]).checked()
        }
        let metadata = try runner.run(brew, ["info", "--json=v2", "--formula", target], environment: [:]).checked()
        guard let data = metadata.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = (json["formulae"] as? [[String: Any]])?.first,
              let canonical = item["name"] as? String,
              item["disabled"] as? Bool != true else {
            throw MorrowError.message("That version channel is unavailable. Choose a supported release.")
        }
        if let existing = found.first(where: { Self.matches($0, request: canonical) }) {
            let validated = try NativeInstallationDetector(runner: runner).validate(existing)
            guard Self.matches(validated, request: canonical) else { throw MorrowError.message("The existing server does not match the requested release series. No duplicate was installed.") }
            return [validated]
        }
        try runner.run(brew, ["install", "--formula", target], environment: [:]).checked()
        let installed = try installations().filter { $0.engine == engine && Self.matches($0, request: canonical) }
        guard !installed.isEmpty else { throw MorrowError.message("Homebrew completed, but Morrow could not find the native server binary.") }
        return try installed.map {
            let validated = try NativeInstallationDetector(runner: runner).validate($0)
            guard Self.matches(validated, request: canonical) else { throw MorrowError.message("The installed server reports an unexpected version.") }
            return validated
        }
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
