import SwiftUI
import XCTest
@testable import MacMeter

@MainActor
final class ViewRenderingTests: XCTestCase {
    func testAppCompositionCanBeConstructed() {
        let app = MacMeterApp()
        _ = app.body
    }

    func testVersionLabelIncludesVersionAndBuild() {
        let version = AppVersionInfo(version: "0.1.0", build: "1")
        XCTAssertEqual(version.displayLabel, "Version 0.1.0 (1)")
    }

    func testSettingsWindowControllerShowsAndReusesNativeWindow() throws {
        _ = NSApplication.shared
        let suite = "MacMeterSettingsWindowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let loginItem = LoginItemManager()
        var activationCount = 0
        let controller = SettingsWindowController(
            settings: settings,
            loginItem: loginItem,
            activateApplication: { activationCount += 1 }
        )
        defer { controller.close() }

        controller.show()
        let firstWindow = try XCTUnwrap(controller.window)
        XCTAssertTrue(firstWindow.isVisible)
        XCTAssertEqual(firstWindow.title, "MacMeter Settings")
        XCTAssertEqual(firstWindow.identifier?.rawValue, "MacMeter.Settings")
        XCTAssertEqual(activationCount, 1)

        controller.show()
        XCTAssertTrue(firstWindow === controller.window)
        XCTAssertEqual(activationCount, 2)

        firstWindow.performClose(nil)
        XCTAssertFalse(firstWindow.isVisible)
        controller.show()
        XCTAssertTrue(firstWindow.isVisible)
        XCTAssertTrue(firstWindow === controller.window)
        XCTAssertEqual(activationCount, 3)

        controller.close()
        XCTAssertFalse(firstWindow.isVisible)
    }

