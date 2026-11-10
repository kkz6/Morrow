import XCTest
@testable import MorrowCore

final class ProjectInspectionTests: XCTestCase {
    private func fixture(_ operation: (URL, StateStore) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Morrow inspection \(UUID())").resolvingSymlinksInPath()
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try operation(project, StateStore(root: root.appendingPathComponent("state")))
    }
    private func write(_ text: String, _ path: String, in root: URL) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }
    func testFrameworkRootsAndPHPPrecedenceOverFrontendPackages() throws {
        try fixture { root, _ in
            try write(#"{"dependencies":{"nuxt":"^4"}}"#, "package.json", in: root)
            for (package, name, directory) in [("laravel/framework", "Laravel", "public"), ("statamic/cms", "Statamic", "public"), ("symfony/framework-bundle", "Symfony", "public"), ("roots/wordpress", "WordPress · Bedrock", "web"), ("drupal/core-recommended", "Drupal", "web"), ("cakephp/cakephp", "CakePHP", "webroot"), ("magento/product-community-edition", "Magento", "pub")] {
                try write("{\"require\":{\"\(package)\":\"*\"}}", "composer.json", in: root)
                let profile = try ProjectProfile.detect(at: root.path)
                XCTAssertEqual(profile.name, name); XCTAssertEqual(profile.mode, .php)
                XCTAssertEqual(profile.documentRoot, root.appendingPathComponent(directory).path)
                XCTAssertTrue(profile.requiresPublicDirectory)
            }
        }
    }
    func testServerProjectsWaitForPortsAndDoNotExposeSourceAsStaticFiles() throws {
        try fixture { root, store in
            for (file, content, name) in [("package.json", #"{"devDependencies":{"@sveltejs/kit":"*"}}"#, "SvelteKit"), ("go.mod", "module example", "Go"), ("Cargo.toml", "[package]", "Rust"), ("pyproject.toml", "[project]", "Python"), ("manage.py", "raise Exception('must not run')", "Django"), ("Gemfile", "raise 'must not run'", "Ruby")] {
                try write(content, file, in: root)
                let profile = try ProjectProfile.detect(at: root.path)
                XCTAssertEqual(profile.mode, .proxy); XCTAssertEqual(profile.name, name)
                let site = try SiteManager(store: store).link(path: root.path)
                XCTAssertEqual(site.mode, .proxy); XCTAssertNotNil(site.issue); XCTAssertNil(site.proxyPort)
                try FileManager.default.removeItem(at: root.appendingPathComponent(file))
                try SiteManager(store: store).unlink(site.id)
            }
        }
    }
    func testMalformedManifestOnlyBlocksItsOwnDiscoveredRoute() throws {
        try fixture { root, store in
            try write("invalid-json", "bad/package.json", in: root)
            try write("<html>hello</html>", "good/index.html", in: root)
            try SiteManager(store: store).park(root.path)
            let sites = try store.load().web.sites
            XCTAssertEqual(sites.count, 2)
            XCTAssertEqual(sites.first { $0.domain == "bad.test" }?.mode, .proxy)
            XCTAssertNotNil(sites.first { $0.domain == "bad.test" }?.issue)
            XCTAssertNil(sites.first { $0.domain == "good.test" }?.issue)
        }
    }
    func testHealthChecksReportMissingSetupWithoutLeakingSecretsOrWritingFiles() throws {
        try fixture { root, store in
            let composer = #"{"require":{"laravel/framework":"^12","php":"^8.2","ext-intl":"*"},"scripts":{"post-install-cmd":"touch /tmp/do-not-run"}}"#
            try write(composer, "composer.json", in: root)
            try write("APP_KEY=\nDB_PASSWORD=secret-fixture-password\n", ".env", in: root)
            try write("APP_KEY=", ".env.example", in: root)
            try write("<?php throw new Exception('do not execute');", "bootstrap/cache/config.php", in: root)
            let report = try ProjectInspection.inspect(path: root.path, store: store)
            for id in ["public-root", "composer", "php", "app-key", "config-cache"] { XCTAssertEqual(report.checks.first { $0.id == id }?.level, .warning) }
            XCTAssertEqual(report.requirements.count, 2)
            let output = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
            XCTAssertFalse(output.contains("secret-fixture-password")); XCTAssertFalse(output.contains("post-install-cmd"))
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("composer.json"), encoding: .utf8), composer)
            XCTAssertEqual(try String(contentsOf: root.appendingPathComponent(".env"), encoding: .utf8), "APP_KEY=\nDB_PASSWORD=secret-fixture-password\n")
        }
    }
    func testVersionRequirementsUseSavedFolderOverridesAndRespectMajorBoundaries() throws {
        try fixture { root, store in
            try write(#"{"engines":{"node":">=22"},"packageManager":"pnpm@10.0.0"}"#, "package.json", in: root)
            try write("# team version\nv22 # LTS\n", ".nvmrc", in: root)
            let node = RuntimeInstallation(engine: .node, formula: "node", version: "22.15.0", prefix: "/fixture", executable: "/usr/bin/true", source: "external")
            try ProjectRuntimeStore(store: store).save([.init(path: root.path, runtimes: ["node": node])])
            var report = try ProjectInspection.inspect(path: root.path, store: store)
            XCTAssertEqual(report.checks.first { $0.id == "version-.nvmrc" }?.level, .passed)
            XCTAssertEqual(report.requirements.count, 3)
            try write("2", ".nvmrc", in: root)
            report = try ProjectInspection.inspect(path: root.path, store: store)
            XCTAssertEqual(report.checks.first { $0.id == "version-.nvmrc" }?.level, .warning)
            try write("lts/*", ".nvmrc", in: root)
            report = try ProjectInspection.inspect(path: root.path, store: store)
            XCTAssertEqual(report.checks.first { $0.id == "version-.nvmrc" }?.level, .information)
        }
    }
    func testUnsafeOrOversizedMetadataIsRejectedWithoutPrintingContents() throws {
        try fixture { root, store in
            let outside = root.deletingLastPathComponent().appendingPathComponent("secret.json")
            try Data(#"{"secret":"private"}"#.utf8).write(to: outside)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("composer.json"), withDestinationURL: outside)
            XCTAssertThrowsError(try ProjectInspection.inspect(path: root.path, store: store)) { XCTAssertFalse($0.localizedDescription.contains("private")) }
            try FileManager.default.removeItem(at: root.appendingPathComponent("composer.json"))
            try write(String(repeating: " ", count: 1_048_577), "composer.json", in: root)
            XCTAssertThrowsError(try ProjectProfile.detect(at: root.path))
        }
    }
}
