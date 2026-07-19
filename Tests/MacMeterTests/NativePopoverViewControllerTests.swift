import AppKit
import XCTest
@testable import MacMeter

@MainActor
final class NativePopoverViewControllerTests: XCTestCase {
    func testFullFixtureRendersValuesVersionTimestampAndCoreAccessibility() throws {
        let sampledAt = Date(timeIntervalSince1970: 1_721_234_567)
        let fixture = makeFixture(sampledAt: sampledAt)
        defer { fixture.cleanup() }

        let controller = NativePopoverViewController(
            coordinator: fixture.coordinator,
            settings: fixture.settings,
            appVersion: AppVersionInfo(version: "0.1.5", build: "27")
        )
        let root = controller.view

        XCTAssertEqual(root.identifier?.rawValue, NativePopoverViewController.Identifier.root)
        XCTAssertEqual(try label(in: root, identifier: NativePopoverViewController.Identifier.title).stringValue, "MacMeter")
        XCTAssertEqual(
            try label(in: root, identifier: NativePopoverViewController.Identifier.version).stringValue,
            "Version 0.1.5 (27)"
        )
        XCTAssertEqual(try value(in: root, metric: .cpu, name: "Overall"), "43%")
        XCTAssertEqual(try value(in: root, metric: .cpu, name: "Summed"), "170%")
        XCTAssertEqual(try value(in: root, metric: .temperature, name: "Hottest"), "55°C")
        XCTAssertEqual(try value(in: root, metric: .temperature, name: "Sensors"), "3")
        XCTAssertEqual(try value(in: root, metric: .network, name: "Inbound"), "3.2 MBps")
        XCTAssertEqual(try value(in: root, metric: .network, name: "Outbound"), "0.4 MBps")
        XCTAssertEqual(try value(in: root, metric: .network, name: "Interfaces"), "en0, en1")
        XCTAssertEqual(try value(in: root, metric: .battery, name: "Power"), "D 8.4W")
        XCTAssertEqual(
            try label(
                in: root,
                identifier: NativePopoverViewController.Identifier.value(.cpu, "Overall")
            ).textColor,
            MetricStatusPalette.cpu(normalizedPercent: 43)
        )
        XCTAssertEqual(
            try label(
                in: root,
                identifier: NativePopoverViewController.Identifier.value(.temperature, "Hottest")
            ).textColor,
            MetricStatusPalette.temperature(celsius: 55)
        )

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        let expectedTime = formatter.string(from: sampledAt)
        let updated = try label(in: root, identifier: NativePopoverViewController.Identifier.updated)
        XCTAssertEqual(updated.stringValue, "Updated \(expectedTime)")
        XCTAssertEqual(updated.accessibilityLabel(), "Last updated \(expectedTime)")

        let expectedCores: [(Int, String, String, String)] = [
            (0, "E", "12%", "Core 0, Efficiency, 12%"),
            (1, "P", "88%", "Core 1, Performance, 88%"),
            (2, "?", "50%", "Core 2, Unknown, 50%")
        ]
        for (id, kind, utilization, accessibility) in expectedCores {
            let row = try XCTUnwrap(controller.coreRowView(for: id))
            XCTAssertEqual(row.identifier?.rawValue, NativePopoverViewController.Identifier.coreRow(id))
            XCTAssertEqual(row.kindLabel.stringValue, kind)
            XCTAssertEqual(row.valueLabel.stringValue, utilization)
            let utilizationValue = try XCTUnwrap(Double(utilization.dropLast()))
            let actualColor = try XCTUnwrap(row.valueLabel.textColor?.usingColorSpace(.sRGB))
            let expectedColor = try XCTUnwrap(
                MetricStatusPalette.cpu(normalizedPercent: utilizationValue).usingColorSpace(.sRGB)
            )
            XCTAssertEqual(actualColor.redComponent, expectedColor.redComponent, accuracy: 0.01)
            XCTAssertEqual(actualColor.greenComponent, expectedColor.greenComponent, accuracy: 0.01)
            XCTAssertEqual(actualColor.blueComponent, expectedColor.blueComponent, accuracy: 0.01)
            XCTAssertEqual(row.accessibilityLabel(), accessibility)
        }
        XCTAssertEqual(controller.coreRowView(for: 0)?.kindLabel.accessibilityLabel(), "Efficiency")
        XCTAssertEqual(controller.coreRowView(for: 1)?.kindLabel.accessibilityLabel(), "Performance")
        XCTAssertEqual(controller.coreRowView(for: 2)?.kindLabel.accessibilityLabel(), "Unknown")
    }

