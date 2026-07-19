import AppKit
import Combine

enum StatusItemLabelBuilder {
    static let fontSize: CGFloat = 9
    static let lineHeight: CGFloat = 10.5

    @MainActor
    static func make(
        coordinator: MetricsCoordinator,
        settings: SettingsStore,
        cycleIndex: Int
    ) -> NSAttributedString {
        let enabled = settings.enabledMetrics
        guard !enabled.isEmpty else {
            return attributed("◉", color: .labelColor)
        }

        let rows: [[MetricID]]
        if settings.displayMode == .cycle {
            rows = [[enabled[cycleIndex % enabled.count]]]
        } else {
            rows = MenuBarPresentation.rows(for: enabled)
        }

        let result = NSMutableAttributedString()
        for (rowIndex, row) in rows.enumerated() {
            if rowIndex > 0 {
                result.append(attributed("\n", color: .secondaryLabelColor))
            }
            for (metricIndex, metric) in row.enumerated() {
                if metricIndex > 0 {
                    result.append(attributed(" | ", color: .secondaryLabelColor))
                }
                result.append(segment(metric, coordinator: coordinator, settings: settings))
            }
        }
        return result
    }

    @MainActor
    static func accessibilityLabel(
        coordinator: MetricsCoordinator,
        settings: SettingsStore,
        cycleIndex: Int
    ) -> String {
        let enabled = settings.enabledMetrics
        guard !enabled.isEmpty else { return "MacMeter. No metrics enabled" }
        let metrics = settings.displayMode == .cycle
            ? [enabled[cycleIndex % enabled.count]]
            : MenuBarPresentation.rows(for: enabled).flatMap { $0 }
        return metrics.map { metric in
            switch metric {
            case .cpu:
                guard let reading = coordinator.cpu.value else { return "CPU unavailable" }
                let value = settings.cpuScale == .normalized ? reading.normalized : reading.summed
                return MetricAccessibility.cpu(value)
            case .temperature:
                guard let reading = coordinator.temperature.value else { return "SoC temperature unavailable" }
                return MetricAccessibility.temperature(reading.hottestCelsius, unit: settings.temperatureUnit)
            case .network:
                guard let reading = coordinator.network.value else { return "Network speed unavailable" }
                return MetricAccessibility.network(reading, unit: settings.networkUnit)
            case .battery:
                guard let reading = coordinator.battery.value else { return "Battery power unavailable" }
                return MetricAccessibility.battery(reading)
            }
        }.joined(separator: ", ")
    }

    @MainActor
    private static func segment(
        _ metric: MetricID,
        coordinator: MetricsCoordinator,
        settings: SettingsStore
    ) -> NSAttributedString {
        switch metric {
        case .cpu:
            guard let reading = coordinator.cpu.value else { return attributed("—", color: .secondaryLabelColor) }
            return attributed(MenuBarPresentation.cpu(reading, scale: settings.cpuScale), color: .labelColor)
        case .temperature:
            guard let reading = coordinator.temperature.value else { return attributed("—", color: .secondaryLabelColor) }
            return attributed(MenuBarPresentation.temperature(reading, unit: settings.temperatureUnit), color: .labelColor)
        case .network:
            guard let reading = coordinator.network.value else {
                return attributed("↑—↓—\(settings.networkUnit.menuLabel)", color: .secondaryLabelColor)
            }
            return networkAttributed(reading, unit: settings.networkUnit)
        case .battery:
            guard let reading = coordinator.battery.value else { return attributed("—", color: .secondaryLabelColor) }
            let color: NSColor
            switch reading.direction.colorRole {
            case .charging: color = .systemGreen
            case .draining: color = .systemRed
            case .idle: color = .systemBlue
            }
            return attributed(MenuBarPresentation.battery(reading), color: color)
        }
    }

    private static func networkAttributed(_ reading: NetworkReading, unit: NetworkUnit) -> NSAttributedString {
        let outgoing = MetricFormatting.network(
            bytesPerSecond: reading.outboundBytesPerSecond,
            unit: unit,
            fixedOneDecimal: true
        )
        let incoming = MetricFormatting.network(
            bytesPerSecond: reading.inboundBytesPerSecond,
            unit: unit,
            fixedOneDecimal: true
        )
        let result = NSMutableAttributedString()
        result.append(attributed("↑\(outgoing)", color: .systemRed))
        result.append(attributed("↓\(incoming)\(unit.menuLabel)", color: .systemGreen))
        return result
    }

