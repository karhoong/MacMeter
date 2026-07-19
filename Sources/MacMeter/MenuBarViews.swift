import AppKit
import Combine
import SwiftUI

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
            // The status bar has a fixed height, so all values share one compact row.
            return [[.network, .cpu, .temperature, .battery]]
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

@MainActor
struct MenuBarLabelView: View {
    @ObservedObject var coordinator: MetricsCoordinator
    @ObservedObject var settings: SettingsStore
    @StateObject private var cycleController: CycleController

    init(
        coordinator: MetricsCoordinator,
        settings: SettingsStore,
        cycleClock: SamplingClock = SystemSamplingClock()
    ) {
        self.coordinator = coordinator
        self.settings = settings
        _cycleController = StateObject(wrappedValue: CycleController(clock: cycleClock))
    }

    init(coordinator: MetricsCoordinator, settings: SettingsStore, cycleController: CycleController) {
        self.coordinator = coordinator
        self.settings = settings
        _cycleController = StateObject(wrappedValue: cycleController)
    }

    var body: some View {
        Group {
            if settings.enabledMetrics.isEmpty {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .accessibilityLabel("MacMeter. No metrics enabled")
            } else if settings.displayMode == .cycle {
                metricView(settings.enabledMetrics[cycleController.index % settings.enabledMetrics.count], compact: true)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                let rows = MenuBarPresentation.rows(for: settings.enabledMetrics)
                metricRow(rows[0])
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .font(menuBarFont)
        .lineLimit(1)
        .onAppear {
            updateCycleActivity()
        }
        .onDisappear { cycleController.stop() }
        .onChange(of: settings.enabledMetrics) { _ in
            cycleController.reset()
            updateCycleActivity()
        }
        .onChange(of: settings.displayMode) { _ in
            cycleController.reset()
            updateCycleActivity()
        }
    }

    private var menuBarFont: Font {
        .system(size: 8, weight: .medium, design: .monospaced)
    }

    private func metricRow(_ metrics: [MetricID]) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                if index > 0 {
                    Text("|").foregroundStyle(.secondary).accessibilityHidden(true)
                }
                metricView(metric, compact: true)
            }
        }
    }

    @ViewBuilder
    private func metricView(_ metric: MetricID, compact: Bool) -> some View {
        switch metric {
        case .cpu:
            if let reading = coordinator.cpu.value {
                let value = settings.cpuScale == .normalized ? reading.normalized : reading.summed
                Text(MenuBarPresentation.cpu(reading, scale: settings.cpuScale))
                    .accessibilityLabel(MetricAccessibility.cpu(value))
            } else {
                Text("—").accessibilityLabel("CPU unavailable")
            }
        case .temperature:
            if let reading = coordinator.temperature.value {
                Text(MenuBarPresentation.temperature(reading, unit: settings.temperatureUnit))
                    .accessibilityLabel(MetricAccessibility.temperature(
                        reading.hottestCelsius,
                        unit: settings.temperatureUnit
                    ))
            } else {
                Text("—").accessibilityLabel("SoC temperature unavailable")
            }
        case .network:
            if let reading = coordinator.network.value {
                Text(MenuBarPresentation.network(reading, unit: settings.networkUnit))
                    .accessibilityLabel(MetricAccessibility.network(reading, unit: settings.networkUnit))
            } else {
                Text("↑—↓—\(settings.networkUnit.menuLabel)").accessibilityLabel("Network speed unavailable")
            }
        case .battery:
            if let reading = coordinator.battery.value {
                Text(MenuBarPresentation.battery(reading))
                    .foregroundStyle(color(for: reading.direction))
                    .accessibilityLabel(MetricAccessibility.battery(reading))
            } else {
                Text("—").foregroundStyle(.secondary).accessibilityLabel("Battery power unavailable")
            }
        }
    }

    private func color(for direction: BatteryDirection) -> Color {
        switch direction.colorRole {
        case .charging: return .green
        case .draining: return .red
        case .idle: return .blue
        }
    }

    private func updateCycleActivity() {
        if CycleActivityPolicy.shouldRun(mode: settings.displayMode, enabledCount: settings.enabledMetrics.count) {
            cycleController.start { settings.enabledMetrics.count }
        } else {
            cycleController.stop()
        }
    }
}

