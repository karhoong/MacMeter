import XCTest
@testable import MacMeter

final class MetricMathTests: XCTestCase {
    func testCalculationAndConversionSemanticDecisionCoverageIsComplete() {
        var covered = Set<MetricDecisionPath>()
        let record: (MetricDecisionPath) -> Void = { path in
            _ = covered.insert(path)
        }

        let previous = [
            CPUTicks(user: 10, system: 10, nice: 0, idle: 80),
            CPUTicks(user: 100, system: 100, nice: 100, idle: 100)
        ]
        let current = [
            CPUTicks(user: 20, system: 10, nice: 0, idle: 90),
            CPUTicks(user: 1, system: 1, nice: 1, idle: 1)
        ]
        _ = MetricMath.cpuReading(current: current, previous: previous, coreKinds: [0: .efficiency], record: record)
        _ = MetricMath.cpuReading(current: previous, previous: previous, coreKinds: [:], record: record)
        _ = MetricMath.cpuReading(current: [], previous: [], coreKinds: [:], record: record)

        let base = NetworkCounters(inboundBytes: 100, outboundBytes: 200, interfaces: ["en0"])
        _ = MetricMath.networkReading(current: base, previous: base, elapsed: 0, record: record)
        _ = MetricMath.networkReading(
            current: NetworkCounters(inboundBytes: 110, outboundBytes: 210, interfaces: ["en1"]),
            previous: base,
            elapsed: 1,
            record: record
        )
        _ = MetricMath.networkReading(
            current: NetworkCounters(inboundBytes: 99, outboundBytes: 210, interfaces: ["en0"]),
            previous: base,
            elapsed: 1,
            record: record
        )
        _ = MetricMath.networkReading(
            current: NetworkCounters(inboundBytes: 110, outboundBytes: 199, interfaces: ["en0"]),
            previous: base,
            elapsed: 1,
            record: record
        )
        _ = MetricMath.networkReading(
            current: NetworkCounters(inboundBytes: 110, outboundBytes: 210, interfaces: ["en0"]),
            previous: base,
            elapsed: 1,
            record: record
        )

        for current in [-1, 0, 1] {
            _ = MetricMath.batteryPower(voltageMillivolts: 12_000, currentMilliamps: Int64(current), record: record)
        }
        for temperature in [Double.nan, -1, 55, 111] {
            _ = MetricMath.validatedTemperature(temperature, record: record)
        }
        _ = MetricFormatting.temperature(55, compact: true, record: record)
        _ = MetricFormatting.temperature(55, compact: false, record: record)
        for unit in NetworkUnit.allCases {
            _ = MetricFormatting.network(bytesPerSecond: 1_250, unit: unit, record: record)
        }
        _ = MetricFormatting.decimal(100.4, record: record)
        _ = MetricFormatting.decimal(30, record: record)
        _ = MetricFormatting.decimal(8.4, record: record)

        let expected = Set(MetricDecisionPath.allCases)
        XCTAssertEqual(
            covered,
            expected,
            "Missing semantic decision paths: \(expected.subtracting(covered).map(\.rawValue).sorted())"
        )
    }

    func testCPUProducesNormalizedSummedAndPerCoreValues() throws {
        let previous = [
            CPUTicks(user: 100, system: 50, nice: 0, idle: 850),
            CPUTicks(user: 200, system: 100, nice: 0, idle: 700)
        ]
        let current = [
            CPUTicks(user: 150, system: 70, nice: 0, idle: 880),
            CPUTicks(user: 270, system: 130, nice: 0, idle: 700)
        ]

        let reading = try XCTUnwrap(MetricMath.cpuReading(
            current: current,
            previous: previous,
            coreKinds: [0: .efficiency, 1: .performance]
        ))

        XCTAssertEqual(reading.cores[0].utilization, 70, accuracy: 0.001)
        XCTAssertEqual(reading.cores[1].utilization, 100, accuracy: 0.001)
        XCTAssertEqual(reading.summed, 170, accuracy: 0.001)
        XCTAssertEqual(reading.normalized, 85, accuracy: 0.001)
        XCTAssertEqual(reading.cores.map(\.kind), [.efficiency, .performance])
    }

    func testCPURejectsMismatchedCounterSets() {
        let ticks = CPUTicks(user: 1, system: 1, nice: 0, idle: 8)
        XCTAssertNil(MetricMath.cpuReading(current: [ticks], previous: [], coreKinds: [:]))
        XCTAssertNil(MetricMath.cpuReading(current: [], previous: [], coreKinds: [:]))
    }

    func testCPUCounterResetDoesNotCreateNegativeUsage() throws {
        let current = [CPUTicks(user: 1, system: 1, nice: 0, idle: 1)]
        let previous = [CPUTicks(user: 100, system: 100, nice: 0, idle: 100)]
        let reading = try XCTUnwrap(MetricMath.cpuReading(current: current, previous: previous, coreKinds: [:]))
        XCTAssertEqual(reading.normalized, 0)
        XCTAssertEqual(reading.cores.first?.kind, .unknown)
    }

    func testCPUUnchangedCountersProduceZeroUtilization() throws {
        let ticks = [CPUTicks(user: 20, system: 10, nice: 5, idle: 100)]
        let reading = try XCTUnwrap(MetricMath.cpuReading(current: ticks, previous: ticks, coreKinds: [:]))
        XCTAssertEqual(reading.normalized, 0)
        XCTAssertEqual(reading.summed, 0)
    }

