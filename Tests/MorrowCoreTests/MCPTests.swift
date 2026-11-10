import XCTest
@testable import MorrowCore

final class MCPTests: XCTestCase {
    private func fixture() throws -> (URL, StateStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Morrow AI \(UUID())").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, StateStore(root: root.appendingPathComponent("state")))
    }
    private func send(_ server: MCPServer, method: String, params: [String: Any] = [:], id: Any = 1) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        let reply = await server.handle(data)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(reply)) as? [String: Any])
    }
    private func initialize(_ server: MCPServer, version: String = "2025-11-25") async throws -> [String: Any] {
        let response = try await send(server, method: "initialize", params: ["protocolVersion": version, "capabilities": [:], "clientInfo": ["name": "Test", "version": "1"]])
        let reply = await server.handle(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
        XCTAssertNil(reply)
        return try XCTUnwrap(response["result"] as? [String: Any])
    }
    func testNegotiationLifecycleAndInvalidMessages() async throws {
        let (_, store) = try fixture(), server = MCPServer(store: store)
        let early = try await send(server, method: "tools/list")
        XCTAssertEqual((early["error"] as? [String: Any])?["code"] as? Int, -32002)
        let result = try await initialize(server, version: "future-version")
        XCTAssertEqual(result["protocolVersion"] as? String, MCPServer.protocolVersions[0])
        let list = try await send(server, method: "tools/list", id: "string-id")
        XCTAssertEqual(list["id"] as? String, "string-id")
        let tools = ((list["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        XCTAssertEqual(tools.count, 10)
        XCTAssertTrue(tools.allSatisfy { ($0["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool == true })
        for (data, code) in [("{", -32700), ("[]", -32600), (#"{"jsonrpc":"2.0","id":true,"method":"ping"}"#, -32600)] {
            let reply = await server.handle(Data(data.utf8))
            let value = try JSONSerialization.jsonObject(with: XCTUnwrap(reply)) as! [String: Any]
            XCTAssertEqual((value["error"] as? [String: Any])?["code"] as? Int, code)
        }
        let invalid = try await send(server, method: "tools/call", params: ["name": "list_sites", "arguments": ["exec": "rm"]])
        XCTAssertEqual((invalid["error"] as? [String: Any])?["code"] as? Int, -32602)
        let unknown = try await send(server, method: "unrecognized")
        XCTAssertEqual((unknown["error"] as? [String: Any])?["code"] as? Int, -32601)
        let notification = await server.handle(Data(#"{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_runtimes"}}"#.utf8))
        XCTAssertNil(notification)
    }
    func testPermissionsAreOffByDefaultAndRevokedForExistingConnection() async throws {
        let (_, store) = try fixture(), server = MCPServer(store: store), integration = AIIntegration(store: store)
        _ = try await initialize(server, version: "2024-11-05")
        func isError(_ reply: [String: Any]) -> Bool { (reply["result"] as? [String: Any])?["isError"] as? Bool ?? false }
        let disabled = try await send(server, method: "tools/call", params: ["name": "list_runtimes"])
        XCTAssertTrue(isError(disabled))
        try integration.update { $0.enabled = true }
        let enabled = try await send(server, method: "tools/call", params: ["name": "list_runtimes"])
        XCTAssertFalse(isError(enabled))
        for (name, args) in [("service_logs", ["service": "unknown"]), ("list_mail", ["service": "unknown"])] {
            let denied = try await send(server, method: "tools/call", params: ["name": name, "arguments": args])
            XCTAssertTrue(isError(denied))
            let text = ((denied["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String
            XCTAssertTrue(text?.contains("Enable") == true)
        }
        try integration.update { $0.enabled = false }
        let revoked = try await send(server, method: "tools/call", params: ["name": "list_runtimes"])
        XCTAssertTrue(isError(revoked))
        XCTAssertEqual(try AIIntegration(store: store).settings(), AISettings())
    }
    func testProjectScopeAndLogLimitsDoNotAcceptArbitraryPaths() async throws {
        let (root, store) = try fixture(), server = MCPServer(store: store)
        let project = root.appendingPathComponent("site")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let site = LocalSite(domain: "test.test", path: project.path, documentRoot: project.path, mode: .files)
        let db = DatabaseInstance(name: "test", installation: Installation(engine: .redis, formula: "redis", version: "8", prefix: "/missing"), port: 6379)
        try store.update { $0.web.sites = [site]; $0.instances = [db] }
        try FileManager.default.createDirectory(at: store.instanceDirectory(db), withIntermediateDirectories: true)
        try Data(String(repeating: "x", count: 50_000).utf8).write(to: store.logURL(db))
        try AIIntegration(store: store).update { $0.enabled = true; $0.includeDebugData = true }
        _ = try await initialize(server)
        let forbidden = try await send(server, method: "tools/call", params: ["name": "project_health", "arguments": ["site": root.path]])
        XCTAssertEqual((forbidden["result"] as? [String: Any])?["isError"] as? Bool, true)
        let healthy = try await send(server, method: "tools/call", params: ["name": "project_health", "arguments": ["site": "test.test"]])
        XCTAssertEqual((healthy["result"] as? [String: Any])?["isError"] as? Bool, false)
        let logs = try await send(server, method: "tools/call", params: ["name": "service_logs", "arguments": ["service": db.id.uuidString]])
        let contents = ((logs["result"] as? [String: Any])?["content"] as! [[String: Any]])[0]["text"] as! String
        let value = try JSONSerialization.jsonObject(with: Data(contents.utf8)) as! [String: Any]
        XCTAssertEqual((value["text"] as? String)?.count, 32_768); XCTAssertEqual(value["truncated"] as? Bool, true)
        let arbitrary = try await send(server, method: "tools/call", params: ["name": "service_logs", "arguments": ["service": "/etc/passwd"]])
        XCTAssertEqual((arbitrary["result"] as? [String: Any])?["isError"] as? Bool, true)
    }
    func testFramesHandleSplitAndMultipleMessagesAndBoundUnterminatedInput() throws {
        var frames = MCPFrames()
        XCTAssertTrue(try frames.append(Data("{\"a\":".utf8)).isEmpty)
        let values = try frames.append(Data("1}\n{}\n\n".utf8))
        XCTAssertEqual(values.map { String(decoding: $0, as: UTF8.self) }, ["{\"a\":1}", "{}"])
        XCTAssertTrue(frames.buffer.isEmpty)
        XCTAssertThrowsError(try frames.append(Data(repeating: 120, count: MCPServer.maximumFrameBytes + 1)))
    }
    func testClientConfigurationPreservesOtherServersAndCreatesPrivateBackup() throws {
        let (root, _) = try fixture()
        let config = AIClientConfiguration(executable: "/usr/bin/true", home: root)
        for client in AIClient.allCases {
            let file = client.file(home: root)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let original = try JSONSerialization.data(withJSONObject: [client.key: ["other": ["command": "keep-me"]], "theme": "dark"])
            try original.write(to: file)
            try config.setAdded(true, to: client)
            XCTAssertTrue(try config.isAdded(to: client))
            let document = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            XCTAssertEqual(document["theme"] as? String, "dark")
            XCTAssertNotNil((document[client.key] as? [String: Any])?["other"])
            let backups = try FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(file.lastPathComponent + ".morrow-backup-") }
            XCTAssertEqual(backups.count, 1); XCTAssertEqual(try Data(contentsOf: backups[0]), original)
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: backups[0].path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
            try config.setAdded(false, to: client)
            XCTAssertFalse(try config.isAdded(to: client))
            let restored = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! NSDictionary
            XCTAssertEqual(restored, try JSONSerialization.jsonObject(with: original) as? NSDictionary)
        }
    }
    func testClientConflictsAndCommentedJSONRemainUnchanged() throws {
        let (root, _) = try fixture(), client = AIClient.cursor
        let config = AIClientConfiguration(executable: "/usr/bin/true", home: root)
        let file = client.file(home: root)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        for text in ["{ // custom comment\n}", #"{"mcpServers":{"morrow":{"command":"other-server"}}}"#, #"{"mcpServers":[]}"#] {
            let original = Data(text.utf8); try original.write(to: file)
            XCTAssertThrowsError(try config.setAdded(true, to: client))
            XCTAssertThrowsError(try config.setAdded(false, to: client))
            XCTAssertEqual(try Data(contentsOf: file), original)
        }
    }
}
