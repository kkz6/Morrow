import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import CryptoKit

public struct ObjectStorageService: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let executable: String
    public let version: String
    public var apiPort: Int
    public var consolePort: Int
    public var autoStart: Bool
    public var label: String { "dev.morrow.s3.\(id.uuidString.lowercased())" }
    public var endpoint: URL { URL(string: "http://127.0.0.1:\(apiPort)")! }
    public var consoleURL: URL { URL(string: "http://127.0.0.1:\(consolePort)")! }
    public init(id: UUID = UUID(), name: String, executable: String, version: String, apiPort: Int = 9000, consolePort: Int = 9001, autoStart: Bool = false) {
        self.id = id; self.name = name; self.executable = executable; self.version = version
        self.apiPort = apiPort; self.consolePort = consolePort; self.autoStart = autoStart
    }
}
public struct S3Credentials: Codable, Sendable {
    public let accessKey: String
    public let secretKey: String
    public init(accessKey: String, secretKey: String) { self.accessKey = accessKey; self.secretKey = secretKey }
}
public struct ObjectStorageManager: Sendable {
    public let store: StateStore
    public let runner: any CommandRunning
    public init(store: StateStore = StateStore(), runner: any CommandRunning = CommandRunner()) { self.store = store; self.runner = runner }
    private var launchd: LaunchdControl { LaunchdControl(runner: runner) }
    public func directory(_ service: ObjectStorageService) -> URL { store.root.appendingPathComponent("object-storage/\(service.id.uuidString.lowercased())") }
    public func logURL(_ service: ObjectStorageService) -> URL { directory(service).appendingPathComponent("server.log") }
    private func job(_ service: ObjectStorageService) -> URL { store.root.appendingPathComponent("jobs/\(service.label).plist") }
    public func credentialsURL(_ service: ObjectStorageService) -> URL { directory(service).appendingPathComponent("credentials.json") }
    public func credentials(_ service: ObjectStorageService) throws -> S3Credentials {
        try JSONDecoder().decode(S3Credentials.self, from: Data(contentsOf: credentialsURL(service)))
    }
    public func resolve(_ name: String) throws -> ObjectStorageService {
        guard let service = try store.load().objectStorage.first(where: { $0.name == name || $0.id.uuidString.lowercased() == name.lowercased() }) else { throw MorrowError.message("No S3 service named '\(name)'. Run morrow storage list.") }; return service
    }
    public func suggestedPorts() throws -> (Int, Int) {
        let state = try store.load()
        let used = Set(state.instances.map(\.port) + state.mailServices.flatMap { [$0.smtpPort, $0.httpPort] } + state.webReservedPorts + state.objectStorage.flatMap { [$0.apiPort, $0.consolePort] })
        let free = (9000..<10000).filter { !used.contains($0) && DatabaseManager.portAvailable($0) }
        guard free.count >= 2 else { throw MorrowError.message("No free local S3 ports.") }; return (free[0], free[1])
    }
    public func preflight(name: String, api: Int, console: Int, excluding: UUID? = nil) throws {
        try DatabaseManager.validate(DatabaseInstance(name: name, installation: Installation(engine: .postgresql, formula: "", version: "", prefix: ""), port: api))
        guard (1024...65535).contains(console), api != console else { throw MorrowError.message("API and console need different ports between 1024 and 65535.") }
        let state = try store.load()
        let others = state.objectStorage.filter { $0.id != excluding }
        guard !others.contains(where: { $0.name.lowercased() == name.lowercased() }) else { throw MorrowError.message("An S3 server with this name already exists.") }
        let used = Set(state.instances.map(\.port) + state.mailServices.flatMap { [$0.smtpPort, $0.httpPort] } + state.webReservedPorts + others.flatMap { [$0.apiPort, $0.consolePort] })
        for port in [api, console] { guard !used.contains(port), DatabaseManager.portAvailable(port) else { throw MorrowError.message("Port \(port) is already reserved or in use.") } }
    }
    @discardableResult public func create(name: String, api: Int, console: Int, autoStart: Bool = false) throws -> ObjectStorageService {
        try store.operation {
            try preflight(name: name, api: api, console: console)
            let brew = HomebrewInstaller(runner: runner, configuredPath: try store.load().preferences.homebrewPath)
            var candidates = ["/opt/homebrew/bin/minio", "/usr/local/bin/minio"]
            candidates += (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":").filter { !$0.isEmpty }.map { $0 + "/minio" }
            if let executable = brew.executable {
                let prefix = URL(fileURLWithPath: executable).deletingLastPathComponent().deletingLastPathComponent()
                candidates.insert(prefix.appendingPathComponent("opt/minio/bin/minio").path, at: 0)
            }
            let path = try BinaryInstaller(store: store, runner: runner).auxiliary("minio", preferred: candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }))
            let binary = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            let output = try runner.run(binary, ["--version"], environment: [:]).checked()
            guard output.lowercased().contains("minio version") else { throw MorrowError.message("The executable is not MinIO.") }
            let version = output.components(separatedBy: .newlines).first ?? "MinIO"
            try preflight(name: name, api: api, console: console)
            let service = ObjectStorageService(name: name, executable: binary, version: version, apiPort: api, consolePort: console, autoStart: autoStart)
            try FileManager.default.createDirectory(at: directory(service).appendingPathComponent("data"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let credentials = S3Credentials(accessKey: "morrow" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(14), secretKey: UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
            try JSONEncoder().encode(credentials).write(to: credentialsURL(service), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsURL(service).path)
            try writeJobs(service)
            try store.update { $0.objectStorage.append(service) }
            return service
        }
    }
    public func start(_ id: UUID) throws {
        try store.operation {
            let service = try resolve(id.uuidString)
            if status(service) == .running || status(service) == .starting { return }
            guard FileManager.default.isExecutableFile(atPath: service.executable) else { throw MorrowError.message("The pinned MinIO binary is missing. Its data has been preserved.") }
            try preflight(name: service.name, api: service.apiPort, console: service.consolePort, excluding: id)
            try launchd.unload(service.label); try writeJobs(service); try launchd.bootstrap(job(service))
            for _ in 0..<40 {
                let state = status(service)
                if state == .running { return }
                if state == .failed { throw MorrowError.message("MinIO could not start. Open the server's logs.") }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }
    public func stop(_ id: UUID) throws { try store.operation { try launchd.unload(resolve(id.uuidString).label) } }
    public func update(_ service: ObjectStorageService) throws {
        try store.operation {
            let existing = try resolve(service.id.uuidString)
            guard ![.running, .starting].contains(status(existing)) else { throw MorrowError.message("Stop the S3 server before changing ports or settings.") }
            guard service.executable == existing.executable else { throw MorrowError.message("The native binary cannot be changed in this editor.") }
            try preflight(name: service.name, api: service.apiPort, console: service.consolePort, excluding: service.id)
            try writeJobs(service)
            try store.update { state in if let index = state.objectStorage.firstIndex(where: { $0.id == service.id }) { state.objectStorage[index] = service } }
        }
    }
    public func status(_ service: ObjectStorageService) -> InstanceStatus {
        guard let result = try? launchd.inspect(service.label) else { return .unknown }
        let info = LaunchdStatus(result.output)
        if result.status == 0, let pid = info.pid, ServiceHealth(runner: runner).processAlive(pid) {
            guard DatabaseManager.portListening(service.apiPort) else { return .starting }
            let response = try? HTTPTransport.send(URLRequest(url: service.endpoint.appendingPathComponent("minio/health/ready")), timeout: 2)
            return response?.status == 200 ? .running : .starting
        }
        if !FileManager.default.isExecutableFile(atPath: service.executable) { return .missingBinary }
        if result.status != 0 { return .stopped }
        if info.failed { return .failed }; return info.exitCode == 0 ? .stopped : .starting
    }
    public func buckets(_ service: ObjectStorageService) throws -> [String] {
        let result = try request(service, method: "GET", bucket: nil)
        let parser = XMLParser(data: result); parser.shouldResolveExternalEntities = false
        let delegate = BucketXML(); parser.delegate = delegate
        guard parser.parse() else { throw MorrowError.message("Could not read the bucket list.") }; return delegate.names.sorted()
    }
    public func createBucket(_ name: String, service: ObjectStorageService) throws { try validateBucket(name); _ = try request(service, method: "PUT", bucket: name) }
    public func deleteBucket(_ name: String, service: ObjectStorageService) throws { try validateBucket(name); _ = try request(service, method: "DELETE", bucket: name) }
    public func configuration(_ service: ObjectStorageService, bucket: String? = nil) throws -> String {
        let keys = try credentials(service)
        return "AWS_ACCESS_KEY_ID=\(keys.accessKey)\nAWS_SECRET_ACCESS_KEY=\(keys.secretKey)\nAWS_DEFAULT_REGION=us-east-1\nAWS_BUCKET=\(bucket ?? "your-bucket")\nAWS_ENDPOINT=\(service.endpoint.absoluteString)\nAWS_USE_PATH_STYLE_ENDPOINT=true"
    }
    public func remove(_ id: UUID) throws {
        try store.operation {
            let service = try resolve(id.uuidString); try launchd.unload(service.label)
            for file in [job(service), store.loginAgentURL(label: service.label)] where FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            let archive = store.root.appendingPathComponent("archives/s3-\(id.uuidString.lowercased())")
            try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: directory(service), to: archive)
            try store.update { $0.objectStorage.removeAll { $0.id == id } }
        }
    }
    private func validateBucket(_ value: String) throws {
        guard (3...63).contains(value.count), value.range(of: "^[a-z0-9][a-z0-9.-]*[a-z0-9]$", options: .regularExpression) != nil,
              !value.contains(".."), !value.contains(".-"), !value.contains("-."), !value.hasPrefix("xn--"), !value.hasSuffix("--x-s3"),
              value.range(of: "^[0-9]+(?:\\.[0-9]+){3}$", options: .regularExpression) == nil else { throw MorrowError.message("Use a 3–63 character S3 bucket name: lowercase letters, numbers, dots, or hyphens.") }
    }
    private func request(_ service: ObjectStorageService, method: String, bucket: String?) throws -> Data {
        let keys = try credentials(service)
        let uri = bucket.map { "/" + $0 } ?? "/"
        let url = URL(string: service.endpoint.absoluteString + uri)!
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let date = formatter.string(from: Date()), day = String(date.prefix(8)), host = "127.0.0.1:\(service.apiPort)"
        func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        func hmac(_ key: Data, _ text: String) -> Data { Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: key))) }
        let empty = hash(Data()), scope = "\(day)/us-east-1/s3/aws4_request"
        let headers = "host:\(host)\nx-amz-content-sha256:\(empty)\nx-amz-date:\(date)\n"
        let canonical = "\(method)\n\(uri)\n\n\(headers)\nhost;x-amz-content-sha256;x-amz-date\n\(empty)"
        let string = "AWS4-HMAC-SHA256\n\(date)\n\(scope)\n\(hash(Data(canonical.utf8)))"
        let signing = hmac(hmac(hmac(hmac(Data(("AWS4" + keys.secretKey).utf8), day), "us-east-1"), "s3"), "aws4_request")
        let signature = hmac(signing, string).map { String(format: "%02x", $0) }.joined()
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue(date, forHTTPHeaderField: "x-amz-date"); request.setValue(empty, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue("AWS4-HMAC-SHA256 Credential=\(keys.accessKey)/\(scope), SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=\(signature)", forHTTPHeaderField: "Authorization")
        let result = try HTTPTransport.send(request, timeout: 10)
        guard (200...299).contains(result.status) else {
            let message = String(decoding: result.data, as: UTF8.self)
            throw MorrowError.message("S3 request failed (\(result.status)). \(String(message.prefix(500)))")
        }
        return result.data
    }
    private func writeJobs(_ service: ObjectStorageService) throws {
        let keys = try credentials(service)
        let environment = ["MINIO_ROOT_USER": keys.accessKey, "MINIO_ROOT_PASSWORD": keys.secretKey, "MINIO_BROWSER_REDIRECT_URL": service.consoleURL.absoluteString, "MINIO_SERVER_URL": service.endpoint.absoluteString]
        let description: [String: Any] = ["Label": service.label, "ProgramArguments": ManagedServiceRunner.arguments([service.executable, "server", "--address", "127.0.0.1:\(service.apiPort)", "--console-address", "127.0.0.1:\(service.consolePort)", directory(service).appendingPathComponent("data").path]), "AssociatedBundleIdentifiers": ManagedServiceRunner.bundleIdentifiers,
            "WorkingDirectory": directory(service).path, "RunAtLoad": true, "KeepAlive": false, "ExitTimeOut": 30,
            "StandardOutPath": logURL(service).path, "StandardErrorPath": logURL(service).path, "EnvironmentVariables": environment]
        let data = try PropertyListSerialization.data(fromPropertyList: description, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: job(service).deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: job(service), options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: job(service).path)
        let login = store.loginAgentURL(label: service.label)
        if service.autoStart {
            try FileManager.default.createDirectory(at: login.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: login, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: login.path)
        } else if FileManager.default.fileExists(atPath: login.path) { try FileManager.default.removeItem(at: login) }
    }
}

