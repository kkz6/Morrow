import XCTest
import MorrowCore

private struct StoppedRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult {
        CommandResult(status: executable == "/bin/launchctl" ? 1 : 0, output: "")
    }
}

private struct RunningRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult {
        CommandResult(status: 0, output: "state = running")
    }
}

final class CoreTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Morrow Test 'Folder' \(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func installation(_ engine: DatabaseEngine = .mongodb) throws -> Installation {
        let prefix = root.appendingPathComponent("native \(engine.rawValue)")
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let executable = prefix.appendingPathComponent("bin/\(engine.binary)")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return Installation(engine: engine, formula: engine.formulaBase, version: "1.2.3", prefix: prefix.path)
    }
    func testStateSurvivesRoundTripAndRejectsCorruption() throws {
        let store = StateStore(root: root)
        try store.update { $0.preferences.appearance = "dark" }
        XCTAssertEqual(try store.load().preferences.appearance, "dark")
        let file = root.appendingPathComponent("state.json")
        let corrupted = Data("{bad json".utf8)
        try corrupted.write(to: file)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: file), corrupted)
    }
    func testConcurrentMetadataUpdatesDoNotLoseInstances() throws {
        let store = StateStore(root: root)
        let binary = try installation()
        DispatchQueue.concurrentPerform(iterations: 25) { index in
            try! store.update { $0.instances.append(DatabaseInstance(name: "db-\(index)", installation: binary, port: 30000 + index)) }
        }
        XCTAssertEqual(try store.load().instances.count, 25)
    }
    func testInvalidNamesPortsAndLimitsAreRejected() throws {
        let binary = try installation()
        for name in ["../outside", "", "bad\nname", "$(touch file)", "two words"] {
            XCTAssertThrowsError(try DatabaseManager.validate(DatabaseInstance(name: name, installation: binary, port: 5432)))
        }
        for port in [0, -1, 80, 65536] {
            XCTAssertThrowsError(try DatabaseManager.validate(DatabaseInstance(name: "local", installation: binary, port: port)))
        }
        var instance = DatabaseInstance(name: "local", installation: binary, port: 5432)
        instance.memoryMB = -1
        XCTAssertThrowsError(try DatabaseManager.validate(instance))
    }
    func testNativeConfigsBindToLoopbackAndPinExactBinary() throws {
        let store = StateStore(root: root)
        let provider = NativeProvider(store: store, runner: StoppedRunner())
        let manager = DatabaseManager(store: store, runner: StoppedRunner())
        for engine in DatabaseEngine.allCases {
            let instance = DatabaseInstance(name: "local", installation: try installation(engine), port: engine.defaultPort)
            XCTAssertTrue(provider.configuration(instance).contains("127.0.0.1") || engine == .memcached)
            let args = manager.jobDescription(instance)["ProgramArguments"] as! [String]
            let env = manager.jobDescription(instance)["EnvironmentVariables"] as! [String: String]
            XCTAssertEqual(env["LC_ALL"], "C")
            XCTAssertEqual(args.first, instance.installation.executable)
            XCTAssertFalse(args.contains("-d"))
            if engine == .mysql { XCTAssertTrue(provider.configuration(instance).contains("mysqlx=0")) }
            if engine == .memcached { XCTAssertEqual(Array(args.suffix(2)), ["-U", "0"]) }
            XCTAssertLessThan(store.socketURL(instance).path.utf8.count, 104)
        }
    }
    func testRemovePreservesDataByDefaultAndDeletionIsExplicit() throws {
        let store = StateStore(root: root)
        let manager = DatabaseManager(store: store, runner: StoppedRunner())
        let binary = try installation()
        for deleteData in [false, true] {
            let instance = DatabaseInstance(name: deleteData ? "delete" : "preserve", installation: binary, port: try manager.suggestedPort(engine: .mongodb))
            try manager.create(instance)
            let marker = store.dataDirectory(instance).appendingPathComponent("important-data")
            try Data("database".utf8).write(to: marker)
            try manager.remove(instance.id, deleteData: deleteData)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.instanceDirectory(instance).path))
            let archive = store.root.appendingPathComponent("archives/\(instance.id.uuidString.lowercased())/data/important-data")
            XCTAssertEqual(FileManager.default.fileExists(atPath: archive.path), !deleteData)
        }
        XCTAssertTrue(try store.load().instances.isEmpty)
    }
    func testSeparateInstancesNeverShareDataOrJobs() throws {
        let store = StateStore(root: root)
        let manager = DatabaseManager(store: store, runner: StoppedRunner())
        let binary = try installation()
        let first = DatabaseInstance(name: "first", installation: binary, port: try manager.suggestedPort(engine: .mongodb))
        try manager.create(first)
        let second = DatabaseInstance(name: "second", installation: binary, port: try manager.suggestedPort(engine: .mongodb))
        try manager.create(second)
        XCTAssertNotEqual(first.port, second.port)
        XCTAssertNotEqual(store.dataDirectory(first), store.dataDirectory(second))
        XCTAssertNotEqual(first.label, second.label)
        XCTAssertThrowsError(try manager.create(DatabaseInstance(name: "FIRST", installation: binary, port: second.port + 1)))
        XCTAssertEqual(try store.load().instances.count, 2)
        try manager.remove(first.id, deleteData: true)
        try manager.remove(second.id, deleteData: true)
    }
    func testVersionChangeCannotReuseAnInitializedDataDirectory() throws {
        let store = StateStore(root: root)
        let manager = DatabaseManager(store: store, runner: StoppedRunner())
        let binary = try installation()
        let original = DatabaseInstance(name: "local", installation: binary, port: try manager.suggestedPort(engine: .mongodb))
        try manager.create(original)
        let changed = DatabaseInstance(id: original.id, name: original.name,
            installation: Installation(engine: .mongodb, formula: "mongodb-community@8.0", version: "8.0", prefix: binary.prefix), port: original.port)
        XCTAssertThrowsError(try manager.update(changed))
        XCTAssertEqual(try manager.store.load().instances.first?.installation, binary)
        try manager.remove(original.id, deleteData: true)
    }
    func testInstallerRejectsForeignFormulaeAndCommandOptions() {
        XCTAssertTrue(HomebrewInstaller.isAllowedFormula("postgresql@17", engine: .postgresql))
        XCTAssertTrue(HomebrewInstaller.isAllowedFormula("mongodb/brew/mongodb-community@8.0", engine: .mongodb))
        for formula in ["--force", "mysql; touch /tmp/file", "other/tap/mysql", "mysql@8.4\n--force"] {
            XCTAssertFalse(HomebrewInstaller.isAllowedFormula(formula, engine: .mysql))
        }
    }
    func testAutoStartInIsolatedStoreDoesNotWriteRealLoginItems() throws {
        let store = StateStore(root: root)
        let manager = DatabaseManager(store: store, runner: StoppedRunner())
        let instance = DatabaseInstance(name: "login", installation: try installation(), port: try manager.suggestedPort(engine: .mongodb), autoStart: true)
        try manager.create(instance)
        XCTAssertTrue(store.loginJobURL(instance).path.hasPrefix(root.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.loginJobURL(instance).path))
        try manager.setAutoStart(instance.id, enabled: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.loginJobURL(instance).path))
        try manager.remove(instance.id, deleteData: true)
    }
    func testJSONCommandOutputIsNotCorruptedByLargeStderr() throws {
        let result = try CommandRunner().run("/usr/bin/python3", ["-c", "import sys; sys.stdout.write('{\"ok\":true}'); sys.stderr.write('warning\\n' * 10000)"], environment: [:])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(try result.checked(), "{\"ok\":true}")
        XCTAssertEqual(result.errorOutput.count, 80000)
    }
    func testRunningJobRemainsControllableAfterExternalBinaryRemoval() throws {
        let store = StateStore(root: root)
        let binary = try installation()
        let port = try DatabaseManager(store: store, runner: StoppedRunner()).suggestedPort(engine: .mongodb)
        let instance = DatabaseInstance(name: "running", installation: binary, port: port)
        try FileManager.default.removeItem(atPath: binary.executable)
        let manager = DatabaseManager(store: store, runner: RunningRunner())
        XCTAssertEqual(manager.status(instance), .starting)
    }
}
