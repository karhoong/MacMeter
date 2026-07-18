import Foundation
import ServiceManagement

@MainActor
protocol LoginItemServicing: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
final class SystemLoginItemService: LoginItemServicing {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var errorMessage: String?
    private let service: LoginItemServicing

    init(service: LoginItemServicing = SystemLoginItemService()) {
        self.service = service
        status = service.status
    }

    var isEnabled: Bool { status == .enabled }

    var statusText: String {
        switch status {
        case .enabled: return "Enabled"
        case .requiresApproval: return "Approval required in System Settings"
        case .notRegistered: return "Disabled"
        case .notFound: return "App must be installed before enabling"
        @unknown default: return "Unknown"
        }
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
        if enabled && status == .requiresApproval {
            service.openSystemSettings()
        }
    }

    func refresh() {
        status = service.status
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
