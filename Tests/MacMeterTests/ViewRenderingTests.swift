import ServiceManagement
import SwiftUI
import XCTest
@testable import MacMeter

@MainActor
final class ViewRenderingTests: XCTestCase {
    func testAppCompositionCanBeConstructed() {
        let delegate = MacMeterApplicationDelegate()
        XCTAssertFalse(delegate.isRunning)
        delegate.start()
        XCTAssertTrue(delegate.isRunning)
        delegate.stop()
        XCTAssertFalse(delegate.isRunning)
    }

    func testVersionLabelIncludesVersionAndBuild() {
        let version = AppVersionInfo(version: "0.1.0", build: "1")
        XCTAssertEqual(version.displayLabel, "Version 0.1.0 (1)")
    }

    func testSettingsWindowControllerReusesOneNativeTreeAcrossRepeatedCloseAndShow() throws {
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
        let firstHost = try XCTUnwrap(firstWindow.contentViewController)
        XCTAssertTrue(firstHost is NativeSettingsViewController)
        XCTAssertTrue(firstWindow.isVisible)
        XCTAssertEqual(firstWindow.title, "MacMeter Settings")
        XCTAssertEqual(firstWindow.identifier?.rawValue, "MacMeter.Settings")
        XCTAssertEqual(activationCount, 1)

        controller.show()
        XCTAssertTrue(firstWindow === controller.window)
        XCTAssertEqual(activationCount, 2)

        firstWindow.performClose(nil)
        XCTAssertFalse(firstWindow.isVisible)
        XCTAssertTrue(firstWindow === controller.window)
        controller.show()
        XCTAssertTrue(firstWindow.isVisible)
        XCTAssertTrue(firstWindow === controller.window)
        XCTAssertTrue(firstHost === controller.window?.contentViewController)
        XCTAssertEqual(activationCount, 3)

        for _ in 0..<25 {
            controller.close()
            XCTAssertFalse(firstWindow.isVisible)
            controller.show()
            XCTAssertTrue(firstWindow.isVisible)
            XCTAssertTrue(firstWindow === controller.window)
            XCTAssertTrue(firstHost === controller.window?.contentViewController)
        }
    }

    func testNativeSettingsControlsImmediatelyPersistEveryDisplayPreference() throws {
        let suite = "MacMeterNativeSettingsControls.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let loginService = NativeSettingsLoginItemService()
        let loginManager = LoginItemManager(service: loginService)
        let controller = NativeSettingsViewController(settings: settings, loginItem: loginManager)
        _ = controller.view
        XCTAssertEqual(controller.tabViewItems.map(\.label), ["Metrics", "Appearance", "General", "About"])

        let metricsView = try XCTUnwrap(controller.tabViewItems[0].viewController?.view)
        let metricToggles: [(String, @MainActor () -> Bool)] = [
            ("settings.cpu.enabled", { settings.cpuEnabled }),
            ("settings.temperature.enabled", { settings.temperatureEnabled }),
            ("settings.network.enabled", { settings.networkEnabled }),
            ("settings.battery.enabled", { settings.batteryEnabled })
        ]
        for (identifier, value) in metricToggles {
            let toggle: NSButton = try control(in: metricsView, identifier: identifier)
            XCTAssertTrue(value())
            toggle.performClick(nil)
            XCTAssertFalse(value())
        }

        let cpuScale: NSPopUpButton = try control(in: metricsView, identifier: "settings.cpu.scale")
        for (index, expected) in CPUScale.allCases.enumerated() {
            cpuScale.selectItem(at: index)
            sendAction(cpuScale)
            XCTAssertEqual(settings.cpuScale, expected)
        }

        let temperature: NSSegmentedControl = try control(in: metricsView, identifier: "settings.temperature.unit")
        for (index, expected) in TemperatureUnit.allCases.enumerated() {
            temperature.selectedSegment = index
            sendAction(temperature)
            XCTAssertEqual(settings.temperatureUnit, expected)
        }

        let network: NSSegmentedControl = try control(in: metricsView, identifier: "settings.network.unit")
        for (index, expected) in NetworkUnit.allCases.enumerated() {
            network.selectedSegment = index
            sendAction(network)
            XCTAssertEqual(settings.networkUnit, expected)
        }

        let appearanceView = try XCTUnwrap(controller.tabViewItems[1].viewController?.view)
        let appearance: NSSegmentedControl = try control(in: appearanceView, identifier: "settings.display.mode")
        for (index, expected) in DisplayMode.allCases.enumerated() {
            appearance.selectedSegment = index
            sendAction(appearance)
            XCTAssertEqual(settings.displayMode, expected)
        }

        let generalView = try XCTUnwrap(controller.tabViewItems[2].viewController?.view)
        let updateRate: NSPopUpButton = try control(in: generalView, identifier: "settings.update.rate")
        for (index, expected) in [1.0, 2.0, 5.0, 10.0].enumerated() {
            updateRate.selectItem(at: index)
            sendAction(updateRate)
            XCTAssertEqual(settings.updateInterval, expected)
        }

        let launchAtLogin: NSButton = try control(in: generalView, identifier: "settings.launch.at.login")
        launchAtLogin.performClick(nil)
        XCTAssertEqual(loginService.registerCount, 1)
        XCTAssertTrue(loginManager.isEnabled)
        launchAtLogin.performClick(nil)
        XCTAssertEqual(loginService.unregisterCount, 1)
        XCTAssertFalse(loginManager.isEnabled)

        let restored = SettingsStore(defaults: defaults)
        XCTAssertFalse(restored.cpuEnabled)
        XCTAssertFalse(restored.temperatureEnabled)
        XCTAssertFalse(restored.networkEnabled)
        XCTAssertFalse(restored.batteryEnabled)
        XCTAssertEqual(restored.cpuScale, .summed)
        XCTAssertEqual(restored.temperatureUnit, .fahrenheit)
        XCTAssertEqual(restored.networkUnit, .MBps)
        XCTAssertEqual(restored.displayMode, .cycle)
        XCTAssertEqual(restored.updateInterval, 10)
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

    func testPersistentCompactLabelResistsCompressionForEveryMetricSelection() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.settings.displayMode = .compact
        setMetricMask(1, settings: fixture.settings)

        let hostingController = NSHostingController(rootView: MenuBarLabelView(
            coordinator: fixture.coordinator,
            settings: fixture.settings
        ))
        let host = hostingController.view
        host.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        host.layoutSubtreeIfNeeded()
        for mask in 1..<16 {
            setMetricMask(mask, settings: fixture.settings)
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            let ideal = hostingController.sizeThatFits(in: CGSize(width: 1_000, height: 40))
            let constrained = hostingController.sizeThatFits(in: CGSize(width: 1, height: 40))

            XCTAssertEqual(constrained.width, ideal.width, accuracy: 1, "Selection mask \(mask) compressed horizontally")
            XCTAssertLessThanOrEqual(ideal.width, 180, "Selection mask \(mask) is too wide for compact display")
            XCTAssertLessThanOrEqual(ideal.height, 24, "Selection mask \(mask) is too tall for the menu bar")
        }
    }

