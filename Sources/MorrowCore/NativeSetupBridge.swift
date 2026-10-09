import Foundation
import Darwin
import SystemConfiguration

/// A deliberately narrow request channel for the approved setup daemon.
/// It accepts only the console user's private, regular request file and never
/// executes commands or paths supplied by that file.
public enum NativeSetupBridge {
    public struct Request: Codable, Sendable {
        public let id: UUID
        public let uid: UInt32
        public let created: Date
        public let http: Int
        public let https: Int
        public let dns: Int
        public let suffixes: [String]
        public let replaceResolvers: Bool
    }
    public struct Response: Codable, Sendable {
        public let id: UUID
        public let uid: UInt32
        public let success: Bool
        public let message: String
    }
    private static let resultDirectory = URL(fileURLWithPath: "/Library/Application Support/Morrow Setup")
    private static func resultURL(_ uid: UInt32) -> URL { resultDirectory.appendingPathComponent("result-\(uid).json") }
    private static func requestURL(_ uid: UInt32) throws -> URL {
        guard let entry = getpwuid(uid) else { throw MorrowError.message("Mac user not found.") }
        return URL(fileURLWithPath: String(cString: entry.pointee.pw_dir)).appendingPathComponent("Library/Application Support/Morrow/setup-request.json")
    }
    public static func submit(_ web: WebWorkspace, replaceResolvers: Bool) throws -> Request {
        try SiteSystemSetup.validatePorts(http: web.httpPort, https: web.httpsPort, dns: web.dnsPort)
        let request = Request(id: UUID(), uid: getuid(), created: Date(), http: web.httpPort, https: web.httpsPort, dns: web.dnsPort, suffixes: try web.suffixes.map(SiteSystemSetup.validateSuffix), replaceResolvers: replaceResolvers)
        let url = try requestURL(request.uid)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(request).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return request
    }
    public static func response(for request: Request) -> Response? {
        guard let data = try? Data(contentsOf: resultURL(request.uid)), let value = try? JSONDecoder().decode(Response.self, from: data), value.id == request.id, value.uid == request.uid else { return nil }; return value
    }
    public static func runService() throws {
        guard geteuid() == 0 else { throw MorrowError.message("The setup service must be launched by macOS after approval.") }
        try prepareResultDirectory()
        var lastIDs: [UInt32: UUID] = [:]
        while true {
            var uid: uid_t = 0, gid: gid_t = 0
            if SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) != nil, uid > 0 {
                if lastIDs[uid] == nil { lastIDs[uid] = (try? JSONDecoder().decode(Response.self, from: Data(contentsOf: resultURL(uid))))?.id }
                if let request = try? readRequest(uid), request.id != lastIDs[uid] {
                    lastIDs[uid] = request.id
                    let response: Response
                    do {
                        guard request.uid == uid, abs(Date().timeIntervalSince(request.created)) < 86_400 else { throw MorrowError.message("This setup request expired. Start setup again in Morrow.") }
                        try SiteSystemSetup.install(http: request.http, https: request.https, dns: request.dns, suffixes: request.suffixes, uid: uid, replaceResolvers: request.replaceResolvers)
                        response = Response(id: request.id, uid: uid, success: true, message: "Local domains configured.")
                    } catch { response = Response(id: request.id, uid: uid, success: false, message: error.localizedDescription) }
                    let result = resultURL(uid)
                    try JSONEncoder().encode(response).write(to: result, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o644, .ownerAccountID: 0], ofItemAtPath: result.path)
                }
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }
    private static func readRequest(_ uid: UInt32) throws -> Request {
        let url = try requestURL(uid)
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw MorrowError.message("No setup request.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == uid, info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0, info.st_size > 0, info.st_size <= 8192 else { throw MorrowError.message("Invalid setup request file.") }
        return try JSONDecoder().decode(Request.self, from: handle.read(upToCount: 8192) ?? Data())
    }
    private static func prepareResultDirectory() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: resultDirectory.path) {
            let values = try resultDirectory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            let attributes = try fm.attributesOfItem(atPath: resultDirectory.path)
            guard values.isSymbolicLink != true, values.isDirectory == true, (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == 0,
                  ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o022 == 0 else { throw MorrowError.message("The setup result directory is not protected.") }
        } else { try fm.createDirectory(at: resultDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755, .ownerAccountID: 0]) }
    }
}
