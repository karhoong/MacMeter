import AppKit
import Combine

enum MetricStatusPalette {
    static let safe = NSColor(srgbRed: 0.30, green: 1.0, blue: 0.53, alpha: 1)
    static let caution = NSColor(srgbRed: 1.0, green: 0.87, blue: 0.25, alpha: 1)
    static let warm = NSColor(srgbRed: 1.0, green: 0.58, blue: 0.20, alpha: 1)
    static let critical = NSColor(srgbRed: 1.0, green: 0.34, blue: 0.40, alpha: 1)

    private struct Stop {
        let value: Double
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
    }

    static func cpu(normalizedPercent: Double) -> NSColor {
        interpolated(
            normalizedPercent,
            stops: [
                Stop(value: 0, red: 0.30, green: 1.0, blue: 0.53),
                Stop(value: 45, red: 0.30, green: 1.0, blue: 0.53),
                Stop(value: 65, red: 1.0, green: 0.87, blue: 0.25),
                Stop(value: 82, red: 1.0, green: 0.58, blue: 0.20),
                Stop(value: 100, red: 1.0, green: 0.34, blue: 0.40)
            ]
        )
    }

    static func temperature(celsius: Double) -> NSColor {
        interpolated(
            celsius,
            stops: [
                Stop(value: 0, red: 0.30, green: 1.0, blue: 0.53),
                Stop(value: 60, red: 0.30, green: 1.0, blue: 0.53),
                Stop(value: 75, red: 1.0, green: 0.87, blue: 0.25),
                Stop(value: 88, red: 1.0, green: 0.58, blue: 0.20),
                Stop(value: 100, red: 1.0, green: 0.34, blue: 0.40)
            ]
        )
    }

    private static func interpolated(_ rawValue: Double, stops: [Stop]) -> NSColor {
        guard let first = stops.first, let last = stops.last else { return safe }
        let value = min(max(rawValue, first.value), last.value)
        guard let upperIndex = stops.firstIndex(where: { value <= $0.value }) else {
            return NSColor(srgbRed: last.red, green: last.green, blue: last.blue, alpha: 1)
        }
        guard upperIndex > 0 else {
            return NSColor(srgbRed: first.red, green: first.green, blue: first.blue, alpha: 1)
        }
        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let span = max(upper.value - lower.value, .leastNonzeroMagnitude)
        let progress = CGFloat((value - lower.value) / span)
        return NSColor(
            srgbRed: lower.red + ((upper.red - lower.red) * progress),
            green: lower.green + ((upper.green - lower.green) * progress),
            blue: lower.blue + ((upper.blue - lower.blue) * progress),
            alpha: 1
        )
    }
}

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
        guard enabledMetrics.count > 1 else { return [enabledMetrics] }

        if enabledMetrics.contains(.network) {
            let remaining = enabledMetrics.filter { $0 != .network }
            return remaining.isEmpty ? [[.network]] : [[.network], remaining]
        }

        if enabledMetrics == [.cpu, .temperature] {
            return [[.cpu], [.temperature]]
        }

        if enabledMetrics.count == 3,
           enabledMetrics.contains(.cpu),
           enabledMetrics.contains(.temperature),
           enabledMetrics.contains(.battery) {
            return [[.cpu, .temperature], [.battery]]
        }

        return [[enabledMetrics[0]], Array(enabledMetrics.dropFirst())]
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