    func testCompactPresentationContainsEverySelectedMetricExactlyOnce() {
        for mask in 1..<16 {
            let enabled = MetricID.allCases.enumerated().compactMap { index, metric in
                mask & (1 << index) != 0 ? metric : nil
            }
            let rows = MenuBarPresentation.rows(for: enabled)
            let flattened = rows.flatMap { $0 }
            XCTAssertEqual(flattened.count, enabled.count, "Selection mask \(mask) duplicated or omitted a metric")
            XCTAssertEqual(Set(flattened), Set(enabled), "Selection mask \(mask) changed selected metrics")
            if mask != 15 {
                XCTAssertEqual(flattened, enabled, "Selection mask \(mask) changed metric order")
            }
        }

        XCTAssertEqual(
            MenuBarPresentation.rows(for: MetricID.allCases),
            [[.network], [.cpu, .temperature, .battery]]
        )
    }

    func testFourMetricPresentationUsesExactRequestedVisibleStrings() {
        let cpu = CPUReading(normalized: 50, summed: 100, cores: [])
        let temperature = TemperatureReading(hottestCelsius: 80, sensorCount: 1)
        let network = NetworkReading(
            inboundBytesPerSecond: 500_000,
            outboundBytesPerSecond: 0,
            interfaces: ["en0"]
        )
        let battery = BatteryPowerReading(watts: 12, direction: .draining)

        XCTAssertEqual(MenuBarPresentation.network(network, unit: .MBps), "↑0.0↓0.5MB/s")
        XCTAssertEqual(
            [
                MenuBarPresentation.network(network, unit: .MBps),
                MenuBarPresentation.cpu(cpu, scale: .normalized),
                MenuBarPresentation.temperature(temperature, unit: .celsius),
                MenuBarPresentation.battery(battery)
            ].joined(separator: " | "),
            "↑0.0↓0.5MB/s | 50% | 80°C | D 12W"
        )
        XCTAssertEqual(MenuBarPresentation.temperature(temperature, unit: .fahrenheit), "176°F")
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

        let constrainedBudgets: [(DisplayMode, CGFloat)] = [(.compact, 180)]
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

    func testBatteryDirectionsRenderRedGreenAndBlue() throws {
        let cases: [(BatteryPowerReading, DominantColor)] = [
            (BatteryPowerReading(watts: 8.4, direction: .draining), .red),
            (BatteryPowerReading(watts: 30, direction: .charging), .green),
            (BatteryPowerReading(watts: 0, direction: .idle), .blue)
        ]

        for (reading, expectedColor) in cases {
            let suite = "MacMeterBatteryColorTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = SettingsStore(defaults: defaults)
            setMetricMask(8, settings: settings)
            let coordinator = MetricsCoordinator(
                settings: settings,
                cpuProvider: FakeCPUProvider(),
                temperatureProvider: FakeTemperatureProvider(),
                networkProvider: FakeNetworkProvider(),
                batteryProvider: StaticBatteryProvider(reading: reading),
                startAutomatically: false
            )
            coordinator.sampleNow()
            let image = try XCTUnwrap(render(
                MenuBarLabelView(coordinator: coordinator, settings: settings)
                    .environment(\.colorScheme, .light)
            ))
            XCTAssertTrue(
                containsDominantColor(expectedColor, in: image),
                "Battery \(reading.direction.rawValue) did not render \(expectedColor)"
            )
        }
    }

    func testNativeStatusLabelUsesSmallFontAndEverySelectedMetric() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        setMetricMask(15, settings: fixture.settings)

        let label = StatusItemLabelBuilder.make(
            coordinator: fixture.coordinator,
            settings: fixture.settings,
            cycleIndex: 0
        )
        XCTAssertEqual(label.string, "↑0.4↓3.2MB/s\n50% | 55°C | D 8.4W")
        label.enumerateAttribute(.font, in: NSRange(location: 0, length: label.length)) { value, _, _ in
            XCTAssertEqual((value as? NSFont)?.pointSize, StatusItemLabelBuilder.fontSize)
        }
        let batteryRange = (label.string as NSString).range(of: "D 8.4W")
        XCTAssertEqual(
            label.attribute(.foregroundColor, at: batteryRange.location, effectiveRange: nil) as? NSColor,
            .systemRed
        )
    }

