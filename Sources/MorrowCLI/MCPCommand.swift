import Foundation
import MorrowCore

func mcpMain(_ args: [String]) async throws {
    let command = args.first ?? "serve"
    let options = try Options(Array(args.dropFirst()), allowedValues: ["--site", "--client"])
    let integration = AIIntegration()
    let executable = try ExecutableLocation.current().resolvingSymlinksInPath().path
    let configuration = AIClientConfiguration(executable: executable)
    switch command {
    case "serve":
        try options.requireCount(0, usage: "morrow mcp serve [--site <folder>]")
        guard options.values["--client"] == nil else { throw MorrowError.message("--client applies only to mcp config.") }
        try await MCPServer(site: options.values["--site"] ?? FileManager.default.currentDirectoryPath).run()
    case "status", "enable", "disable":
        try options.requireCount(0, usage: "morrow mcp status|enable|disable")
        guard options.values.isEmpty else { throw MorrowError.message("This command does not accept options.") }
        if command != "status" { try integration.update { $0.enabled = command == "enable" } }
        try printJSON(integration.settings())
    case "access":
        guard options.positional.count == 2, ["mail", "debug"].contains(options.positional[0]), ["on", "off"].contains(options.positional[1]), options.values.isEmpty else { throw MorrowError.message("Usage: morrow mcp access mail|debug on|off") }
        try integration.update {
            if options.positional[0] == "mail" { $0.includeMail = options.positional[1] == "on" }
            else { $0.includeDebugData = options.positional[1] == "on" }
        }
        try printJSON(integration.settings())
    case "config":
        try options.requireCount(0, usage: "morrow mcp config [--client claude-desktop|cursor|vscode|windsurf]")
        guard options.values["--site"] == nil else { throw MorrowError.message("--site applies only to mcp serve.") }
        let client = options.values["--client"].flatMap(AIClient.init(rawValue:))
        guard options.values["--client"] == nil || client != nil else { throw MorrowError.message("Unknown AI client.") }
        print(try configuration.json(for: client))
    case "add", "remove":
        guard options.positional.count == 1, let client = AIClient(rawValue: options.positional[0]), options.values.isEmpty else { throw MorrowError.message("Usage: morrow mcp add|remove claude-desktop|cursor|vscode|windsurf") }
        try configuration.setAdded(command == "add", to: client)
        print(command == "add" ? "Morrow added to \(client.title). Enable AI access, then restart the client to connect." : "Morrow removed from \(client.title).")
    default: throw MorrowError.message("Unknown MCP command. Use morrow --help.")
    }
}

