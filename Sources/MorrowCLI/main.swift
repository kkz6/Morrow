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
Morrow — databases and development runtimes.

  morrow doctor                          Check Homebrew and local paths
  morrow mail create <name>               Create a local SMTP testing server
      --smtp-port <port>                 Default: next free port from 1025
      --http-port <port>                 Default: next free port from 8025
      --version <version>                Detected version or current; reuses by default
      --start --autostart                Start now or at macOS login
  morrow mail list [--json]               Show mail servers and actual status
  morrow mail start|stop|restart <name>   Control a mail server
  morrow mail inbox <name>                Open its browser inbox
  morrow mail smtp|config|logs <name>     Print SMTP URL, app settings, or logs
  morrow mail configure <name>            Edit a stopped mail server
      --smtp-port <port> --http-port <port> --name <name> --autostart on|off
  morrow mail remove <name>               Remove server; preserve its messages
      --delete-messages                  Permanently delete its captured messages
  morrow sync enable [--folder <path>]    Enable iCloud Drive workspace recipes
      --auto-install                     Set up missing services on this Mac
  morrow sync disable                    Disable workspace sync on this Mac
  morrow sync status                     Show the last workspace sync result
  morrow sync now [--retry] [--json]      Reconcile settings and missing services
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
  morrow db updates [name] [--refresh]    Check maintenance and package updates
      --json                             Print structured update results
  morrow db upgrade <name>               Back up and update a compatible instance
  morrow db recover <name>               Recover an interrupted database update
  morrow tool catalog                    List supported development runtimes
  morrow tool channels <runtime>          Show Homebrew release channels
  morrow tool versions [runtime]          Discover existing runtime versions
  morrow tool install <runtime> [version] Reuse or install a version
  morrow tool use <runtime> <version>     Select the default for Morrow commands
  morrow tool list [--json]               Show tracked runtimes and defaults
  morrow tool updates [--refresh]         Check tracked runtime updates
  morrow tool upgrade <runtime> [version] Install an update; move selected default
  morrow tool remove <runtime> <version>  Forget a version; preserve shared files
  morrow tool exec <runtime> -- <args>    Run the selected runtime interactively
  morrow tool shell                      Print Morrow's runtime PATH setup
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
    if command == "mail" { try mailMain(args, manager: MailManager(store: manager.store, runner: manager.runner)); return }
    if command == "sync" { try syncMain(args, manager: WorkspaceSync(store: manager.store, runner: manager.runner)); return }
    if command == "tool" { try toolsMain(args, manager: RuntimeManager(store: manager.store, runner: manager.runner)); return }
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
    case "updates":
        let options = try Options(args, allowedFlags: ["--json", "--refresh"])
        guard options.positional.count <= 1 else { throw MorrowError.message("Usage: morrow db updates [name] [--refresh] [--json]") }
        let selected = try options.positional.first.map { try manager.resolve($0).id }
        let updates = try manager.databaseUpdates(refresh: options.flags.contains("--refresh")).filter { selected == nil || $0.instanceID == selected }
        if options.flags.contains("--json") { try printJSON(updates) }
        else { for item in updates { print("\(item.name): \(item.currentVersion) → \(item.availableVersion ?? "—") · \(item.message)") } }
    case "upgrade", "recover":
        let options = try Options(args)
        try options.requireCount(1, usage: "morrow db \(subcommand) <name>")
        let instance = try manager.resolve(options.positional[0])
        if subcommand == "recover" { try manager.recoverUpdate(instance.id); print("Recovered \(instance.name).") }
        else {
            print("Backing up and updating \(instance.name)…")
            let updated = try manager.upgrade(instance.id)
            print("Updated \(updated.name): \(updated.installation.version). Backup preserved under \(manager.store.root.path)/backups.")
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

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

func toolsMain(_ args: [String], manager: RuntimeManager) throws {
    guard let action = args.first else { throw MorrowError.message("Run morrow tool catalog or morrow --help.") }
    let remaining = Array(args.dropFirst())
    let cli = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    func runtime(_ value: String) throws -> RuntimeEngine {
        guard let selected = RuntimeEngine.parse(value) else { throw MorrowError.message("Unknown runtime. Run morrow tool catalog.") }; return selected
    }
    switch action {
    case "catalog":
        guard remaining.isEmpty else { throw MorrowError.message("Usage: morrow tool catalog") }
        for item in RuntimeEngine.allCases { print("\(item.rawValue) · \(item.title) · \(item.isCask ? "Homebrew cask" : "Homebrew formula")") }
    case "channels":
        let options = try Options(remaining); try options.requireCount(1, usage: "morrow tool channels <runtime>")
        for item in try manager.channels(runtime(options.positional[0])) { print("\(item.formula) · \(item.version)") }
    case "versions":
        let options = try Options(remaining)
        guard options.positional.count <= 1 else { throw MorrowError.message("Usage: morrow tool versions [runtime]") }
        let filter = try options.positional.first.map(runtime)
        for item in try manager.installations().filter({ filter == nil || $0.engine == filter }) { print("\(item.engine.title) \(item.version) [\(item.source)]\n  \(item.executable)") }
    case "install":
        let options = try Options(remaining)
        guard (1...2).contains(options.positional.count) else { throw MorrowError.message("Usage: morrow tool install <runtime> [version-or-channel]") }
        let selected = try runtime(options.positional[0])
        let item = try manager.install(selected, version: options.positional.count == 2 ? options.positional[1] : "automatic")
        print("Ready: \(selected.title) \(item.version). Run morrow tool use \(selected.rawValue) \(item.version) to select it.")
    case "use", "remove":
        let options = try Options(remaining); try options.requireCount(2, usage: "morrow tool \(action) <runtime> <version>")
        let selected = try runtime(options.positional[0]); let item = try manager.resolve(selected, version: options.positional[1])
        if action == "use" { try manager.use(item, cli: cli); print("Selected \(selected.title) \(item.version).\nRun morrow tool shell for PATH setup, or morrow tool exec \(selected.rawValue) -- <args>.") }
        else { try manager.forget(item); print("Removed from Morrow. Runtime files remain available on this Mac.") }
    case "list":
        let options = try Options(remaining, allowedFlags: ["--json"]); try options.requireCount(0, usage: "morrow tool list [--json]")
        let state = try manager.store.load()
        if options.flags.contains("--json") { try printJSON(state.tools) }
        else {
            if state.tools.isEmpty { print("No tracked runtimes. Run morrow tool install <runtime> or morrow tool use <runtime> <version>.") }
            for item in state.tools { print("\(item.engine.title) \(item.version)\(state.toolDefaults[item.engine.rawValue] == item.id ? " · Default" : "") [\(item.source)]") }
        }
    case "updates":
        let options = try Options(remaining, allowedFlags: ["--refresh", "--json"]); try options.requireCount(0, usage: "morrow tool updates [--refresh] [--json]")
        let updates = try manager.updates(refresh: options.flags.contains("--refresh"))
        if options.flags.contains("--json") { try printJSON(updates) }
        else { for item in updates { print("\(item.engine.title): \(item.currentVersion) → \(item.availableVersion ?? "—") · \(item.message)") } }
    case "upgrade":
        let options = try Options(remaining)
        guard (1...2).contains(options.positional.count) else { throw MorrowError.message("Usage: morrow tool upgrade <runtime> [version]") }
        let selected = try runtime(options.positional[0])
        let item = try manager.resolve(selected, version: options.positional.count == 2 ? options.positional[1] : nil)
        let upgraded = try manager.upgrade(item, cli: cli); print("Updated \(selected.title): \(upgraded.version).")
    case "exec":
        guard let separator = remaining.firstIndex(of: "--") else { throw MorrowError.message("Usage: morrow tool exec <runtime> [--command <name>] -- <args>") }
        let options = try Options(Array(remaining[..<separator]), allowedValues: ["--command"])
        try options.requireCount(1, usage: "morrow tool exec <runtime> [--command <name>] -- <args>")
        exit(try manager.launch(runtime(options.positional[0]), arguments: Array(remaining.dropFirst(separator + 1)), command: options.values["--command"]))
    case "shell":
        guard remaining.isEmpty else { throw MorrowError.message("Usage: morrow tool shell") }
        let path = manager.shimDirectory.path.replacingOccurrences(of: "'", with: "'\\''")
        print("export PATH='\(path)':\"$PATH\"")
    default: throw MorrowError.message("Unknown runtime command. Run morrow --help.")
    }
}

func mailMain(_ args: [String], manager: MailManager) throws {
    guard let action = args.first else { throw MorrowError.message("Usage: morrow mail create|list|start|stop|inbox|smtp|config|logs|configure|remove") }
    let remaining = Array(args.dropFirst())
    switch action {
    case "create":
        let options = try Options(remaining, allowedValues: ["--smtp-port", "--http-port", "--version"], allowedFlags: ["--start", "--autostart"])
        try options.requireCount(1, usage: "morrow mail create <name> [options]")
        let smtp = try options.number("--smtp-port", default: options.values["--smtp-port"] == nil ? manager.suggestedPort(1025) : 1025)
        let http = try options.number("--http-port", default: options.values["--http-port"] == nil ? manager.suggestedPort(8025, excluding: smtp) : 8025)
        let service = try manager.provision(name: options.positional[0], smtpPort: smtp, httpPort: http, autoStart: options.flags.contains("--autostart"), version: options.values["--version"] ?? "automatic")
        if options.flags.contains("--start") { try manager.start(service.id) }
        print("Created \(service.name): \(service.smtpURL)\nInbox: \(service.inboxURL.absoluteString)")
    case "list":
        let options = try Options(remaining, allowedFlags: ["--json"]); try options.requireCount(0, usage: "morrow mail list [--json]")
        let services = try manager.store.load().mailServices
        if options.flags.contains("--json") {
            let rows = services.map { ["id": $0.id.uuidString, "name": $0.name, "version": $0.installation.version, "smtp": $0.smtpURL, "inbox": $0.inboxURL.absoluteString, "status": manager.status($0).rawValue] }
            try printJSON(rows)
        } else { for service in services { print("\(service.name) · Mailpit \(service.installation.version) · SMTP :\(service.smtpPort) · Inbox :\(service.httpPort) · \(manager.status(service).title)") } }
    case "configure":
        let options = try Options(remaining, allowedValues: ["--smtp-port", "--http-port", "--name", "--autostart"])
        try options.requireCount(1, usage: "morrow mail configure <name> [options]")
        var service = try manager.resolve(options.positional[0])
        service.smtpPort = try options.number("--smtp-port", default: service.smtpPort)
        service.httpPort = try options.number("--http-port", default: service.httpPort)
        service.name = options.values["--name"] ?? service.name
        if let auto = options.values["--autostart"] { guard ["on", "off"].contains(auto) else { throw MorrowError.message("Use --autostart on|off.") }; service.autoStart = auto == "on" }
        try manager.update(service); print("Saved mail settings.")
    case "start", "stop", "restart", "inbox", "smtp", "config", "logs", "remove":
        let options = try Options(remaining, allowedFlags: action == "remove" ? ["--delete-messages"] : [])
        try options.requireCount(1, usage: "morrow mail \(action) <name>")
        let service = try manager.resolve(options.positional[0])
        switch action {
        case "start": try manager.start(service.id); print(manager.status(service).title)
        case "stop": try manager.stop(service.id); print("Stopped")
        case "restart": try manager.restart(service.id); print(manager.status(service).title)
        case "inbox": try CommandRunner().run("/usr/bin/open", [service.inboxURL.absoluteString]).checked()
        case "smtp": print(service.smtpURL)
        case "config": print(service.appConfiguration)
        case "logs": print(try manager.logs(service))
        default: try manager.remove(service.id, deleteMessages: options.flags.contains("--delete-messages")); print("Mail server removed.")
        }
    default: throw MorrowError.message("Unknown mail command. Run morrow --help.")
    }
}

func syncMain(_ args: [String], manager: WorkspaceSync) throws {
    guard let action = args.first else { throw MorrowError.message("Usage: morrow sync enable|disable|status|now") }
    let remaining = Array(args.dropFirst())
    switch action {
    case "enable":
        let options = try Options(remaining, allowedValues: ["--folder"], allowedFlags: ["--auto-install"])
        try options.requireCount(0, usage: "morrow sync enable [--folder <path>] [--auto-install]")
        let folder = options.values["--folder"].map { URL(fileURLWithPath: $0) }
        try manager.configure(enabled: true, folder: folder, automatic: options.flags.contains("--auto-install"))
        print("Workspace sync enabled. Run morrow sync now, or keep the app open for automatic checks.")
    case "disable":
        guard remaining.isEmpty else { throw MorrowError.message("Usage: morrow sync disable") }
        try manager.configure(enabled: false); print("Workspace sync disabled on this Mac.")
    case "status":
        guard remaining.isEmpty else { throw MorrowError.message("Usage: morrow sync status") }
        let preferences = try manager.store.load().preferences
        print("Enabled: \(preferences.iCloudSyncEnabled) · Automatic setup: \(preferences.autoSetupSyncedServices)")
        print("Folder: \(preferences.syncFolder.isEmpty ? WorkspaceSync.defaultFolder.path : preferences.syncFolder)")
        let report = try manager.report(); print(report.message)
        for detail in report.details { print(detail) }
        for failure in report.failures { print("Needs attention: \(failure)") }
    case "now":
        let options = try Options(remaining, allowedFlags: ["--retry", "--json"])
        try options.requireCount(0, usage: "morrow sync now [--retry] [--json]")
        let cli = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let report = try manager.synchronize(cli: cli, retry: options.flags.contains("--retry"))
        if options.flags.contains("--json") { try printJSON(report) }
        else {
            print(report.message)
            for detail in report.details { print(detail) }
            for failure in report.failures { print("Needs attention: \(failure)") }
        }
        if !report.failures.isEmpty { throw MorrowError.message("Some synced services could not be set up. Review the results and retry after resolving them.") }
    default: throw MorrowError.message("Unknown sync command. Run morrow --help.")
    }
}

do { try main() }
catch { FileHandle.standardError.write(Data("morrow: \(error.localizedDescription)\n".utf8)); exit(1) }