    func testTemperatureRendersCelsiusAndFahrenheit() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let controller = makeController(fixture)
        let root = controller.view

        fixture.settings.temperatureUnit = .celsius
        controller.refreshFromModel()
        XCTAssertEqual(try value(in: root, metric: .temperature, name: "Hottest"), "55°C")

        fixture.settings.temperatureUnit = .fahrenheit
        controller.refreshFromModel()
        XCTAssertEqual(try value(in: root, metric: .temperature, name: "Hottest"), "131°F")
        XCTAssertEqual(try value(in: root, metric: .temperature, name: "Sensors"), "3")
    }

    func testNetworkRendersAllFourUnits() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let controller = makeController(fixture)
        let root = controller.view
        let expected: [(NetworkUnit, String, String)] = [
            (.Kbps, "25600 Kbps", "3200 Kbps"),
            (.KBps, "3200 KBps", "400 KBps"),
            (.Mbps, "25.6 Mbps", "3.2 Mbps"),
            (.MBps, "3.2 MBps", "0.4 MBps")
        ]

        for (unit, inbound, outbound) in expected {
            fixture.settings.networkUnit = unit
            controller.refreshFromModel()
            XCTAssertEqual(try value(in: root, metric: .network, name: "Inbound"), inbound)
            XCTAssertEqual(try value(in: root, metric: .network, name: "Outbound"), outbound)
            XCTAssertEqual(try value(in: root, metric: .network, name: "Interfaces"), "en0, en1")
        }
    }

    func testBatteryChargingDrainingAndIdleRenderColorAndAccessibility() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let controller = makeController(fixture)
        let root = controller.view
        let cases: [(BatteryPowerReading, String, NSColor, String)] = [
            (BatteryPowerReading(watts: 30, direction: .charging), "C 30W", .systemGreen, "Battery Charging, 30 watts"),
            (BatteryPowerReading(watts: 8.4, direction: .draining), "D 8.4W", .systemRed, "Battery Draining, 8.4 watts"),
            (BatteryPowerReading(watts: 0, direction: .idle), "— 0W", .systemBlue, "Battery Idle, 0 watts")
        ]

        for (reading, expectedValue, expectedColor, expectedAccessibility) in cases {
            fixture.battery.result = .available(reading, sampledAt: fixture.sampledAt)
            fixture.coordinator.sampleNow(at: fixture.sampledAt)
            controller.refreshFromModel()

            let valueLabel = try label(
                in: root,
                identifier: NativePopoverViewController.Identifier.value(.battery, "Power")
            )
            let row = try XCTUnwrap(valueLabel.superview as? NativePopoverValueRowView)
            XCTAssertEqual(row.title, reading.direction.spokenLabel)
            XCTAssertEqual(valueLabel.stringValue, expectedValue)
            XCTAssertEqual(valueLabel.textColor, expectedColor)
            XCTAssertEqual(row.accessibilityLabel(), expectedAccessibility)
        }
    }

    func testEveryMetricEnableMaskControlsExactlyItsFourSections() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let controller = makeController(fixture)
        _ = controller.view

        for mask in 0..<16 {
            setMetricMask(mask, settings: fixture.settings)
            controller.refreshFromModel()

            for (index, metric) in MetricID.allCases.enumerated() {
                let section = try XCTUnwrap(controller.sectionView(for: metric))
                let shouldBeEnabled = mask & (1 << index) != 0
                XCTAssertEqual(
                    section.isHidden,
                    !shouldBeEnabled,
                    "Metric \(metric.rawValue) had the wrong visibility for mask \(mask)"
                )
            }
        }
    }

    func testUnavailableReasonsReplaceAvailableContentForEveryMetric() throws {
        let sampledAt = Date(timeIntervalSince1970: 1_700_000_000)
        let suite = "NativePopoverUnavailable.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let coordinator = MetricsCoordinator(
            settings: settings,
            cpuProvider: PopoverFixtureCPUProvider(result: .unavailable("CPU fixture unavailable", observedAt: sampledAt)),
            temperatureProvider: PopoverFixtureTemperatureProvider(result: .unavailable("Temperature fixture unavailable", observedAt: sampledAt)),
            networkProvider: PopoverFixtureNetworkProvider(result: .unavailable("Network fixture unavailable", observedAt: sampledAt)),
            batteryProvider: PopoverFixtureBatteryProvider(result: .unavailable("Battery fixture unavailable", observedAt: sampledAt)),
            startAutomatically: false
        )
        coordinator.sampleNow(at: sampledAt)
        let controller = NativePopoverViewController(coordinator: coordinator, settings: settings)
        _ = controller.view
        let reasons: [MetricID: String] = [
            .cpu: "CPU fixture unavailable",
            .temperature: "Temperature fixture unavailable",
            .network: "Network fixture unavailable",
            .battery: "Battery fixture unavailable"
        ]

        for metric in MetricID.allCases {
            let section = try XCTUnwrap(controller.sectionViews[metric])
            let reason = try XCTUnwrap(reasons[metric])
            XCTAssertTrue(section.availableView?.isHidden == true)
            XCTAssertFalse(section.unavailableLabel.isHidden)
            XCTAssertEqual(section.unavailableLabel.stringValue, reason)
            XCTAssertEqual(section.unavailableLabel.accessibilityLabel(), reason)
        }
    }

    func testSettingsAndQuitButtonsInvokeInjectedActions() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        var settingsCount = 0
        var quitCount = 0
        let controller = NativePopoverViewController(
            coordinator: fixture.coordinator,
            settings: fixture.settings,
            openSettings: { settingsCount += 1 },
            quit: { quitCount += 1 }
        )
        let root = controller.view
        let settingsButton: NSButton = try control(
            in: root,
            identifier: NativePopoverViewController.Identifier.settingsButton
        )
        let quitButton: NSButton = try control(
            in: root,
            identifier: NativePopoverViewController.Identifier.quitButton
        )

        XCTAssertEqual(settingsButton.accessibilityLabel(), "Open MacMeter Settings")
        XCTAssertEqual(quitButton.accessibilityLabel(), "Quit MacMeter")
        XCTAssertNotNil(settingsButton.target)
        XCTAssertNotNil(settingsButton.action)
        XCTAssertNotNil(quitButton.target)
        XCTAssertNotNil(quitButton.action)

        settingsButton.performClick(nil)
        quitButton.performClick(nil)
        XCTAssertEqual(settingsCount, 1)
        XCTAssertEqual(quitCount, 1)
    }

    func testRepeatedRefreshesPreserveRootSectionAndCoreRowIdentity() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let controller = makeController(fixture)
        let root = controller.view
        let rootIdentity = ObjectIdentifier(root)
        let sectionIdentities = Dictionary(uniqueKeysWithValues: try MetricID.allCases.map { metric in
            (metric, ObjectIdentifier(try XCTUnwrap(controller.sectionViews[metric])))
        })
        let coreIdentities = Dictionary(uniqueKeysWithValues: try [0, 1, 2].map { id in
            (id, ObjectIdentifier(try XCTUnwrap(controller.coreRowViews[id])))
        })
        let initialRefreshCount = controller.refreshCount

        for iteration in 1...30 {
            let orderedCores = [
                CoreReading(id: 0, utilization: Double(iteration), kind: .efficiency),
                CoreReading(id: 1, utilization: Double(iteration + 10), kind: .performance),
                CoreReading(id: 2, utilization: Double(iteration + 20), kind: .unknown)
            ]
            fixture.cpu.result = .available(
                CPUReading(
                    normalized: Double(iteration),
                    summed: Double(iteration * 3),
                    cores: iteration.isMultiple(of: 2) ? orderedCores.reversed() : orderedCores
                ),
                sampledAt: fixture.sampledAt
            )
            fixture.coordinator.sampleNow(at: fixture.sampledAt.addingTimeInterval(Double(iteration)))
            controller.refreshFromModel()

            XCTAssertEqual(ObjectIdentifier(controller.view), rootIdentity)
            for metric in MetricID.allCases {
                XCTAssertEqual(
                    ObjectIdentifier(try XCTUnwrap(controller.sectionViews[metric])),
                    sectionIdentities[metric]
                )
            }
            for id in [0, 1, 2] {
                XCTAssertEqual(
                    ObjectIdentifier(try XCTUnwrap(controller.coreRowViews[id])),
                    coreIdentities[id]
                )
            }
        }

        XCTAssertGreaterThanOrEqual(controller.refreshCount, initialRefreshCount + 30)
        XCTAssertEqual(controller.coreRowViews[0]?.valueLabel.stringValue, "30%")
        XCTAssertEqual(controller.coreRowViews[1]?.valueLabel.stringValue, "40%")
        XCTAssertEqual(controller.coreRowViews[2]?.valueLabel.stringValue, "50%")
    }

    func testConstrainedContentUsesScrollableMetricHierarchyAt390By520() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let controller = makeController(fixture)
        let root = controller.view
        root.frame = NSRect(origin: .zero, size: NativePopoverViewController.contentSize)
        root.layoutSubtreeIfNeeded()

        let scrollView: NSScrollView = try control(
            in: root,
            identifier: NativePopoverViewController.Identifier.scrollView
        )
        let metricsStack: NSStackView = try control(
            in: root,
            identifier: NativePopoverViewController.Identifier.metricsStack
        )

        XCTAssertEqual(controller.preferredContentSize, NSSize(width: 390, height: 520))
        XCTAssertEqual(root.frame.size, NSSize(width: 390, height: 520))
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertTrue(scrollView.isDescendant(of: root))
        XCTAssertTrue(metricsStack === scrollView.documentView)
        XCTAssertTrue(metricsStack.isDescendant(of: scrollView))
        XCTAssertEqual(metricsStack.arrangedSubviews.count, MetricID.allCases.count)
        XCTAssertGreaterThanOrEqual(scrollView.frame.height, 120)
        XCTAssertGreaterThanOrEqual(scrollView.frame.minX, root.bounds.minX)
        XCTAssertLessThanOrEqual(scrollView.frame.maxX, root.bounds.maxX)
        XCTAssertGreaterThanOrEqual(scrollView.frame.minY, root.bounds.minY)
        XCTAssertLessThanOrEqual(scrollView.frame.maxY, root.bounds.maxY)
    }

    func testNativePopoverRendersInLightAndDarkAppearances() throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let controller = makeController(fixture)
        let root = controller.view
        root.frame = NSRect(origin: .zero, size: NativePopoverViewController.contentSize)

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            root.appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            root.needsLayout = true
            root.needsDisplay = true
            root.layoutSubtreeIfNeeded()
            root.displayIfNeeded()
            let representation = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
            root.cacheDisplay(in: root.bounds, to: representation)
            XCTAssertGreaterThan(representation.pixelsWide, 0)
            XCTAssertGreaterThan(representation.pixelsHigh, 0)
            if let captureDirectory = ProcessInfo.processInfo.environment["MACMETER_DESIGN_CAPTURE_DIR"] {
                let directory = URL(fileURLWithPath: captureDirectory, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let appearance = appearanceName == .darkAqua ? "dark" : "light"
                let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("popover-\(appearance).png"))
            }
        }
    }

    func testProductionSourcesContainNoSwiftUIOrHostingController() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourcesRoot = repositoryRoot.appendingPathComponent("Sources", isDirectory: true)
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: sourcesRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        let swiftFiles = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
        XCTAssertFalse(swiftFiles.isEmpty, "Expected Swift production sources under \(sourcesRoot.path)")

        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(source.contains("import SwiftUI"), "SwiftUI import remains in \(file.path)")
            XCTAssertFalse(source.contains("NSHostingController"), "NSHostingController remains in \(file.path)")
        }
    }

    private func makeController(_ fixture: PopoverFixture) -> NativePopoverViewController {
        NativePopoverViewController(
            coordinator: fixture.coordinator,
            settings: fixture.settings,
            appVersion: AppVersionInfo(version: "0.1.5", build: "1")
        )
    }

    private func makeFixture(sampledAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> PopoverFixture {
        _ = NSApplication.shared
        let suite = "NativePopoverViewControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults)
        let cpu = PopoverFixtureCPUProvider(result: .available(
            CPUReading(
                normalized: 42.5,
                summed: 170.4,
                cores: [
                    CoreReading(id: 0, utilization: 12.4, kind: .efficiency),
                    CoreReading(id: 1, utilization: 87.6, kind: .performance),
                    CoreReading(id: 2, utilization: 50, kind: .unknown)
                ]
            ),
            sampledAt: sampledAt
        ))
        let temperature = PopoverFixtureTemperatureProvider(result: .available(
            TemperatureReading(hottestCelsius: 55, sensorCount: 3),
            sampledAt: sampledAt
        ))
        let network = PopoverFixtureNetworkProvider(result: .available(
            NetworkReading(
                inboundBytesPerSecond: 3_200_000,
                outboundBytesPerSecond: 400_000,
                interfaces: ["en0", "en1"]
            ),
            sampledAt: sampledAt
        ))
        let battery = PopoverFixtureBatteryProvider(result: .available(
            BatteryPowerReading(watts: 8.4, direction: .draining),
            sampledAt: sampledAt
        ))
        let coordinator = MetricsCoordinator(
            settings: settings,
            cpuProvider: cpu,
            temperatureProvider: temperature,
            networkProvider: network,
            batteryProvider: battery,
            startAutomatically: false
        )
        coordinator.sampleNow(at: sampledAt)
        return PopoverFixture(
            settings: settings,
            coordinator: coordinator,
            cpu: cpu,
            battery: battery,
            sampledAt: sampledAt,
            cleanup: { defaults.removePersistentDomain(forName: suite) }
        )
    }

    private func setMetricMask(_ mask: Int, settings: SettingsStore) {
        settings.cpuEnabled = mask & 1 != 0
        settings.temperatureEnabled = mask & 2 != 0
        settings.networkEnabled = mask & 4 != 0
        settings.batteryEnabled = mask & 8 != 0
    }

    private func value(in root: NSView, metric: MetricID, name: String) throws -> String {
        try label(
            in: root,
            identifier: NativePopoverViewController.Identifier.value(metric, name)
        ).stringValue
    }

    private func label(in root: NSView, identifier: String) throws -> NSTextField {
        try control(in: root, identifier: identifier)
    }

    private func control<Control: NSView>(in root: NSView, identifier: String) throws -> Control {
        if let root = root as? Control, root.identifier?.rawValue == identifier {
            return root
        }
        for subview in root.subviews {
            if let match: Control = try? control(in: subview, identifier: identifier) {
                return match
            }
        }
        throw NSError(
            domain: "NativePopoverViewControllerTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing control \(identifier)"]
        )
    }
}

