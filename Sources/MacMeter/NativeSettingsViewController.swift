import AppKit
import Combine

@MainActor
final class NativeSettingsViewController: NSTabViewController {
    private let settings: SettingsStore
    private let loginItem: LoginItemManager
    private let appVersion: AppVersionInfo
    private var cancellables = Set<AnyCancellable>()

    private let cpuToggle = NSButton(checkboxWithTitle: "CPU usage", target: nil, action: nil)
    private let temperatureToggle = NSButton(checkboxWithTitle: "SoC temperature", target: nil, action: nil)
    private let networkToggle = NSButton(checkboxWithTitle: "Network speed", target: nil, action: nil)
    private let batteryToggle = NSButton(checkboxWithTitle: "Battery power", target: nil, action: nil)
    private let cpuScalePopup = NSPopUpButton()
    private let temperatureUnitControl = NSSegmentedControl()
    private let networkUnitControl = NSSegmentedControl()
    private let displayModeControl = NSSegmentedControl()
    private let updateRatePopup = NSPopUpButton()
    private let launchAtLoginToggle = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let loginStatusLabel = NSTextField(labelWithString: "")
    private let loginErrorLabel = NSTextField(wrappingLabelWithString: "")
    private let openLoginSettingsButton = NSButton(title: "Open Login Items Settings", target: nil, action: nil)

    private let updateRates: [TimeInterval] = [1, 2, 5, 10]

    init(
        settings: SettingsStore,
        loginItem: LoginItemManager,
        appVersion: AppVersionInfo = .current
    ) {
        self.settings = settings
        self.loginItem = loginItem
        self.appVersion = appVersion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        preferredContentSize = NSSize(width: 520, height: 360)
        configureControls()
        addTab(label: "Metrics", viewController: makeMetricsTab())
        addTab(label: "Appearance", viewController: makeAppearanceTab())
        addTab(label: "General", viewController: makeGeneralTab())
        addTab(label: "About", viewController: makeAboutTab())
        observeStores()
        syncControls()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        loginItem.refresh()
        syncControls()
    }

    private func configureControls() {
        cpuToggle.identifier = NSUserInterfaceItemIdentifier("settings.cpu.enabled")
        temperatureToggle.identifier = NSUserInterfaceItemIdentifier("settings.temperature.enabled")
        networkToggle.identifier = NSUserInterfaceItemIdentifier("settings.network.enabled")
        batteryToggle.identifier = NSUserInterfaceItemIdentifier("settings.battery.enabled")
        for toggle in [cpuToggle, temperatureToggle, networkToggle, batteryToggle] {
            toggle.target = self
            toggle.action = #selector(metricToggleChanged(_:))
        }

        CPUScale.allCases.forEach { cpuScalePopup.addItem(withTitle: $0.title) }
        cpuScalePopup.target = self
        cpuScalePopup.action = #selector(cpuScaleChanged(_:))
        cpuScalePopup.identifier = NSUserInterfaceItemIdentifier("settings.cpu.scale")
        cpuScalePopup.setAccessibilityLabel("CPU menu-bar value")

        configureSegmentedControl(
            temperatureUnitControl,
            labels: TemperatureUnit.allCases.map { "\($0.title) (\($0.symbol))" },
            action: #selector(temperatureUnitChanged(_:))
        )
        temperatureUnitControl.setAccessibilityLabel("Temperature unit")
        temperatureUnitControl.identifier = NSUserInterfaceItemIdentifier("settings.temperature.unit")

        configureSegmentedControl(
            networkUnitControl,
            labels: NetworkUnit.allCases.map(\.rawValue),
            action: #selector(networkUnitChanged(_:))
        )
        networkUnitControl.setAccessibilityLabel("Network unit")
        networkUnitControl.identifier = NSUserInterfaceItemIdentifier("settings.network.unit")

        configureSegmentedControl(
            displayModeControl,
            labels: DisplayMode.allCases.map(\.title),
            action: #selector(displayModeChanged(_:))
        )
        displayModeControl.setAccessibilityLabel("Display mode")
        displayModeControl.identifier = NSUserInterfaceItemIdentifier("settings.display.mode")

        updateRates.forEach { interval in
            updateRatePopup.addItem(withTitle: interval == 1 ? "1 second" : "\(Int(interval)) seconds")
        }
        updateRatePopup.target = self
        updateRatePopup.action = #selector(updateRateChanged(_:))
        updateRatePopup.identifier = NSUserInterfaceItemIdentifier("settings.update.rate")
        updateRatePopup.setAccessibilityLabel("Update rate")

        launchAtLoginToggle.target = self
        launchAtLoginToggle.action = #selector(launchAtLoginChanged(_:))
        launchAtLoginToggle.identifier = NSUserInterfaceItemIdentifier("settings.launch.at.login")
        loginStatusLabel.textColor = .secondaryLabelColor
        loginStatusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        loginErrorLabel.textColor = .systemRed
        loginErrorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        loginErrorLabel.maximumNumberOfLines = 3
        openLoginSettingsButton.target = self
        openLoginSettingsButton.action = #selector(openLoginSettings(_:))
    }

