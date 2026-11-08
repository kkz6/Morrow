import Observation
import Sparkle

/// Owns Sparkle's updater for the lifetime of the application.
///
/// Sparkle performs scheduled background checks and presents its standard,
/// accessible update UI when a newer signed release is available.
@MainActor
@Observable
final class AppUpdater: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private(set) var isPreparingUpdateCheck = false

    let isAvailable: Bool

    @ObservationIgnored
    private let startsAutomatically: Bool
    @ObservationIgnored
    private var hasStarted: Bool
    @ObservationIgnored
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: startsAutomatically,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    init(startingUpdater: Bool? = nil) {
        let shouldStart = startingUpdater ?? AppUpdater.defaultAutomaticStart
        isAvailable = Bundle.main.object(forInfoDictionaryKey: "MorrowEnableUpdater") as? Bool == true
        startsAutomatically = shouldStart && isAvailable
        hasStarted = shouldStart && isAvailable
        super.init()
        if isAvailable { _ = controller }
    }

    func checkForUpdates() {
        guard isAvailable, !isPreparingUpdateCheck else { return }

        if !hasStarted {
            controller.startUpdater()
            hasStarted = true
        }

        if controller.updater.canCheckForUpdates {
            controller.checkForUpdates(nil)
            return
        }

        // Starting Sparkle is asynchronous. A manual check issued immediately
        // after startup would otherwise be discarded, making the button appear
        // to work only after several clicks.
        isPreparingUpdateCheck = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isPreparingUpdateCheck = false }

            for _ in 0..<50 {
                if controller.updater.canCheckForUpdates {
                    controller.checkForUpdates(nil)
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { isAvailable && controller.updater.automaticallyChecksForUpdates }
        set {
            guard isAvailable else { return }
            if !hasStarted {
                controller.startUpdater()
                hasStarted = true
            }
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// Morrow is dockless, so explicitly opting into Sparkle's background-app
    /// behavior prevents scheduled update windows from stealing focus.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    private static var defaultAutomaticStart: Bool {
#if DEBUG
        false
#else
        true
#endif
    }
}
