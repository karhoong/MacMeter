import Darwin
import Foundation
import IOKit
import IOKit.ps
#if SWIFT_PACKAGE
import MacMeterSensors
#endif

@MainActor
protocol CPUProviding: AnyObject {
    func sample(at date: Date) -> MetricAvailability<CPUReading>
    func resetBaseline()
}

@MainActor
protocol TemperatureProviding: AnyObject {
    func sample(at date: Date) -> MetricAvailability<TemperatureReading>
}

@MainActor
protocol NetworkProviding: AnyObject {
    func sample(at date: Date) -> MetricAvailability<NetworkReading>
    func resetBaseline()
}

@MainActor
protocol BatteryProviding: AnyObject {
    func sample(at date: Date) -> MetricAvailability<BatteryPowerReading>
}

struct NetworkInterfaceSnapshot: Equatable {
    let name: String
    let isUp: Bool
    let isRunning: Bool
    let inboundBytes: UInt64
    let outboundBytes: UInt64
}

struct BatteryTelemetry: Equatable {
    let voltageMillivolts: Int64?
    let currentMilliamps: Int64?
    let isCharging: Bool?
    let isExternalConnected: Bool?
}

@MainActor
final class CPUProvider: CPUProviding {
    private var previous: [CPUTicks]?
    private let coreKinds: [Int: CoreKind]

    init(coreKinds: [Int: CoreKind] = CoreTopologyReader.read()) {
        self.coreKinds = coreKinds
    }

    func sample(at date: Date) -> MetricAvailability<CPUReading> {
        guard let current = readTicks() else { return .unavailable("CPU counters could not be read", observedAt: date) }
        defer { previous = current }
        guard let previous,
              let reading = MetricMath.cpuReading(current: current, previous: previous, coreKinds: coreKinds) else {
            return .unavailable("Collecting initial CPU sample", observedAt: date)
        }
        return .available(reading, sampledAt: date)
    }

    func resetBaseline() { previous = nil }

    private func readTicks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            let size = vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
        }

        let buffer = UnsafeBufferPointer(start: info, count: Int(infoCount))
        return (0..<Int(cpuCount)).map { index in
            let offset = index * Int(CPU_STATE_MAX)
            return CPUTicks(
                user: UInt64(UInt32(bitPattern: buffer[offset + Int(CPU_STATE_USER)])),
                system: UInt64(UInt32(bitPattern: buffer[offset + Int(CPU_STATE_SYSTEM)])),
                nice: UInt64(UInt32(bitPattern: buffer[offset + Int(CPU_STATE_NICE)])),
                idle: UInt64(UInt32(bitPattern: buffer[offset + Int(CPU_STATE_IDLE)]))
            )
        }
    }
}

enum CoreTopologyReader {
    static func read() -> [Int: CoreKind] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMPE"), &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        var result: [Int: CoreKind] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &children) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(children) }

            while case let child = IOIteratorNext(children), child != 0 {
                defer { IOObjectRelease(child) }
                guard let name = registryName(child), name.hasPrefix("cpu"),
                      let id = Int(name.dropFirst(3)),
                      let property = IORegistryEntryCreateCFProperty(
                        child,
                        "cluster-type" as CFString,
                        kCFAllocatorDefault,
                        0
                      )?.takeRetainedValue() as? Data,
                      let cluster = String(data: property, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) else { continue }
                result[id] = cluster == "E" ? .efficiency : (["P", "M"].contains(cluster) ? .performance : .unknown)
            }
        }
        return Dictionary(uniqueKeysWithValues: result.sorted(by: { $0.key < $1.key }).enumerated().map { index, element in
            (index, element.value)
        })
    }

    private static func registryName(_ entry: io_registry_entry_t) -> String? {
        var rawName = [CChar](repeating: 0, count: 128)
        let status = rawName.withUnsafeMutableBufferPointer { buffer in
            IORegistryEntryGetName(entry, buffer.baseAddress!)
        }
        guard status == KERN_SUCCESS else { return nil }
        return rawName.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
}

@MainActor
final class SoCTemperatureProvider: TemperatureProviding {
    func sample(at date: Date) -> MetricAvailability<TemperatureReading> {
        var count: Int32 = 0
        let hottest = MMHottestSoCTemperature(&count)
        guard let value = MetricMath.validatedTemperature(hottest), count > 0 else {
            return .unavailable("No supported SoC temperature sensor", observedAt: date)
        }
        return .available(TemperatureReading(hottestCelsius: value, sensorCount: Int(count)), sampledAt: date)
    }
}

