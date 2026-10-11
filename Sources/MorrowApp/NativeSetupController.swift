import Foundation
import ServiceManagement
import AppKit
import MorrowCore

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
    private static var service: SMAppService { .daemon(plistName: "dev.morrow.helper.setup.plist") }
    // Retained solely to unregister the earlier development helper. Never register it.
    private static var legacyService: SMAppService { .daemon(plistName: "dev.morrow.setup.plist") }
    static var permission: Permission { Permission(service.status) }
    static var loginPermission: Permission { Permission(SMAppService.mainApp.status) }
    static var approved: Bool { service.status == .enabled }
    static func register() throws -> Bool {
        if service.status != .enabled && service.status != .requiresApproval {
            do { try service.register() }
            catch { guard needsApproval(error) else { throw error }; return false }
        }
        switch service.status {
        case .enabled: return true
        case .requiresApproval: return false
        default: throw MorrowError.message("Morrow's setup helper is unavailable. Install the complete app bundle; customer releases need Developer ID signing and notarization.")
        }
    }
    private static func needsApproval(_ error: Error) -> Bool {
        let error = error as NSError
        return service.status == .requiresApproval || (error.domain == "SMAppServiceErrorDomain" && error.code == 1)
    }
    private struct Registration: Codable, Equatable {
        let app: String
        let executableCodeHash: String
    }
    private static func currentRegistration() throws -> Registration {
        let launcher = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/morrow")
        let attribution = BackgroundAttribution(launcher: launcher)
        guard attribution.ready, let codeHash = attribution.launcherCodeHash else {
            throw MorrowError.message("Install the signed Morrow app before updating its setup helper.")
        }
        return Registration(app: Bundle.main.bundleURL.path, executableCodeHash: codeHash)
    }
    /// Refresh an existing approved helper after a real executable update.
    /// This does not register a helper for users who have never enabled setup.
    static func updateRegisteredHelperIfChanged(store: StateStore) async throws -> Bool? {
        guard service.status == .enabled, NativeSetupBridge.pendingRequest() == nil,
              let data = try? Data(contentsOf: store.root.appendingPathComponent("setup-registration.json")),
              let previous = try? JSONDecoder().decode(Registration.self, from: data) else { return nil }
        guard try currentRegistration() != previous else { return nil }
        return try await refreshSignedRegistration(store: store)
    }
    /// Explicit cleanup migrates an older helper registration to this signed
    /// bundle. Only the setup helper is re-registered; server jobs are untouched.
    static func refreshSignedRegistration(store: StateStore) async throws -> Bool {
        // CodeDirectory hashes exclude signing timestamps, so signing identical
        // executable code again does not needlessly replace an approved helper.
        let current = try currentRegistration()
        let marker = store.root.appendingPathComponent("setup-registration.json")
        let previous = (try? Data(contentsOf: marker)).flatMap { try? JSONDecoder().decode(Registration.self, from: $0) }
        if previous == current, service.status == .enabled || service.status == .requiresApproval { return service.status == .enabled }
        if legacyService.status == .enabled || legacyService.status == .requiresApproval {
            try await legacyService.unregister()
        }
        if service.status == .enabled || service.status == .requiresApproval {
            try await service.unregister()
        }
        var awaitingApproval = false
        do { try service.register() }
        catch { guard needsApproval(error) else { throw error }; awaitingApproval = true }
        guard awaitingApproval || service.status == .enabled || service.status == .requiresApproval else {
            throw MorrowError.message("macOS could not register Morrow's signed setup helper.")
        }
        try FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(current).write(to: marker, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        return service.status == .enabled
    }
    static func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }
    static func requestApproval(afterRegistrationDenied: Bool = false) {
        guard afterRegistrationDenied || permission == .needsApproval else { return }
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