    func testNetworkDeltaUsesElapsedTime() throws {
        let previous = NetworkCounters(inboundBytes: 1_000, outboundBytes: 2_000, interfaces: ["en0"])
        let current = NetworkCounters(inboundBytes: 5_000, outboundBytes: 4_000, interfaces: ["en0"])
        let reading = try XCTUnwrap(MetricMath.networkReading(current: current, previous: previous, elapsed: 2))
        XCTAssertEqual(reading.inboundBytesPerSecond, 2_000)
        XCTAssertEqual(reading.outboundBytesPerSecond, 1_000)
    }

    func testNetworkRebaselinesOnInterfaceOrCounterChange() {
        let previous = NetworkCounters(inboundBytes: 1_000, outboundBytes: 2_000, interfaces: ["en0"])
        let changedInterface = NetworkCounters(inboundBytes: 2_000, outboundBytes: 3_000, interfaces: ["en1"])
        let reset = NetworkCounters(inboundBytes: 10, outboundBytes: 20, interfaces: ["en0"])
        let inboundReset = NetworkCounters(inboundBytes: 10, outboundBytes: 3_000, interfaces: ["en0"])
        let outboundReset = NetworkCounters(inboundBytes: 3_000, outboundBytes: 20, interfaces: ["en0"])
        XCTAssertNil(MetricMath.networkReading(current: changedInterface, previous: previous, elapsed: 2))
        XCTAssertNil(MetricMath.networkReading(current: reset, previous: previous, elapsed: 2))
        XCTAssertNil(MetricMath.networkReading(current: inboundReset, previous: previous, elapsed: 2))
        XCTAssertNil(MetricMath.networkReading(current: outboundReset, previous: previous, elapsed: 2))
        XCTAssertNil(MetricMath.networkReading(current: previous, previous: previous, elapsed: 0))
    }

    func testBatteryDirectionAndPrecision() {
        let charging = MetricMath.batteryPower(voltageMillivolts: 12_000, currentMilliamps: 2_500)
        XCTAssertEqual(charging.watts, 30, accuracy: 0.001)
        XCTAssertEqual(charging.direction, .charging)
        XCTAssertEqual(MetricFormatting.battery(charging), "C 30W")

        let draining = MetricMath.batteryPower(voltageMillivolts: 12_000, currentMilliamps: -700)
        XCTAssertEqual(draining.watts, 8.4, accuracy: 0.001)
        XCTAssertEqual(draining.direction, .draining)
        XCTAssertEqual(MetricFormatting.battery(draining), "D 8.4W")

        let idle = MetricMath.batteryPower(voltageMillivolts: 12_000, currentMilliamps: 0)
        XCTAssertEqual(idle.direction, .idle)
        XCTAssertEqual(MetricFormatting.battery(idle), "— 0W")
    }

    func testBatteryPreservesLowRateChargeAndDrainPower() {
        for current in [-50, -49, -20, -1, 1, 20, 49, 50] {
            let reading = MetricMath.batteryPower(voltageMillivolts: 12_000, currentMilliamps: Int64(current))
            XCTAssertEqual(reading.watts, Double(abs(current)) * 0.012, accuracy: 0.000_001)
            XCTAssertEqual(reading.direction, current > 0 ? .charging : .draining)
        }
    }

    func testNetworkUnitConversionsUseDecimalSI() {
        XCTAssertEqual(MetricFormatting.network(bytesPerSecond: 1_000_000, unit: .MBps), "1")
        XCTAssertEqual(MetricFormatting.network(bytesPerSecond: 1_000_000, unit: .Mbps), "8")
        XCTAssertEqual(MetricFormatting.network(bytesPerSecond: 1_000, unit: .KBps), "1")
        XCTAssertEqual(MetricFormatting.network(bytesPerSecond: 1_000, unit: .Kbps), "8")
        let reading = NetworkReading(inboundBytesPerSecond: 1_000_000, outboundBytesPerSecond: 200_000, interfaces: ["en0"])
        XCTAssertEqual(MetricFormatting.networkPair(reading, unit: .MBps), "↓1 ↑0.2 MBps")
    }

    func testFormattingCoversRoundedCompactIntegerDecimalAndLargeValues() {
        XCTAssertEqual(MetricFormatting.percent(42.6), "43%")
        XCTAssertEqual(MetricFormatting.temperature(61.6), "62°C")
        XCTAssertEqual(MetricFormatting.temperature(61.6, compact: true), "62°")
        XCTAssertEqual(MetricFormatting.decimal(100.4), "100")
        XCTAssertEqual(MetricFormatting.decimal(30), "30")
        XCTAssertEqual(MetricFormatting.decimal(8.44), "8.4")
    }

    func testTemperatureValidation() {
        XCTAssertEqual(MetricMath.validatedTemperature(65.2), 65.2)
        XCTAssertEqual(MetricMath.validatedTemperature(0), 0)
        XCTAssertEqual(MetricMath.validatedTemperature(110), 110)
        XCTAssertNil(MetricMath.validatedTemperature(-1))
        XCTAssertNil(MetricMath.validatedTemperature(110.1))
        XCTAssertNil(MetricMath.validatedTemperature(.nan))
        XCTAssertNil(MetricMath.validatedTemperature(.infinity))
        XCTAssertNil(MetricMath.validatedTemperature(-.infinity))
    }

    func testCycleSequenceWrapsAndStopsForOneMetric() {
        XCTAssertEqual(CycleSequence.nextIndex(current: 0, enabledCount: 4), 1)
        XCTAssertEqual(CycleSequence.nextIndex(current: 3, enabledCount: 4), 0)
        XCTAssertEqual(CycleSequence.nextIndex(current: 0, enabledCount: 1), 0)
        XCTAssertEqual(CycleSequence.nextIndex(current: 0, enabledCount: 0), 0)
    }
}
