import Foundation

/// launchctl uses "(never exited)" before the first launch completes. That
/// field's presence alone is not evidence that a process failed.
struct LaunchdStatus {
    let state: String?
    let pid: Int32?
    let exitCode: Int?
    let terminatingSignal: Int?
    init(_ output: String) {
        let lines = output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        func value(_ key: String) -> String? {
            lines.first { $0.hasPrefix(key + " = ") }.map { String($0.dropFirst(key.count + 3)) }
        }
        state = value("state")
        pid = value("pid").flatMap(Int32.init)
        exitCode = value("last exit code").flatMap(Int.init)
        terminatingSignal = value("last terminating signal").flatMap { text in
            text.split(whereSeparator: { !$0.isNumber }).last.flatMap { Int($0) }
        }
    }
    var isRunning: Bool { state == "running" }
    var isLaunching: Bool { ["spawn scheduled", "spawning", "initializing", "spawned"].contains(state ?? "") }
    var failed: Bool { !isRunning && !isLaunching && ((exitCode ?? 0) != 0 || (terminatingSignal ?? 0) != 0) }
}
