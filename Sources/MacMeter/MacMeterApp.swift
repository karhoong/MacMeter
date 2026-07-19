import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
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

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: MacMeterSettingsView(settings: settings, loginItem: loginItem)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MacMeter Settings"
        window.identifier = NSUserInterfaceItemIdentifier("MacMeter.Settings")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.isReleasedWhenClosed = false
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
