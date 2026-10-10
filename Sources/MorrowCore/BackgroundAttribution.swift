import Foundation
import CoreServices
import Security

/// Launch Services registration and signing diagnostics do not change launchd
/// jobs or running processes. macOS requires matching Apple team identifiers
/// before it honors legacy helpers' AssociatedBundleIdentifiers.
public struct BackgroundAttribution: Sendable {
    public let appURL: URL?
    public let appTeam: String?
    public let launcherTeam: String?
    public let signaturesValid: Bool
    public var ready: Bool { signaturesValid && appTeam != nil && appTeam == launcherTeam }
    public var message: String {
        guard appURL != nil else { return "The complete Morrow app is needed for background grouping." }
        guard appTeam != nil, launcherTeam != nil else { return "This unsigned development build cannot consolidate macOS background entries. Apple signing is deferred until release." }
        guard ready else { return "The app and service launcher need valid signatures from the same Apple team." }
        return "The app and service launcher share an Apple signing team. macOS controls when its background list refreshes."
    }
    public init(launcher: URL) {
        let bundle = launcher.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard bundle.pathExtension == "app", Bundle(url: bundle)?.bundleIdentifier == "dev.morrow.app",
              let executable = Bundle(url: bundle)?.executableURL else {
            appURL = nil; appTeam = nil; launcherTeam = nil; signaturesValid = false; return
        }
        appURL = bundle
        let app = Self.signature(executable), cli = Self.signature(launcher)
        appTeam = app.team; launcherTeam = cli.team; signaturesValid = app.valid && cli.valid
    }
    static func signature(_ url: URL) -> (team: String?, valid: Bool) {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return (nil, false) }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any] else { return (nil, false) }
        let team = values[kSecCodeInfoTeamIdentifier as String] as? String
        return (team?.isEmpty == false ? team : nil, SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess)
    }
    public func registerApp() throws {
        guard let appURL else { return }
        let result = LSRegisterURL(appURL as CFURL, true)
        guard result == noErr else { throw MorrowError.message("Morrow could not register its app identity with macOS (\(result)).") }
    }
}
