import Foundation
import CryptoKit
import Darwin
import CArchive

/// A catalog describes complete relocatable distributions, including their
/// libraries and initialization tools. It never contains installation scripts.
public struct BinaryCatalog: Codable, Sendable {
    public let schemaVersion: Int
    public let releases: [BinaryRelease]
}

public struct BinaryRelease: Codable, Equatable, Identifiable, Sendable {
    public let package: String
    public let version: String
    public let architecture: String
    public let minimumMacOS: String
    public let url: URL
    public let sha256: String
    public let archive: String
    public let rootDirectory: String
    public let executables: [String]
    public var id: String { "\(package):\(version):\(architecture):\(sha256.lowercased())" }
    public var channel: String { "managed:\(package)@\(version)" }
}

public struct ManagedBinaryInstallation: Codable, Sendable {
    public let release: BinaryRelease
    public let prefix: String
}

public struct ManagedBinaryStore: Sendable {
    public let store: StateStore
    public let runner: any CommandRunning
    public init(store: StateStore, runner: any CommandRunning = CommandRunner()) { self.store = store; self.runner = runner }
    public static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
    private static var packages: Set<String> {
        Set(DatabaseEngine.allCases.map(\.rawValue) + RuntimeEngine.allCases.map(\.rawValue) + ["caddy", "dnsmasq", "mailpit", "minio"])
    }
    private var directory: URL { store.root.appendingPathComponent("binaries") }
    private struct Cache: Codable { let source: String; let updated: Date; let catalog: BinaryCatalog }
    public static func validateCatalogURL(_ value: String) throws -> URL? {
        if value.isEmpty { return nil }
        guard let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.fragment == nil else {
            throw MorrowError.message("Use an HTTPS catalog URL without embedded credentials.")
        }
        return url
    }
    public func configure(url: String) throws {
        _ = try Self.validateCatalogURL(url)
        // Validate the source before saving it, leaving the previous one intact
        // on a network failure or unsupported catalog format.
        if let endpoint = try Self.validateCatalogURL(url) { _ = try fetchCatalog(endpoint) }
        try store.update { $0.preferences.binaryCatalogURL = url }
        var inventory = InventoryStore(store: store).load(); inventory.channels = [:]
        try InventoryStore(store: store).save(inventory)
        try? FileManager.default.removeItem(at: store.root.appendingPathComponent("binary-catalog.json"))
    }
    public func releases(package: String? = nil, refresh: Bool = false) throws -> [BinaryRelease] {
        let source = try store.load().preferences.binaryCatalogURL
        var values: [BinaryRelease] = []
        if let endpoint = try Self.validateCatalogURL(source) {
            let cacheURL = store.root.appendingPathComponent("binary-catalog.json")
            let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
            let catalog: BinaryCatalog
            if !refresh, let cached, cached.source == source, Date().timeIntervalSince(cached.updated) < 3600 {
                catalog = cached.catalog
            } else {
                catalog = try fetchCatalog(endpoint)
                try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try JSONEncoder().encode(Cache(source: source, updated: Date(), catalog: catalog)).write(to: cacheURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
            }
            values = catalog.releases
        }
        // Go publishes complete macOS archives and authoritative SHA-256 hashes.
        // No guessed database download URLs or Homebrew bottles are used.
        if package == "go", !values.contains(where: { $0.package == "go" }) { values += try goReleases() }
        var seen = Set<String>()
        return values.filter { (package == nil || $0.package == package) && compatible($0) }
            .sorted {
                if $0.version == $1.version { return $0.architecture == Self.architecture && $1.architecture != Self.architecture }
                return Self.newer($0.version, than: $1.version)
            }.filter { seen.insert($0.package + ":" + $0.version).inserted }
    }
    public func release(package: String, request: String) throws -> BinaryRelease? {
        let values = try releases(package: package)
        if ["automatic", "latest", "current"].contains(request) { return values.first }
        let wanted = Self.requestedVersion(request, package: package)
        if request.hasPrefix("managed:") { return values.first { $0.version == wanted } }
        return values.first { $0.version == wanted } ?? values.first { $0.version.hasPrefix(wanted + ".") }
    }
    public static func requestedVersion(_ request: String, package: String) -> String {
        for prefix in ["managed:\(package)@", "\(package)@"] where request.hasPrefix(prefix) { return String(request.dropFirst(prefix.count)) }
        return request
    }
    public static func matches(_ version: String, request: String, package: String) -> Bool {
        let wanted = requestedVersion(request, package: package)
        if request.hasPrefix("managed:") { return version == wanted }
        return version == wanted || version.hasPrefix(wanted + ".")
    }
    private static func newer(_ lhs: String, than rhs: String) -> Bool {
        if let l = SoftwareVersion(lhs), let r = SoftwareVersion(rhs) { return l > r }
        return lhs.localizedStandardCompare(rhs) == .orderedDescending
    }
    private func compatible(_ release: BinaryRelease) -> Bool {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let current = SoftwareVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")!
        return [Self.architecture, "universal"].contains(release.architecture) && SoftwareVersion(release.minimumMacOS).map { current >= $0 } == true
    }
    private func fetchCatalog(_ url: URL) throws -> BinaryCatalog {
        let catalog = try JSONDecoder().decode(BinaryCatalog.self, from: fetchJSON(url))
        guard catalog.schemaVersion == 1, catalog.releases.count <= 5000 else { throw MorrowError.message("Unsupported binary catalog format.") }
        var seen = Set<String>()
        for release in catalog.releases {
            try validate(release)
            guard seen.insert("\(release.package):\(release.version):\(release.architecture)").inserted else { throw MorrowError.message("The binary catalog contains conflicting releases. Publish rebuilds with a new revision.") }
        }
        return catalog
    }
    private func fetchJSON(_ url: URL, limit: Int = 2_097_152) throws -> Data {
        let output = try runner.run("/usr/bin/curl", ["--fail", "--silent", "--show-error", "--location", "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "10", "--max-time", "30", "--max-filesize", String(limit), url.absoluteString], environment: [:]).checked()
        guard let data = output.data(using: .utf8), data.count <= limit else { throw MorrowError.message("Binary catalog is too large.") }
        return data
    }
    private func goReleases() throws -> [BinaryRelease] {
        struct GoFile: Decodable { let filename: String; let os: String; let arch: String; let sha256: String; let kind: String }
        struct GoRelease: Decodable { let version: String; let stable: Bool; let files: [GoFile] }
        let cacheURL = store.root.appendingPathComponent("go-releases.json")
        let age = (try? FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date).map { Date().timeIntervalSince($0) } ?? .infinity
        let data: Data
        if age < 3600, let cached = try? Data(contentsOf: cacheURL) { data = cached }
        else {
            data = try fetchJSON(URL(string: "https://go.dev/dl/?mode=json&include=all")!, limit: 16_777_216)
            _ = try JSONDecoder().decode([GoRelease].self, from: data)
            try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: cacheURL, options: .atomic)
        }
        let arch = Self.architecture == "arm64" ? "arm64" : "amd64"
        return try JSONDecoder().decode([GoRelease].self, from: data).filter(\.stable).compactMap { release in
            guard let file = release.files.first(where: { $0.os == "darwin" && $0.arch == arch && $0.kind == "archive" && $0.filename.hasSuffix(".tar.gz") }),
                  file.filename.range(of: "^go[0-9.]+\\.darwin-(arm64|amd64)\\.tar\\.gz$", options: .regularExpression) != nil else { return nil }
            return BinaryRelease(package: "go", version: String(release.version.dropFirst(2)), architecture: Self.architecture, minimumMacOS: "14.0", url: URL(string: "https://go.dev/dl/" + file.filename)!, sha256: file.sha256, archive: "tar", rootDirectory: "go", executables: ["bin/go", "bin/gofmt"])
        }
    }
    private func validate(_ release: BinaryRelease) throws {
        guard Self.packages.contains(release.package), release.version.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$", options: .regularExpression) != nil,
              ["arm64", "x86_64", "universal"].contains(release.architecture), SoftwareVersion(release.minimumMacOS) != nil,
              release.sha256.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil,
              ["tar", "zip", "binary"].contains(release.archive), !release.executables.isEmpty else { throw MorrowError.message("Invalid binary release metadata.") }
        _ = try Self.validateCatalogURL(release.url.absoluteString)
        if !release.rootDirectory.isEmpty { _ = try relative(release.rootDirectory) }
        for path in release.executables { _ = try relative(path) }
    }
    public func installations() -> [ManagedBinaryInstallation] {
        let fm = FileManager.default
        var result: [ManagedBinaryInstallation] = []
        for package in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            for version in (try? fm.contentsOfDirectory(at: package, includingPropertiesForKeys: nil)) ?? [] {
                if let data = try? Data(contentsOf: version.appendingPathComponent(".morrow-release.json")), let release = try? JSONDecoder().decode(BinaryRelease.self, from: data),
                   (try? validate(release)) != nil, compatible(release), release.executables.allSatisfy({ fm.isExecutableFile(atPath: version.appendingPathComponent($0).path) }) {
                    result.append(ManagedBinaryInstallation(release: release, prefix: version.path))
                }
            }
        }
        return result.sorted { Self.newer($0.release.version, than: $1.release.version) }
    }
    /// Called inside the shared operation lock. Downloads are staged privately,
    /// hashed before extraction, and published without replacing another copy.
    public func install(_ release: BinaryRelease) throws -> ManagedBinaryInstallation {
        try validate(release)
        guard compatible(release) else { throw MorrowError.message("This binary does not support this Mac's architecture or macOS version.") }
        let fm = FileManager.default
        let target = directory.appendingPathComponent(release.package).appendingPathComponent("\(release.version)-\(release.architecture)-\(release.sha256.lowercased().prefix(12))")
        if let existing = installations().first(where: { $0.release.id == release.id }) { return existing }
        guard !fm.fileExists(atPath: target.path) else { throw MorrowError.message("An incomplete binary directory exists. It was preserved; repair it before retrying.") }
        let staging = store.root.appendingPathComponent("downloads/\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        let download = staging.appendingPathComponent("download")
        try runner.run("/usr/bin/curl", ["--fail", "--silent", "--show-error", "--location", "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "15", "--max-time", "1200", "--max-filesize", "4294967296", "--output", download.path, release.url.absoluteString], environment: [:]).checked()
        let handle = try FileHandle(forReadingFrom: download)
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        try handle.close()
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == release.sha256.lowercased() else { throw MorrowError.message("Binary checksum failed. Nothing was installed.") }
        let payload = staging.appendingPathComponent("payload")
        try fm.createDirectory(at: payload, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if release.archive == "binary" {
            guard release.rootDirectory.isEmpty, release.executables.count == 1 else { throw MorrowError.message("A raw binary must define one executable.") }
            let binary = payload.appendingPathComponent(release.executables[0])
            try fm.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: download, to: binary)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        } else { try extract(download, to: payload) }
        let prefix = release.rootDirectory.isEmpty ? payload : payload.appendingPathComponent(release.rootDirectory)
        for path in release.executables {
            let binary = prefix.appendingPathComponent(path)
            guard binary.resolvingSymlinksInPath().path.hasPrefix(prefix.standardizedFileURL.path + "/"), fm.isExecutableFile(atPath: binary.path) else { throw MorrowError.message("The distribution is missing \(path).") }
            try validateArchitecture(binary)
        }
        try JSONEncoder().encode(release).write(to: prefix.appendingPathComponent(".morrow-release.json"), options: .atomic)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.moveItem(at: prefix, to: target)
        return ManagedBinaryInstallation(release: release, prefix: target.path)
    }
    /// Read Mach-O headers directly; customers need neither Xcode nor lipo.
    /// Runtime scripts are subsequently checked by their native version probe.
    private func validateArchitecture(_ binary: URL) throws {
        let handle = try FileHandle(forReadingFrom: binary)
        defer { try? handle.close() }
        let bytes = [UInt8](try handle.read(upToCount: 4096) ?? Data())
        if bytes.starts(with: [0x23, 0x21]) { return }
        func number(_ offset: Int, little: Bool) -> UInt32? {
            guard offset + 4 <= bytes.count else { return nil }
            let values = Array(bytes[offset..<offset + 4])
            let ordered = little ? Array(values.reversed()) : values
            return ordered.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        let expected: UInt32 = Self.architecture == "arm64" ? 0x0100000c : 0x01000007
        let magic = Array(bytes.prefix(4))
        let little = magic == [0xcf, 0xfa, 0xed, 0xfe] || magic == [0xce, 0xfa, 0xed, 0xfe]
        let big = magic == [0xfe, 0xed, 0xfa, 0xcf] || magic == [0xfe, 0xed, 0xfa, 0xce]
        if little || big, number(4, little: little) == expected { return }
        let fatBig = magic == [0xca, 0xfe, 0xba, 0xbe] || magic == [0xca, 0xfe, 0xba, 0xbf]
        let fatLittle = magic == [0xbe, 0xba, 0xfe, 0xca] || magic == [0xbf, 0xba, 0xfe, 0xca]
        if fatBig || fatLittle, let count = number(4, little: fatLittle), count <= 64 {
            let width = magic == [0xca, 0xfe, 0xba, 0xbf] || magic == [0xbf, 0xba, 0xfe, 0xca] ? 32 : 20
            if (0..<Int(count)).contains(where: { number(8 + $0 * width, little: fatLittle) == expected }) { return }
        }
        throw MorrowError.message("The distribution contains an executable that does not support this Mac's native architecture.")
    }
    private func relative(_ value: String) throws -> String {
        let pieces = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !value.hasPrefix("/"), !value.contains("\\"), !pieces.contains(".."), !value.contains("\0"), value.count <= 4096 else { throw MorrowError.message("Unsafe archive path.") }
        return pieces.filter { !$0.isEmpty && $0 != "." }.joined(separator: "/")
    }
    private func extract(_ file: URL, to root: URL) throws {
        guard let reader = archive_read_new() else { throw MorrowError.message("Archive reader unavailable.") }
        defer { archive_read_free(reader) }
        archive_read_support_filter_all(reader); archive_read_support_format_tar(reader); archive_read_support_format_zip(reader)
        guard archive_read_open_filename(reader, file.path, 65536) == ARCHIVE_OK else { throw MorrowError.message("The binary archive could not be opened.") }
        var entry: OpaquePointer?
        var links: [(URL, String)] = [], count = 0, total: Int64 = 0
        let fm = FileManager.default
        while true {
            let status = archive_read_next_header(reader, &entry)
            if status == ARCHIVE_EOF { break }
            guard status == ARCHIVE_OK, let entry, let raw = archive_entry_pathname(entry) else { throw MorrowError.message("Invalid binary archive.") }
            count += 1
            let path = try relative(String(cString: raw))
            guard count <= 100_000 else { throw MorrowError.message("Binary archive has too many entries.") }
            if path.isEmpty { archive_read_data_skip(reader); continue }
            let destination = root.appendingPathComponent(path)
            guard archive_entry_hardlink(entry) == nil else { throw MorrowError.message("Binary archives must not contain hard links.") }
            let type = archive_entry_filetype(entry)
            if type == mode_t(S_IFDIR) {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
            } else if type == mode_t(S_IFLNK), let target = archive_entry_symlink(entry) {
                let link = String(cString: target)
                guard !link.hasPrefix("/"), !link.contains("\0"), destination.deletingLastPathComponent().appendingPathComponent(link).standardizedFileURL.path.hasPrefix(root.path + "/") else { throw MorrowError.message("A binary archive link escapes its directory.") }
                links.append((destination, link))
            } else if type == mode_t(S_IFREG) {
                let size = archive_entry_size(entry)
                guard size >= 0, size <= 8_589_934_592, total <= 8_589_934_592 - size else { throw MorrowError.message("Binary archive is too large.") }
                total += size
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
                let fd = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(archive_entry_perm(entry) & 0o755))
                guard fd >= 0 else { throw MorrowError.message("The binary archive contains conflicting paths.") }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                var buffer = [UInt8](repeating: 0, count: 65536), written: Int64 = 0
                while true {
                    let length = archive_read_data(reader, &buffer, buffer.count)
                    guard length >= 0 else { throw MorrowError.message("Truncated binary archive.") }
                    if length == 0 { break }
                    written += Int64(length)
                    guard written <= size else { throw MorrowError.message("Invalid archive entry size.") }
                    try handle.write(contentsOf: Data(buffer.prefix(length)))
                }
                try handle.close()
                guard written == size else { throw MorrowError.message("Truncated archive entry.") }
            } else { throw MorrowError.message("Binary archives can contain only files, directories, and internal symbolic links.") }
            archive_read_data_skip(reader)
        }
        // Links are created last, so extraction can never write through them.
        for (destination, target) in links {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
        }
        for (destination, _) in links where !destination.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") { throw MorrowError.message("An archive link escapes its directory.") }
    }
}
