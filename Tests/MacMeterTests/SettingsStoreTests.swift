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
        XCTAssertEqual(settings.temperatureUnit, .celsius)
        XCTAssertEqual(settings.networkUnit, .MBps)
        XCTAssertEqual(settings.displayMode, .compact)
        XCTAssertEqual(settings.updateInterval, 2)
        XCTAssertEqual(settings.language, .system)
    }

    func testSettingsPersistAcrossInstances() {
        let suite = "MacMeterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings: SettingsStore? = SettingsStore(defaults: defaults)
        settings?.cpuEnabled = false
        settings?.temperatureEnabled = false
        settings?.networkEnabled = false
        settings?.batteryEnabled = false
        settings?.cpuScale = .summed
        settings?.temperatureUnit = .fahrenheit
        settings?.networkUnit = .Kbps
        settings?.displayMode = .cycle
        settings?.updateInterval = 5
        settings?.language = .malay
        settings = nil

        let restored = SettingsStore(defaults: defaults)
        XCTAssertFalse(restored.cpuEnabled)
        XCTAssertFalse(restored.temperatureEnabled)
        XCTAssertFalse(restored.networkEnabled)
        XCTAssertFalse(restored.batteryEnabled)
        XCTAssertEqual(restored.cpuScale, .summed)
        XCTAssertEqual(restored.temperatureUnit, .fahrenheit)
        XCTAssertEqual(restored.networkUnit, .Kbps)
        XCTAssertEqual(restored.displayMode, .cycle)
        XCTAssertEqual(restored.updateInterval, 5)
        XCTAssertEqual(restored.language, .malay)
    }

    func testRemovedDefaultModeMigratesToCompact() {
        let suite = "MacMeterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("default", forKey: "appearance.mode")

        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.displayMode, .compact)
        XCTAssertEqual(defaults.string(forKey: "appearance.mode"), "compact")
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
