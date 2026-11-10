import AppKit
import SwiftUI
import MorrowCore

/// A reading workspace, independent of the fixed-size settings window.
@MainActor final class MailWindowController: NSObject, NSWindowDelegate {
    static let initialSize = CGSize(width: 1040, height: 740)
    static let minimumSize = CGSize(width: 800, height: 540)
    private let id: UUID
    private let title: String
    private let onClose: () -> Void
    private var controller: NSWindowController?

    init(id: UUID, title: String, onClose: @escaping () -> Void = {}) {
        self.id = id; self.title = title; self.onClose = onClose
    }

    func show(service: MailService, model: AppModel) {
        let window = prepareWindow(MailWindowRoot(service: service, model: model))
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller?.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    @discardableResult func prepareWindow<Content: View>(_ content: Content) -> NSWindow {
        if let window = controller?.window { return window }
        let visible = NSScreen.main?.visibleFrame.size ?? Self.initialSize
        let size = CGSize(width: max(Self.minimumSize.width, min(Self.initialSize.width, visible.width - 48)),
                          height: max(Self.minimumSize.height, min(Self.initialSize.height, visible.height - 80)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.identifier = NSUserInterfaceItemIdentifier("morrow.mail.\(id)")
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.contentMinSize = Self.minimumSize
        window.setContentSize(size)
        let frameName = "morrow.mail.\(id.uuidString)"
        if !window.setFrameUsingName(frameName) { window.center() }
        window.setFrameAutosaveName(frameName)
        window.delegate = self
        controller = NSWindowController(window: window)
        return window
    }

    func close() { controller?.close() }

    func windowWillClose(_ notification: Notification) {
        // Release the view so closing the window cancels its polling tasks.
        controller?.window?.contentViewController = nil
        onClose()
    }
}

private struct MailWindowRoot: View {
    let service: MailService
    let model: AppModel
    var body: some View {
        MailInboxView(service: service).environment(model).tint(.morrowAccent)
            .preferredColorScheme(model.colorScheme)
            .background(SettingsWindowAppearance(scheme: model.colorScheme))
    }
}