    func testNativeStatusLabelBatteryColorsAreRedGreenAndBlue() throws {
        let cases: [(BatteryPowerReading, NSColor)] = [
            (BatteryPowerReading(watts: 8.4, direction: .draining), .systemRed),
            (BatteryPowerReading(watts: 30, direction: .charging), .systemGreen),
            (BatteryPowerReading(watts: 0, direction: .idle), .systemBlue)
        ]

        for (reading, expectedColor) in cases {
            let suite = "MacMeterNativeBatteryColorTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = SettingsStore(defaults: defaults)
            setMetricMask(8, settings: settings)
            let coordinator = MetricsCoordinator(
                settings: settings,
                cpuProvider: FakeCPUProvider(),
                temperatureProvider: FakeTemperatureProvider(),
                networkProvider: FakeNetworkProvider(),
                batteryProvider: StaticBatteryProvider(reading: reading),
                startAutomatically: false
            )
            coordinator.sampleNow()
            let label = StatusItemLabelBuilder.make(
                coordinator: coordinator,
                settings: settings,
                cycleIndex: 0
            )
            XCTAssertEqual(label.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, expectedColor)
        }
    }

    func testNativeStatusControllerUsesAttributedButtonTitleWithoutCustomSubviews() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        setMetricMask(15, settings: fixture.settings)
        let settingsWindowController = SettingsWindowController(
            settings: fixture.settings,
            loginItem: LoginItemManager()
        )
        let controller = StatusItemController(
            coordinator: fixture.coordinator,
            settings: fixture.settings,
            settingsWindowController: settingsWindowController
        )
        defer { controller.close() }

        XCTAssertEqual(controller.renderedTitle.string, "↑0.4↓3.2MB/s\n50% | 55°C | D 8.4W")
        XCTAssertEqual(controller.statusButtonSubviewCount, 0, "Custom status-button subviews trigger continuous AppKit replicant snapshots")
        let bounds = controller.renderedTitle.boundingRect(
            with: NSSize(width: 1_000, height: NSStatusBar.system.thickness),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        XCTAssertGreaterThanOrEqual(controller.renderedLength, ceil(bounds.width) + 8)
    }

    func testStatusButtonOpensLazyPopoverAndSettingsActionClosesIt() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let settingsWindowController = SettingsWindowController(
            settings: fixture.settings,
            loginItem: LoginItemManager(),
            activateApplication: {}
        )
        var presentedHostIdentities: [ObjectIdentifier] = []
        var dismissCount = 0
        let controller = StatusItemController(
            coordinator: fixture.coordinator,
            settings: fixture.settings,
            settingsWindowController: settingsWindowController,
            presentPopover: { popover, button in
                XCTAssertNotNil(popover.contentViewController)
                XCTAssertNotNil(button.window)
                presentedHostIdentities.append(ObjectIdentifier(popover.contentViewController!))
            },
            dismissPopover: { _ in
                dismissCount += 1
            }
        )
        defer {
            controller.close()
            settingsWindowController.close()
        }

