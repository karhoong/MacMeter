import AppKit
import Combine

@MainActor
final class NativeSettingsViewController: NSTabViewController {
    static let contentSize = NSSize(width: 560, height: 430)

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
    private let languagePopup = NSPopUpButton()
    private let launchAtLoginToggle = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let loginStatusLabel = NSTextField(labelWithString: "")
    private let loginErrorLabel = NSTextField(wrappingLabelWithString: "")
    private let openLoginSettingsButton = NSButton(title: "Open Login Items Settings", target: nil, action: nil)

    private let updateRates: [TimeInterval] = [1, 2, 5, 10]
    private var renderedLanguage: AppLanguage?

    init(
        settings: SettingsStore,
        loginItem: LoginItemManager,
        appVersion: AppVersionInfo = .current
    ) {
        self.settings = settings
        self.loginItem = loginItem
        self.appVersion = appVersion
        super.init(nibName: nil, bundle: nil)
        title = settings.localizer.text(.settingsWindowTitle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        preferredContentSize = Self.contentSize
        configureControls()
        rebuildLocalizedInterface()
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
            toggle.setButtonType(.switch)
        }

        cpuScalePopup.target = self
        cpuScalePopup.action = #selector(cpuScaleChanged(_:))
        cpuScalePopup.identifier = NSUserInterfaceItemIdentifier("settings.cpu.scale")
        cpuScalePopup.setAccessibilityLabel("CPU menu-bar value")

        configureSegmentedControl(temperatureUnitControl, count: TemperatureUnit.allCases.count, action: #selector(temperatureUnitChanged(_:)))
        temperatureUnitControl.identifier = NSUserInterfaceItemIdentifier("settings.temperature.unit")

        configureSegmentedControl(networkUnitControl, count: NetworkUnit.allCases.count, action: #selector(networkUnitChanged(_:)))
        networkUnitControl.identifier = NSUserInterfaceItemIdentifier("settings.network.unit")

        configureSegmentedControl(displayModeControl, count: DisplayMode.allCases.count, action: #selector(displayModeChanged(_:)))
        displayModeControl.identifier = NSUserInterfaceItemIdentifier("settings.display.mode")

        updateRatePopup.target = self
        updateRatePopup.action = #selector(updateRateChanged(_:))
        updateRatePopup.identifier = NSUserInterfaceItemIdentifier("settings.update.rate")

        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        languagePopup.identifier = NSUserInterfaceItemIdentifier("settings.language")

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

    private func configureSegmentedControl(_ control: NSSegmentedControl, count: Int, action: Selector) {
        control.segmentCount = count
        control.trackingMode = .selectOne
        control.target = self
        control.action = action
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func makeMetricsTab() -> NSViewController {
        let l = settings.localizer
        let stack = tabStack()
        stack.addArrangedSubview(settingsCard(
            title: l.text(.visibleMetrics),
            symbolName: "eye",
            views: [cpuToggle, temperatureToggle, networkToggle, batteryToggle]
        ))
        stack.addArrangedSubview(settingsCard(
            title: l.text(.displayValues),
            symbolName: "textformat.123",
            views: [
                settingRow(label: l.text(.cpuConvention), control: cpuScalePopup),
                settingRow(label: l.text(.temperature), control: temperatureUnitControl),
                settingRow(label: l.text(.networkUnit), control: networkUnitControl)
            ]
        ))
        return tabController(stack: stack)
    }

    private func makeAppearanceTab() -> NSViewController {
        let l = settings.localizer
        let stack = tabStack()
        let explanation = NSTextField(wrappingLabelWithString: l.text(.layoutExplanation))
        explanation.textColor = .secondaryLabelColor
        explanation.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        explanation.maximumNumberOfLines = 3
        stack.addArrangedSubview(settingsCard(
            title: l.text(.menuBarLayout),
            symbolName: "rectangle.split.2x1",
            views: [
                settingRow(label: l.text(.displayMode), control: displayModeControl),
                explanation
            ]
        ))
        return tabController(stack: stack)
    }

    private func makeGeneralTab() -> NSViewController {
        let l = settings.localizer
        let stack = tabStack()
        stack.addArrangedSubview(settingsCard(
            title: l.text(.sampling),
            symbolName: "clock.arrow.circlepath",
            views: [settingRow(label: l.text(.updateRate), control: updateRatePopup)]
        ))
        stack.addArrangedSubview(settingsCard(
            title: l.text(.language),
            symbolName: "globe",
            views: [settingRow(label: l.text(.interfaceLanguage), control: languagePopup)]
        ))
        stack.addArrangedSubview(settingsCard(
            title: l.text(.startup),
            symbolName: "power",
            views: [launchAtLoginToggle, loginStatusLabel, loginErrorLabel, openLoginSettingsButton]
        ))
        return tabController(stack: stack)
    }

    private func makeAboutTab() -> NSViewController {
        let l = settings.localizer
        let content = tabStack(alignment: .centerX, spacing: 12)
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("MacMeter")
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72)
        ])
        let name = NSTextField(labelWithString: "MacMeter")
        name.font = .boldSystemFont(ofSize: 20)
        let version = NSTextField(labelWithString: l.version(appVersion))
        let privacy = NSTextField(wrappingLabelWithString: l.text(.privacy))
        privacy.alignment = .center
        privacy.textColor = .secondaryLabelColor
        privacy.maximumNumberOfLines = 4
        let platform = NSTextField(labelWithString: l.text(.platform))
        platform.textColor = .secondaryLabelColor
        platform.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        [icon, name, version, privacy, platform].forEach(content.addArrangedSubview)
        privacy.widthAnchor.constraint(lessThanOrEqualToConstant: 420).isActive = true
        let card = NSBox()
        card.boxType = .custom
        card.titlePosition = .noTitle
        card.borderWidth = 0.5
        card.borderColor = NSColor.separatorColor.withAlphaComponent(0.55)
        card.cornerRadius = 10
        card.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.60)
        card.contentViewMargins = NSSize(width: 18, height: 18)
        content.translatesAutoresizingMaskIntoConstraints = false
        card.contentView?.addSubview(content)
        if let contentView = card.contentView {
            NSLayoutConstraint.activate([
                content.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                content.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                content.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 48),
                content.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -48),
                content.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
                content.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
            ])
        }
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        let stack = tabStack()
        stack.addArrangedSubview(card)
        return tabController(stack: stack)
    }

    private func addTab(label: String, symbolName: String, viewController: NSViewController) {
        let item = NSTabViewItem(viewController: viewController)
        item.label = label
        item.image = symbol(symbolName, pointSize: 16)
        viewController.title = label
        addTabViewItem(item)
    }

    private func tabController(stack: NSStackView, centerVertically: Bool = false) -> NSViewController {
        let controller = NSViewController()
        controller.preferredContentSize = Self.contentSize
        let container = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))
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
        if !centerVertically {
            for arrangedView in stack.arrangedSubviews {
                arrangedView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
        controller.view = container
        return controller
    }

    private func tabStack(
        alignment: NSLayoutConstraint.Attribute = .leading,
        spacing: CGFloat = 12
    ) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = alignment
        stack.spacing = spacing
        return stack
    }

    private func settingRow(label: String, control: NSView) -> NSStackView {
        let title = NSTextField(wrappingLabelWithString: label)
        title.textColor = .secondaryLabelColor
        title.maximumNumberOfLines = 2
        title.widthAnchor.constraint(equalToConstant: 145).isActive = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [title, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return row
    }

    private func settingsCard(title: String, symbolName: String, views: [NSView]) -> NSBox {
        let card = NSBox()
        card.boxType = .custom
        card.titlePosition = .noTitle
        card.borderWidth = 0.5
        card.borderColor = NSColor.separatorColor.withAlphaComponent(0.55)
        card.cornerRadius = 10
        card.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.60)
        card.contentViewMargins = NSSize(width: 14, height: 12)

        let icon = NSImageView(image: symbol(symbolName, pointSize: 14))
        icon.contentTintColor = .controlAccentColor
        icon.setAccessibilityElement(false)
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let header = NSStackView(views: [icon, heading])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 7

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.addArrangedSubview(header)
        for view in views {
            content.addArrangedSubview(view)
            view.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor).isActive = true
            if view is NSStackView || view is NSTextField {
                view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            }
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        card.contentView?.addSubview(content)
        if let contentView = card.contentView {
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                content.topAnchor.constraint(equalTo: contentView.topAnchor),
                content.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
        return card
    }

    private func symbol(_ name: String, pointSize: CGFloat = 13) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        return image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        ) ?? image
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
        if renderedLanguage != settings.language {
            rebuildLocalizedInterface()
        }
        cpuToggle.state = settings.cpuEnabled ? .on : .off
        temperatureToggle.state = settings.temperatureEnabled ? .on : .off
        networkToggle.state = settings.networkEnabled ? .on : .off
        batteryToggle.state = settings.batteryEnabled ? .on : .off
        cpuScalePopup.selectItem(at: CPUScale.allCases.firstIndex(of: settings.cpuScale) ?? 0)
        temperatureUnitControl.selectedSegment = TemperatureUnit.allCases.firstIndex(of: settings.temperatureUnit) ?? 0
        networkUnitControl.selectedSegment = NetworkUnit.allCases.firstIndex(of: settings.networkUnit) ?? 0
        displayModeControl.selectedSegment = DisplayMode.allCases.firstIndex(of: settings.displayMode) ?? 0
        updateRatePopup.selectItem(at: updateRates.firstIndex(of: settings.updateInterval) ?? 1)
        languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: settings.language) ?? 0)
        launchAtLoginToggle.state = loginItem.isEnabled ? .on : .off
        loginStatusLabel.stringValue = localizedLoginStatus()
        loginErrorLabel.stringValue = loginItem.errorMessage ?? ""
        loginErrorLabel.isHidden = loginItem.errorMessage == nil
        openLoginSettingsButton.isHidden = loginItem.status != .requiresApproval
    }

    private func rebuildLocalizedInterface() {
        let selectedIndex = max(0, min(selectedTabViewItemIndex, 3))
        renderedLanguage = settings.language
        let l = settings.localizer
        title = l.text(.settingsWindowTitle)
        relocalizeControls(using: l)
        while let first = tabViewItems.first {
            removeTabViewItem(first)
        }
        addTab(label: l.text(.metrics), symbolName: "gauge.medium", viewController: makeMetricsTab())
        addTab(label: l.text(.appearance), symbolName: "paintbrush", viewController: makeAppearanceTab())
        addTab(label: l.text(.general), symbolName: "gearshape", viewController: makeGeneralTab())
        addTab(label: l.text(.about), symbolName: "info.circle", viewController: makeAboutTab())
        selectedTabViewItemIndex = selectedIndex
        view.window?.title = l.text(.settingsWindowTitle)
    }

    private func relocalizeControls(using l: Localizer) {
        cpuToggle.title = l.text(.cpuUsage)
        temperatureToggle.title = l.text(.socTemperature)
        networkToggle.title = l.text(.networkSpeed)
        batteryToggle.title = l.text(.batteryPower)
        launchAtLoginToggle.title = l.text(.launchAtLogin)
        openLoginSettingsButton.title = l.text(.openLoginSettings)

        cpuScalePopup.removeAllItems()
        cpuScalePopup.addItems(withTitles: [l.text(.overallConvention), l.text(.allCoresConvention)])
        cpuScalePopup.setAccessibilityLabel(l.text(.cpuConvention))

        temperatureUnitControl.setLabel("\(l.text(.celsius)) (°C)", forSegment: 0)
        temperatureUnitControl.setLabel("\(l.text(.fahrenheit)) (°F)", forSegment: 1)
        temperatureUnitControl.setAccessibilityLabel(l.text(.temperature))
        for (index, unit) in NetworkUnit.allCases.enumerated() {
            networkUnitControl.setLabel(unit.rawValue, forSegment: index)
        }
        networkUnitControl.setAccessibilityLabel(l.text(.networkUnit))
        displayModeControl.setLabel(l.text(.compact), forSegment: 0)
        displayModeControl.setLabel(l.text(.cycle), forSegment: 1)
        displayModeControl.setAccessibilityLabel(l.text(.displayMode))

        updateRatePopup.removeAllItems()
        updateRatePopup.addItems(withTitles: updateRates.map(l.updateRate))
        updateRatePopup.setAccessibilityLabel(l.text(.updateRate))
        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: AppLanguage.allCases.map(l.languageTitle))
        languagePopup.setAccessibilityLabel(l.text(.interfaceLanguage))
    }

    private func localizedLoginStatus() -> String {
        let l = settings.localizer
        switch loginItem.status {
        case .enabled: return l.text(.enabled)
        case .requiresApproval: return l.text(.approvalRequired)
        case .notRegistered: return l.text(.disabled)
        case .notFound: return l.text(.installRequired)
        @unknown default: return l.text(.unknown)
        }
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

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard AppLanguage.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        settings.language = AppLanguage.allCases[sender.indexOfSelectedItem]
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        loginItem.setEnabled(sender.state == .on)
    }

    @objc private func openLoginSettings(_ sender: Any?) {
        loginItem.openSystemSettings()
    }
}
