import Foundation

enum MetricMath {
    static func cpuReading(
        current: [CPUTicks],
        previous: [CPUTicks],
        coreKinds: [Int: CoreKind]
    ) -> CPUReading? {
        guard current.count == previous.count, !current.isEmpty else { return nil }

        let cores = zip(current, previous).enumerated().map { index, pair -> CoreReading in
            let busy = positiveDelta(pair.0.user, pair.1.user)
                + positiveDelta(pair.0.system, pair.1.system)
                + positiveDelta(pair.0.nice, pair.1.nice)
            let idle = positiveDelta(pair.0.idle, pair.1.idle)
            let total = busy + idle
            let utilization = total == 0 ? 0 : (Double(busy) / Double(total)) * 100
            return CoreReading(
                id: index,
                utilization: min(max(utilization, 0), 100),
                kind: coreKinds[index] ?? .unknown
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
        elapsed: TimeInterval
    ) -> NetworkReading? {
        guard elapsed > 0,
              current.interfaces == previous.interfaces,
              current.inboundBytes >= previous.inboundBytes,
              current.outboundBytes >= previous.outboundBytes else { return nil }

        return NetworkReading(
            inboundBytesPerSecond: Double(current.inboundBytes - previous.inboundBytes) / elapsed,
            outboundBytesPerSecond: Double(current.outboundBytes - previous.outboundBytes) / elapsed,
            interfaces: current.interfaces
        )
    }

    static func batteryPower(voltageMillivolts: Int64, currentMilliamps: Int64) -> BatteryPowerReading {
        let watts = abs(Double(voltageMillivolts) * Double(currentMilliamps) / 1_000_000)
        let direction: BatteryDirection
        if currentMilliamps == 0 {
            direction = .idle
        } else if currentMilliamps > 0 {
            direction = .charging
        } else {
            direction = .draining
        }
        return BatteryPowerReading(watts: watts, direction: direction)
    }

    static func validatedTemperature(_ value: Double) -> Double? {
        guard value.isFinite, value >= 0, value <= 110 else { return nil }
        return value
    }

    private static func positiveDelta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }
}

enum MetricFormatting {
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func temperature(_ value: Double, compact: Bool = false) -> String {
        compact ? "\(Int(value.rounded()))°" : "\(Int(value.rounded()))°C"
    }

    static func battery(_ reading: BatteryPowerReading) -> String {
        "\(reading.direction.shortLabel) \(decimal(reading.watts))W"
    }

    static func network(bytesPerSecond: Double, unit: NetworkUnit) -> String {
        let converted: Double
        switch unit {
        case .Kbps: converted = bytesPerSecond * 8 / 1_000
        case .KBps: converted = bytesPerSecond / 1_000
        case .Mbps: converted = bytesPerSecond * 8 / 1_000_000
        case .MBps: converted = bytesPerSecond / 1_000_000
        }
        return decimal(converted)
    }

    static func networkPair(_ reading: NetworkReading, unit: NetworkUnit) -> String {
        "↓\(network(bytesPerSecond: reading.inboundBytesPerSecond, unit: unit)) ↑\(network(bytesPerSecond: reading.outboundBytesPerSecond, unit: unit)) \(unit.rawValue)"
    }

    static func decimal(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if value.rounded() == value { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }
}

enum CycleSequence {
    static func nextIndex(current: Int, enabledCount: Int) -> Int {
        guard enabledCount > 1 else { return 0 }
        return (current + 1) % enabledCount
    }
}
