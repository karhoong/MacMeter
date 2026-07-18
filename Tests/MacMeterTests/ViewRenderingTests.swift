import SwiftUI
import XCTest
@testable import MacMeter

@MainActor
final class ViewRenderingTests: XCTestCase {
    func testAppCompositionCanBeConstructed() {
        let app = MacMeterApp()
        _ = app.body
    }

    func testMenuBarModesAndMetricCombinationsRender() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        for mode in DisplayMode.allCases {
            fixture.settings.displayMode = mode
            XCTAssertNotNil(render(MenuBarLabelView(coordinator: fixture.coordinator, settings: fixture.settings)))
        }

        for metric in MetricID.allCases {
            fixture.settings.cpuEnabled = metric == .cpu
            fixture.settings.temperatureEnabled = metric == .temperature
            fixture.settings.networkEnabled = metric == .network
            fixture.settings.batteryEnabled = metric == .battery
            XCTAssertNotNil(render(MenuBarLabelView(coordinator: fixture.coordinator, settings: fixture.settings)))
        }

        fixture.settings.cpuEnabled = false
        fixture.settings.temperatureEnabled = false
        fixture.settings.networkEnabled = false
        fixture.settings.batteryEnabled = false
        XCTAssertNotNil(render(MenuBarLabelView(coordinator: fixture.coordinator, settings: fixture.settings)))
    }

    func testPopoverAndSettingsRenderWithLiveFixtureValues() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        XCTAssertNotNil(render(MeterPopoverView(coordinator: fixture.coordinator, settings: fixture.settings)))
        XCTAssertNotNil(render(MacMeterSettingsView(settings: fixture.settings, loginItem: LoginItemManager())))
    }

    func testUnavailableStatesRender() {
        let suite = "MacMeterViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let coordinator = MetricsCoordinator(
            settings: settings,
            cpuProvider: FakeCPUProvider(result: .unavailable("CPU unavailable")),
            temperatureProvider: UnavailableTemperatureProvider(),
            networkProvider: FakeNetworkProvider(result: .unavailable("Network unavailable")),
            batteryProvider: UnavailableBatteryProvider(),
            startAutomatically: false
        )
        coordinator.sampleNow()
        XCTAssertNotNil(render(MenuBarLabelView(coordinator: coordinator, settings: settings)))
        XCTAssertNotNil(render(MeterPopoverView(coordinator: coordinator, settings: settings)))
    }

    private func render<V: View>(_ view: V) -> NSImage? {
        let renderer = ImageRenderer(content: view.padding().frame(minWidth: 120, minHeight: 32))
        renderer.scale = 2
        return renderer.nsImage
    }

    private func makeFixture() -> (settings: SettingsStore, coordinator: MetricsCoordinator, cleanup: () -> Void) {
        let suite = "MacMeterViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults)
        let cores = [
            CoreReading(id: 0, utilization: 20, kind: .efficiency),
            CoreReading(id: 1, utilization: 80, kind: .performance)
        ]
        let coordinator = MetricsCoordinator(
            settings: settings,
            cpuProvider: FakeCPUProvider(result: .available(CPUReading(normalized: 50, summed: 100, cores: cores), sampledAt: .distantPast)),
            temperatureProvider: FakeTemperatureProvider(),
            networkProvider: FakeNetworkProvider(result: .available(NetworkReading(inboundBytesPerSecond: 3_200_000, outboundBytesPerSecond: 400_000, interfaces: ["en0"]), sampledAt: .distantPast)),
            batteryProvider: FakeBatteryProvider(),
            startAutomatically: false
        )
        coordinator.sampleNow(at: Date(timeIntervalSince1970: 1_000))
        return (settings, coordinator, { defaults.removePersistentDomain(forName: suite) })
    }
}

@MainActor
private final class UnavailableTemperatureProvider: TemperatureProviding {
    func sample(at date: Date) -> MetricAvailability<TemperatureReading> { .unavailable("Temperature unavailable") }
}

@MainActor
private final class UnavailableBatteryProvider: BatteryProviding {
    func sample(at date: Date) -> MetricAvailability<BatteryPowerReading> { .unavailable("Battery unavailable") }
}
