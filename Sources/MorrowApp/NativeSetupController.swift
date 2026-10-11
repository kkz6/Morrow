import Foundation
import ServiceManagement
import AppKit
import MorrowCore
import CryptoKit

@MainActor enum NativeSetupController {
    enum Permission: Equatable {
        case allowed, needsApproval, notRegistered, unavailable
        var title: String {
            switch self { case .allowed: return "Allowed"; case .needsApproval: return "Approval needed"; case .notRegistered: return "Not enabled"; case .unavailable: return "Unavailable" }
        }
        init(_ status: SMAppService.Status) {
            switch status { case .enabled: self = .allowed; case .requiresApproval: self = .needsApproval; case .notRegistered: self = .notRegistered; default: self = .unavailable }
        }
    }
    private static var service: SMAppService { .daemon(plistName: "dev.morrow.setup.plist") }
    static var permission: Permission { Permission(service.status) }
    static var loginPermission: Permission { Permission(SMAppService.mainApp.status) }
    static var approved: Bool { service.status == .enabled }
    static func register() throws -> Bool {
        if service.status != .enabled && service.status != .requiresApproval { try service.register() }
        switch service.status {
        case .enabled: return true
        case .requiresApproval: return false
        default: throw MorrowError.message("Morrow's setup helper is unavailable. Install the complete app bundle; customer releases need Developer ID signing and notarization.")
        }
    }
    /// Explicit cleanup migrates an older helper registration to this signed
    /// bundle. Only the setup helper is re-registered; server jobs are untouched.
    static func refreshSignedRegistration(store: StateStore) async throws -> Bool {
        let launcher = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/morrow")
        guard BackgroundAttribution(launcher: launcher).ready else {
            throw MorrowError.message("Install the signed Morrow app before updating its setup helper.")
        }
        struct Registration: Codable, Equatable {
            let app: String
            let executableSHA256: String
        }
        let current = Registration(app: Bundle.main.bundleURL.path,
            executableSHA256: SHA256.hash(data: try Data(contentsOf: launcher)).map { String(format: "%02x", $0) }.joined())
        let marker = store.root.appendingPathComponent("setup-registration.json")
        let previous = (try? Data(contentsOf: marker)).flatMap { try? JSONDecoder().decode(Registration.self, from: $0) }
        if previous == current, service.status == .enabled || service.status == .requiresApproval { return service.status == .enabled }
        if service.status == .enabled || service.status == .requiresApproval {
            try await service.unregister()
        }
        do { try service.register() }
        catch { if service.status != .requiresApproval { throw error } }
        guard service.status == .enabled || service.status == .requiresApproval else {
            throw MorrowError.message("macOS could not register Morrow's signed setup helper.")
        }
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(current).write(to: marker, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        return service.status == .enabled
    }
    static func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }
    static func requestApproval() {
        guard permission == .needsApproval else { return }
        let alert = NSAlert()
        alert.messageText = "Allow Morrow Setup"
        alert.informativeText = "Morrow needs permission to configure local project domains and ports 80/443. macOS will keep the approval for its setup helper. Your password is never stored. Continue to macOS's approval settings to allow it."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Not Now")
        if var window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "morrow.settings" }) {
            while let sheet = window.attachedSheet { window = sheet }
            alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { openApprovalSettings() } }
        } else if alert.runModal() == .alertFirstButtonReturn { openApprovalSettings() }
    }
}
