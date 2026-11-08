import XCTest
@testable import MorrowCore

final class SiteConfigurationTests: XCTestCase {
    func testExecutableLocationIsAnExistingAbsoluteExecutable() throws {
        let executable = try ExecutableLocation.current()
        XCTAssertTrue(executable.path.hasPrefix("/"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
    }

    func testHTTPSStaysOnGatewaySupportedProtocolsAndClearsAlternateRoutes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = SiteManager(store: StateStore(root: root))
        var web = WebWorkspace()
        web.sites = [LocalSite(domain: "example.test", path: root.path, documentRoot: root.path, mode: .files, https: true)]

        let configuration = try manager.caddyConfiguration(web)

        XCTAssertTrue(configuration.contains("protocols h1 h2"))
        XCTAssertTrue(configuration.contains("issuer internal {\n            lifetime 368d"))
        XCTAssertTrue(configuration.contains("intermediate_lifetime 1460d"))
        XCTAssertTrue(configuration.contains("renew_interval 1m"))
        XCTAssertTrue(configuration.contains("header Alt-Svc clear"))
        XCTAssertTrue(configuration.contains("https://example.test:8443"))
        XCTAssertFalse(configuration.contains("protocols h1 h2 h3"))
    }

    func testHTTPProjectsKeepTheirExistingUnsecuredRoutes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = SiteManager(store: StateStore(root: root))
        var web = WebWorkspace()
        web.sites = [LocalSite(domain: "example.test", path: root.path, documentRoot: root.path, mode: .files)]

        let configuration = try manager.caddyConfiguration(web)

        XCTAssertTrue(configuration.contains("http://example.test:8080"))
        XCTAssertFalse(configuration.contains("issuer internal"))
        XCTAssertFalse(configuration.contains("header Alt-Svc clear"))
    }
}
