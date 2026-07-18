import AppKit
import SwiftUI

@main
struct MacMeterApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var coordinator: MetricsCoordinator
    @StateObject private var loginItem = LoginItemManager()

    @MainActor
    init() {
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _coordinator = StateObject(wrappedValue: MetricsCoordinator(settings: settings))
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MeterPopoverView(coordinator: coordinator, settings: settings)
        } label: {
            MenuBarLabelView(coordinator: coordinator, settings: settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacMeterSettingsView(settings: settings, loginItem: loginItem)
        }
    }
}
