import XCTest
import MorrowCore

final class LogTailTests: XCTestCase {
    private var root: URL!
    private var file: URL { root.appendingPathComponent("server.log") }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MorrowLogTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func append(_ data: Data) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
    func testMissingFileThenNewOutputAndAppends() async throws {
        let reader = LogTail(url: file)
        let empty = try await reader.read()
        XCTAssertFalse(empty.exists)
        try Data("starting\n".utf8).write(to: file)
        let initial = try await reader.read()
        XCTAssertEqual(initial.output, "starting\n")
        try append(Data("ready\n".utf8))
        let updated = try await reader.read()
        XCTAssertEqual(updated.output, "starting\nready\n")
        let unchanged = try await reader.read()
        XCTAssertEqual(unchanged.output, updated.output)
    }
    func testTruncationAndRotationDiscardPreviousOutput() async throws {
        let reader = LogTail(url: file)
        try Data("old longer output\n".utf8).write(to: file)
        _ = try await reader.read()
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("new\n".utf8))
        try handle.close()
        let truncated = try await reader.read()
        XCTAssertEqual(truncated.output, "new\n")
        try Data("rotated\n".utf8).write(to: file, options: .atomic)
        let rotated = try await reader.read()
        XCTAssertEqual(rotated.output, "rotated\n")
    }
    func testLargeLogsRetainABoundedTailWithLatestLines() async throws {
        let reader = LogTail(url: file, limit: 1024)
        let initial = (0..<10000).map { "line \($0)\n" }.joined()
        try Data(initial.utf8).write(to: file)
        let snapshot = try await reader.read()
        XCTAssertTrue(snapshot.truncated)
        XCTAssertLessThanOrEqual(snapshot.output.utf8.count, 1024)
        XCTAssertTrue(snapshot.output.hasSuffix("line 9999\n"))
        try append(Data("latest line\n".utf8))
        let updated = try await reader.read()
        XCTAssertLessThanOrEqual(updated.output.utf8.count, 1024)
        XCTAssertTrue(updated.output.hasSuffix("latest line\n"))
    }
    func testUTF8CharacterSplitAcrossWritesIsReconstructed() async throws {
        let reader = LogTail(url: file)
        let text = Data("Connection ready ☀\n".utf8)
        try text.dropLast(2).write(to: file)
        _ = try await reader.read()
        try append(Data(text.suffix(2)))
        let snapshot = try await reader.read()
        XCTAssertEqual(snapshot.output, "Connection ready ☀\n")
    }
    func testSingleOversizedLineStillHasVisibleOutput() async throws {
        let reader = LogTail(url: file, limit: 1024)
        try Data((String(repeating: "x", count: 4096) + "\n").utf8).write(to: file)
        let snapshot = try await reader.read()
        XCTAssertFalse(snapshot.output.isEmpty)
        XCTAssertTrue(snapshot.truncated)
        XCTAssertLessThanOrEqual(snapshot.output.utf8.count, 1024)
    }
}
