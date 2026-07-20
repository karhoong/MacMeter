import AppKit
import Combine

@MainActor
final class NativePopoverViewController: NSViewController {
    enum Identifier {
        static let root = "MacMeter.Popover.Root"
        static let title = "MacMeter.Popover.Title"
        static let version = "MacMeter.Popover.Version"
        static let scrollView = "MacMeter.Popover.ScrollView"
        static let metricsStack = "MacMeter.Popover.Metrics"
        static let updated = "MacMeter.Popover.Updated"
        static let settingsButton = "MacMeter.Popover.Settings"
        static let quitButton = "MacMeter.Popover.Quit"

        static func section(_ metric: MetricID) -> String {
            "MacMeter.Popover.\(metric.rawValue).Section"
        }

        static func unavailable(_ metric: MetricID) -> String {
            "MacMeter.Popover.\(metric.rawValue).Unavailable"
        }

        static func value(_ metric: MetricID, _ name: String) -> String {
            "MacMeter.Popover.\(metric.rawValue).\(name)"
        }

        static func coreRow(_ id: Int) -> String { "MacMeter.Popover.CPU.Core.\(id)" }
        static func coreKind(_ id: Int) -> String { "MacMeter.Popover.CPU.Core.\(id).Kind" }
        static func coreValue(_ id: Int) -> String { "MacMeter.Popover.CPU.Core.\(id).Value" }
    }

    static let contentSize = NSSize(width: 390, height: 520)

    private let coordinator: MetricsCoordinator
    private let settings: SettingsStore
    private let appVersion: AppVersionInfo
    private let openSettingsAction: () -> Void
    private let quitAction: () -> Void

    private var cancellables = Set<AnyCancellable>()
    private var scheduledRefresh: Task<Void, Never>?
    private let timeFormatter: DateFormatter

    private(set) var refreshCount = 0
    private(set) var sectionViews: [MetricID: NativePopoverMetricSectionView] = [:]
    private(set) var coreRowViews: [Int: NativePopoverCoreRowView] = [:]

    private let titleLabel = NativePopoverViewController.makeLabel(
        identifier: Identifier.title,
        font: .systemFont(ofSize: 15, weight: .semibold)
    )
    private let versionLabel = NativePopoverViewController.makeLabel(
        identifier: Identifier.version,
        font: .systemFont(ofSize: NSFont.smallSystemFontSize),
        color: .secondaryLabelColor
    )
    private let metricsStack = NativePopoverViewController.makeStack(
        identifier: Identifier.metricsStack,
        orientation: .vertical,
        spacing: 14
    )
    private let updatedLabel = NativePopoverViewController.makeLabel(
        identifier: Identifier.updated,
        font: .systemFont(ofSize: NSFont.smallSystemFontSize),
        color: .secondaryLabelColor
    )
    private(set) lazy var settingsButton: NSButton = makeButton(
        title: "Settings…",
        symbolName: "slider.horizontal.3",
        identifier: Identifier.settingsButton,
        action: #selector(openSettingsPressed)
    )
    private(set) lazy var quitButton: NSButton = makeButton(
        title: "Quit",
        symbolName: "power",
        identifier: Identifier.quitButton,
        action: #selector(quitPressed)
    )

    private let cpuAvailableStack = NativePopoverViewController.makeStack(orientation: .vertical, spacing: 5)
    private let cpuOverallRow = NativePopoverValueRowView(
        title: "Overall",
        valueIdentifier: Identifier.value(.cpu, "Overall")
    )
    private let cpuSummedRow = NativePopoverValueRowView(
        title: "All cores",
        valueIdentifier: Identifier.value(.cpu, "Summed")
    )
    private let cpuCoreStack = NativePopoverViewController.makeStack(orientation: .vertical, spacing: 3)

    private let temperatureAvailableStack = NativePopoverViewController.makeStack(orientation: .vertical, spacing: 5)
    private let temperatureValueRow = NativePopoverValueRowView(
        title: "Hottest",
        valueIdentifier: Identifier.value(.temperature, "Hottest")
    )
    private let temperatureSensorRow = NativePopoverValueRowView(
        title: "Sensors",
        valueIdentifier: Identifier.value(.temperature, "Sensors")
    )

