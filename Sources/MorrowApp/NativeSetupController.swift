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
