import Foundation

public enum RuntimeEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case php, go, flutter, node, python, ruby
    public var id: String { rawValue }
    public var title: String {
        switch self { case .php: return "PHP"; case .go: return "Go"; case .flutter: return "Flutter"; case .node: return "Node.js"; case .python: return "Python"; case .ruby: return "Ruby" }
    }
    public var commands: [String] {
        switch self {
        case .php: return ["php", "phpize", "php-config"]
        case .go: return ["go", "gofmt"]
        case .flutter: return ["flutter", "dart"]
        case .node: return ["node", "npm", "npx", "corepack"]
        case .python: return ["python", "python3", "pip", "pip3"]
        case .ruby: return ["ruby", "gem", "irb", "bundle"]
        }
    }
    var binary: String { self == .python ? "python3" : rawValue }
    var formulaBase: String { self == .python ? "python" : rawValue }
    public var isCask: Bool { self == .flutter }
    public static func parse(_ value: String) -> Self? {
        switch value.lowercased() { case "nodejs": return .node; case "python3": return .python; default: return Self(rawValue: value.lowercased()) }
    }
    func allows(_ formula: String) -> Bool {
        formula.range(of: "^\(formulaBase)(@[0-9]+(\\.[0-9]+)*)?$", options: .regularExpression) != nil
    }
}

