import XCTest
@testable import MacMeter

@MainActor
final class MetricsCoordinatorTests: XCTestCase {
    func testDisabledProvidersAreNotSampled() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults.value)
        settings.temperatureEnabled = false
        settings.networkEnabled = false
        settings.batteryEnabled = false
        let cpu = FakeCPUProvider()
        let temperature = FakeTemperatureProvider()
        let network = FakeNetworkProvider()
        let battery = FakeBatteryProvider()
        let coordinator = MetricsCoordinator(
            settings: settings,
            cpuProvider: cpu,
            temperatureProvider: temperature,
            networkProvider: network,
            batteryProvider: battery,
            startAutomatically: false
        )

        coordinator.sampleNow(at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(cpu.sampleCount, 1)
        XCTAssertEqual(temperature.sampleCount, 0)
        XCTAssertEqual(network.sampleCount, 0)
        XCTAssertEqual(battery.sampleCount, 0)
        XCTAssertEqual(coordinator.temperature.reason, "Disabled")
        defaults.cleanup()
    }

    func testProviderFailureDoesNotBlockOtherMetrics() throws {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults.value)
        let cpu = FakeCPUProvider(result: .unavailable("fixture failure"))
        let networkReading = NetworkReading(inboundBytesPerSecond: 100, outboundBytesPerSecond: 50, interfaces: ["en0"])
        let coordinator = MetricsCoordinator(
            settings: settings,
            cpuProvider: cpu,
            temperatureProvider: FakeTemperatureProvider(),
            networkProvider: FakeNetworkProvider(result: .available(networkReading, sampledAt: .distantPast)),
            batteryProvider: FakeBatteryProvider(),
            startAutomatically: false
        )

        let date = Date(timeIntervalSince1970: 200)
        coordinator.sampleNow(at: date)

        XCTAssertEqual(coordinator.cpu.reason, "fixture failure")
        XCTAssertEqual(try XCTUnwrap(coordinator.network.value), networkReading)
        XCTAssertEqual(coordinator.lastUpdated, date)
        defaults.cleanup()
    }

    func testResetClearsRateBaselines() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults.value)
        let cpu = FakeCPUProvider()
        let network = FakeNetworkProvider()
        let coordinator = MetricsCoordinator(
            settings: settings,
            cpuProvider: cpu,
            temperatureProvider: FakeTemperatureProvider(),
            networkProvider: network,
            batteryProvider: FakeBatteryProvider(),
            startAutomatically: false
        )

        coordinator.resetRateBaselines()

        XCTAssertEqual(cpu.resetCount, 1)
        XCTAssertEqual(network.resetCount, 1)
        XCTAssertNotNil(coordinator.cpu.reason)
        XCTAssertNotNil(coordinator.network.reason)
        defaults.cleanup()
    }

    func testInjectedClockProvidesSamplingTimestamp() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults.value)
        let date = Date(timeIntervalSince1970: 42)
        let clock = FakeSamplingClock(now: date)
        let cpu = FakeCPUProvider()
        let coordinator = MetricsCoordinator(
            settings: settings,
            cpuProvider: cpu,
            temperatureProvider: FakeTemperatureProvider(),
            networkProvider: FakeNetworkProvider(),
            batteryProvider: FakeBatteryProvider(),
            clock: clock,
            startAutomatically: false
        )

        coordinator.sampleNow()

        XCTAssertEqual(cpu.lastSampleDate, date)
        XCTAssertEqual(coordinator.lastUpdated, date)
        defaults.cleanup()
    }

    func testPresentationChangesDoNotTriggerHardwareSamples() async {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults.value)
        let cpu = FakeCPUProvider()
        let coordinator = MetricsCoordinator(
            settings: settings,
            cpuProvider: cpu,
            temperatureProvider: FakeTemperatureProvider(),
            networkProvider: FakeNetworkProvider(),
            batteryProvider: FakeBatteryProvider(),
            startAutomatically: false
        )

        settings.cpuScale = .summed
        settings.networkUnit = .Kbps
        settings.displayMode = .compact
        await Task.yield()

        XCTAssertEqual(cpu.sampleCount, 0)
        XCTAssertEqual(coordinator.samplingStartCount, 0)
        defaults.cleanup()
    }

    func testRateProvidersRebaselineWhenDisabledAndReenabled() async {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults.value)
        settings.temperatureEnabled = false
        settings.batteryEnabled = false
        let cpu = BaselineCPUProvider()
        let network = BaselineNetworkProvider()
        let coordinator = MetricsCoordinator(
            settings: settings,
            cpuProvider: cpu,
            temperatureProvider: FakeTemperatureProvider(),
            networkProvider: network,
            batteryProvider: FakeBatteryProvider(),
            startAutomatically: false
        )

        coordinator.sampleNow()
        coordinator.sampleNow()
        XCTAssertNotNil(coordinator.cpu.value)
        XCTAssertNotNil(coordinator.network.value)

        settings.cpuEnabled = false
        settings.networkEnabled = false
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(coordinator.cpu.reason, "Disabled")
        XCTAssertEqual(coordinator.network.reason, "Disabled")

        settings.cpuEnabled = true
        settings.networkEnabled = true
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(coordinator.cpu.reason, "Collecting fresh CPU sample")
        XCTAssertEqual(coordinator.network.reason, "Collecting fresh network sample")
        XCTAssertEqual(cpu.resetCount, 2)
        XCTAssertEqual(network.resetCount, 2)

        coordinator.sampleNow()
        XCTAssertNotNil(coordinator.cpu.value)
        XCTAssertNotNil(coordinator.network.value)
        defaults.cleanup()
    }

    func testIntervalChangeRestartsExactlyOnceAndCanBeCancelled() async {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults.value)
        let clock = FakeSamplingClock(now: Date(timeIntervalSince1970: 10))
        let coordinator = MetricsCoordinator(settings: settings, clock: clock)
        XCTAssertEqual(coordinator.samplingStartCount, 1)
        XCTAssertTrue(coordinator.isSampling)

        settings.updateInterval = 5
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(coordinator.samplingStartCount, 2)

        settings.updateInterval = 5
        await Task.yield()
        XCTAssertEqual(coordinator.samplingStartCount, 2)

        coordinator.stopSampling()
        XCTAssertFalse(coordinator.isSampling)
        defaults.cleanup()
    }

    func testCycleControllerUsesFiveSecondClockAndAdvancesOnce() async {
        let clock = StepSamplingClock(steps: 1)
        let controller = CycleController(clock: clock)

        controller.start { 4 }
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(clock.requestedIntervals.first, 5)
        XCTAssertEqual(controller.interval, 5)
        XCTAssertEqual(controller.index, 1)
        controller.reset()
        XCTAssertEqual(controller.index, 0)
        controller.stop()
    }

    func testCycleActivityPolicyStopsInactiveAndEmptyModes() {
        XCTAssertFalse(CycleActivityPolicy.shouldRun(mode: .compact, enabledCount: 4))
        XCTAssertFalse(CycleActivityPolicy.shouldRun(mode: .default, enabledCount: 4))
        XCTAssertFalse(CycleActivityPolicy.shouldRun(mode: .cycle, enabledCount: 0))
        XCTAssertTrue(CycleActivityPolicy.shouldRun(mode: .cycle, enabledCount: 1))
    }

    func testCycleControllerCancellationAndRestart() async {
        let clock = BlockingSamplingClock()
        let controller = CycleController(clock: clock)
        XCTAssertFalse(controller.isRunning)

        controller.start { 4 }
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(clock.requestedIntervals, [5])

        controller.start { 4 }
        for _ in 0..<2 { await Task.yield() }
        XCTAssertEqual(clock.requestedIntervals, [5], "Starting twice must not add a second cycle task")

        controller.stop()
        XCTAssertFalse(controller.isRunning)
        controller.start { 4 }
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(clock.requestedIntervals, [5, 5])
        controller.stop()
    }

    private func makeDefaults() -> (value: UserDefaults, cleanup: () -> Void) {
        let suite = "MacMeterCoordinatorTests.\(UUID().uuidString)"
        let value = UserDefaults(suiteName: suite)!
        return (value, { value.removePersistentDomain(forName: suite) })
    }
}