    private func configureSegmentedControl(
        _ control: NSSegmentedControl,
        labels: [String],
        action: Selector
    ) {
        control.segmentCount = labels.count
        control.trackingMode = .selectOne
        control.target = self
        control.action = action
        for (index, label) in labels.enumerated() {
            control.setLabel(label, forSegment: index)
        }
    }

    private func makeMetricsTab() -> NSViewController {
        let stack = tabStack()
        stack.addArrangedSubview(sectionLabel("Visible metrics"))
        [cpuToggle, temperatureToggle, networkToggle, batteryToggle].forEach(stack.addArrangedSubview)
        stack.addArrangedSubview(sectionSpacer())
        stack.addArrangedSubview(sectionLabel("CPU"))
        stack.addArrangedSubview(settingRow(label: "Menu-bar value", control: cpuScalePopup))
        stack.addArrangedSubview(sectionLabel("Temperature"))
        stack.addArrangedSubview(settingRow(label: "Unit", control: temperatureUnitControl))
        stack.addArrangedSubview(sectionLabel("Network"))
        stack.addArrangedSubview(settingRow(label: "Unit", control: networkUnitControl))
        return tabController(stack: stack)
    }

    private func makeAppearanceTab() -> NSViewController {
        let stack = tabStack()
        stack.addArrangedSubview(sectionLabel("Display mode"))
        stack.addArrangedSubview(displayModeControl)
        let explanation = NSTextField(wrappingLabelWithString:
            "Compact shows every enabled metric. Cycle rotates through them every five seconds."
        )
        explanation.textColor = .secondaryLabelColor
        explanation.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        stack.addArrangedSubview(explanation)
        return tabController(stack: stack)
    }

    private func makeGeneralTab() -> NSViewController {
        let stack = tabStack()
        stack.addArrangedSubview(sectionLabel("Sampling"))
        stack.addArrangedSubview(settingRow(label: "Update rate", control: updateRatePopup))
        stack.addArrangedSubview(sectionSpacer())
        stack.addArrangedSubview(sectionLabel("Startup"))
        stack.addArrangedSubview(launchAtLoginToggle)
        stack.addArrangedSubview(loginStatusLabel)
        stack.addArrangedSubview(loginErrorLabel)
        stack.addArrangedSubview(openLoginSettingsButton)
        return tabController(stack: stack)
    }