@MainActor
final class NetworkProvider: NetworkProviding {
    private var previous: (counters: NetworkCounters, date: Date)?
    private let interfaceReader: @MainActor () -> [NetworkInterfaceSnapshot]?

    init(interfaceReader: @escaping @MainActor () -> [NetworkInterfaceSnapshot]? = NetworkProvider.readInterfaces) {
        self.interfaceReader = interfaceReader
    }

    func sample(at date: Date) -> MetricAvailability<NetworkReading> {
        guard let interfaces = interfaceReader() else {
            return .unavailable("Network counters could not be read", observedAt: date)
        }
        let current = Self.aggregate(interfaces)
        defer { previous = (current, date) }
        guard let previous,
              let reading = MetricMath.networkReading(
                current: current,
                previous: previous.counters,
                elapsed: date.timeIntervalSince(previous.date)
              ) else {
            return .unavailable("Collecting initial network sample", observedAt: date)
        }
        return .available(reading, sampledAt: date)
    }

    func resetBaseline() { previous = nil }

    static func aggregate(_ interfaces: [NetworkInterfaceSnapshot]) -> NetworkCounters {
        let active = interfaces.filter { snapshot in
            snapshot.name.hasPrefix("en") && snapshot.isUp && snapshot.isRunning
        }
        return NetworkCounters(
            inboundBytes: active.reduce(0) { $0 + $1.inboundBytes },
            outboundBytes: active.reduce(0) { $0 + $1.outboundBytes },
            interfaces: active.map(\.name).sorted()
        )
    }

    private static func readInterfaces() -> [NetworkInterfaceSnapshot]? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        var snapshots: [NetworkInterfaceSnapshot] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let rawName = entry.pointee.ifa_name else { continue }
            let name = String(cString: rawName)
            let flags = entry.pointee.ifa_flags
            guard let rawData = entry.pointee.ifa_data else { continue }
            let data = rawData.assumingMemoryBound(to: if_data.self).pointee
            snapshots.append(NetworkInterfaceSnapshot(
                name: name,
                isUp: flags & UInt32(IFF_UP) != 0,
                isRunning: flags & UInt32(IFF_RUNNING) != 0,
                inboundBytes: UInt64(data.ifi_ibytes),
                outboundBytes: UInt64(data.ifi_obytes)
            ))
        }
        return snapshots
    }
}

@MainActor
final class BatteryPowerProvider: BatteryProviding {
    private let telemetryReader: @MainActor () -> BatteryTelemetry?

    init(telemetryReader: @escaping @MainActor () -> BatteryTelemetry? = BatteryPowerProvider.readTelemetry) {
        self.telemetryReader = telemetryReader
    }

    func sample(at date: Date) -> MetricAvailability<BatteryPowerReading> {
        guard let telemetry = telemetryReader() else {
            return .unavailable("This Mac has no battery", observedAt: date)
        }
        guard let voltage = telemetry.voltageMillivolts,
              let current = telemetry.currentMilliamps else {
            return .unavailable("Battery voltage or current is unavailable", observedAt: date)
        }

        let reading = MetricMath.batteryPower(voltageMillivolts: voltage, currentMilliamps: current)
        let charging = telemetry.isCharging ?? false
        let external = telemetry.isExternalConnected ?? false
        if reading.direction == .charging && (!charging || !external) {
            return .unavailable("Battery power state is inconsistent", observedAt: date)
        }
        if reading.direction == .draining && charging {
            return .unavailable("Battery power state is inconsistent", observedAt: date)
        }
        return .available(reading, sampledAt: date)
    }

    private static func readTelemetry() -> BatteryTelemetry? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        return BatteryTelemetry(
            voltageMillivolts: integerProperty("Voltage", service: service),
            currentMilliamps: integerProperty("InstantAmperage", service: service)
                ?? integerProperty("Amperage", service: service),
            isCharging: boolProperty("IsCharging", service: service),
            isExternalConnected: boolProperty("ExternalConnected", service: service)
        )
    }

    private static func integerProperty(_ key: String, service: io_registry_entry_t) -> Int64? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let number = value as? NSNumber else { return nil }
        return number.int64Value
    }

    private static func boolProperty(_ key: String, service: io_registry_entry_t) -> Bool? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        return value as? Bool
    }
}