@MainActor
final class FakeCPUProvider: CPUProviding {
    var sampleCount = 0
    var resetCount = 0
    var result: MetricAvailability<CPUReading>
    var lastSampleDate: Date?
    init(result: MetricAvailability<CPUReading> = .available(CPUReading(normalized: 10, summed: 20, cores: []), sampledAt: .distantPast)) {
        self.result = result
    }
    func sample(at date: Date) -> MetricAvailability<CPUReading> { sampleCount += 1; lastSampleDate = date; return result }
    func resetBaseline() { resetCount += 1 }
}

@MainActor
final class FakeSamplingClock: SamplingClock {
    var now: Date
    init(now: Date) { self.now = now }
    func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: 3_600_000_000_000)
    }
}

@MainActor
final class StepSamplingClock: SamplingClock {
    var now = Date(timeIntervalSince1970: 0)
    private var steps: Int
    private(set) var requestedIntervals: [TimeInterval] = []
    init(steps: Int) { self.steps = steps }
    func sleep(for seconds: TimeInterval) async throws {
        requestedIntervals.append(seconds)
        guard steps > 0 else { throw CancellationError() }
        steps -= 1
    }
}

@MainActor
final class BlockingSamplingClock: SamplingClock {
    var now = Date(timeIntervalSince1970: 0)
    private(set) var requestedIntervals: [TimeInterval] = []
    func sleep(for seconds: TimeInterval) async throws {
        requestedIntervals.append(seconds)
        try await Task.sleep(nanoseconds: 3_600_000_000_000)
    }
}

