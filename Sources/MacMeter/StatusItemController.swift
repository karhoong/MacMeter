import AppKit
import Combine

enum StatusItemLabelBuilder {
    static let fontSize: CGFloat = 9

    struct Typography: Equatable {
        let lineHeight: CGFloat
        let baselineOffset: CGFloat
    }

    enum Palette {
        static let backdrop = NSColor(srgbRed: 0.055, green: 0.067, blue: 0.086, alpha: 0.88)
        static let primary = NSColor(srgbRed: 0.96, green: 0.98, blue: 1.0, alpha: 1)
        static let secondary = NSColor(srgbRed: 0.72, green: 0.76, blue: 0.82, alpha: 1)
        static let upload = NSColor(srgbRed: 1.0, green: 0.34, blue: 0.40, alpha: 1)
        static let download = NSColor(srgbRed: 0.30, green: 1.0, blue: 0.53, alpha: 1)
        static let idle = NSColor(srgbRed: 0.31, green: 0.75, blue: 1.0, alpha: 1)
    }

    static func typography(availableHeight: CGFloat, rowCount: Int) -> Typography {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let naturalLineHeight = font.ascender - font.descender + font.leading
        let quarterPointRoundedHeight = ceil(naturalLineHeight * 4) / 4
        let maximumLineHeight = max(1, availableHeight / CGFloat(max(1, rowCount)))
        let lineHeight = min(quarterPointRoundedHeight, maximumLineHeight)

        // NSButtonCell places a two-line attributed title slightly above its
        // visual center. Keep the natural font box, then use the remaining
        // status-bar height (capped at 0.75 pt) to nudge both baselines down.
        let baselineOffset: CGFloat = rowCount > 1 ? -min(0.75, max(0, availableHeight - lineHeight * CGFloat(rowCount))) : 0
        return Typography(lineHeight: lineHeight, baselineOffset: baselineOffset)
    }

    @MainActor
    static func make(
        coordinator: MetricsCoordinator,
        settings: SettingsStore,
        cycleIndex: Int,
        availableHeight: CGFloat = NSStatusBar.system.thickness
    ) -> NSAttributedString {
        let enabled = settings.enabledMetrics
        guard !enabled.isEmpty else {
            let layout = typography(availableHeight: availableHeight, rowCount: 1)
            return attributed("◉", color: Palette.primary, typography: layout)
        }

        let rows: [[MetricID]]
        if settings.displayMode == .cycle {
            rows = [[enabled[cycleIndex % enabled.count]]]
        } else {
            rows = MenuBarPresentation.rows(for: enabled)
        }
        let layout = typography(availableHeight: availableHeight, rowCount: rows.count)

        let result = NSMutableAttributedString()
        for (rowIndex, row) in rows.enumerated() {
            if rowIndex > 0 {
                result.append(attributed("\n", color: Palette.secondary, typography: layout))
            }
            for (metricIndex, metric) in row.enumerated() {
                if metricIndex > 0 {
                    result.append(attributed(" | ", color: Palette.secondary, typography: layout))
                }
                result.append(segment(metric, coordinator: coordinator, settings: settings, typography: layout))
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
        settings: SettingsStore,
        typography: Typography
    ) -> NSAttributedString {
        switch metric {
        case .cpu:
            guard let reading = coordinator.cpu.value else { return attributed("—", color: Palette.secondary, typography: typography) }
            return attributed(MenuBarPresentation.cpu(reading, scale: settings.cpuScale), color: Palette.primary, typography: typography)
        case .temperature:
            guard let reading = coordinator.temperature.value else { return attributed("—", color: Palette.secondary, typography: typography) }
            return attributed(MenuBarPresentation.temperature(reading, unit: settings.temperatureUnit), color: Palette.primary, typography: typography)
        case .network:
            guard let reading = coordinator.network.value else {
                return attributed("↑— ↓—\(settings.networkUnit.menuLabel)", color: Palette.secondary, typography: typography)
            }
            return networkAttributed(reading, unit: settings.networkUnit, typography: typography)
        case .battery:
            guard let reading = coordinator.battery.value else { return attributed("—", color: Palette.secondary, typography: typography) }
            let color: NSColor
            switch reading.direction.colorRole {
            case .charging: color = Palette.download
            case .draining: color = Palette.upload
            case .idle: color = Palette.idle
            }
            return attributed(MenuBarPresentation.battery(reading), color: color, typography: typography)
        }
    }

    private static func networkAttributed(
        _ reading: NetworkReading,
        unit: NetworkUnit,
        typography: Typography
    ) -> NSAttributedString {
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
        result.append(attributed("↑\(outgoing)", color: Palette.upload, typography: typography))
        result.append(attributed(" ", color: Palette.secondary, typography: typography))
        result.append(attributed("↓\(incoming)\(unit.menuLabel)", color: Palette.download, typography: typography))
        return result
    }

    private static func attributed(
        _ text: String,
        color: NSColor,
        typography: Typography
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.minimumLineHeight = typography.lineHeight
        paragraph.maximumLineHeight = typography.lineHeight
        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: color,
                .paragraphStyle: paragraph,
                .baselineOffset: typography.baselineOffset
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
    var renderedBackdropColor: NSColor? {
        guard let color = statusItem.button?.layer?.backgroundColor else { return nil }
        return NSColor(cgColor: color)
    }
    var renderedBackdropCornerRadius: CGFloat { statusItem.button?.layer?.cornerRadius ?? 0 }
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
        button.wantsLayer = true
        button.layer?.backgroundColor = StatusItemLabelBuilder.Palette.backdrop.cgColor
        button.layer?.cornerRadius = 5
        button.layer?.masksToBounds = true
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
            cycleIndex: cycleIndex,
            availableHeight: button.bounds.height > 0
                ? button.bounds.height
                : NSStatusBar.system.thickness
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
