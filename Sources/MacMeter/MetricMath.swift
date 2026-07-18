import Foundation

enum MetricDecisionPath: String, CaseIterable {
    case cpuInputAccepted
    case cpuInputRejected
    case cpuCounterAdvanced
    case cpuCounterReset
    case cpuTotalAdvanced
    case cpuTotalUnchanged
    case cpuKindKnown
    case cpuKindUnknown
    case networkAccepted
    case networkRejectedElapsed
    case networkRejectedInterfaces
    case networkRejectedInboundReset
    case networkRejectedOutboundReset
    case batteryCharging
    case batteryDraining
    case batteryIdle
    case temperatureAccepted
    case temperatureRejectedNonfinite
    case temperatureRejectedLow
    case temperatureRejectedHigh
    case temperatureCompact
    case temperatureFull
    case networkKbps
    case networkKBps
    case networkMbps
    case networkMBps
    case decimalLarge
    case decimalInteger
    case decimalFractional
}

enum MetricMath {
    static func cpuReading(
        current: [CPUTicks],
        previous: [CPUTicks],
        coreKinds: [Int: CoreKind],
        record: ((MetricDecisionPath) -> Void)? = nil
    ) -> CPUReading? {
        guard current.count == previous.count, !current.isEmpty else {
            record?(.cpuInputRejected)
            return nil
        }
        record?(.cpuInputAccepted)

        let cores = zip(current, previous).enumerated().map { index, pair -> CoreReading in
            let busy = positiveDelta(pair.0.user, pair.1.user, record: record)
                + positiveDelta(pair.0.system, pair.1.system, record: record)
                + positiveDelta(pair.0.nice, pair.1.nice, record: record)
            let idle = positiveDelta(pair.0.idle, pair.1.idle, record: record)
            let total = busy + idle
            let utilization: Double
            if total == 0 {
                record?(.cpuTotalUnchanged)
                utilization = 0
            } else {
                record?(.cpuTotalAdvanced)
                utilization = (Double(busy) / Double(total)) * 100
            }
            let kind: CoreKind
            if let knownKind = coreKinds[index] {
                record?(.cpuKindKnown)
                kind = knownKind
            } else {
                record?(.cpuKindUnknown)
                kind = .unknown
            }
            return CoreReading(
                id: index,
                utilization: min(max(utilization, 0), 100),
                kind: kind
            )
        }

        let summed = cores.reduce(0) { $0 + $1.utilization }
        return CPUReading(
            normalized: summed / Double(cores.count),
            summed: summed,
            cores: cores
        )
    }

    static func networkReading(
        current: NetworkCounters,
        previous: NetworkCounters,
        elapsed: TimeInterval,
        record: ((MetricDecisionPath) -> Void)? = nil
    ) -> NetworkReading? {
        guard elapsed > 0 else {
            record?(.networkRejectedElapsed)
            return nil
        }
        guard current.interfaces == previous.interfaces else {
            record?(.networkRejectedInterfaces)
            return nil
        }
        guard current.inboundBytes >= previous.inboundBytes else {
            record?(.networkRejectedInboundReset)
            return nil
        }
        guard current.outboundBytes >= previous.outboundBytes else {
            record?(.networkRejectedOutboundReset)
            return nil
        }
        record?(.networkAccepted)

        return NetworkReading(
            inboundBytesPerSecond: Double(current.inboundBytes - previous.inboundBytes) / elapsed,
            outboundBytesPerSecond: Double(current.outboundBytes - previous.outboundBytes) / elapsed,
            interfaces: current.interfaces
        )
    }

    static func batteryPower(
        voltageMillivolts: Int64,
        currentMilliamps: Int64,
        record: ((MetricDecisionPath) -> Void)? = nil
    ) -> BatteryPowerReading {
        let watts = abs(Double(voltageMillivolts) * Double(currentMilliamps) / 1_000_000)
        let direction: BatteryDirection
        if currentMilliamps == 0 {
            record?(.batteryIdle)
            direction = .idle
        } else if currentMilliamps > 0 {
            record?(.batteryCharging)
            direction = .charging
        } else {
            record?(.batteryDraining)
            direction = .draining
        }
        return BatteryPowerReading(watts: watts, direction: direction)
    }

    static func validatedTemperature(
        _ value: Double,
        record: ((MetricDecisionPath) -> Void)? = nil
    ) -> Double? {
        guard value.isFinite else {
            record?(.temperatureRejectedNonfinite)
            return nil
        }
        guard value >= 0 else {
            record?(.temperatureRejectedLow)
            return nil
        }
        guard value <= 110 else {
            record?(.temperatureRejectedHigh)
            return nil
        }
        record?(.temperatureAccepted)
        return value
    }

    private static func positiveDelta(
        _ current: UInt64,
        _ previous: UInt64,
        record: ((MetricDecisionPath) -> Void)?
    ) -> UInt64 {
        if current >= previous {
            record?(.cpuCounterAdvanced)
            return current - previous
        }
        record?(.cpuCounterReset)
        return 0
    }
}

enum MetricFormatting {
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func temperature(
        _ value: Double,
        compact: Bool = false,
        record: ((MetricDecisionPath) -> Void)? = nil
    ) -> String {
        if compact {
            record?(.temperatureCompact)
            return "\(Int(value.rounded()))°"
        }
        record?(.temperatureFull)
        return "\(Int(value.rounded()))°C"
    }

    static func battery(_ reading: BatteryPowerReading) -> String {
        "\(reading.direction.shortLabel) \(decimal(reading.watts))W"
    }

    static func network(
        bytesPerSecond: Double,
        unit: NetworkUnit,
        record: ((MetricDecisionPath) -> Void)? = nil
    ) -> String {
        let converted: Double
        switch unit {
        case .Kbps:
            record?(.networkKbps)
            converted = bytesPerSecond * 8 / 1_000
        case .KBps:
            record?(.networkKBps)
            converted = bytesPerSecond / 1_000
        case .Mbps:
            record?(.networkMbps)
            converted = bytesPerSecond * 8 / 1_000_000
        case .MBps:
            record?(.networkMBps)
            converted = bytesPerSecond / 1_000_000
        }
        return decimal(converted, record: record)
    }

    static func networkPair(_ reading: NetworkReading, unit: NetworkUnit) -> String {
        "↓\(network(bytesPerSecond: reading.inboundBytesPerSecond, unit: unit)) ↑\(network(bytesPerSecond: reading.outboundBytesPerSecond, unit: unit)) \(unit.rawValue)"
    }

    static func decimal(
        _ value: Double,
        record: ((MetricDecisionPath) -> Void)? = nil
    ) -> String {
        if value >= 100 {
            record?(.decimalLarge)
            return String(format: "%.0f", value)
        }
        if value.rounded() == value {
            record?(.decimalInteger)
            return String(format: "%.0f", value)
        }
        record?(.decimalFractional)
        return String(format: "%.1f", value)
    }
}

enum CycleSequence {
    static func nextIndex(current: Int, enabledCount: Int) -> Int {
        guard enabledCount > 1 else { return 0 }
        return (current + 1) % enabledCount
    }
}