private final class BucketXML: NSObject, XMLParserDelegate {
    var names: [String] = [], path: [String] = [], text = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) { path.append(elementName); text = "" }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Name", path.contains("Bucket") { names.append(text) }; path.removeLast(); text = ""
    }
}
public enum HTTPTransport {
    public struct Response: Sendable { public let status: Int; public let data: Data }
    public static func send(_ request: URLRequest, timeout: TimeInterval) throws -> Response {
        let box = HTTPResultBox(), semaphore = DispatchSemaphore(value: 0)
        let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForRequest = timeout; configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        let task = session.dataTask(with: request) { data, response, error in
            box.result = Result {
                if let error { throw error }
                guard let response = response as? HTTPURLResponse else { throw MorrowError.message("No HTTP response.") }
                let bytes = data ?? Data(); guard bytes.count <= 4_194_304 else { throw MorrowError.message("The response is too large.") }
                return Response(status: response.statusCode, data: bytes)
            }
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + timeout + 1) == .success else { task.cancel(); session.invalidateAndCancel(); throw MorrowError.message("The local server did not respond in time.") }
        defer { session.finishTasksAndInvalidate() }
        guard let result = box.result else { throw MorrowError.message("No server response.") }; return try result.get()
    }
}
private final class HTTPResultBox: @unchecked Sendable { var result: Result<HTTPTransport.Response, Error>? }