@MainActor
final class BaselineCPUProvider: CPUProviding {
    var resetCount = 0
    private var hasBaseline = false
    func sample(at date: Date) -> MetricAvailability<CPUReading> {
        guard hasBaseline else {
            hasBaseline = true
            return .unavailable("Collecting fresh CPU sample")
        }
        return .available(CPUReading(normalized: 10, summed: 20, cores: []), sampledAt: date)
    }
    func resetBaseline() { resetCount += 1; hasBaseline = false }
}

@MainActor
final class BaselineNetworkProvider: NetworkProviding {
    var resetCount = 0
    private var hasBaseline = false
    func sample(at date: Date) -> MetricAvailability<NetworkReading> {
        guard hasBaseline else {
            hasBaseline = true
            return .unavailable("Collecting fresh network sample")
        }
        return .available(NetworkReading(inboundBytesPerSecond: 1, outboundBytesPerSecond: 1, interfaces: ["en0"]), sampledAt: date)
    }
    func resetBaseline() { resetCount += 1; hasBaseline = false }
}

@MainActor
final class FakeTemperatureProvider: TemperatureProviding {
    var sampleCount = 0
    func sample(at date: Date) -> MetricAvailability<TemperatureReading> {
        sampleCount += 1
        return .available(TemperatureReading(hottestCelsius: 55, sensorCount: 2), sampledAt: date)
    }
}

@MainActor
final class FakeNetworkProvider: NetworkProviding {
    var sampleCount = 0
    var resetCount = 0
    var result: MetricAvailability<NetworkReading>
    init(result: MetricAvailability<NetworkReading> = .available(NetworkReading(inboundBytesPerSecond: 1, outboundBytesPerSecond: 1, interfaces: ["en0"]), sampledAt: .distantPast)) {
        self.result = result
    }
    func sample(at date: Date) -> MetricAvailability<NetworkReading> { sampleCount += 1; return result }
    func resetBaseline() { resetCount += 1 }
}

@MainActor
final class FakeBatteryProvider: BatteryProviding {
    var sampleCount = 0
    func sample(at date: Date) -> MetricAvailability<BatteryPowerReading> {
        sampleCount += 1
        return .available(BatteryPowerReading(watts: 8.4, direction: .draining), sampledAt: date)
    }
}