    private static func attributed(_ text: String, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }
}

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let coordinator: MetricsCoordinator
    private let settings: SettingsStore
    private let settingsWindowController: SettingsWindowController
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let presentPopover: (NSPopover, NSStatusBarButton) -> Void
    private let dismissPopover: (NSPopover) -> Void
    private var cancellables = Set<AnyCancellable>()
    private var cycleTask: Task<Void, Never>?
    private var cycleIndex = 0
    private var refreshScheduled = false
    private var pendingSettingsChange = false

    var renderedTitle: NSAttributedString { statusItem.button?.attributedTitle ?? NSAttributedString() }
    private(set) var refreshCount = 0
    var statusButtonSubviewCount: Int { statusItem.button?.subviews.count ?? 0 }
    var renderedLength: CGFloat { statusItem.length }
    var statusButton: NSStatusBarButton? { statusItem.button }
    var isPopoverPrepared: Bool { popover.contentViewController != nil }
    weak var popoverContentViewController: NSViewController? { popover.contentViewController }

    init(
        coordinator: MetricsCoordinator,
        settings: SettingsStore,
        settingsWindowController: SettingsWindowController,
        presentPopover: @escaping (NSPopover, NSStatusBarButton) -> Void = { popover, button in
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        },
        dismissPopover: @escaping (NSPopover) -> Void = { popover in
            popover.performClose(nil)
        }
    ) {
        self.coordinator = coordinator
        self.settings = settings
        self.settingsWindowController = settingsWindowController
        self.presentPopover = presentPopover
        self.dismissPopover = dismissPopover
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NativePopoverViewController.contentSize
        popover.delegate = self

        coordinator.objectWillChange.sink { [weak self] in
            self?.scheduleRefresh(settingsChanged: false)
        }.store(in: &cancellables)
        settings.objectWillChange.sink { [weak self] in
            self?.scheduleRefresh(settingsChanged: true)
        }.store(in: &cancellables)

        applySettingsChange()
    }

    func close() {
        cycleTask?.cancel()
        cycleTask = nil
        dismissPopover(popover)
        popover.contentViewController = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.image = nil
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp])
        button.cell?.lineBreakMode = .byClipping
        button.cell?.usesSingleLineMode = false
        button.cell?.wraps = true
    }

    private func scheduleRefresh(settingsChanged: Bool) {
        pendingSettingsChange = pendingSettingsChange || settingsChanged
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            refreshScheduled = false
            let applySettings = pendingSettingsChange
            pendingSettingsChange = false
            if applySettings {
                applySettingsChange()
            } else {
                refresh()
            }
        }
    }

    private func applySettingsChange() {
        cycleIndex = 0
        updateCycleTask()
        refresh()
    }

    private func updateCycleTask() {
        cycleTask?.cancel()
        cycleTask = nil
        guard settings.displayMode == .cycle, !settings.enabledMetrics.isEmpty else { return }
        cycleTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled else { return }
                cycleIndex = CycleSequence.nextIndex(
                    current: cycleIndex,
                    enabledCount: settings.enabledMetrics.count
                )
                refresh()
            }
        }
    }

    private func refresh() {
        guard let button = statusItem.button else { return }
        refreshCount += 1
        let attributedTitle = StatusItemLabelBuilder.make(
            coordinator: coordinator,
            settings: settings,
            cycleIndex: cycleIndex
        )
        button.attributedTitle = attributedTitle
        let bounds = attributedTitle.boundingRect(
            with: NSSize(width: 1_000, height: NSStatusBar.system.thickness),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        statusItem.length = max(18, ceil(bounds.width) + 8)
        button.setAccessibilityLabel(StatusItemLabelBuilder.accessibilityLabel(
            coordinator: coordinator,
            settings: settings,
            cycleIndex: cycleIndex
        ))
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            dismissPopover(popover)
        } else {
            preparePopoverIfNeeded()
            presentPopover(popover, button)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func preparePopoverIfNeeded() {
        guard popover.contentViewController == nil else { return }
        popover.contentViewController = NativePopoverViewController(
            coordinator: coordinator,
            settings: settings,
            openSettings: { [weak self] in
                self?.openSettings()
            },
            quit: {
                NSApp.terminate(nil)
            }
        )
    }

    func openSettings() {
        dismissPopover(popover)
        settingsWindowController.show()
    }

    func popoverDidClose(_ notification: Notification) {
        // Retain and reuse one native AppKit tree. Recreating the previous
        // SwiftUI host on every click caused a ~30 MiB cold allocation and
        // crossed the release RSS ceiling while the popover was visible.
    }
}
