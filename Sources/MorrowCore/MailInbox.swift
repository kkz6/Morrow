import Foundation

public struct MailAddress: Codable, Sendable {
    public let Name: String
    public let Address: String
    public var label: String { Name.isEmpty ? Address : "\(Name) <\(Address)>" }
}

public struct MailMessageSummary: Codable, Identifiable, Sendable {
    public let ID: String
    public let Subject: String
    public let From: MailAddress
    public let To: [MailAddress]?
    public let Created: String
    public let Read: Bool
    public let Snippet: String
    public let Tags: [String]?
    public var id: String { self.ID }
}

public struct MailMessagePage: Codable, Sendable {
    public let messages: [MailMessageSummary]
    public let total: Int
    public let messages_count: Int?
    public let tags: [String]?
    public var matchingCount: Int { messages_count ?? total }
}

public struct MailAttachment: Codable, Identifiable, Sendable {
    public let PartID: String
    public let FileName: String
    public let ContentType: String
    public let Size: Int
    public var id: String { PartID }
}

public struct MailMessage: Codable, Identifiable, Sendable {
    public let ID: String
    public let Subject: String
    public let From: MailAddress
    public let To: [MailAddress]?
    public let Cc: [MailAddress]?
    public let Bcc: [MailAddress]?
    public let Date: String
    public let Text: String
    public let HTML: String
    public let Attachments: [MailAttachment]?
    public let Inline: [MailAttachment]?
    public var id: String { self.ID }
}

/// Only the owned loopback mail catcher's read/delete API is exposed. Relay and
/// outbound send endpoints are intentionally absent.
public final class MailInbox: Sendable {
    private let base: URL
    private let session: URLSession
    private let ownsSession: Bool
    public init(service: MailService, session: URLSession? = nil) {
        base = service.inboxURL
        ownsSession = session == nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 8
        self.session = session ?? URLSession(configuration: configuration, delegate: NoMailRedirects(), delegateQueue: nil)
    }
    deinit { if ownsSession { session.invalidateAndCancel() } }
    public func messages(search: String = "", project: String = "", offset: Int = 0) async throws -> MailMessagePage {
        var query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !project.isEmpty {
            try Self.validateProject(project)
            query = "tag:\"\(project)\" " + query
        }
        let data = try await request(query.isEmpty ? "api/v1/messages" : "api/v1/search", query: [
            .init(name: "query", value: query), .init(name: "start", value: String(max(0, offset))), .init(name: "limit", value: "50")])
        return try JSONDecoder().decode(MailMessagePage.self, from: data)
    }
    public func message(_ id: String) async throws -> MailMessage {
        try await decode(MailMessage.self, path: "api/v1/message/" + Self.identifier(id))
    }
    public func headers(_ id: String) async throws -> [String: [String]] {
        try await decode([String: [String]].self, path: "api/v1/message/" + Self.identifier(id) + "/headers")
    }
    public func raw(_ id: String) async throws -> Data {
        try await request("api/v1/message/" + Self.identifier(id) + "/raw")
    }
    public func attachment(_ part: String, message id: String) async throws -> Data {
        try await request("api/v1/message/" + Self.identifier(id) + "/part/" + Self.identifier(part))
    }
    public func delete(_ ids: [String]) async throws {
        // Mailpit interprets an empty list as ALL messages. Never send one.
        guard !ids.isEmpty, ids.count <= 500 else { throw MorrowError.message("Select the messages to delete.") }
        for id in ids { _ = try Self.identifier(id) }
        _ = try await request("api/v1/messages", method: "DELETE", body: JSONEncoder().encode(["IDs": ids]))
    }
    public static func validateProject(_ name: String) throws {
        guard (1...100).contains(name.utf8.count), name.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._ @").contains($0) }) else {
            throw MorrowError.message("Use 1–100 letters, numbers, spaces, dots, hyphens, underscores, or @ for the inbox name.")
        }
    }
    private static func identifier(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf8.count <= 200, value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 95, 46].contains($0) }), value != ".", value != ".." else {
            throw MorrowError.message("Invalid mail message or attachment identifier.")
        }
        return value
    }
    private func decode<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        try await JSONDecoder().decode(type, from: request(path))
    }
    private func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) async throws -> Data {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw MorrowError.message("The inbox could not complete this request. Check that the mail server is running.")
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 36 * 1024 * 1024 else { throw MorrowError.message("This email exceeds the inbox preview limit.") }
            data.append(byte)
        }
        return data
    }
}

private final class NoMailRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

extension MailService {
    public func appConfiguration(project: String) throws -> String {
        try MailInbox.validateProject(project)
        return appConfiguration.replacingOccurrences(of: "MAIL_USERNAME=null\nMAIL_PASSWORD=null", with: "MAIL_USERNAME=\"\(project)\"\nMAIL_PASSWORD=morrow")
    }
}
