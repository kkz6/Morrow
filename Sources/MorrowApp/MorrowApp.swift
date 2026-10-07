import SwiftUI
import AppKit

@main
struct MorrowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel
    private let settingsController: SettingsWindowController

    init() {
        let snapshot = CommandLine.arguments.contains("--snapshot")
        let model = AppModel(preview: snapshot)
        if CommandLine.arguments.contains("--logs") { model.selection = .logs }
        if snapshot && CommandLine.arguments.contains("--snapshot-installed") {
            model.instances = []
            model.statuses = [:]
        }
        if snapshot && CommandLine.arguments.contains("--snapshot-logs") {
            model.selection = .logs
            model.logInstanceID = model.instances.first?.id
        }
        if snapshot, let index = CommandLine.arguments.firstIndex(of: "--snapshot-section"),
           index + 1 < CommandLine.arguments.count,
           let section = SettingsSection(rawValue: CommandLine.arguments[index + 1]) {
            model.selection = section
        }
        let controller = SettingsWindowController(configuration: SettingsWindowConfiguration(
            identifier: NSUserInterfaceItemIdentifier("morrow.settings"), title: "Morrow Settings",
            size: SettingsLayout.windowSize, trafficLightLeading: SettingsLayout.trafficLightLeading,
            trafficLightCenterFromTop: SettingsLayout.titlebarControlCenterFromTop))
        _model = State(initialValue: model)
        settingsController = controller
        AppDelegate.onLaunch = {
            if snapshot {
                SnapshotRenderer.render(model: model, controller: controller)
            } else {
                model.startMonitoring()
                if CommandLine.arguments.contains("--settings") {
                    controller.show(SettingsRoot(model: model))
                }
            }
        }
        AppDelegate.onReopen = { controller.show(SettingsRoot(model: model)) }
    }
    var body: some Scene {
        MenuBarExtra {
            DatabasePopover().environment(model)
                .environment(\.openSettingsWindow, SettingsWindowOpeningAction { openSettings() })
                .tint(.morrowAccent).preferredColorScheme(model.colorScheme)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "externaldrive.fill")
                if model.preferences.showRunningCount { Text("\(model.runningCount)").monospacedDigit() }
            }
        }.menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { openSettings() }.keyboardShortcut(",", modifiers: .command)
            }
        }
    }
    private func openSettings() { settingsController.show(SettingsRoot(model: model)) }
}

private struct SettingsRoot: View {
    let model: AppModel
    var body: some View { SettingsWindow().environment(model).tint(.morrowAccent).preferredColorScheme(model.colorScheme) }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    static var onLaunch: (() -> Void)?
    static var onReopen: (() -> Void)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        Self.onLaunch?()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.onReopen?(); return true
    }
}

/// Render only Morrow's own views with isolated fixture data. No screen capture
/// or access to the user's databases is involved.
@MainActor private enum SnapshotRenderer {
    static func render(model: AppModel, controller: SettingsWindowController) {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { NSApplication.shared.terminate(nil); return }
        let directory = URL(fileURLWithPath: args[index + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let window = controller.prepareWindow(SettingsRoot(model: model))
        window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            if let view = window.contentView { save(view: view, to: directory.appendingPathComponent("settings.png")) }
            let menu = NSHostingView(rootView: DatabasePopover().environment(model).tint(.morrowAccent)
                .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.light))
            let instanceRows = min(model.instances.count, 6)
            let height = CGFloat(model.instances.isEmpty ? 266 : 92 + instanceRows * 58)
            menu.frame = NSRect(x: 0, y: 0, width: 340, height: height)
            let menuWindow = NSWindow(contentRect: menu.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            menuWindow.contentView = menu
            menuWindow.backgroundColor = .windowBackgroundColor
            menuWindow.orderFront(nil)
            menu.layoutSubtreeIfNeeded()
            save(view: menu, to: directory.appendingPathComponent("menu.png"))
            if args.contains("--snapshot-editor") {
                let editor = NSHostingView(rootView: InstanceEditor(installation: model.installations.first)
                    .environment(model).tint(.morrowAccent).background(Color(nsColor: .windowBackgroundColor)))
                editor.frame = NSRect(x: 0, y: 0, width: 470, height: 640)
                let editorWindow = NSWindow(contentRect: editor.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                editorWindow.contentView = editor
                editorWindow.backgroundColor = .windowBackgroundColor
                editorWindow.orderFront(nil)
                editor.layoutSubtreeIfNeeded()
                save(view: editor, to: directory.appendingPathComponent("editor.png"))
            }
            NSApplication.shared.terminate(nil)
        }
    }
    private static func save(view: NSView, to url: URL) {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) { try? png.write(to: url) }
    }
}
