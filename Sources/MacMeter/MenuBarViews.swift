import AppKit
import Combine
import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var coordinator: MetricsCoordinator
    @ObservedObject var settings: SettingsStore
    @State private var cycleIndex = 0
    private let cycleTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if settings.enabledMetrics.isEmpty {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .accessibilityLabel("MacMeter. No metrics enabled")
            } else if settings.displayMode == .cycle {
                metricView(settings.enabledMetrics[cycleIndex % settings.enabledMetrics.count], compact: true)
                    .frame(minWidth: 72)
            } else {
                HStack(spacing: settings.displayMode == .compact ? 3 : 5) {
                    ForEach(Array(settings.enabledMetrics.enumerated()), id: \.element.id) { index, metric in
                        if index > 0 && settings.displayMode == .default {
                            Text("|").foregroundStyle(.secondary)
                        }
                        metricView(metric, compact: settings.displayMode == .compact)
                    }
                }
            }
        }
        .font(.system(size: settings.displayMode == .compact ? 9 : 11, weight: .medium, design: .monospaced))
        .lineLimit(1)
        .onReceive(cycleTimer) { _ in
            guard settings.displayMode == .cycle, !settings.enabledMetrics.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                cycleIndex = CycleSequence.nextIndex(current: cycleIndex, enabledCount: settings.enabledMetrics.count)
            }
        }
        .onChange(of: settings.enabledMetrics) { _ in cycleIndex = 0 }
    }

    @ViewBuilder
    private func metricView(_ metric: MetricID, compact: Bool) -> some View {
        switch metric {
        case .cpu:
            if let reading = coordinator.cpu.value {
                let value = settings.cpuScale == .normalized ? reading.normalized : reading.summed
                Text("\(compact ? "C" : "CPU") \(MetricFormatting.percent(value))")
                    .accessibilityLabel("CPU utilization \(MetricFormatting.percent(value))")
            } else {
                Text("\(compact ? "C" : "CPU") —").accessibilityLabel("CPU unavailable")
            }
        case .temperature:
            if let reading = coordinator.temperature.value {
                Text("\(compact ? "T" : "SoC") \(MetricFormatting.temperature(reading.hottestCelsius, compact: compact))")
                    .accessibilityLabel("SoC temperature \(MetricFormatting.temperature(reading.hottestCelsius))")
            } else {
                Text("\(compact ? "T" : "SoC") —").accessibilityLabel("SoC temperature unavailable")
            }
        case .network:
            if let reading = coordinator.network.value {
                Text(MetricFormatting.networkPair(reading, unit: settings.networkUnit))
                    .accessibilityLabel("Network download \(MetricFormatting.network(bytesPerSecond: reading.inboundBytesPerSecond, unit: settings.networkUnit)) \(settings.networkUnit.rawValue), upload \(MetricFormatting.network(bytesPerSecond: reading.outboundBytesPerSecond, unit: settings.networkUnit)) \(settings.networkUnit.rawValue)")
            } else {
                Text("↓— ↑—").accessibilityLabel("Network speed unavailable")
            }
        case .battery:
            if let reading = coordinator.battery.value {
                Text(MetricFormatting.battery(reading))
                    .foregroundStyle(color(for: reading.direction))
                    .accessibilityLabel("Battery \(reading.direction.spokenLabel), \(MetricFormatting.decimal(reading.watts)) watts")
            } else {
                Text("—").foregroundStyle(.secondary).accessibilityLabel("Battery power unavailable")
            }
        }
    }

    private func color(for direction: BatteryDirection) -> Color {
        switch direction {
        case .charging: return .green
        case .draining: return .red
        case .idle: return .secondary
        }
    }
}

struct MeterPopoverView: View {
    @ObservedObject var coordinator: MetricsCoordinator
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MacMeter").font(.headline)
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
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
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
                LabeledContent("Hottest", value: MetricFormatting.temperature(reading.hottestCelsius))
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
                        .foregroundStyle(reading.direction == .charging ? .green : reading.direction == .draining ? .red : .secondary)
                }
            } else {
                UnavailableView(reason: coordinator.battery.reason)
            }
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
