import XCTest
@testable import MacMeter

@MainActor
final class HardwareProviderFixtureTests: XCTestCase {
    func testNetworkAggregationIncludesOnlyActivePhysicalInterfaces() {
        let counters = NetworkProvider.aggregate([
            snapshot("utun4", up: true, running: true, inbound: 10_000, outbound: 20_000),
            snapshot("lo0", up: true, running: true, inbound: 30_000, outbound: 40_000),
            snapshot("en7", up: true, running: true, inbound: 700, outbound: 70),
            snapshot("en0", up: true, running: true, inbound: 100, outbound: 10),
            snapshot("en1", up: false, running: true, inbound: 2_000, outbound: 200),
            snapshot("en2", up: true, running: false, inbound: 3_000, outbound: 300),
            snapshot("bridge0", up: true, running: true, inbound: 4_000, outbound: 400)
        ])

        XCTAssertEqual(counters.interfaces, ["en0", "en7"])
        XCTAssertEqual(counters.inboundBytes, 800)
        XCTAssertEqual(counters.outboundBytes, 80)
    }

    func testNetworkAggregationAllowsNoActivePhysicalInterface() {
        let counters = NetworkProvider.aggregate([
            snapshot("utun0", up: true, running: true, inbound: 1, outbound: 2),
            snapshot("en0", up: false, running: false, inbound: 3, outbound: 4)
        ])
        XCTAssertEqual(counters, NetworkCounters(inboundBytes: 0, outboundBytes: 0, interfaces: []))
    }

    func testNetworkProviderDeterministicallySamplesAndReportsSourceFailure() throws {
        var fixtures: [[NetworkInterfaceSnapshot]?] = [
            [snapshot("en0", up: true, running: true, inbound: 1_000, outbound: 2_000)],
            [snapshot("en0", up: true, running: true, inbound: 5_000, outbound: 4_000)],
            nil
        ]
        let provider = NetworkProvider(interfaceReader: { fixtures.removeFirst() })
        let start = Date(timeIntervalSince1970: 10)

        XCTAssertEqual(provider.sample(at: start).reason, "Collecting initial network sample")
        let reading = try XCTUnwrap(provider.sample(at: start.addingTimeInterval(2)).value)
        XCTAssertEqual(reading.inboundBytesPerSecond, 2_000)
        XCTAssertEqual(reading.outboundBytesPerSecond, 1_000)
        XCTAssertEqual(reading.interfaces, ["en0"])
        XCTAssertEqual(provider.sample(at: start.addingTimeInterval(4)).reason, "Network counters could not be read")
    }

    func testBatteryProviderHandlesMissingBatteryAndProperties() {
        XCTAssertEqual(
            BatteryPowerProvider(telemetryReader: { nil }).sample(at: .distantPast).reason,
            "This Mac has no battery"
        )
        XCTAssertEqual(
            BatteryPowerProvider(telemetryReader: {
                BatteryTelemetry(voltageMillivolts: nil, currentMilliamps: 10, isCharging: true, isExternalConnected: true)
            }).sample(at: .distantPast).reason,
            "Battery voltage or current is unavailable"
        )
        XCTAssertEqual(
            BatteryPowerProvider(telemetryReader: {
                BatteryTelemetry(voltageMillivolts: 12_000, currentMilliamps: nil, isCharging: false, isExternalConnected: false)
            }).sample(at: .distantPast).reason,
            "Battery voltage or current is unavailable"
        )
    }

    func testBatteryProviderRejectsEveryInconsistentDirectionState() {
        let chargingWithoutChargingFlag = BatteryTelemetry(
            voltageMillivolts: 12_000,
            currentMilliamps: 2_500,
            isCharging: false,
            isExternalConnected: true
        )
        let chargingWithoutExternalPower = BatteryTelemetry(
            voltageMillivolts: 12_000,
            currentMilliamps: 2_500,
            isCharging: true,
            isExternalConnected: false
        )
        let drainingWhileCharging = BatteryTelemetry(
            voltageMillivolts: 12_000,
            currentMilliamps: -700,
            isCharging: true,
            isExternalConnected: true
        )

        for telemetry in [chargingWithoutChargingFlag, chargingWithoutExternalPower, drainingWhileCharging] {
            let result = BatteryPowerProvider(telemetryReader: { telemetry }).sample(at: .distantPast)
            XCTAssertEqual(result.reason, "Battery power state is inconsistent")
        }
    }

    func testBatteryProviderReturnsChargeDrainAndIdleFixtures() throws {
        let fixtures: [(BatteryTelemetry, BatteryDirection, Double)] = [
            (BatteryTelemetry(voltageMillivolts: 12_000, currentMilliamps: 2_500, isCharging: true, isExternalConnected: true), .charging, 30),
            (BatteryTelemetry(voltageMillivolts: 12_000, currentMilliamps: -700, isCharging: false, isExternalConnected: false), .draining, 8.4),
            (BatteryTelemetry(voltageMillivolts: 12_000, currentMilliamps: 0, isCharging: false, isExternalConnected: true), .idle, 0)
        ]

        for (telemetry, direction, watts) in fixtures {
            let reading = try XCTUnwrap(BatteryPowerProvider(telemetryReader: { telemetry }).sample(at: .distantPast).value)
            XCTAssertEqual(reading.direction, direction)
            XCTAssertEqual(reading.watts, watts, accuracy: 0.001)
        }
    }

    private func snapshot(
        _ name: String,
        up: Bool,
        running: Bool,
        inbound: UInt64,
        outbound: UInt64
    ) -> NetworkInterfaceSnapshot {
        NetworkInterfaceSnapshot(
            name: name,
            isUp: up,
            isRunning: running,
            inboundBytes: inbound,
            outboundBytes: outbound
        )
    }
}