        XCTAssertFalse(controller.isPopoverPrepared)
        controller.statusButton?.performClick(nil)
        XCTAssertTrue(controller.isPopoverPrepared)
        let releasedPopoverHost = WeakReference(controller.popoverContentViewController)
        XCTAssertNotNil(releasedPopoverHost.value)
        XCTAssertEqual(presentedHostIdentities.count, 1)
        XCTAssertEqual(dismissCount, 0)

        controller.openSettings()
        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(settingsWindowController.window?.identifier?.rawValue, "MacMeter.Settings")
        XCTAssertTrue(settingsWindowController.window?.isVisible == true)

        controller.popoverDidClose(Notification(name: NSPopover.didCloseNotification))
        XCTAssertFalse(controller.isPopoverPrepared)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertNil(releasedPopoverHost.value)

        controller.statusButton?.performClick(nil)
        XCTAssertTrue(controller.isPopoverPrepared)
        let releasedSecondPopoverHost = WeakReference(controller.popoverContentViewController)
        XCTAssertEqual(presentedHostIdentities.count, 2)
        XCTAssertNotEqual(presentedHostIdentities[0], presentedHostIdentities[1])

        controller.popoverDidClose(Notification(name: NSPopover.didCloseNotification))
        XCTAssertFalse(controller.isPopoverPrepared)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertNil(releasedSecondPopoverHost.value)
    }

    private func render<V: View>(_ view: V) -> NSImage? {
        let renderer = ImageRenderer(content: view.padding(8).frame(minWidth: 120, minHeight: 32))
        renderer.scale = 2
        return renderer.nsImage
    }

    private enum DominantColor: CustomStringConvertible {
        case red
        case green
        case blue

        var description: String {
            switch self {
            case .red: return "red"
            case .green: return "green"
            case .blue: return "blue"
            }
        }
    }

    private func containsDominantColor(_ expected: DominantColor, in image: NSImage) -> Bool {
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data) else { return false }
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.1 else { continue }
                let red = color.redComponent
                let green = color.greenComponent
                let blue = color.blueComponent
                switch expected {
                case .red where red > 0.35 && red > green * 1.25 && red > blue * 1.25: return true
                case .green where green > 0.35 && green > red * 1.25 && green > blue * 1.25: return true
                case .blue where blue > 0.35 && blue > red * 1.25 && blue > green * 1.25: return true
                default: continue
                }
            }
        }
        return false
    }

    private func setMetricMask(_ mask: Int, settings: SettingsStore) {
        settings.cpuEnabled = mask & 1 != 0
        settings.temperatureEnabled = mask & 2 != 0
        settings.networkEnabled = mask & 4 != 0
        settings.batteryEnabled = mask & 8 != 0
    }

    private func control<Control: NSView>(
        in root: NSView,
        identifier: String
    ) throws -> Control {
        if let root = root as? Control, root.identifier?.rawValue == identifier {
            return root
        }
        for subview in root.subviews {
            if let match: Control = try? control(in: subview, identifier: identifier) {
                return match
            }
        }
        throw NSError(
            domain: "MacMeterTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing control \(identifier)"]
        )
    }

    private func sendAction(_ control: NSControl) {
        guard let action = control.action else {
            XCTFail("Control \(control.identifier?.rawValue ?? "unknown") has no action")
            return
        }
        XCTAssertTrue(NSApp.sendAction(action, to: control.target, from: control))
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

private final class WeakReference<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

@MainActor
private final class NativeSettingsLoginItemService: LoginItemServicing {
    var status: SMAppService.Status = .notRegistered
    var registerCount = 0
    var unregisterCount = 0

    func register() throws {
        registerCount += 1
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        status = .notRegistered
    }

    func openSystemSettings() {}
}

@MainActor
private final class UnavailableTemperatureProvider: TemperatureProviding {
    func sample(at date: Date) -> MetricAvailability<TemperatureReading> { .unavailable("Temperature unavailable") }
}

@MainActor
private final class UnavailableBatteryProvider: BatteryProviding {
    func sample(at date: Date) -> MetricAvailability<BatteryPowerReading> { .unavailable("Battery unavailable") }
}

@MainActor
private final class StaticBatteryProvider: BatteryProviding {
    let reading: BatteryPowerReading

    init(reading: BatteryPowerReading) {
        self.reading = reading
    }

    func sample(at date: Date) -> MetricAvailability<BatteryPowerReading> {
        .available(reading, sampledAt: date)
    }
}
