import Foundation
import MorrowCore
import Darwin

struct Options {
    var positional: [String] = []
    var values: [String: String] = [:]
    var flags: Set<String> = []
    init(_ args: [String], allowedValues: Set<String> = [], allowedFlags: Set<String> = []) throws {
        var index = 0
        while index < args.count {
            let arg = args[index]
            if allowedFlags.contains(arg) { flags.insert(arg) }
            else if allowedValues.contains(arg) {
                guard index + 1 < args.count, !args[index + 1].hasPrefix("--") else { throw MorrowError.message("Missing value for \(arg).") }
                index += 1; values[arg] = args[index]
            } else if arg.hasPrefix("-") { throw MorrowError.message("Unknown option: \(arg).") }
            else { positional.append(arg) }
            index += 1
        }
    }
    func number(_ key: String, default fallback: Int) throws -> Int {
        guard let raw = values[key] else { return fallback }
        guard let value = Int(raw) else { throw MorrowError.message("\(key) must be a number.") }
        return value
    }
    func requireCount(_ count: Int, usage: String) throws {
        guard positional.count == count else { throw MorrowError.message("Usage: \(usage)") }
    }
}

let help = """
Morrow — native databases, quietly managed.

  morrow doctor                          Check Homebrew and local paths
  morrow db catalog                      List supported engines
  morrow db versions [engine]             Show native versions already installed
  morrow db channels [engine]             Find available Homebrew version channels
  morrow db install <engine> <channel>    Install a channel (17, 8.4, current, …)
  morrow db create <engine> <name>        Create a separate local instance
      --version <version-or-channel>     Choose a version; install only if missing
      --port <port>                      Default: next free engine port
      --memory <MB>                      Default: 128
      --connections <count>              Default: 100
      --autostart                        Start at macOS login
      --start                            Start after creating
  morrow db list [--json]                 List instances and current status
  morrow db start|stop|restart <name>     Control a native process
  morrow db configure <name>             Change a stopped instance
      --port <port> --memory <MB> --connections <count> --name <name>
  morrow db autostart <name> on|off       Set launch-at-login behavior
  morrow db logs <name>                   Read recent server output
  morrow db connection <name>             Print its local connection address
  morrow db remove <name>                 Remove instance; archive its data
      --delete-data                      Permanently delete this instance's data
  morrow settings                        Open the macOS Settings window

Instances listen on 127.0.0.1 and use passwordless local development accounts.
Versions are installed separately from the app. MORROW_HOME overrides data storage.
"""

func engine(_ name: String) throws -> DatabaseEngine {
    guard let engine = DatabaseEngine.parse(name) else { throw MorrowError.message("Unknown engine '\(name)'. Run morrow db catalog.") }
    return engine
}

