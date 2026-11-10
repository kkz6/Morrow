import XCTest
@testable import MorrowCore

final class MailInboxTests: XCTestCase {
    private func client() -> MailInbox {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InboxProtocol.self]
        return MailInbox(service: MailService(name: "test", installation: .init(executable: "/unused", version: "1.31.4", source: "test")), session: URLSession(configuration: config))
    }
    func testProjectFilterPaginationAndReadDetailsUseLocalAPI() async throws {
        let page = try await client().messages(search: "subject:Receipt", project: "shop.test", offset: 50)
        XCTAssertEqual(page.matchingCount, 1)
        XCTAssertEqual(page.messages.first?.Subject, "Receipt")
        XCTAssertEqual(page.messages.first?.Attachments, 1)
        let message = try await client().message("mail-1")
        XCTAssertEqual(message.Text, "Your receipt")
        XCTAssertEqual(message.Attachments?.first?.FileName, "receipt.txt")
        let headers = try await client().headers("mail-1")
        XCTAssertEqual(headers["Subject"], ["Receipt"])
    }
    func testDeletionCannotAccidentallyClearMailboxAndIdentifiersCannotEscape() async throws {
        do { try await client().delete([]); XCTFail("Empty deletion must be rejected") } catch { }
        do { _ = try await client().message("../messages"); XCTFail("Invalid identifier must be rejected") } catch { }
        try await client().delete(["mail-1"])
        XCTAssertThrowsError(try MailInbox.validateProject("other\" OR tag:secret"))
    }
    func testStoppedServerReturnsActionableError() async {
        do { _ = try await client().message("stopped"); XCTFail("Expected server error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("mail server is running")) }
    }
    func testProjectSMTPSettingsDoNotInjectEnvironmentLines() throws {
        let service = MailService(name: "test", installation: .init(executable: "/unused", version: "1.31.4", source: "test"))
        XCTAssertTrue(try service.appConfiguration(project: "shop.test").contains("MAIL_USERNAME=\"shop.test\""))
        XCTAssertThrowsError(try service.appConfiguration(project: "shop\nMAIL_HOST=external"))
        XCTAssertTrue(service.appConfiguration.contains("MAIL_USERNAME=null"))
    }
}

private final class InboxProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.url?.host, "127.0.0.1")
        let path = request.url!.path
        var status = 200, response = "{}"
        if path == "/api/v1/search" {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "query" }?.value, "tag:\"shop.test\" subject:Receipt")
            XCTAssertEqual(query.first { $0.name == "start" }?.value, "50")
            response = #"{"total":2,"messages_count":1,"tags":["shop.test"],"messages":[{"ID":"mail-1","Subject":"Receipt","From":{"Name":"Shop","Address":"shop@example.test"},"Created":"2026-11-10T01:00:00Z","Read":false,"Snippet":"Your receipt","Attachments":1}]}"#
        } else if path.hasSuffix("/headers") { response = #"{"Subject":["Receipt"]}"# }
        else if path.hasSuffix("/mail-1") { response = #"{"ID":"mail-1","Subject":"Receipt","From":{"Name":"Shop","Address":"shop@example.test"},"Date":"2026-11-10T01:00:00Z","Text":"Your receipt","HTML":"<p>Your receipt</p>","Attachments":[{"PartID":"1.2","FileName":"receipt.txt","ContentType":"text/plain","Size":7}]}"# }
        else if path.hasSuffix("/stopped") { status = 503 }
        else if path == "/api/v1/messages" {
            XCTAssertEqual(request.httpMethod, "DELETE")
            // URLSession may move the body into an input stream.
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream { stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 1024); let count = stream.read(&buffer, maxLength: buffer.count); if count > 0 { body = Data(buffer.prefix(count)) } }
            XCTAssertEqual(try? JSONDecoder().decode([String: [String]].self, from: body), ["IDs": ["mail-1"]])
        } else { XCTFail("Unexpected endpoint \(path)") }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(response.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
