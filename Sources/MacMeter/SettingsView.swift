import SwiftUI

struct MacMeterSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var loginItem: LoginItemManager

    var body: some View {
        TabView {
            metricsTab
                .tabItem { Label("Metrics", systemImage: "gauge.with.dots.needle.50percent") }
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "menubar.rectangle") }
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(18)
        .frame(width: 520, height: 360)
        .onAppear { loginItem.refresh() }
    }

    private var metricsTab: some View {
        Form {
            Section("Visible metrics") {
                Toggle("CPU usage", isOn: $settings.cpuEnabled)
                Toggle("SoC temperature", isOn: $settings.temperatureEnabled)
                Toggle("Network speed", isOn: $settings.networkEnabled)
                Toggle("Battery power", isOn: $settings.batteryEnabled)
            }
            Section("CPU") {
                Picker("Menu-bar value", selection: $settings.cpuScale) {
                    ForEach(CPUScale.allCases) { scale in Text(scale.title).tag(scale) }
                }
            }
            Section("Network") {
                Picker("Unit", selection: $settings.networkUnit) {
                    ForEach(NetworkUnit.allCases) { unit in Text(unit.rawValue).tag(unit) }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceTab: some View {
        Form {
            Picker("Display mode", selection: $settings.displayMode) {
                ForEach(DisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.radioGroup)
            Text("Cycle mode rotates through enabled metrics every five seconds.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Picker("Update rate", selection: $settings.updateInterval) {
                Text("1 second").tag(1.0)
                Text("2 seconds").tag(2.0)
                Text("5 seconds").tag(5.0)
                Text("10 seconds").tag(10.0)
            }
            Toggle("Launch at Login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))
            Text(loginItem.statusText).font(.caption).foregroundStyle(.secondary)
            if let error = loginItem.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if loginItem.status == .requiresApproval {
                Button("Open Login Items Settings") { loginItem.openSystemSettings() }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 48)).foregroundStyle(.tint)
            Text("MacMeter").font(.title2.bold())
            Text("Version \(version) (\(build))")
            Text("Private by design: MacMeter reads local system counters and makes no network requests.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("Apple Silicon · macOS 13+").font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
}
