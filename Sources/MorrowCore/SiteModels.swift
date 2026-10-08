import Foundation

public enum SiteMode: String, Codable, CaseIterable, Sendable { case php, files, proxy }
public struct ProjectDirectory: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let path: String
    public var enabled: Bool
    public init(id: UUID = UUID(), path: String, enabled: Bool = true) { self.id = id; self.path = path; self.enabled = enabled }
}
public struct LocalSite: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var domain: String
    public var automaticDomain: Bool
    public let path: String
    public var documentRoot: String
    public var mode: SiteMode
    public var proxyPort: Int?
    public var https: Bool
    public var phpID: String?
    public let directoryID: UUID?
    public var issue: String?
    public init(id: UUID = UUID(), domain: String, path: String, documentRoot: String, mode: SiteMode, proxyPort: Int? = nil, https: Bool = false, phpID: String? = nil, directoryID: UUID? = nil, issue: String? = nil, automaticDomain: Bool = true) {
        self.id = id; self.domain = domain; self.automaticDomain = automaticDomain; self.path = path; self.documentRoot = documentRoot; self.mode = mode
        self.proxyPort = proxyPort; self.https = https; self.phpID = phpID; self.directoryID = directoryID; self.issue = issue
    }
}
public struct WebWorkspace: Codable, Equatable, Sendable {
    public var id = UUID()
    public var enabled = false
    public var suffix = "test"
    public var additionalSuffixes: [String] = []
    public var defaultHTTPS = false
    public var autoStart = true
    public var httpPort = 8080
    public var httpsPort = 8443
    public var dnsPort = 5354
    public var directories: [ProjectDirectory] = []
    public var sites: [LocalSite] = []
    public var php: [RuntimeInstallation] = []
    public var defaultPHPID: String?
    public var caddyPath: String?
    public var dnsmasqPath: String?
    public var cliPath: String?
    public init() {}
}
public enum SiteStatus: String, Sendable {
    case serving = "Serving", stopped = "Stopped", missingFolder = "Folder missing", needsPHP = "PHP unavailable", waitingForApp = "Waiting for app", configurationIssue = "Needs attention"
}
public struct WebStatus: Sendable {
    public let proxy: InstanceStatus
    public let dns: InstanceStatus
    public let systemConfigured: Bool
    public let setupMessage: String
    public let sites: [UUID: SiteStatus]
}

extension WebWorkspace {
    public var suffixes: [String] { Array(Set([suffix] + additionalSuffixes)).sorted() }
}

extension MorrowState {
    var webReservedPorts: [Int] {
        guard web.caddyPath != nil || !web.sites.isEmpty || !web.directories.isEmpty else { return [] }
        return [web.httpPort, web.httpsPort, web.dnsPort] + web.sites.filter { $0.mode == .proxy }.compactMap(\.proxyPort)
    }
}
