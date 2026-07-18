import Darwin
import XCTest
@testable import MacMeter

@MainActor
final class HardwareProviderSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["MACMETER_RUN_HARDWARE_TESTS"] == "1" else {
            throw XCTSkip("Hardware smoke tests run through Scripts/qa.sh")
        }
    }

    func testAppleSiliconCoreTopologyAndCPUProvider() throws {
        let topology = CoreTopologyReader.read()
        XCTAssertFalse(topology.isEmpty)
        XCTAssertFalse(topology.values.contains(.unknown))
        if cpuBrand().contains("M4 Max") {
            XCTAssertEqual(topology.count, 16)
            XCTAssertEqual(topology.values.filter { $0 == .efficiency }.count, 4)
            XCTAssertEqual(topology.values.filter { $0 == .performance }.count, 12)
        }

        let provider = CPUProvider(coreKinds: topology)
        _ = provider.sample(at: Date())
        Thread.sleep(forTimeInterval: 0.1)
        let reading = try XCTUnwrap(provider.sample(at: Date()).value)
        XCTAssertEqual(reading.cores.count, ProcessInfo.processInfo.processorCount)
        XCTAssertTrue(reading.cores.allSatisfy { (0...100).contains($0.utilization) })
        XCTAssertEqual(reading.summed, reading.cores.reduce(0) { $0 + $1.utilization }, accuracy: 0.1)
    }

    func testSoCTemperatureProviderReturnsValidLiveReading() throws {
        let reading = try XCTUnwrap(SoCTemperatureProvider().sample(at: Date()).value)
        XCTAssertTrue((0...110).contains(reading.hottestCelsius))
        XCTAssertGreaterThan(reading.sensorCount, 0)
    }

    func testNetworkProviderProducesNonnegativeLiveRates() throws {
        let provider = NetworkProvider()
        _ = provider.sample(at: Date())
        Thread.sleep(forTimeInterval: 0.1)
        let reading = try XCTUnwrap(provider.sample(at: Date()).value)
        XCTAssertGreaterThanOrEqual(reading.inboundBytesPerSecond, 0)
        XCTAssertGreaterThanOrEqual(reading.outboundBytesPerSecond, 0)
        XCTAssertFalse(reading.interfaces.isEmpty)
    }

    func testBatteryProviderReturnsLiveReadingOnLaptop() throws {
        let result = BatteryPowerProvider().sample(at: Date())
        if let reading = result.value {
            XCTAssertGreaterThanOrEqual(reading.watts, 0)
        } else {
            XCTFail("Battery provider unavailable on battery-equipped QA Mac: \(result.reason ?? "unknown")")
        }
    }

    private func cpuBrand() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return "" }
        let utf8 = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: utf8, as: UTF8.self)
    }
}
