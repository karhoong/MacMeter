import Darwin
import MacMeterSensors
import XCTest

final class SensorSelectionTests: XCTestCase {
    func testNamedSoCSensorsChooseHottestValidValue() throws {
        let result = select([
            ("SOC MTR Temp Sensor 0", 62),
            ("SOC MTR Temp Sensor 1", 67)
        ])
        XCTAssertEqual(result.value, 67)
        XCTAssertEqual(result.count, 2)
    }

    func testNamedSensorsDeduplicateNamesAndKeepHottestValue() {
        let result = select([
            ("SOC MTR Temp Sensor 0", 54),
            ("SOC MTR Temp Sensor 0", 59),
            ("SOC MTR Temp Sensor 1", 57),
            ("Battery Temp", 100)
        ])
        XCTAssertEqual(result.value, 59)
        XCTAssertEqual(result.count, 2)
    }

    func testPMUDieSensorsAreNotSubstituted() {
        let result = select([("PMU tdie1", 59), ("PMU tdie2", 61)])
        XCTAssertTrue(result.value.isNaN)
        XCTAssertEqual(result.count, 0)
    }

    func testInvalidAndUnrelatedSensorsReturnUnavailable() {
        let result = select([
            ("PMU tdie1", .nan),
            ("PMU tdie2", -1),
            ("PMU tdie3", 111),
            ("Battery Temp", 40)
        ])
        XCTAssertTrue(result.value.isNaN)
        XCTAssertEqual(result.count, 0)
    }

    func testEmptyFixtureReturnsUnavailable() {
        let result = select([])
        XCTAssertTrue(result.value.isNaN)
        XCTAssertEqual(result.count, 0)
    }

    private func select(_ fixtures: [(String, Double)]) -> (value: Double, count: Int32) {
        let allocated = fixtures.map { strdup($0.0) }
        defer { allocated.forEach { free($0) } }
        var names: [UnsafePointer<CChar>?] = allocated.map { pointer in
            guard let pointer else { return nil }
            return UnsafePointer<CChar>(pointer)
        }
        var values = fixtures.map(\.1)
        var count: Int32 = 0
        let value = names.withUnsafeMutableBufferPointer { nameBuffer in
            values.withUnsafeMutableBufferPointer { valueBuffer in
                MMSelectSoCTemperature(nameBuffer.baseAddress, valueBuffer.baseAddress, Int32(fixtures.count), &count)
            }
        }
        return (value, count)
    }
}
