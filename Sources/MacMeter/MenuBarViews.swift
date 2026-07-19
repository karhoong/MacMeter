import AppKit
import Combine

enum MetricAccessibility {
    static func cpu(_ value: Double) -> String {
        "CPU utilization \(MetricFormatting.percent(value))"
    }

    static func temperature(_ value: Double, unit: TemperatureUnit) -> String {
        "SoC temperature \(MetricFormatting.temperature(value, unit: unit))"
    }

    static func network(_ reading: NetworkReading, unit: NetworkUnit) -> String {
        "Network inbound \(MetricFormatting.network(bytesPerSecond: reading.inboundBytesPerSecond, unit: unit)) \(unit.rawValue), outbound \(MetricFormatting.network(bytesPerSecond: reading.outboundBytesPerSecond, unit: unit)) \(unit.rawValue)"
    }

    static func battery(_ reading: BatteryPowerReading) -> String {
        "Battery \(reading.direction.spokenLabel), \(MetricFormatting.decimal(reading.watts)) watts"
    }
}

enum CycleActivityPolicy {
    static func shouldRun(mode: DisplayMode, enabledCount: Int) -> Bool {
        mode == .cycle && enabledCount > 0
    }
}

enum MenuBarPresentation {
    static func rows(for enabledMetrics: [MetricID]) -> [[MetricID]] {
        guard !enabledMetrics.isEmpty else { return [] }
        if enabledMetrics.count == MetricID.allCases.count,
           MetricID.allCases.allSatisfy(enabledMetrics.contains) {
            // Keep the widest network reading on its own line. This is the exact
            // compact four-metric layout shown in the product specification.
            return [[.network], [.cpu, .temperature, .battery]]
        }
        return [enabledMetrics]
    }

    static func cpu(_ reading: CPUReading, scale: CPUScale) -> String {
        MetricFormatting.percent(scale == .normalized ? reading.normalized : reading.summed)
    }

    static func temperature(_ reading: TemperatureReading, unit: TemperatureUnit) -> String {
        MetricFormatting.temperature(reading.hottestCelsius, unit: unit, compact: true)
    }

    static func network(_ reading: NetworkReading, unit: NetworkUnit) -> String {
        MetricFormatting.networkPair(reading, unit: unit)
    }

    static func battery(_ reading: BatteryPowerReading) -> String {
        MetricFormatting.battery(reading)
    }
}

@MainActor
final class CycleController: ObservableObject {
    @Published private(set) var index = 0
    let interval: TimeInterval
    private let clock: SamplingClock
    private var task: Task<Void, Never>?

    init(clock: SamplingClock = SystemSamplingClock(), interval: TimeInterval = 5, initialIndex: Int = 0) {
        self.clock = clock
        self.interval = interval
        index = initialIndex
    }

    var isRunning: Bool { task != nil }

    func start(enabledCount: @escaping @MainActor () -> Int) {
        guard task == nil else { return }
        let clock = self.clock
        let interval = self.interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: interval)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                index = CycleSequence.nextIndex(current: index, enabledCount: enabledCount())
            }
        }
    }

    func reset() { index = 0 }

    func stop() {
        task?.cancel()
        task = nil
    }
}