    func testMenuBarModesAndMetricCombinationsRender() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        for mode in DisplayMode.allCases {
            for mask in 0..<16 {
                fixture.settings.displayMode = mode
                setMetricMask(mask, settings: fixture.settings)
                let image = try XCTUnwrap(render(MenuBarLabelView(coordinator: fixture.coordinator, settings: fixture.settings)))
                XCTAssertGreaterThan(image.size.width, 0)
                XCTAssertGreaterThan(image.size.height, 0)
            }
        }
    }

    func testMenuBarAppearanceTextSizeAndConstrainedCycleMatrixRenders() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let appearances: [ColorScheme] = [.light, .dark]
        let textSizes: [DynamicTypeSize] = [.small, .large, .accessibility3]

        for mode in DisplayMode.allCases {
            for mask in 0..<16 {
                for appearance in appearances {
                    for textSize in textSizes {
                        fixture.settings.displayMode = mode
                        setMetricMask(mask, settings: fixture.settings)
                        let view = MenuBarLabelView(coordinator: fixture.coordinator, settings: fixture.settings)
                            .environment(\.colorScheme, appearance)
                            .environment(\.dynamicTypeSize, textSize)
                        let image = try XCTUnwrap(render(view))
                        XCTAssertGreaterThan(image.size.width, 0)
                        XCTAssertLessThanOrEqual(image.size.height, 64)
                    }
                }
            }
        }

        fixture.settings.displayMode = .cycle
        setMetricMask(15, settings: fixture.settings)
        for metricIndex in 0..<4 {
            let controller = CycleController(clock: StepSamplingClock(steps: 0), initialIndex: metricIndex)
            let intrinsic = MenuBarLabelView(
                coordinator: fixture.coordinator,
                settings: fixture.settings,
                cycleController: controller
            )
            let intrinsicImage = try XCTUnwrap(render(intrinsic))
            XCTAssertLessThanOrEqual(intrinsicImage.size.width, 136, "Cycle page \(metricIndex) exceeds constrained width")
            XCTAssertLessThanOrEqual(intrinsicImage.size.height, 40)
        }

        let constrainedBudgets: [(DisplayMode, CGFloat)] = [(.compact, 300), (.default, 480)]
        for (mode, widthBudget) in constrainedBudgets {
            fixture.settings.displayMode = mode
            setMetricMask(15, settings: fixture.settings)
            for textSize in textSizes {
                let constrained = MenuBarLabelView(coordinator: fixture.coordinator, settings: fixture.settings)
                    .environment(\.dynamicTypeSize, textSize)
                let image = try XCTUnwrap(render(constrained))
                XCTAssertLessThanOrEqual(
                    image.size.width,
                    widthBudget,
                    "\(mode.title) at \(textSize) exceeds its constrained menu-bar budget"
                )
                XCTAssertLessThanOrEqual(image.size.height, 40)
            }
        }
    }

    func testPopoverAndSettingsRenderWithLiveFixtureValues() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }

        for appearance in [ColorScheme.light, .dark] {
            for textSize in [DynamicTypeSize.small, .large, .accessibility3] {
                XCTAssertNotNil(render(
                    MeterPopoverView(
                        coordinator: fixture.coordinator,
                        settings: fixture.settings,
                        appVersion: AppVersionInfo(version: "0.1.0", build: "1")
                    )
                        .environment(\.colorScheme, appearance)
                        .environment(\.dynamicTypeSize, textSize)
                ))
                XCTAssertNotNil(render(
                    MacMeterSettingsView(settings: fixture.settings, loginItem: LoginItemManager())
                        .environment(\.colorScheme, appearance)
                        .environment(\.dynamicTypeSize, textSize)
                ))
            }
        }
    }

    func testUnavailableStatesRender() {
        let suite = "MacMeterViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let coordinator = MetricsCoordinator(
            settings: settings,
            cpuProvider: FakeCPUProvider(result: .unavailable("CPU unavailable")),
            temperatureProvider: UnavailableTemperatureProvider(),
            networkProvider: FakeNetworkProvider(result: .unavailable("Network unavailable")),
            batteryProvider: UnavailableBatteryProvider(),
            startAutomatically: false
        )
        coordinator.sampleNow()
        XCTAssertNotNil(render(MenuBarLabelView(coordinator: coordinator, settings: settings)))
        XCTAssertNotNil(render(MeterPopoverView(coordinator: coordinator, settings: settings)))
    }

    private func render<V: View>(_ view: V) -> NSImage? {
        let renderer = ImageRenderer(content: view.padding(8).frame(minWidth: 120, minHeight: 32))
        renderer.scale = 2
        return renderer.nsImage
    }

    private func setMetricMask(_ mask: Int, settings: SettingsStore) {
        settings.cpuEnabled = mask & 1 != 0
        settings.temperatureEnabled = mask & 2 != 0
        settings.networkEnabled = mask & 4 != 0
        settings.batteryEnabled = mask & 8 != 0
    }

    private func makeFixture() -> (settings: SettingsStore, coordinator: MetricsCoordinator, cleanup: () -> Void) {
        let suite = "MacMeterViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults)
        let cores = [
            CoreReading(id: 0, utilization: 20, kind: .efficiency),
            CoreReading(id: 1, utilization: 80, kind: .performance)
        ]
        let coordinator = MetricsCoordinator(
            settings: settings,
            cpuProvider: FakeCPUProvider(result: .available(CPUReading(normalized: 50, summed: 100, cores: cores), sampledAt: .distantPast)),
            temperatureProvider: FakeTemperatureProvider(),
            networkProvider: FakeNetworkProvider(result: .available(NetworkReading(inboundBytesPerSecond: 3_200_000, outboundBytesPerSecond: 400_000, interfaces: ["en0"]), sampledAt: .distantPast)),
            batteryProvider: FakeBatteryProvider(),
            startAutomatically: false
        )
        coordinator.sampleNow(at: Date(timeIntervalSince1970: 1_000))
        return (settings, coordinator, { defaults.removePersistentDomain(forName: suite) })
    }
}

@MainActor
private final class UnavailableTemperatureProvider: TemperatureProviding {
    func sample(at date: Date) -> MetricAvailability<TemperatureReading> { .unavailable("Temperature unavailable") }
}

@MainActor
private final class UnavailableBatteryProvider: BatteryProviding {
    func sample(at date: Date) -> MetricAvailability<BatteryPowerReading> { .unavailable("Battery unavailable") }
}
