import XCTest
@testable import MacMeter

final class ModelTests: XCTestCase {
    func testAvailabilityAccessors() {
        let date = Date(timeIntervalSince1970: 42)
        let available = MetricAvailability.available(12, sampledAt: date)
        XCTAssertEqual(available.value, 12)
        XCTAssertEqual(available.sampledAt, date)
        XCTAssertNil(available.reason)

        let unavailableDate = Date(timeIntervalSince1970: 20)
        let unavailable = MetricAvailability<Int>.unavailable("missing", observedAt: unavailableDate)
        XCTAssertNil(unavailable.value)
        XCTAssertNil(unavailable.sampledAt)
        XCTAssertEqual(available.observedAt, date)
        XCTAssertEqual(unavailable.observedAt, unavailableDate)
        XCTAssertEqual(unavailable.reason, "missing")
    }

    func testCoreLabelsAreExplicit() {
        XCTAssertEqual(CoreKind.efficiency.shortLabel, "E")
        XCTAssertEqual(CoreKind.efficiency.displayName, "Efficiency")
        XCTAssertEqual(CoreKind.performance.shortLabel, "P")
        XCTAssertEqual(CoreKind.performance.displayName, "Performance")
        XCTAssertEqual(CoreKind.unknown.shortLabel, "?")
        XCTAssertEqual(CoreKind.unknown.displayName, "Unknown")
    }

    func testBatteryDirectionLabelsDoNotRelyOnColor() {
        XCTAssertEqual(BatteryDirection.charging.shortLabel, "C")
        XCTAssertEqual(BatteryDirection.charging.spokenLabel, "Charging")
        XCTAssertEqual(BatteryDirection.draining.shortLabel, "D")
        XCTAssertEqual(BatteryDirection.draining.spokenLabel, "Draining")
        XCTAssertEqual(BatteryDirection.idle.shortLabel, "—")
        XCTAssertEqual(BatteryDirection.idle.spokenLabel, "Idle")
        XCTAssertEqual(BatteryDirection.charging.colorRole, .charging)
        XCTAssertEqual(BatteryDirection.draining.colorRole, .draining)
        XCTAssertEqual(BatteryDirection.idle.colorRole, .idle)
    }

    func testMetricAccessibilityLabelsContainNamesUnitsAndDirection() {
        XCTAssertEqual(MetricAccessibility.cpu(42), "CPU utilization 42%")
        XCTAssertEqual(MetricAccessibility.temperature(61, unit: .celsius), "SoC temperature 61°C")
        XCTAssertEqual(MetricAccessibility.temperature(61, unit: .fahrenheit), "SoC temperature 142°F")
        let network = NetworkReading(inboundBytesPerSecond: 1_000_000, outboundBytesPerSecond: 250_000, interfaces: ["en0"])
        XCTAssertEqual(MetricAccessibility.network(network, unit: .Mbps), "Network inbound 8 Mbps, outbound 2 Mbps")
        XCTAssertEqual(
            MetricAccessibility.battery(BatteryPowerReading(watts: 8.4, direction: .draining)),
            "Battery Draining, 8.4 watts"
        )
        XCTAssertEqual(
            MetricAccessibility.battery(BatteryPowerReading(watts: 30, direction: .charging)),
            "Battery Charging, 30 watts"
        )
    }

    func testSettingTitlesAndIdentifiers() {
        XCTAssertEqual(CPUScale.normalized.title, "Overall (0–100%)")
        XCTAssertEqual(CPUScale.summed.title, "All cores (n×100%)")
        XCTAssertEqual(CPUScale.normalized.id, "normalized")
        XCTAssertEqual(NetworkUnit.MBps.id, "MBps")
        XCTAssertEqual(NetworkUnit.MBps.menuLabel, "MB/s")
        XCTAssertEqual(NetworkUnit.Mbps.menuLabel, "Mb/s")
        XCTAssertEqual(NetworkUnit.KBps.menuLabel, "KB/s")
        XCTAssertEqual(NetworkUnit.Kbps.menuLabel, "Kb/s")
        XCTAssertEqual(TemperatureUnit.celsius.symbol, "°C")
        XCTAssertEqual(TemperatureUnit.fahrenheit.symbol, "°F")
        XCTAssertEqual(TemperatureUnit.celsius.title, "Celsius")
        XCTAssertEqual(TemperatureUnit.fahrenheit.title, "Fahrenheit")
        XCTAssertEqual(TemperatureUnit.celsius.convert(celsius: 100), 100)
        XCTAssertEqual(TemperatureUnit.fahrenheit.convert(celsius: 100), 212)
        XCTAssertEqual(DisplayMode.allCases, [.compact, .cycle])
        XCTAssertEqual(DisplayMode.compact.id, "compact")
        XCTAssertEqual(MetricID.temperature.id, "temperature")
    }
}
