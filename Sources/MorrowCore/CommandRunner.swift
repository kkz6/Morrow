import Foundation

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
    public let errorOutput: String
    public init(status: Int32, output: String, errorOutput: String = "") {
        self.status = status; self.output = output; self.errorOutput = errorOutput
    }
    @discardableResult public func checked() throws -> String {
        guard status == 0 else {
            let diagnostic = [output, errorOutput].filter { !$0.isEmpty }.joined(separator: "\n")
            throw MorrowError.message(diagnostic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Command failed with exit code \(status)." : String(diagnostic.suffix(6000)))
        }
        return output
    }
}

public protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult
}

public struct CommandRunner: CommandRunning {
    public init() {}
    public func run(_ executable: String, _ arguments: [String], environment: [String: String] = [:]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env.merge(environment) { _, new in new }
        process.environment = env
        // Keep stdout clean for JSON commands. stderr goes to a temporary file
        // so verbose output cannot fill a second, undrained pipe and deadlock.
        let pipe = Pipe()
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent("morrow-command-\(UUID()).stderr")
        guard FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw MorrowError.message("Could not create a temporary command log.")
        }
        defer { try? FileManager.default.removeItem(at: errorURL) }
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer { try? errorHandle.close() }
        process.standardOutput = pipe
        process.standardError = errorHandle
        process.standardInput = FileHandle.nullDevice
        do { try process.run() }
        catch { throw MorrowError.message("Could not run \(executable): \(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self),
            errorOutput: String(decoding: try Data(contentsOf: errorURL), as: UTF8.self))
    }
}
