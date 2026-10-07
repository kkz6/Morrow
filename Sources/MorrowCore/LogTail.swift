import Foundation
import Darwin

public struct LogSnapshot: Sendable {
    public let output: String
    public let exists: Bool
    public let truncated: Bool
    public init(output: String, exists: Bool, truncated: Bool) {
        self.output = output; self.exists = exists; self.truncated = truncated
    }
}

/// Reads appended bytes without repeatedly loading an entire server log.
/// Rotation and truncation reset the cursor; the retained tail stays bounded.
public actor LogTail {
    private let url: URL
    private let limit: Int
    private var offset: UInt64 = 0
    private var inode: UInt64?
    private var bytes = Data()
    private var truncated = false

    public init(url: URL, limit: Int = 128 * 1024) {
        self.url = url; self.limit = max(1024, limit)
    }
    public func read() throws -> LogSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            offset = 0; inode = nil; bytes.removeAll(); truncated = false
            return LogSnapshot(output: "", exists: false, truncated: false)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        var info = stat()
        guard fstat(handle.fileDescriptor, &info) == 0 else { throw MorrowError.message("Could not read the log file's metadata.") }
        let identity = UInt64(info.st_ino)
        if identity != inode || size < offset {
            offset = 0; bytes.removeAll(); truncated = false; inode = identity
        }
        if size > offset + UInt64(limit) {
            offset = size - UInt64(limit)
            bytes.removeAll()
            truncated = true
        }
        try handle.seek(toOffset: offset)
        let appended = try handle.read(upToCount: limit) ?? Data()
        offset += UInt64(appended.count)
        bytes.append(appended)
        if bytes.count > limit {
            bytes.removeFirst(bytes.count - limit)
            truncated = true
        }
        // Keep raw bytes so a UTF-8 character split across two appends is
        // reconstructed on the next read. Skip an incomplete leading line.
        let visible: Data
        if truncated, let newline = bytes.firstIndex(of: 10), bytes.index(after: newline) < bytes.endIndex {
            visible = Data(bytes.suffix(from: bytes.index(after: newline)))
        } else { visible = bytes }
        return LogSnapshot(output: String(decoding: visible, as: UTF8.self), exists: true, truncated: truncated)
    }
}
