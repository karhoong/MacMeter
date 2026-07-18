import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let cpuEnabled = "metrics.cpu.enabled"
        static let temperatureEnabled = "metrics.temperature.enabled"
        static let networkEnabled = "metrics.network.enabled"
        static let batteryEnabled = "metrics.battery.enabled"
        static let cpuScale = "metrics.cpu.scale"
        static let networkUnit = "metrics.network.unit"
        static let displayMode = "appearance.mode"
        static let updateInterval = "general.updateInterval"
    }

    private let defaults: UserDefaults

    @Published var cpuEnabled: Bool { didSet { defaults.set(cpuEnabled, forKey: Key.cpuEnabled) } }
    @Published var temperatureEnabled: Bool { didSet { defaults.set(temperatureEnabled, forKey: Key.temperatureEnabled) } }
    @Published var networkEnabled: Bool { didSet { defaults.set(networkEnabled, forKey: Key.networkEnabled) } }
    @Published var batteryEnabled: Bool { didSet { defaults.set(batteryEnabled, forKey: Key.batteryEnabled) } }
    @Published var cpuScale: CPUScale { didSet { defaults.set(cpuScale.rawValue, forKey: Key.cpuScale) } }
    @Published var networkUnit: NetworkUnit { didSet { defaults.set(networkUnit.rawValue, forKey: Key.networkUnit) } }
    @Published var displayMode: DisplayMode { didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) } }
    @Published var updateInterval: TimeInterval { didSet { defaults.set(updateInterval, forKey: Key.updateInterval) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cpuEnabled = defaults.object(forKey: Key.cpuEnabled) as? Bool ?? true
        temperatureEnabled = defaults.object(forKey: Key.temperatureEnabled) as? Bool ?? true
        networkEnabled = defaults.object(forKey: Key.networkEnabled) as? Bool ?? true
        batteryEnabled = defaults.object(forKey: Key.batteryEnabled) as? Bool ?? true
        cpuScale = CPUScale(rawValue: defaults.string(forKey: Key.cpuScale) ?? "") ?? .normalized
        networkUnit = NetworkUnit(rawValue: defaults.string(forKey: Key.networkUnit) ?? "") ?? .MBps
        displayMode = DisplayMode(rawValue: defaults.string(forKey: Key.displayMode) ?? "") ?? .default
        let storedInterval = defaults.double(forKey: Key.updateInterval)
        updateInterval = [1.0, 2.0, 5.0, 10.0].contains(storedInterval) ? storedInterval : 2.0
    }

    var enabledMetrics: [MetricID] {
        MetricID.allCases.filter { metric in
            switch metric {
            case .cpu: return cpuEnabled
            case .temperature: return temperatureEnabled
            case .network: return networkEnabled
            case .battery: return batteryEnabled
            }
        }
    }
}
