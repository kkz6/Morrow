import Foundation
import Darwin

struct LaunchdControl {
    let runner: any CommandRunning
    var domain: String { "gui/\(getuid())" }
    func inspect(_ label: String) throws -> CommandResult { try runner.run("/bin/launchctl", ["print", "\(domain)/\(label)"], environment: [:]) }
    func bootstrap(_ job: URL) throws { try runner.run("/bin/launchctl", ["bootstrap", domain, job.path], environment: [:]).checked() }
    func unload(_ label: String) throws {
        let result = try inspect(label)
        guard result.status == 0 else { return }
        let pid = LaunchdStatus(result.output).pid
        try runner.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"], environment: [:]).checked()
        if let pid, pid > 1 {
            for _ in 0..<300 {
                if kill(pid, 0) != 0 { return }
                Thread.sleep(forTimeInterval: 0.1)
            }
            throw MorrowError.message("The service is still shutting down. Its files were preserved; retry shortly.")
        }
    }
}