func main() throws {
    let manager = DatabaseManager()
    var args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { print(help); return }
    args.removeFirst()
    if ["help", "--help", "-h"].contains(command) { print(help); return }
    if command == "--version" { print("Morrow 0.1.0"); return }
    if command == "settings" {
        guard args.isEmpty else { throw MorrowError.message("Usage: morrow settings") }
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundle = binary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if bundle.pathExtension == "app" {
            try CommandRunner().run("/usr/bin/open", [bundle.path, "--args", "--settings"]).checked()
        } else {
            let siblingApp = binary.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Morrow.app").path
            let candidates = ["/Applications/Morrow.app", siblingApp, FileManager.default.currentDirectoryPath + "/build/Morrow.app"]
            guard let app = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                throw MorrowError.message("Build Morrow.app with scripts/build-app.sh first.")
            }
            try CommandRunner().run("/usr/bin/open", [app, "--args", "--settings"]).checked()
        }
        return
    }
    if command == "doctor" {
        let installer = try manager.installer()
        print("Data:      \(manager.store.root.path)")
        print("Homebrew:  \(installer.executable ?? "Not found — install from https://brew.sh")")
        print("Versions:  \(try installer.installations().count) native installations")
        print("Instances: \(try manager.store.load().instances.count)")
        return
    }
    guard command == "db", let subcommand = args.first else { throw MorrowError.message("Unknown command. Run morrow --help.") }
    args.removeFirst()
    switch subcommand {
    case "catalog":
        guard args.isEmpty else { throw MorrowError.message("Usage: morrow db catalog") }
        for item in DatabaseEngine.allCases { print("\(item.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)) \(item.title) · port \(item.defaultPort)") }
    case "versions", "channels":
        guard args.count <= 1 else { throw MorrowError.message("Usage: morrow db \(subcommand) [engine]") }
        let filter = try args.first.map(engine)
        let installer = try manager.installer()
        if subcommand == "versions" {
            let versions = try installer.installations().filter { filter == nil || $0.engine == filter }
            for item in versions { print("\(item.engine.title) \(item.version) [\(item.formula)]\n  \(item.prefix)") }
            if versions.isEmpty { print("No native versions detected. Create an instance and Morrow will provision its version automatically.") }
        } else {
            for item in try installer.channels().filter({ filter == nil || $0.engine == filter }) { print("\(item.engine.title) · \(item.title)") }
        }
    case "install":
        let options = try Options(args)
        try options.requireCount(2, usage: "morrow db install <engine> <channel>")
        let selected = try engine(options.positional[0])
        print("Installing \(selected.title) \(options.positional[1]) through Homebrew…")
        let installations = try manager.install(engine: selected, channel: options.positional[1])
        for installation in installations { print("Installed: \(installation.version) [\(installation.formula)]") }
    case "create":
        let options = try Options(args, allowedValues: ["--version", "--port", "--memory", "--connections"], allowedFlags: ["--autostart", "--start"])
        try options.requireCount(2, usage: "morrow db create <engine> <name> [options]")
        let selected = try engine(options.positional[0])
        let requested = options.values["--version"] ?? "automatic"
        let defaultPort = options.values["--port"] == nil ? try manager.suggestedPort(engine: selected) : selected.defaultPort
        let instance = try manager.provision(engine: selected, version: requested, name: options.positional[1],
            port: options.number("--port", default: defaultPort),
            autoStart: options.flags.contains("--autostart"),
            memoryMB: options.number("--memory", default: 128),
            maxConnections: options.number("--connections", default: 100))
        let installation = instance.installation
        print("Created \(instance.name) · \(selected.title) \(installation.version)\n\(instance.connectionURL)")
        if options.flags.contains("--start") { try manager.start(instance.id); print("\(manager.status(instance).title)") }
    case "list", "status":
        let options = try Options(args, allowedFlags: ["--json"])
        try options.requireCount(0, usage: "morrow db list [--json]")
        let instances = try manager.store.load().instances
        if options.flags.contains("--json") {
            let rows = instances.map { ["name": $0.name, "id": $0.id.uuidString, "engine": $0.engine.rawValue, "version": $0.installation.version, "port": String($0.port), "status": manager.status($0).rawValue] }
            print(String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        } else {
            if instances.isEmpty { print("No instances yet. Run morrow db create <engine> <name>.") }
            for item in instances { print("\(item.name) · \(item.engine.title) \(item.installation.version) · :\(item.port) · \(manager.status(item).title)") }
        }
    case "configure":
        let options = try Options(args, allowedValues: ["--port", "--memory", "--connections", "--name"])
        try options.requireCount(1, usage: "morrow db configure <name> [options]")
        var instance = try manager.resolve(options.positional[0])
        instance.port = try options.number("--port", default: instance.port)
        instance.memoryMB = try options.number("--memory", default: instance.memoryMB)
        instance.maxConnections = try options.number("--connections", default: instance.maxConnections)
        instance.name = options.values["--name"] ?? instance.name
        try manager.update(instance)
        print("Saved settings for \(instance.name).")
    case "autostart":
        let options = try Options(args)
        try options.requireCount(2, usage: "morrow db autostart <name> on|off")
        guard ["on", "off"].contains(options.positional[1]) else { throw MorrowError.message("Use on or off.") }
        let instance = try manager.resolve(options.positional[0])
        try manager.setAutoStart(instance.id, enabled: options.positional[1] == "on")
        print("Launch at login: \(options.positional[1])")
    case "start", "stop", "restart", "logs", "connection", "remove":
        let options = try Options(args, allowedFlags: subcommand == "remove" ? ["--delete-data"] : [])
        try options.requireCount(1, usage: "morrow db \(subcommand) <name>")
        let instance = try manager.resolve(options.positional[0])
        switch subcommand {
        case "start": try manager.start(instance.id); print("\(instance.name): \(manager.status(instance).title)")
        case "stop": try manager.stop(instance.id); print("\(instance.name): Stopped")
        case "restart": try manager.restart(instance.id); print("\(instance.name): \(manager.status(instance).title)")
        case "logs": print(try manager.logs(instance))
        case "connection": print(instance.connectionURL)
        default:
            try manager.remove(instance.id, deleteData: options.flags.contains("--delete-data"))
            print(options.flags.contains("--delete-data") ? "Instance and data deleted." : "Instance removed. Data preserved in \(manager.store.root.path)/archives/\(instance.id.uuidString.lowercased()).")
        }
    default: throw MorrowError.message("Unknown database command '\(subcommand)'. Run morrow --help.")
    }
}

do { try main() }
catch { FileHandle.standardError.write(Data("morrow: \(error.localizedDescription)\n".utf8)); exit(1) }
