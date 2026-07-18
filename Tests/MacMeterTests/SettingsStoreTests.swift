import XCTest
@testable import MacMeter

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testDefaultsMatchProductContract() {
        let suite = "MacMeterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertTrue(settings.cpuEnabled)
        XCTAssertTrue(settings.temperatureEnabled)
        XCTAssertTrue(settings.networkEnabled)
        XCTAssertTrue(settings.batteryEnabled)
        XCTAssertEqual(settings.cpuScale, .normalized)
        XCTAssertEqual(settings.networkUnit, .MBps)
        XCTAssertEqual(settings.displayMode, .default)
        XCTAssertEqual(settings.updateInterval, 2)
    }

    func testSettingsPersistAcrossInstances() {
        let suite = "MacMeterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings: SettingsStore? = SettingsStore(defaults: defaults)
        settings?.cpuEnabled = false
        settings?.cpuScale = .summed
        settings?.networkUnit = .Kbps
        settings?.displayMode = .cycle
        settings?.updateInterval = 5
        settings = nil

        let restored = SettingsStore(defaults: defaults)
        XCTAssertFalse(restored.cpuEnabled)
        XCTAssertEqual(restored.cpuScale, .summed)
        XCTAssertEqual(restored.networkUnit, .Kbps)
        XCTAssertEqual(restored.displayMode, .cycle)
        XCTAssertEqual(restored.updateInterval, 5)
    }

    func testEnabledMetricOrderIsStable() {
        let suite = "MacMeterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.temperatureEnabled = false
        settings.batteryEnabled = false
        XCTAssertEqual(settings.enabledMetrics, [.cpu, .network])
    }
}
