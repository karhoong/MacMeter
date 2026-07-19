import Foundation

struct AppVersionInfo: Equatable {
    let version: String
    let build: String

    init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    init(bundle: Bundle = .main) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var current: AppVersionInfo { AppVersionInfo() }
    var displayLabel: String { "Version \(version) (\(build))" }
}

enum MetricAvailability<Value> {
    case available(Value, sampledAt: Date)
    case unavailable(String, observedAt: Date = Date())

    var value: Value? {
        guard case let .available(value, _) = self else { return nil }
        return value
    }

    var reason: String? {
        guard case let .unavailable(reason, _) = self else { return nil }
        return reason
    }

    var sampledAt: Date? {
        guard case let .available(_, sampledAt) = self else { return nil }
        return sampledAt
    }

    var observedAt: Date {
        switch self {
        case let .available(_, sampledAt): return sampledAt
        case let .unavailable(_, observedAt): return observedAt
        }
    }
}

enum CoreKind: String, Codable, CaseIterable {
    case efficiency
    case performance
    case unknown

    var shortLabel: String {
        switch self {
        case .efficiency: return "E"
        case .performance: return "P"
        case .unknown: return "?"
        }
    }

    var displayName: String {
        switch self {
        case .efficiency: return "Efficiency"
        case .performance: return "Performance"
        case .unknown: return "Unknown"
        }
    }
}

struct CoreReading: Equatable, Identifiable {
    let id: Int
    let utilization: Double
    let kind: CoreKind
}

struct CPUReading: Equatable {
    let normalized: Double
    let summed: Double
    let cores: [CoreReading]
}

struct TemperatureReading: Equatable {
    let hottestCelsius: Double
    let sensorCount: Int
}

struct NetworkReading: Equatable {
    let inboundBytesPerSecond: Double
    let outboundBytesPerSecond: Double
    let interfaces: [String]
}

enum BatteryDirection: String, Codable {
    case charging
    case draining
    case idle

    var shortLabel: String {
        switch self {
        case .charging: return "C"
        case .draining: return "D"
        case .idle: return "—"
        }
    }

    var spokenLabel: String {
        switch self {
        case .charging: return "Charging"
        case .draining: return "Draining"
        case .idle: return "Idle"
        }
    }
}

struct BatteryPowerReading: Equatable {
    let watts: Double
    let direction: BatteryDirection
}

enum CPUScale: String, Codable, CaseIterable, Identifiable {
    case normalized
    case summed
    var id: String { rawValue }
    var title: String { self == .normalized ? "Overall (0–100%)" : "All cores (n×100%)" }
}

enum NetworkUnit: String, Codable, CaseIterable, Identifiable {
    case Kbps
    case KBps
    case Mbps
    case MBps
    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .Kbps: return "Kb/s"
        case .KBps: return "KB/s"
        case .Mbps: return "Mb/s"
        case .MBps: return "MB/s"
        }
    }
}

enum TemperatureUnit: String, Codable, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }
    var symbol: String { self == .celsius ? "°C" : "°F" }
    var title: String { self == .celsius ? "Celsius" : "Fahrenheit" }

    func convert(celsius: Double) -> Double {
        self == .celsius ? celsius : (celsius * 9 / 5) + 32
    }
}

enum DisplayMode: String, Codable, CaseIterable, Identifiable {
    case compact
    case cycle
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum BatteryColorRole: Equatable {
    case charging
    case draining
    case idle
}

extension BatteryDirection {
    var colorRole: BatteryColorRole {
        switch self {
        case .charging: return .charging
        case .draining: return .draining
        case .idle: return .idle
        }
    }
}

enum MetricID: String, CaseIterable, Identifiable {
    case cpu
    case temperature
    case network
    case battery
    var id: String { rawValue }
}

struct CPUTicks: Equatable {
    let user: UInt64
    let system: UInt64
    let nice: UInt64
    let idle: UInt64
}

struct NetworkCounters: Equatable {
    let inboundBytes: UInt64
    let outboundBytes: UInt64
    let interfaces: [String]
}
