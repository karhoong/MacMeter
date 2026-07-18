import ServiceManagement
import XCTest
@testable import MacMeter

@MainActor
final class LoginItemManagerTests: XCTestCase {
    func testEnableDisableAndRefreshUseInjectedService() {
        let service = FakeLoginItemService(status: .notRegistered)
        let manager = LoginItemManager(service: service)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(manager.statusText, "Disabled")

        manager.setEnabled(true)
        XCTAssertEqual(service.registerCount, 1)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(manager.statusText, "Enabled")

        manager.setEnabled(false)
        XCTAssertEqual(service.unregisterCount, 1)
        XCTAssertFalse(manager.isEnabled)
    }

    func testApprovalRequiredOpensSettingsAndReportsState() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let manager = LoginItemManager(service: service)

        manager.setEnabled(true)

        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertEqual(manager.statusText, "Approval required in System Settings")
        XCTAssertEqual(service.openSettingsCount, 1)
        manager.openSystemSettings()
        XCTAssertEqual(service.openSettingsCount, 2)
    }

    func testServiceErrorIsIsolatedAndVisible() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.registerError = NSError(domain: "MacMeterTests", code: 7, userInfo: [NSLocalizedDescriptionKey: "Denied fixture"])
        let manager = LoginItemManager(service: service)

        manager.setEnabled(true)

        XCTAssertEqual(manager.errorMessage, "Denied fixture")
        XCTAssertEqual(manager.status, .notRegistered)
        XCTAssertEqual(manager.statusText, "Disabled")
    }

    func testNotFoundStatusText() {
        let manager = LoginItemManager(service: FakeLoginItemService(status: .notFound))
        XCTAssertEqual(manager.statusText, "App must be installed before enabling")
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemServicing {
    var status: SMAppService.Status
    var statusAfterRegister: SMAppService.Status = .enabled
    var registerError: Error?
    var registerCount = 0
    var unregisterCount = 0
    var openSettingsCount = 0

    init(status: SMAppService.Status) { self.status = status }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCount += 1
        status = .notRegistered
    }

    func openSystemSettings() { openSettingsCount += 1 }
}
