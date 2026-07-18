import AppKit
import Combine
import Foundation

@MainActor
protocol SamplingClock: AnyObject {
    var now: Date { get }
    func sleep(for seconds: TimeInterval) async throws
}

@MainActor
final class SystemSamplingClock: SamplingClock {
    var now: Date { Date() }

    func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

@MainActor
final class MetricsCoordinator: ObservableObject {
    @Published private(set) var cpu: MetricAvailability<CPUReading> = .unavailable("Waiting for first sample")
    @Published private(set) var temperature: MetricAvailability<TemperatureReading> = .unavailable("Waiting for first sample")
    @Published private(set) var network: MetricAvailability<NetworkReading> = .unavailable("Waiting for first sample")
    @Published private(set) var battery: MetricAvailability<BatteryPowerReading> = .unavailable("Waiting for first sample")
    @Published private(set) var lastUpdated: Date?

    let settings: SettingsStore
    private let cpuProvider: CPUProviding
    private let temperatureProvider: TemperatureProviding
    private let networkProvider: NetworkProviding
    private let batteryProvider: BatteryProviding
    private let clock: SamplingClock
    private var samplingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private(set) var samplingStartCount = 0
    var isSampling: Bool { samplingTask != nil }

    init(
        settings: SettingsStore,
        cpuProvider: CPUProviding? = nil,
        temperatureProvider: TemperatureProviding? = nil,
        networkProvider: NetworkProviding? = nil,
        batteryProvider: BatteryProviding? = nil,
        clock: SamplingClock = SystemSamplingClock(),
        startAutomatically: Bool = true
    ) {
        self.settings = settings
        self.cpuProvider = cpuProvider ?? CPUProvider()
        self.temperatureProvider = temperatureProvider ?? SoCTemperatureProvider()
        self.networkProvider = networkProvider ?? NetworkProvider()
        self.batteryProvider = batteryProvider ?? BatteryPowerProvider()
        self.clock = clock

        settings.$updateInterval.dropFirst().removeDuplicates().sink { [weak self] _ in
            Task { @MainActor in self?.restartSampling() }
        }.store(in: &cancellables)

        settings.$cpuEnabled.dropFirst().removeDuplicates().sink { [weak self] enabled in
            Task { @MainActor in self?.setCPUEnabled(enabled) }
        }.store(in: &cancellables)
        settings.$temperatureEnabled.dropFirst().removeDuplicates().sink { [weak self] enabled in
            Task { @MainActor in self?.setTemperatureEnabled(enabled) }
        }.store(in: &cancellables)
        settings.$networkEnabled.dropFirst().removeDuplicates().sink { [weak self] enabled in
            Task { @MainActor in self?.setNetworkEnabled(enabled) }
        }.store(in: &cancellables)
        settings.$batteryEnabled.dropFirst().removeDuplicates().sink { [weak self] enabled in
            Task { @MainActor in self?.setBatteryEnabled(enabled) }
        }.store(in: &cancellables)

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resetRateBaselines() }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resetRateBaselines()
                self?.sampleNow()
            }
        })

        if startAutomatically { restartSampling() }
    }

    func restartSampling() {
        samplingTask?.cancel()
        sampleNow()
        samplingStartCount += 1
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.settings.updateInterval
                do {
                    try await self.clock.sleep(for: interval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self.sampleNow()
            }
        }
    }

    func stopSampling() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    func sampleNow() {
        sampleNow(at: clock.now)
    }

    func sampleNow(at date: Date) {
        var sampledSomething = false
        if settings.cpuEnabled {
            cpu = cpuProvider.sample(at: date)
            sampledSomething = sampledSomething || cpu.value != nil
        } else {
            cpu = .unavailable("Disabled", observedAt: date)
        }
        if settings.temperatureEnabled {
            temperature = temperatureProvider.sample(at: date)
            sampledSomething = sampledSomething || temperature.value != nil
        } else {
            temperature = .unavailable("Disabled", observedAt: date)
        }
        if settings.networkEnabled {
            network = networkProvider.sample(at: date)
            sampledSomething = sampledSomething || network.value != nil
        } else {
            network = .unavailable("Disabled", observedAt: date)
        }
        if settings.batteryEnabled {
            battery = batteryProvider.sample(at: date)
            sampledSomething = sampledSomething || battery.value != nil
        } else {
            battery = .unavailable("Disabled", observedAt: date)
        }
        if sampledSomething { lastUpdated = date }
    }

    func resetRateBaselines() {
        cpuProvider.resetBaseline()
        networkProvider.resetBaseline()
        cpu = .unavailable("Collecting fresh CPU sample", observedAt: clock.now)
        network = .unavailable("Collecting fresh network sample", observedAt: clock.now)
    }

    private func setCPUEnabled(_ enabled: Bool) {
        cpuProvider.resetBaseline()
        guard enabled else {
            cpu = .unavailable("Disabled", observedAt: clock.now)
            return
        }
        cpu = cpuProvider.sample(at: clock.now)
    }

    private func setTemperatureEnabled(_ enabled: Bool) {
        guard enabled else {
            temperature = .unavailable("Disabled", observedAt: clock.now)
            return
        }
        temperature = temperatureProvider.sample(at: clock.now)
    }

    private func setNetworkEnabled(_ enabled: Bool) {
        networkProvider.resetBaseline()
        guard enabled else {
            network = .unavailable("Disabled", observedAt: clock.now)
            return
        }
        network = networkProvider.sample(at: clock.now)
    }

    private func setBatteryEnabled(_ enabled: Bool) {
        guard enabled else {
            battery = .unavailable("Disabled", observedAt: clock.now)
            return
        }
        battery = batteryProvider.sample(at: clock.now)
    }
}