struct MeterPopoverView: View {
    @ObservedObject var coordinator: MetricsCoordinator
    @ObservedObject var settings: SettingsStore
    var appVersion: AppVersionInfo = .current
    var openSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MacMeter").font(.headline)
                Spacer()
                Text(appVersion.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(appVersion.displayLabel)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if settings.cpuEnabled { cpuCard }
                    if settings.temperatureEnabled { temperatureCard }
                    if settings.networkEnabled { networkCard }
                    if settings.batteryEnabled { batteryCard }
                }
            }
            .frame(maxHeight: 430)
            Divider()
            HStack {
                if let date = coordinator.lastUpdated {
                    Text("Updated \(date.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Waiting for data").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Settings…", action: openSettings)
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 390)
    }

    private var cpuCard: some View {
        MetricCard(title: "CPU", systemImage: "cpu") {
            if let reading = coordinator.cpu.value {
                LabeledContent("Overall", value: MetricFormatting.percent(reading.normalized))
                LabeledContent("All cores", value: MetricFormatting.percent(reading.summed))
                Divider()
                ForEach(reading.cores) { core in
                    HStack {
                        Text("Core \(core.id)")
                        Text(core.kind.shortLabel)
                            .font(.caption.bold())
                            .foregroundStyle(core.kind == .efficiency ? .green : core.kind == .performance ? .orange : .secondary)
                            .accessibilityLabel(core.kind.displayName)
                        Spacer()
                        Text(MetricFormatting.percent(core.utilization)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Core \(core.id), \(core.kind.displayName), \(MetricFormatting.percent(core.utilization))")
                }
            } else {
                UnavailableView(reason: coordinator.cpu.reason)
            }
        }
    }

    private var temperatureCard: some View {
        MetricCard(title: "SoC Temperature", systemImage: "thermometer.medium") {
            if let reading = coordinator.temperature.value {
                LabeledContent("Hottest", value: MetricFormatting.temperature(
                    reading.hottestCelsius,
                    unit: settings.temperatureUnit
                ))
                LabeledContent("Sensors", value: "\(reading.sensorCount)")
            } else {
                UnavailableView(reason: coordinator.temperature.reason)
            }
        }
    }

    private var networkCard: some View {
        MetricCard(title: "Network", systemImage: "network") {
            if let reading = coordinator.network.value {
                LabeledContent("Inbound", value: "\(MetricFormatting.network(bytesPerSecond: reading.inboundBytesPerSecond, unit: settings.networkUnit)) \(settings.networkUnit.rawValue)")
                LabeledContent("Outbound", value: "\(MetricFormatting.network(bytesPerSecond: reading.outboundBytesPerSecond, unit: settings.networkUnit)) \(settings.networkUnit.rawValue)")
                LabeledContent("Interfaces", value: reading.interfaces.joined(separator: ", "))
            } else {
                UnavailableView(reason: coordinator.network.reason)
            }
        }
    }

    private var batteryCard: some View {
        MetricCard(title: "Battery Power", systemImage: "battery.75percent") {
            if let reading = coordinator.battery.value {
                HStack {
                    Text(reading.direction.spokenLabel)
                    Spacer()
                    Text(MetricFormatting.battery(reading))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(color(for: reading.direction))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(MetricAccessibility.battery(reading))
            } else {
                UnavailableView(reason: coordinator.battery.reason)
            }
        }
    }

    private func color(for direction: BatteryDirection) -> Color {
        switch direction.colorRole {
        case .charging: return .green
        case .draining: return .red
        case .idle: return .blue
        }
    }
}

private struct MetricCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct UnavailableView: View {
    let reason: String?
    var body: some View {
        Label(reason ?? "Unavailable", systemImage: "exclamationmark.circle")
            .font(.caption).foregroundStyle(.secondary)
    }
}
