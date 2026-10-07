import Foundation
import Observation
import MorrowCore

@MainActor @Observable
final class LogViewerModel {
    var output = ""
    var query = ""
    var follow = true
    var loading = false
    var error: String?
    var truncated = false
    var exists = false
    var lastUpdated: Date?
    @ObservationIgnored private var reader: LogTail?
    @ObservationIgnored private var generation = UUID()

    var lines: [String] { output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
    var visibleOutput: String {
        guard !query.isEmpty else { return output }
        return lines.filter { $0.localizedCaseInsensitiveContains(query) }.joined(separator: "\n")
    }
    func configure(url: URL) {
        generation = UUID()
        reader = LogTail(url: url)
        output = ""; error = nil; exists = false; truncated = false; loading = false; lastUpdated = nil
    }
    func refresh() async {
        guard !loading, let reader else { return }
        let token = generation
        loading = true
        defer { if token == generation { loading = false } }
        do {
            let snapshot = try await reader.read()
            guard token == generation, !Task.isCancelled else { return }
            output = snapshot.output; exists = snapshot.exists; truncated = snapshot.truncated
            error = nil; lastUpdated = Date()
        } catch {
            if token == generation && !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
    func previewOutput() {
        output = """
        2026-10-07 12:50:00 LOG: starting PostgreSQL 17.6
        2026-10-07 12:50:00 LOG: listening on IPv4 address \"127.0.0.1\", port 5432
        2026-10-07 12:50:00 LOG: database system is ready to accept connections
        2026-10-07 12:50:12 LOG: connection received: host=127.0.0.1
        2026-10-07 12:50:12 LOG: connection authorized: user=postgres database=postgres
        2026-10-07 12:51:00 LOG: checkpoint starting: time
        2026-10-07 12:51:00 LOG: checkpoint complete: wrote 4 buffers
        """
        exists = true
    }
}
