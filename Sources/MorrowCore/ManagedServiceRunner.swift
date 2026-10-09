import Foundation
import Darwin
import CLaunch

/// Signed customer builds attribute these jobs to Morrow, while each server
/// remains a separate native child process with its own lifecycle and logs.
public enum ManagedServiceRunner {
    public static let bundleIdentifiers = ["dev.morrow.app"]
    public static func arguments(_ original: [String]) -> [String] {
        guard let server = original.first, let launcher = launcher(), server != launcher else { return original }
        return [launcher, "service-runner", "--"] + original
    }
    private static func launcher() -> String? {
        let app = Bundle.main.bundleURL
        if app.pathExtension == "app" {
            let cli = app.appendingPathComponent("Contents/MacOS/morrow").path
            if FileManager.default.isExecutableFile(atPath: cli) { return cli }
        }
        var size: UInt32 = 4096, bytes = [CChar](repeating: 0, count: 4096)
        guard _NSGetExecutablePath(&bytes, &size) == 0 else { return nil }
        let file = URL(fileURLWithPath: String(cString: bytes)).resolvingSymlinksInPath()
        return ["morrow", "morrow-cli", "morrow-gateway"].contains(file.lastPathComponent) ? file.path : nil
    }
    public static func run(_ arguments: [String]) throws -> Int32 {
        guard geteuid() != 0, let executable = arguments.first, executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable) else { throw MorrowError.message("Managed servers need an executable path and must run as the Mac user.") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = Array(arguments.dropFirst())
        process.standardInput = FileHandle.standardInput; process.standardOutput = FileHandle.standardOutput; process.standardError = FileHandle.standardError
        try process.run()
        // Install parent-only handlers after spawning so the server keeps its
        // normal signal dispositions. Forward stop signals to the owned child.
        let signals: [Int32] = [SIGTERM, SIGINT, SIGHUP]
        var sources: [DispatchSourceSignal] = []
        for value in signals {
            signal(value, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: value, queue: .global(qos: .utility))
            source.setEventHandler { if process.isRunning { _ = kill(process.processIdentifier, value) } }
            source.resume(); sources.append(source)
        }
        process.waitUntilExit()
        for source in sources { source.cancel() }
        return process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus
    }
}
