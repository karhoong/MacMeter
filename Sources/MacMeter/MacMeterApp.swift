import AppKit

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: SettingsStore
    private let loginItem: LoginItemManager
    private let activateApplication: () -> Void
    private(set) var window: NSWindow?

    init(
        settings: SettingsStore,
        loginItem: LoginItemManager,
        activateApplication: @escaping () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
        }
    ) {
        self.settings = settings
        self.loginItem = loginItem
        self.activateApplication = activateApplication
        super.init()
    }

    func show() {
        let settingsWindow = window ?? makeWindow()
        if settingsWindow.isMiniaturized {
            settingsWindow.deminiaturize(nil)
        }
        activateApplication()
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func makeWindow() -> NSWindow {
        let settingsController = NativeSettingsViewController(settings: settings, loginItem: loginItem)
        let window = NSWindow(contentViewController: settingsController)
        window.title = "MacMeter Settings"
        window.identifier = NSUserInterfaceItemIdentifier("MacMeter.Settings")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.moveToActiveSpace)
        // Retain and reuse one small native AppKit tree. Recreating Settings on
        // every click allowed AppKit/SwiftUI presentation caches to accumulate.
        window.isReleasedWhenClosed = false
        window.setContentSize(settingsController.preferredContentSize)
        window.delegate = self
        window.center()
        self.window = window
        return window
    }
}

@MainActor
final class MacMeterApplicationDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: MetricsCoordinator?
    private var settingsWindowController: SettingsWindowController?
    private var statusItemController: StatusItemController?

    var isRunning: Bool { statusItemController != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stop()
    }

    func start() {
        guard statusItemController == nil else { return }
        let settings = SettingsStore()
        let loginItem = LoginItemManager()
        NSApplication.shared.setActivationPolicy(.accessory)
        let coordinator = MetricsCoordinator(settings: settings)
        let settingsWindowController = SettingsWindowController(settings: settings, loginItem: loginItem)
        let statusItemController = StatusItemController(
            coordinator: coordinator,
            settings: settings,
            settingsWindowController: settingsWindowController
        )
        self.coordinator = coordinator
        self.settingsWindowController = settingsWindowController
        self.statusItemController = statusItemController
    }

    func stop() {
        statusItemController?.close()
        statusItemController = nil
        coordinator?.stopSampling()
        coordinator = nil
        settingsWindowController?.close()
        settingsWindowController = nil
    }
}

@main
enum MacMeterMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = MacMeterApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