    private let networkAvailableStack = NativePopoverViewController.makeStack(orientation: .vertical, spacing: 5)
    private let networkInboundRow = NativePopoverValueRowView(
        title: "Inbound",
        valueIdentifier: Identifier.value(.network, "Inbound")
    )
    private let networkOutboundRow = NativePopoverValueRowView(
        title: "Outbound",
        valueIdentifier: Identifier.value(.network, "Outbound")
    )
    private let networkInterfacesRow = NativePopoverValueRowView(
        title: "Interfaces",
        valueIdentifier: Identifier.value(.network, "Interfaces")
    )

    private let batteryAvailableStack = NativePopoverViewController.makeStack(orientation: .vertical, spacing: 5)
    private let batteryPowerRow = NativePopoverValueRowView(
        title: "Idle",
        valueIdentifier: Identifier.value(.battery, "Power")
    )

    init(
        coordinator: MetricsCoordinator,
        settings: SettingsStore,
        appVersion: AppVersionInfo = .current,
        openSettings: @escaping () -> Void = {},
        quit: @escaping () -> Void = { NSApp.terminate(nil) }
    ) {
        self.coordinator = coordinator
        self.settings = settings
        self.appVersion = appVersion
        openSettingsAction = openSettings
        quitAction = quit

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        timeFormatter = formatter

        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.contentSize
        observeModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))
        root.identifier = NSUserInterfaceItemIdentifier(Identifier.root)
        view = root

        titleLabel.stringValue = "MacMeter"
        titleLabel.setAccessibilityLabel("MacMeter")
        versionLabel.stringValue = appVersion.displayLabel
        versionLabel.setAccessibilityLabel(appVersion.displayLabel)
        versionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let appIcon = NSImageView(image: NSApp.applicationIconImage)
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.setAccessibilityElement(false)
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            appIcon.widthAnchor.constraint(equalToConstant: 24),
            appIcon.heightAnchor.constraint(equalToConstant: 24)
        ])

        let header = Self.makeStack(orientation: .horizontal, spacing: 9)
        header.addArrangedSubview(appIcon)
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(Self.makeFlexibleSpacer())
        header.addArrangedSubview(versionLabel)

        buildMetricSections()

        let scrollView = NSScrollView()
        scrollView.identifier = NSUserInterfaceItemIdentifier(Identifier.scrollView)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = metricsStack
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        metricsStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            metricsStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            metricsStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            metricsStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            metricsStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        settingsButton.setAccessibilityLabel("Open MacMeter Settings")
        quitButton.setAccessibilityLabel("Quit MacMeter")
        let updatedIcon = Self.makeSymbolImage("clock", pointSize: 11, color: .secondaryLabelColor)
        let updatedGroup = Self.makeStack(orientation: .horizontal, spacing: 5)
        updatedGroup.addArrangedSubview(updatedIcon)
        updatedGroup.addArrangedSubview(updatedLabel)
        let footer = Self.makeStack(orientation: .horizontal, spacing: 10)
        footer.addArrangedSubview(updatedGroup)
        footer.addArrangedSubview(Self.makeFlexibleSpacer())
        footer.addArrangedSubview(settingsButton)
        footer.addArrangedSubview(quitButton)

        let rootStack = Self.makeStack(orientation: .vertical, spacing: 12)
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(header)
        rootStack.addArrangedSubview(Self.makeSeparator())
        rootStack.addArrangedSubview(scrollView)
        rootStack.addArrangedSubview(Self.makeSeparator())
        rootStack.addArrangedSubview(footer)
        root.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            rootStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            rootStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            rootStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])

        refreshFromModel()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshFromModel()
    }

    func sectionView(for metric: MetricID) -> NSView? {
        sectionViews[metric]
    }

    func coreRowView(for id: Int) -> NativePopoverCoreRowView? {
        coreRowViews[id]
    }

    func refreshFromModel() {
        guard isViewLoaded else { return }
        refreshCount += 1
        applyLocalization()

        updateCPU()
        updateTemperature()
        updateNetwork()
        updateBattery()

        sectionViews[.cpu]?.isHidden = !settings.cpuEnabled
        sectionViews[.temperature]?.isHidden = !settings.temperatureEnabled
        sectionViews[.network]?.isHidden = !settings.networkEnabled
        sectionViews[.battery]?.isHidden = !settings.batteryEnabled

        if let date = coordinator.lastUpdated {
            let time = timeFormatter.string(from: date)
            updatedLabel.stringValue = settings.localizer.formatted(.updated, time)
            updatedLabel.setAccessibilityLabel(settings.localizer.formatted(.lastUpdated, time))
        } else {
            updatedLabel.stringValue = settings.localizer.text(.waitingForData)
            updatedLabel.setAccessibilityLabel(settings.localizer.text(.waitingForData))
        }
    }

    private func applyLocalization() {
        let l = settings.localizer
        timeFormatter.locale = l.locale
        versionLabel.stringValue = l.version(appVersion)
        versionLabel.setAccessibilityLabel(l.version(appVersion))
        settingsButton.title = l.text(.settings)
        settingsButton.setAccessibilityLabel(l.text(.openSettingsAccessibility))
        quitButton.title = l.text(.quit)
        quitButton.setAccessibilityLabel(l.text(.quitAccessibility))
        sectionViews[.cpu]?.sectionTitle = l.text(.cpu)
        sectionViews[.temperature]?.sectionTitle = l.text(.socTemperature)
        sectionViews[.network]?.sectionTitle = l.text(.network)
        sectionViews[.battery]?.sectionTitle = l.text(.batteryPower)
        cpuOverallRow.title = l.text(.overall)
        cpuSummedRow.title = l.text(.allCores)
        temperatureValueRow.title = l.text(.hottest)
        temperatureSensorRow.title = l.text(.sensors)
        networkInboundRow.title = l.text(.inbound)
        networkOutboundRow.title = l.text(.outbound)
        networkInterfacesRow.title = l.text(.interfaces)
    }

    private func observeModel() {
        coordinator.objectWillChange.sink { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleRefresh()
            }
        }.store(in: &cancellables)

        settings.objectWillChange.sink { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleRefresh()
            }
        }.store(in: &cancellables)
    }

    private func scheduleRefresh() {
        // The retained native tree does not need to repaint while its popover
        // is closed. It is refreshed immediately in viewWillAppear instead.
        guard isViewLoaded, view.window != nil else { return }
        guard scheduledRefresh == nil else { return }
        scheduledRefresh = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            scheduledRefresh = nil
            refreshFromModel()
        }
    }

    private func buildMetricSections() {
        let cpuSection = NativePopoverMetricSectionView(metric: .cpu, title: "CPU", symbolName: "cpu")
        cpuAvailableStack.addArrangedSubview(cpuOverallRow)
        cpuAvailableStack.addArrangedSubview(cpuSummedRow)
        cpuAvailableStack.addArrangedSubview(Self.makeSeparator())
        cpuAvailableStack.addArrangedSubview(cpuCoreStack)
        cpuSection.setAvailableView(cpuAvailableStack)
        addSection(cpuSection, metric: .cpu)

        let temperatureSection = NativePopoverMetricSectionView(
            metric: .temperature,
            title: "SoC Temperature",
            symbolName: "thermometer.medium"
        )
        temperatureAvailableStack.addArrangedSubview(temperatureValueRow)
        temperatureAvailableStack.addArrangedSubview(temperatureSensorRow)
        temperatureSection.setAvailableView(temperatureAvailableStack)
        addSection(temperatureSection, metric: .temperature)

        let networkSection = NativePopoverMetricSectionView(
            metric: .network,
            title: "Network",
            symbolName: "arrow.up.arrow.down"
        )
        networkAvailableStack.addArrangedSubview(networkInboundRow)
        networkAvailableStack.addArrangedSubview(networkOutboundRow)
        networkAvailableStack.addArrangedSubview(networkInterfacesRow)
        networkSection.setAvailableView(networkAvailableStack)
        addSection(networkSection, metric: .network)

        let batterySection = NativePopoverMetricSectionView(
            metric: .battery,
            title: "Battery Power",
            symbolName: "battery.75"
        )
        batteryAvailableStack.addArrangedSubview(batteryPowerRow)
        batterySection.setAvailableView(batteryAvailableStack)
        addSection(batterySection, metric: .battery)
    }

    private func addSection(_ section: NativePopoverMetricSectionView, metric: MetricID) {
        sectionViews[metric] = section
        metricsStack.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: metricsStack.widthAnchor).isActive = true
    }

    private func updateCPU() {
        guard let section = sectionViews[.cpu] else { return }
        guard let reading = coordinator.cpu.value else {
            section.showUnavailable(localizedUnavailableReason(coordinator.cpu.reason))
            return
        }

        section.showAvailable()
        cpuOverallRow.value = MetricFormatting.percent(reading.normalized)
        cpuSummedRow.value = MetricFormatting.percent(reading.summed)
        let cpuColor = MetricStatusPalette.cpu(normalizedPercent: reading.normalized)
        cpuOverallRow.valueColor = cpuColor
        cpuSummedRow.valueColor = cpuColor
        section.setAccentColor(cpuColor)
        reconcileCoreRows(reading.cores)
    }

    private func reconcileCoreRows(_ readings: [CoreReading]) {
        let desiredIDs = readings.map(\.id)
        let desiredSet = Set(desiredIDs)

        let removedIDs = coreRowViews.keys.filter { !desiredSet.contains($0) }
        for id in removedIDs {
            guard let row = coreRowViews[id] else { continue }
            cpuCoreStack.removeArrangedSubview(row)
            row.removeFromSuperview()
            coreRowViews[id] = nil
        }

        for reading in readings {
            let row: NativePopoverCoreRowView
            if let existing = coreRowViews[reading.id] {
                row = existing
            } else {
                row = NativePopoverCoreRowView(coreID: reading.id)
                coreRowViews[reading.id] = row
            }
            row.update(reading, localizer: settings.localizer)
        }

        let arrangedIDs = cpuCoreStack.arrangedSubviews.compactMap {
            ($0 as? NativePopoverCoreRowView)?.coreID
        }
        if arrangedIDs != desiredIDs {
            for view in cpuCoreStack.arrangedSubviews {
                cpuCoreStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            for id in desiredIDs {
                if let row = coreRowViews[id] {
                    cpuCoreStack.addArrangedSubview(row)
                }
            }
        }
    }

    private func updateTemperature() {
        guard let section = sectionViews[.temperature] else { return }
        guard let reading = coordinator.temperature.value else {
            section.showUnavailable(localizedUnavailableReason(coordinator.temperature.reason))
            return
        }

        section.showAvailable()
        temperatureValueRow.value = MetricFormatting.temperature(
            reading.hottestCelsius,
            unit: settings.temperatureUnit
        )
        let temperatureColor = MetricStatusPalette.temperature(celsius: reading.hottestCelsius)
        temperatureValueRow.valueColor = temperatureColor
        section.setAccentColor(temperatureColor)
        temperatureSensorRow.value = "\(reading.sensorCount)"
    }

    private func updateNetwork() {
        guard let section = sectionViews[.network] else { return }
        guard let reading = coordinator.network.value else {
            section.showUnavailable(localizedUnavailableReason(coordinator.network.reason))
            return
        }

        section.showAvailable()
        networkInboundRow.value = "\(MetricFormatting.network(bytesPerSecond: reading.inboundBytesPerSecond, unit: settings.networkUnit)) \(settings.networkUnit.rawValue)"
        networkOutboundRow.value = "\(MetricFormatting.network(bytesPerSecond: reading.outboundBytesPerSecond, unit: settings.networkUnit)) \(settings.networkUnit.rawValue)"
        networkInboundRow.valueColor = StatusItemLabelBuilder.Palette.download
        networkOutboundRow.valueColor = StatusItemLabelBuilder.Palette.upload
        section.setAccentColor(StatusItemLabelBuilder.Palette.idle)
        networkInterfacesRow.value = reading.interfaces.isEmpty ? "—" : reading.interfaces.joined(separator: ", ")
    }

    private func updateBattery() {
        guard let section = sectionViews[.battery] else { return }
        guard let reading = coordinator.battery.value else {
            section.showUnavailable(localizedUnavailableReason(coordinator.battery.reason))
            return
        }

        section.showAvailable()
        switch reading.direction {
        case .charging: batteryPowerRow.title = settings.localizer.text(.charging)
        case .draining: batteryPowerRow.title = settings.localizer.text(.draining)
        case .idle: batteryPowerRow.title = settings.localizer.text(.idle)
        }
        batteryPowerRow.value = MetricFormatting.battery(reading)
        batteryPowerRow.valueColor = Self.batteryColor(reading.direction)
        section.setAccentColor(Self.batteryColor(reading.direction))
        batteryPowerRow.setAccessibilityLabel(settings.localizer.batteryAccessibility(reading))
    }

    private func localizedUnavailableReason(_ reason: String?) -> String {
        guard let reason else { return settings.localizer.text(.unavailable) }
        if settings.localizer.language == .english { return reason }
        if reason.localizedCaseInsensitiveContains("waiting")
            || reason.localizedCaseInsensitiveContains("collecting") {
            return settings.localizer.text(.waitingForData)
        }
        if reason.localizedCaseInsensitiveContains("disabled") {
            return settings.localizer.text(.disabled)
        }
        return settings.localizer.text(.unavailable)
    }

    @objc private func openSettingsPressed() {
        openSettingsAction()
    }

    @objc private func quitPressed() {
        quitAction()
    }

    private func makeButton(title: String, symbolName: String, identifier: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        return button
    }

    private static func batteryColor(_ direction: BatteryDirection) -> NSColor {
        switch direction.colorRole {
        case .charging: return .systemGreen
        case .draining: return .systemRed
        case .idle: return .systemBlue
        }
    }

    fileprivate static func makeLabel(
        identifier: String? = nil,
        font: NSFont = .systemFont(ofSize: NSFont.systemFontSize),
        color: NSColor = .labelColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        if let identifier {
            label.identifier = NSUserInterfaceItemIdentifier(identifier)
        }
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    fileprivate static func makeStack(
        identifier: String? = nil,
        orientation: NSUserInterfaceLayoutOrientation,
        spacing: CGFloat
    ) -> NSStackView {
        let stack = NSStackView()
        if let identifier {
            stack.identifier = NSUserInterfaceItemIdentifier(identifier)
        }
        stack.orientation = orientation
        stack.alignment = orientation == .vertical ? .leading : .centerY
        stack.distribution = .fill
        stack.spacing = spacing
        return stack
    }

    fileprivate static func makeFlexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    fileprivate static func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    fileprivate static func makeSymbolImage(
        _ name: String,
        pointSize: CGFloat,
        color: NSColor
    ) -> NSImageView {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        let imageView = NSImageView(image: image)
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        imageView.contentTintColor = color
        imageView.imageScaling = .scaleProportionallyDown
        imageView.setAccessibilityElement(false)
        return imageView
    }
}

@MainActor
final class NativePopoverMetricSectionView: NSBox {
    let metric: MetricID
    private let contentStack = NSStackView()
    private let iconView: NSImageView
    private let titleLabel: NSTextField
    private(set) var availableView: NSView?
    private(set) var unavailableLabel: NSTextField

    var sectionTitle: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    init(metric: MetricID, title: String, symbolName: String) {
        self.metric = metric
        iconView = NativePopoverViewController.makeSymbolImage(
            symbolName,
            pointSize: 13,
            color: .secondaryLabelColor
        )
        titleLabel = NSTextField(labelWithString: title)
        unavailableLabel = NSTextField(labelWithString: "")
        super.init(frame: .zero)

        identifier = NSUserInterfaceItemIdentifier(NativePopoverViewController.Identifier.section(metric))
        boxType = .custom
        titlePosition = .noTitle
        borderWidth = 0.5
        borderColor = NSColor.separatorColor.withAlphaComponent(0.50)
        cornerRadius = 10
        fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.56)
        contentViewMargins = NSSize(width: 12, height: 10)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        let header = NativePopoverViewController.makeStack(orientation: .horizontal, spacing: 7)
        header.addArrangedSubview(iconView)
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(NativePopoverViewController.makeFlexibleSpacer())

        unavailableLabel.identifier = NSUserInterfaceItemIdentifier(
            NativePopoverViewController.Identifier.unavailable(metric)
        )
        unavailableLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        unavailableLabel.textColor = .secondaryLabelColor
        unavailableLabel.lineBreakMode = .byWordWrapping
        unavailableLabel.maximumNumberOfLines = 0
        unavailableLabel.isHidden = true

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.distribution = .fill
        contentStack.spacing = 9
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(header)
        contentStack.addArrangedSubview(unavailableLabel)
        contentView?.addSubview(contentStack)
        if let contentView {
            NSLayoutConstraint.activate([
                contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                contentStack.topAnchor.constraint(equalTo: contentView.topAnchor),
                contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAvailableView(_ view: NSView) {
        availableView = view
        contentStack.insertArrangedSubview(view, at: 1)
    }

    func setAccentColor(_ color: NSColor) {
        iconView.contentTintColor = color
        titleLabel.textColor = color
    }

    func showAvailable() {
        availableView?.isHidden = false
        unavailableLabel.isHidden = true
    }

    func showUnavailable(_ reason: String?) {
        availableView?.isHidden = true
        unavailableLabel.stringValue = reason ?? "Unavailable"
        unavailableLabel.setAccessibilityLabel(reason ?? "Unavailable")
        unavailableLabel.isHidden = false
    }
}

@MainActor
final class NativePopoverValueRowView: NSStackView {
    private let titleLabel = NSTextField(labelWithString: "")
    private(set) var valueLabel = NSTextField(labelWithString: "")

    var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    var value: String {
        get { valueLabel.stringValue }
        set { valueLabel.stringValue = newValue }
    }

    var valueColor: NSColor {
        get { valueLabel.textColor ?? .labelColor }
        set { valueLabel.textColor = newValue }
    }

    init(title: String, valueIdentifier: String) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        distribution = .fill
        spacing = 8

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        valueLabel.identifier = NSUserInterfaceItemIdentifier(valueIdentifier)
        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.lineBreakMode = .byTruncatingMiddle

        addArrangedSubview(titleLabel)
        addArrangedSubview(NativePopoverViewController.makeFlexibleSpacer())
        addArrangedSubview(valueLabel)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class NativePopoverCoreRowView: NSStackView {
    let coreID: Int
    private let coreLabel = NSTextField(labelWithString: "")
    private(set) var kindLabel = NSTextField(labelWithString: "")
    private(set) var valueLabel = NSTextField(labelWithString: "")

    init(coreID: Int) {
        self.coreID = coreID
        super.init(frame: .zero)

        identifier = NSUserInterfaceItemIdentifier(NativePopoverViewController.Identifier.coreRow(coreID))
        orientation = .horizontal
        alignment = .centerY
        distribution = .fill
        spacing = 6

        coreLabel.stringValue = "Core \(coreID)"
        kindLabel.identifier = NSUserInterfaceItemIdentifier(NativePopoverViewController.Identifier.coreKind(coreID))
        kindLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        valueLabel.identifier = NSUserInterfaceItemIdentifier(NativePopoverViewController.Identifier.coreValue(coreID))
        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        addArrangedSubview(coreLabel)
        addArrangedSubview(kindLabel)
        addArrangedSubview(NativePopoverViewController.makeFlexibleSpacer())
        addArrangedSubview(valueLabel)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        setAccessibilityElement(true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ reading: CoreReading, localizer: Localizer = Localizer(selection: .english)) {
        coreLabel.stringValue = "\(localizer.text(.core)) \(reading.id)"
        kindLabel.stringValue = reading.kind.shortLabel
        switch reading.kind {
        case .efficiency: kindLabel.textColor = .systemGreen
        case .performance: kindLabel.textColor = .systemOrange
        case .unknown: kindLabel.textColor = .secondaryLabelColor
        }
        let kindName: String
        switch reading.kind {
        case .efficiency: kindName = localizer.text(.efficiency)
        case .performance: kindName = localizer.text(.performance)
        case .unknown: kindName = localizer.text(.unknown)
        }
        kindLabel.setAccessibilityLabel(kindName)
        valueLabel.stringValue = MetricFormatting.percent(reading.utilization)
        valueLabel.textColor = MetricStatusPalette.cpu(normalizedPercent: reading.utilization)
        setAccessibilityLabel(
            "\(localizer.text(.core)) \(reading.id), \(kindName), \(MetricFormatting.percent(reading.utilization))"
        )
    }
}
