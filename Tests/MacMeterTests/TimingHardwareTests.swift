import AppKit
import Combine
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
        var renderFailures = 0
        let renderedLabel = NSTextField(labelWithString: "")
        renderedLabel.frame = NSRect(x: 0, y: 0, width: 600, height: 44)
        renderedLabel.wantsLayer = true
        renderedLabel.layoutSubtreeIfNeeded()

        coordinator.$lastUpdated.sink { candidate in
            guard let date = candidate else { return }
            timestamps.append(date)
            renderedLabel.attributedStringValue = StatusItemLabelBuilder.make(
                coordinator: coordinator,
                settings: settings,
                cycleIndex: 0
            )
            renderedLabel.needsLayout = true
            renderedLabel.needsDisplay = true
            renderedLabel.layoutSubtreeIfNeeded()
            renderedLabel.displayIfNeeded()
            if let representation = renderedLabel.bitmapImageRepForCachingDisplay(in: renderedLabel.bounds) {
                renderedLabel.cacheDisplay(in: renderedLabel.bounds, to: representation)
            } else {
                renderFailures += 1
            }
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
        print("MacMeter timing: refreshErrorP95=\(refreshP95Error)s hostPaintP95=\(renderP95)s")
        XCTAssertEqual(renderFailures, 0)
        XCTAssertLessThanOrEqual(refreshP95Error, 0.2)
        XCTAssertLessThan(renderP95, 0.25)
        writeEvidence(section: "refresh", metrics: [
            "refreshErrorP95Seconds": refreshP95Error,
            "hostPaintP95Seconds": renderP95,
            "renderFailures": Double(renderFailures)
        ])
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
        writeEvidence(section: "cycle", metrics: ["errorP95Seconds": errorP95])
    }

    private func p95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .infinity }
        let sorted = values.sorted()
        let index = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        return sorted[index]
    }

    private func writeEvidence(section: String, metrics: [String: Double]) {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["MACMETER_TIMING_EVIDENCE_PATH"] else { return }
        let url = URL(fileURLWithPath: path)
        var evidence: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            evidence = existing
        }
        evidence["commit"] = environment["MACMETER_QA_COMMIT"] ?? "unknown"
        evidence["startedAt"] = environment["MACMETER_QA_STARTED_AT"] ?? "unknown"
        evidence["dirtyWorktree"] = environment["MACMETER_QA_DIRTY"] == "true"
        evidence["hardware"] = environment["MACMETER_QA_HARDWARE"] ?? "unknown"
        evidence[section] = metrics
        guard let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]) else {
            XCTFail("Could not encode timing evidence")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            XCTFail("Could not write timing evidence: \(error)")
        }
    }
}