@MainActor
private struct PopoverFixture {
    let settings: SettingsStore
    let coordinator: MetricsCoordinator
    let cpu: PopoverFixtureCPUProvider
    let battery: PopoverFixtureBatteryProvider
    let sampledAt: Date
    let cleanup: () -> Void
}

@MainActor
private final class PopoverFixtureCPUProvider: CPUProviding {
    var result: MetricAvailability<CPUReading>

    init(result: MetricAvailability<CPUReading>) {
        self.result = result
    }

    func sample(at date: Date) -> MetricAvailability<CPUReading> { result }
    func resetBaseline() {}
}

@MainActor
private final class PopoverFixtureTemperatureProvider: TemperatureProviding {
    var result: MetricAvailability<TemperatureReading>

    init(result: MetricAvailability<TemperatureReading>) {
        self.result = result
    }

    func sample(at date: Date) -> MetricAvailability<TemperatureReading> { result }
}

@MainActor
private final class PopoverFixtureNetworkProvider: NetworkProviding {
    var result: MetricAvailability<NetworkReading>

    init(result: MetricAvailability<NetworkReading>) {
        self.result = result
    }

    func sample(at date: Date) -> MetricAvailability<NetworkReading> { result }
    func resetBaseline() {}
}

@MainActor
private final class PopoverFixtureBatteryProvider: BatteryProviding {
    var result: MetricAvailability<BatteryPowerReading>

    init(result: MetricAvailability<BatteryPowerReading>) {
        self.result = result
    }

    func sample(at date: Date) -> MetricAvailability<BatteryPowerReading> { result }
}