public struct RuntimeInstallation: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(engine.rawValue):\(version):\(executable)" }
    public let engine: RuntimeEngine
    public let formula: String
    public let version: String
    public let prefix: String
    public let executable: String
    public let source: String
    public var binDirectory: String { URL(fileURLWithPath: executable).deletingLastPathComponent().path }
    public init(engine: RuntimeEngine, formula: String, version: String, prefix: String, executable: String, source: String) {
        self.engine = engine; self.formula = formula; self.version = version; self.prefix = prefix; self.executable = executable; self.source = source
    }
    public func command(_ name: String) -> String? {
        guard engine.commands.contains(name) else { return nil }
        if name == engine.binary || (engine == .python && name == "python") { return executable }
        let candidates = [binDirectory + "/" + name, prefix + "/libexec/bin/" + name]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

public struct RuntimeChannel: Identifiable, Sendable {
    public var id: String { formula }
    public let engine: RuntimeEngine
    public let formula: String
    public let version: String
}

public struct RuntimeUpdate: Codable, Identifiable, Sendable {
    public var id: String { installationID }
    public let installationID: String
    public let engine: RuntimeEngine
    public let currentVersion: String
    public let availableVersion: String?
    public let canUpgrade: Bool
    public let message: String
}

/// Native runtimes share the same Homebrew dependency and store as databases.
/// Selecting a version affects only Morrow's commands, never brew link or shell files.
public struct RuntimeManager: Sendable {
    public let store: StateStore
    public let runner: any CommandRunning
    public init(store: StateStore = StateStore(), runner: any CommandRunning = CommandRunner()) { self.store = store; self.runner = runner }
    func installer() throws -> HomebrewInstaller { HomebrewInstaller(runner: runner, configuredPath: try store.load().preferences.homebrewPath) }
    public var shimDirectory: URL { store.root.appendingPathComponent("bin") }
    public func channels(_ engine: RuntimeEngine) throws -> [RuntimeChannel] {
        let installer = try installer()
        if engine.isCask {
            let package = try installer.package("flutter", cask: true)
            return [RuntimeChannel(engine: engine, formula: "flutter", version: package.version)]
        }
        let output = try runner.run(installer.requireExecutable(), ["search", "--formula", "/^\(engine.formulaBase)(@[0-9.]+)?$/"], environment: [:]).checked()
        let names = output.components(separatedBy: .whitespacesAndNewlines).filter { engine.allows($0) }
        var seen = Set<String>()
        return names.compactMap { name in
            // Disabled formulae are omitted rather than offered as installable.
            guard let package = try? installer.package(name), seen.insert(package.name).inserted else { return nil }
            return RuntimeChannel(engine: engine, formula: package.name, version: package.packageVersion)
        }.sorted { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
    }
    public func installations() throws -> [RuntimeInstallation] {
        let fm = FileManager.default
        var result = try store.load().tools
        if let brew = try installer().executable {
            let root = URL(fileURLWithPath: brew).deletingLastPathComponent().deletingLastPathComponent()
            let cellar = root.appendingPathComponent("Cellar")
            for formula in (try? fm.contentsOfDirectory(at: cellar, includingPropertiesForKeys: nil)) ?? [] {
                guard let engine = RuntimeEngine.allCases.first(where: { !$0.isCask && $0.allows(formula.lastPathComponent) }) else { continue }
                for version in (try? fm.contentsOfDirectory(at: formula, includingPropertiesForKeys: nil)) ?? [] {
                    if let item = try? probe(engine, prefix: version.path, formula: formula.lastPathComponent, source: "homebrew", packageVersion: version.lastPathComponent) { result.append(item) }
                }
            }
            for prefix in [root.appendingPathComponent("share/flutter").path, root.appendingPathComponent("opt/flutter").path] {
                if let item = try? probe(.flutter, prefix: prefix, formula: "flutter", source: "homebrew") { result.append(item) }
            }
        }
        var paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        paths += ["/opt/homebrew/bin", "/usr/local/bin", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Herd/bin").path]
        let herd = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Herd/bin")
        let phpCandidates = ((try? fm.contentsOfDirectory(at: herd, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.range(of: "^php[0-9]+$", options: .regularExpression) != nil }
        for engine in RuntimeEngine.allCases {
            let binaries = paths.filter { !$0.isEmpty && !URL(fileURLWithPath: $0).standardizedFileURL.path.hasPrefix(shimDirectory.standardizedFileURL.path) }
                .map { URL(fileURLWithPath: $0).appendingPathComponent(engine.binary) } + (engine == .php ? phpCandidates : [])
            for candidate in binaries {
                let binary = candidate.resolvingSymlinksInPath()
                guard fm.isExecutableFile(atPath: binary.path), !result.contains(where: { URL(fileURLWithPath: $0.executable).resolvingSymlinksInPath().path == binary.path }) else { continue }
                let prefix = binary.deletingLastPathComponent().deletingLastPathComponent().path
                if let item = try? probe(engine, prefix: prefix, formula: "external", source: "external", binary: binary.path) { result.append(item) }
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }.sorted { $0.version.localizedStandardCompare($1.version) == .orderedDescending }
    }
    @discardableResult public func install(_ engine: RuntimeEngine, version: String = "automatic") throws -> RuntimeInstallation {
        try store.operation { try installUnlocked(engine, version: version) }
    }
    private func installUnlocked(_ engine: RuntimeEngine, version: String) throws -> RuntimeInstallation {
        let found = try installations().filter { $0.engine == engine }
        if version == "automatic", let existing = found.first {
            let valid = try validate(existing); try register(valid); return valid
        }
        if !["current", "latest", "automatic"].contains(version), let existing = found.first(where: { matches($0, request: version) }) {
            let valid = try validate(existing)
            try register(valid); return valid
        }
        guard ["current", "latest", "automatic"].contains(version) || engine.allows(version) || SoftwareVersion(version) != nil else { throw MorrowError.message("Invalid runtime version or channel.") }
        let catalog = try channels(engine)
        guard let channel = catalog.first(where: {
            ["current", "latest", "automatic"].contains(version) ? ($0.formula == engine.formulaBase || catalog.count == 1)
                : ($0.formula == version || Self.versionMatches($0.version, version) || $0.formula == engine.formulaBase + "@" + version)
        }) else { throw MorrowError.message("Homebrew does not provide that release. Choose an available channel or an existing installation.") }
        if let existing = found.first(where: { $0.version == channel.version }) {
            let valid = try validate(existing); try register(valid); return valid
        }
        if engine == .flutter, let previous = found.first(where: { $0.formula == "flutter" && $0.source == "homebrew" }) {
            let retained = try retainFlutter(previous)
            try register(retained)
            try installer().upgradePackage(installer().package("flutter", cask: true))
        } else {
            try runner.run(installer().requireExecutable(), ["install", engine.isCask ? "--cask" : "--formula", channel.formula], environment: [:]).checked()
        }
        guard let installed = try installations().first(where: { $0.engine == engine && $0.formula == channel.formula && $0.version == channel.version }) else {
            throw MorrowError.message("Homebrew completed but the requested runtime was not detected. Refresh before trying again.")
        }
        let valid = try validate(installed)
        let retained = engine == .flutter ? try retainFlutter(valid) : valid
        try register(retained); return retained
    }
    public func use(_ installation: RuntimeInstallation, cli: URL) throws {
        try store.operation {
            let actual = try validate(installation)
            let valid = actual.engine == .flutter ? try retainFlutter(actual) : actual
            guard FileManager.default.isExecutableFile(atPath: cli.path) else { throw MorrowError.message("The morrow CLI is missing. Rebuild or reinstall the app.") }
            try writeShims(valid, cli: cli.resolvingSymlinksInPath())
            try register(valid)
            try store.update { $0.toolDefaults[valid.engine.rawValue] = valid.id }
        }
    }
    public func resolve(_ engine: RuntimeEngine, version: String? = nil) throws -> RuntimeInstallation {
        let all = try installations().filter { $0.engine == engine }
        if let version, let item = all.first(where: { $0.id == version || matches($0, request: version) }) { return try validate(item) }
        if version != nil { throw MorrowError.message("That runtime version was not found.") }
        let state = try store.load()
        guard let id = state.toolDefaults[engine.rawValue], let selected = state.tools.first(where: { $0.id == id }) else {
            throw MorrowError.message("No default \(engine.title) version. Run morrow tool use \(engine.rawValue) <version>.")
        }
        return try validate(selected)
    }
    public func updates(refresh: Bool = false) throws -> [RuntimeUpdate] {
        let installer = try installer()
        if refresh { try installer.refreshMetadata() }
        return try store.load().tools.map { item in
            guard item.engine.allows(item.formula) else { return RuntimeUpdate(installationID: item.id, engine: item.engine, currentVersion: item.version, availableVersion: nil, canUpgrade: false, message: "External installation — use its original installer.") }
            do {
                let package = try installer.package(item.formula, cask: item.engine.isCask)
                let available = SoftwareVersion(package.packageVersion), current = SoftwareVersion(item.version)
                let newer = available != nil && current != nil && available! > current!
                return RuntimeUpdate(installationID: item.id, engine: item.engine, currentVersion: item.version, availableVersion: package.packageVersion, canUpgrade: newer, message: newer ? "Update available" : "Up to date")
            } catch { return RuntimeUpdate(installationID: item.id, engine: item.engine, currentVersion: item.version, availableVersion: nil, canUpgrade: false, message: error.localizedDescription) }
        }
    }
    @discardableResult public func upgrade(_ item: RuntimeInstallation, cli: URL) throws -> RuntimeInstallation {
        try store.operation {
            guard item.engine.allows(item.formula) else { throw MorrowError.message("Update external runtimes with their original installer.") }
            let package = try installer().package(item.formula, cask: item.engine.isCask)
            guard let old = SoftwareVersion(item.version), let next = SoftwareVersion(package.packageVersion), next > old else { throw MorrowError.message("No update is available.") }
            let wasDefault = try store.load().toolDefaults[item.engine.rawValue] == item.id
            // Flutter's cask replaces its global SDK. Preserve the selected SDK
            // inside Morrow before Homebrew removes that directory.
            if item.engine == .flutter {
                let previous = try retainFlutter(item)
                try register(previous)
                if try store.load().toolDefaults[item.engine.rawValue] == item.id {
                    try writeShims(previous, cli: cli.resolvingSymlinksInPath())
                    try store.update { $0.toolDefaults[item.engine.rawValue] = previous.id }
                }
            }
            try installer().upgradePackage(package)
            guard let installed = try installations().first(where: { $0.engine == item.engine && $0.formula == package.name && $0.version == package.packageVersion }) else { throw MorrowError.message("The updated runtime could not be found.") }
            let valid = try validate(installed)
            let retained = item.engine == .flutter ? try retainFlutter(valid) : valid
            try register(retained)
            if wasDefault {
                try writeShims(retained, cli: cli.resolvingSymlinksInPath())
                try store.update { $0.toolDefaults[item.engine.rawValue] = retained.id }
            }
            return retained
        }
    }
    /// Remove a selection from Morrow, leaving shared packages on the machine.
    public func forget(_ item: RuntimeInstallation) throws {
        try store.operation {
            try store.update { state in
                state.tools.removeAll { $0.id == item.id }
                if state.toolDefaults[item.engine.rawValue] == item.id { state.toolDefaults.removeValue(forKey: item.engine.rawValue) }
            }
        }
    }
    public func launch(_ engine: RuntimeEngine, arguments: [String], command: String? = nil) throws -> Int32 {
        let item = try resolve(engine)
        let name = command ?? engine.binary
        guard let executable = item.command(name), FileManager.default.isExecutableFile(atPath: executable) else { throw MorrowError.message("The selected release does not include \(name).") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = item.binDirectory + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        if engine == .go {
            environment.removeValue(forKey: "GOROOT")
            if FileManager.default.fileExists(atPath: item.prefix + "/libexec/pkg") { environment["GOROOT"] = item.prefix + "/libexec" }
        }
        process.environment = environment
        process.standardInput = FileHandle.standardInput; process.standardOutput = FileHandle.standardOutput; process.standardError = FileHandle.standardError
        try process.run(); process.waitUntilExit(); return process.terminationStatus
    }
    private func matches(_ item: RuntimeInstallation, request: String) -> Bool { item.id == request || item.formula == request || Self.versionMatches(item.version, request) }
    private static func versionMatches(_ installed: String, _ requested: String) -> Bool {
        guard SoftwareVersion(requested) != nil else { return false }
        return installed == requested || installed.hasPrefix(requested + ".")
    }
    private func register(_ item: RuntimeInstallation) throws {
        try store.update { state in
            if item.engine == .flutter && item.source == "morrow" {
                let replaced = state.tools.filter { $0.engine == .flutter && $0.version == item.version && $0.id != item.id }.map(\.id)
                if let selected = state.toolDefaults[item.engine.rawValue], replaced.contains(selected) { state.toolDefaults[item.engine.rawValue] = item.id }
                state.tools.removeAll { replaced.contains($0.id) }
            }
            if !state.tools.contains(where: { $0.id == item.id }) { state.tools.append(item) }
        }
    }
    private func validate(_ item: RuntimeInstallation) throws -> RuntimeInstallation {
        let actual = try probe(item.engine, prefix: item.prefix, formula: item.formula, source: item.source, packageVersion: item.version, binary: item.executable)
        guard actual.version == item.version else { throw MorrowError.message("The runtime's actual version changed. Refresh your selection.") }
        return actual
    }
    private func probe(_ engine: RuntimeEngine, prefix: String, formula: String, source: String, packageVersion: String? = nil, binary: String? = nil) throws -> RuntimeInstallation {
        let fm = FileManager.default
        let candidates = [prefix + "/bin/" + engine.binary, prefix + "/libexec/bin/" + engine.binary]
        let executable = binary ?? candidates.first { fm.isExecutableFile(atPath: $0) } ?? candidates[0]
        guard fm.isExecutableFile(atPath: executable) else { throw MorrowError.message("The \(engine.title) executable is missing.") }
        let version: String
        if engine == .flutter {
            // Reading SDK metadata avoids bootstrapping Flutter during discovery.
            let root = URL(fileURLWithPath: executable).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
            if let data = try? Data(contentsOf: root.appendingPathComponent("bin/cache/flutter.version.json")),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let release = json["frameworkVersion"] as? String, SoftwareVersion(release) != nil { version = release }
            else if let release = try? String(contentsOf: root.appendingPathComponent("version"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), SoftwareVersion(release) != nil { version = release }
            else { throw MorrowError.message("Flutter SDK metadata is missing. Run flutter --version once, then refresh Morrow.") }
        } else {
            let result = try runner.run(executable, engine == .go ? ["version"] : ["--version"], environment: [:]).checked()
            let pattern: String
            switch engine {
            case .php: pattern = "PHP ([0-9]+(?:\\.[0-9]+)+)"
            case .go: pattern = "go version go([0-9]+(?:\\.[0-9]+)+)"
            case .node: pattern = "^v([0-9]+(?:\\.[0-9]+)+)"
            case .python: pattern = "Python ([0-9]+(?:\\.[0-9]+)+)"
            case .ruby: pattern = "ruby ([0-9]+(?:\\.[0-9]+)+)"
            case .flutter: pattern = ""
            }
            let regex = try NSRegularExpression(pattern: pattern)
            guard let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)), let range = Range(match.range(at: 1), in: result) else { throw MorrowError.message("The executable did not identify itself as \(engine.title).") }
            version = String(result[range])
        }
        let recorded = packageVersion.flatMap(SoftwareVersion.init)
        let actual = SoftwareVersion(version)
        let release = recorded?.components == actual?.components ? (packageVersion ?? version) : version
        return RuntimeInstallation(engine: engine, formula: formula, version: release, prefix: prefix, executable: executable, source: source)
    }
    private func retainFlutter(_ item: RuntimeInstallation) throws -> RuntimeInstallation {
        let target = store.root.appendingPathComponent("tools/flutter/\(item.version)")
        let source = URL(fileURLWithPath: item.executable).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        if source.standardizedFileURL != target.standardizedFileURL && !FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let staging = target.deletingLastPathComponent().appendingPathComponent(".staging-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staging) }
            try FileManager.default.copyItem(at: source, to: staging)
            try FileManager.default.moveItem(at: staging, to: target)
        }
        return try probe(.flutter, prefix: target.path, formula: "flutter", source: "morrow", packageVersion: item.version)
    }
    private func writeShims(_ item: RuntimeInstallation, cli: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: shimDirectory.path), try shimDirectory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw MorrowError.message("Morrow's command directory must not be a symbolic link.")
        }
        try fm.createDirectory(at: shimDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let owner = "# Managed by Morrow: \(item.engine.rawValue)"
        for command in item.engine.commands {
            let url = shimDirectory.appendingPathComponent(command)
            if fm.fileExists(atPath: url.path) || (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil {
                guard let contents = try? String(contentsOf: url, encoding: .utf8), contents.components(separatedBy: .newlines).contains(owner), (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw MorrowError.message("Morrow will not overwrite the existing \(command) command at \(url.path).") }
            }
        }
        for command in item.engine.commands where item.command(command) != nil {
            let text = "#!/bin/sh\n\(owner)\nexec \(quote(cli.path)) tool exec \(item.engine.rawValue) --command \(command) -- \"$@\"\n"
            let url = shimDirectory.appendingPathComponent(command)
            try Data(text.utf8).write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
    }
}
