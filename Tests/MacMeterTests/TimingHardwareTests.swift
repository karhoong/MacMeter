import Combine
import SwiftUI
import XCTest
@testable import MacMeter

@MainActor
final class TimingHardwareTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["MACMETER_RUN_HARDWARE_TESTS"] == "1" else {
            throw XCTSkip("Hardware timing tests run through Scripts/qa.sh")
        }
    }

    func testRefreshAndRenderP95MeetBudgets() async throws {
        let suite = "MacMeterTimingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.updateInterval = 1
        let coordinator = MetricsCoordinator(settings: settings, startAutomatically: false)
        let expectation = expectation(description: "Eleven refresh samples")
        expectation.expectedFulfillmentCount = 11
        var timestamps: [Date] = []
        var renderLatencies: [TimeInterval] = []

        coordinator.$lastUpdated.compactMap { $0 }.sink { date in
            timestamps.append(date)
            let renderer = ImageRenderer(content: MenuBarLabelView(coordinator: coordinator, settings: settings))
            renderer.scale = 2
            _ = renderer.nsImage
            renderLatencies.append(Date().timeIntervalSince(date))
            expectation.fulfill()
        }.store(in: &cancellables)

        coordinator.restartSampling()
        await fulfillment(of: [expectation], timeout: 12.5)
        coordinator.stopSampling()

        let intervals = zip(timestamps.dropFirst(), timestamps).map { later, earlier in
            later.timeIntervalSince(earlier)
        }
        let refreshP95Error = p95(intervals.map { abs($0 - 1) })
        let renderP95 = p95(renderLatencies)
        print("MacMeter timing: refreshErrorP95=\(refreshP95Error)s renderP95=\(renderP95)s")
        XCTAssertLessThanOrEqual(refreshP95Error, 0.2)
        XCTAssertLessThan(renderP95, 0.25)
    }

    func testCycleP95MeetsFiveSecondBudget() async {
        let controller = CycleController()
        let expectation = expectation(description: "Five cycle advances")
        expectation.expectedFulfillmentCount = 5
        let started = Date()
        var advances: [Date] = []

        controller.$index.dropFirst().sink { _ in
            advances.append(Date())
            expectation.fulfill()
        }.store(in: &cancellables)

        controller.start { 4 }
        await fulfillment(of: [expectation], timeout: 26.5)
        controller.stop()

        let boundaries = [started] + advances
        let intervals = zip(boundaries.dropFirst(), boundaries).map { later, earlier in
            later.timeIntervalSince(earlier)
        }
        let errorP95 = p95(intervals.map { abs($0 - 5) })
        print("MacMeter cycle timing: errorP95=\(errorP95)s")
        XCTAssertLessThanOrEqual(errorP95, 0.2)
    }

    private func p95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .infinity }
        let sorted = values.sorted()
        let index = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        return sorted[index]
    }
}