    private func makeAboutTab() -> NSViewController {
        let stack = tabStack(alignment: .centerX, spacing: 12)
        let icon = NSImageView(image: NSImage(
            systemSymbolName: "gauge.with.dots.needle.50percent",
            accessibilityDescription: "MacMeter"
        ) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        let name = NSTextField(labelWithString: "MacMeter")
        name.font = .boldSystemFont(ofSize: 20)
        let version = NSTextField(labelWithString: appVersion.displayLabel)
        let privacy = NSTextField(wrappingLabelWithString:
            "Private by design: MacMeter reads local system counters and makes no network requests."
        )
        privacy.alignment = .center
        privacy.textColor = .secondaryLabelColor
        privacy.maximumNumberOfLines = 2
        let platform = NSTextField(labelWithString: "Apple Silicon · macOS 13+")
        platform.textColor = .secondaryLabelColor
        platform.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        [icon, name, version, privacy, platform].forEach(stack.addArrangedSubview)
        privacy.widthAnchor.constraint(lessThanOrEqualToConstant: 420).isActive = true
        return tabController(stack: stack, centerVertically: true)
    }

    private func addTab(label: String, viewController: NSViewController) {
        let item = NSTabViewItem(viewController: viewController)
        item.label = label
        addTabViewItem(item)
    }

    private func tabController(stack: NSStackView, centerVertically: Bool = false) -> NSViewController {
        let controller = NSViewController()
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        var constraints = [
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)
        ]
        if centerVertically {
            constraints.append(stack.centerYAnchor.constraint(equalTo: container.centerYAnchor))
        } else {
            constraints.append(stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 22))
            constraints.append(stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -18))
        }
        NSLayoutConstraint.activate(constraints)
        controller.view = container
        return controller
    }

    private func tabStack(
        alignment: NSLayoutConstraint.Attribute = .leading,
        spacing: CGFloat = 8
    ) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = alignment
        stack.spacing = spacing
        return stack
    }

    private func settingRow(label: String, control: NSView) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.widthAnchor.constraint(equalToConstant: 130).isActive = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [title, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.widthAnchor.constraint(greaterThanOrEqualToConstant: 450).isActive = true
        return row
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    private func sectionSpacer() -> NSView {
        let spacer = NSView()
        spacer.heightAnchor.constraint(equalToConstant: 3).isActive = true
        return spacer
    }

    private func observeStores() {
        settings.objectWillChange.sink { [weak self] in
            Task { @MainActor in
                await Task.yield()
                self?.syncControls()
            }
        }.store(in: &cancellables)
        loginItem.objectWillChange.sink { [weak self] in
            Task { @MainActor in
                await Task.yield()
                self?.syncControls()
            }
        }.store(in: &cancellables)
    }

    private func syncControls() {
        cpuToggle.state = settings.cpuEnabled ? .on : .off
        temperatureToggle.state = settings.temperatureEnabled ? .on : .off
        networkToggle.state = settings.networkEnabled ? .on : .off
        batteryToggle.state = settings.batteryEnabled ? .on : .off
        cpuScalePopup.selectItem(at: CPUScale.allCases.firstIndex(of: settings.cpuScale) ?? 0)
        temperatureUnitControl.selectedSegment = TemperatureUnit.allCases.firstIndex(of: settings.temperatureUnit) ?? 0
        networkUnitControl.selectedSegment = NetworkUnit.allCases.firstIndex(of: settings.networkUnit) ?? 0
        displayModeControl.selectedSegment = DisplayMode.allCases.firstIndex(of: settings.displayMode) ?? 0
        updateRatePopup.selectItem(at: updateRates.firstIndex(of: settings.updateInterval) ?? 1)
        launchAtLoginToggle.state = loginItem.isEnabled ? .on : .off
        loginStatusLabel.stringValue = loginItem.statusText
        loginErrorLabel.stringValue = loginItem.errorMessage ?? ""
        loginErrorLabel.isHidden = loginItem.errorMessage == nil
        openLoginSettingsButton.isHidden = loginItem.status != .requiresApproval
    }

    @objc private func metricToggleChanged(_ sender: NSButton) {
        switch sender {
        case cpuToggle: settings.cpuEnabled = sender.state == .on
        case temperatureToggle: settings.temperatureEnabled = sender.state == .on
        case networkToggle: settings.networkEnabled = sender.state == .on
        case batteryToggle: settings.batteryEnabled = sender.state == .on
        default: break
        }
    }

    @objc private func cpuScaleChanged(_ sender: NSPopUpButton) {
        guard CPUScale.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.cpuScale = CPUScale.allCases[sender.indexOfSelectedItem]
    }

    @objc private func temperatureUnitChanged(_ sender: NSSegmentedControl) {
        guard TemperatureUnit.allCases.indices.contains(sender.selectedSegment) else { return }
        settings.temperatureUnit = TemperatureUnit.allCases[sender.selectedSegment]
    }

    @objc private func networkUnitChanged(_ sender: NSSegmentedControl) {
        guard NetworkUnit.allCases.indices.contains(sender.selectedSegment) else { return }
        settings.networkUnit = NetworkUnit.allCases[sender.selectedSegment]
    }

    @objc private func displayModeChanged(_ sender: NSSegmentedControl) {
        guard DisplayMode.allCases.indices.contains(sender.selectedSegment) else { return }
        settings.displayMode = DisplayMode.allCases[sender.selectedSegment]
    }

    @objc private func updateRateChanged(_ sender: NSPopUpButton) {
        guard updateRates.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.updateInterval = updateRates[sender.indexOfSelectedItem]
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        loginItem.setEnabled(sender.state == .on)
    }

    @objc private func openLoginSettings(_ sender: Any?) {
        loginItem.openSystemSettings()
    }
}
