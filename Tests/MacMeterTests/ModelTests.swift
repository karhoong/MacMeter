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
    }

    func testSettingTitlesAndIdentifiers() {
        XCTAssertEqual(CPUScale.normalized.title, "Overall (0–100%)")
        XCTAssertEqual(CPUScale.summed.title, "All cores (n×100%)")
        XCTAssertEqual(CPUScale.normalized.id, "normalized")
        XCTAssertEqual(NetworkUnit.MBps.id, "MBps")
        XCTAssertEqual(DisplayMode.default.title, "Default")
        XCTAssertEqual(DisplayMode.compact.id, "compact")
        XCTAssertEqual(MetricID.temperature.id, "temperature")
    }
}
