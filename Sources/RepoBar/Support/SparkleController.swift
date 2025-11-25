import Sparkle

/// Simple Sparkle wrapper so we can call from menus without passing around the updater.
@MainActor
final class SparkleController {
    static let shared = SparkleController()
    private let updaterController: SPUStandardUpdaterController

    private init() {
        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil)
    }

    var canCheckForUpdates: Bool {
        self.updaterController.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { self.updaterController.updater.automaticallyChecksForUpdates }
        set { self.updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        self.updaterController.checkForUpdates(nil)
    }
}
