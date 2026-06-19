import XCTest
@testable import OverclockCore

final class BatteryBoostPolicyTests: XCTestCase {
    func testAlwaysAllowPolicyAllowsBoostOnBattery() {
        let status = BatteryStatus(powerSource: .battery, batteryPresent: true, percentage: 5)

        let decision = BatteryBoostAuthorizer.decision(
            policy: .alwaysAllowOnBattery,
            thresholdPercentage: 30,
            status: status
        )

        XCTAssertTrue(decision.isAllowed)
    }

    func testNeverAllowPolicyBlocksBoostOnlyOnBattery() {
        let battery = BatteryStatus(powerSource: .battery, batteryPresent: true, percentage: 80)
        let ac = BatteryStatus(powerSource: .ac, batteryPresent: true, percentage: 80)

        XCTAssertFalse(BatteryBoostAuthorizer.decision(
            policy: .neverAllowOnBattery,
            thresholdPercentage: 30,
            status: battery
        ).isAllowed)
        XCTAssertTrue(BatteryBoostAuthorizer.decision(
            policy: .neverAllowOnBattery,
            thresholdPercentage: 30,
            status: ac
        ).isAllowed)
    }

    func testDisableBelowPercentageBlocksOnlyWhenBatteryIsBelowThreshold() {
        let below = BatteryStatus(powerSource: .battery, batteryPresent: true, percentage: 29)
        let atThreshold = BatteryStatus(powerSource: .battery, batteryPresent: true, percentage: 30)
        let acBelow = BatteryStatus(powerSource: .ac, batteryPresent: true, percentage: 10)

        XCTAssertFalse(BatteryBoostAuthorizer.decision(
            policy: .disableBelowPercentage,
            thresholdPercentage: 30,
            status: below
        ).isAllowed)
        XCTAssertTrue(BatteryBoostAuthorizer.decision(
            policy: .disableBelowPercentage,
            thresholdPercentage: 30,
            status: atThreshold
        ).isAllowed)
        XCTAssertTrue(BatteryBoostAuthorizer.decision(
            policy: .disableBelowPercentage,
            thresholdPercentage: 30,
            status: acBelow
        ).isAllowed)
    }

    func testBatterySettingsNormalizeThresholdsToTenPercentMenuValues() {
        let suiteName = "BatteryBoostSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = BatteryBoostSettings(defaults: defaults)
        XCTAssertEqual(settings.minimumBatteryPercentage, 30)
        XCTAssertEqual(BatteryBoostSettings.allowedMinimumBatteryPercentages, [10, 20, 30, 40, 50, 60, 70, 80, 90, 100])

        settings.setMinimumBatteryPercentage(27)
        XCTAssertEqual(settings.minimumBatteryPercentage, 30)

        settings.setMinimumBatteryPercentage(3)
        XCTAssertEqual(settings.minimumBatteryPercentage, 10)

        settings.setMinimumBatteryPercentage(101)
        XCTAssertEqual(settings.minimumBatteryPercentage, 100)
    }

    func testControllerUsesNewPolicyWhenSettingsChange() {
        let suiteName = "BatteryBoostControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = BatteryBoostSettings(defaults: defaults)
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6
        state.boostLevel = 1.4

        let controller = BatteryBoostController(
            state: state,
            settings: settings,
            statusProvider: { BatteryStatus(powerSource: .battery, batteryPresent: true, percentage: 20) }
        )
        controller.start()
        defer { controller.stop() }

        settings.policy = .disableBelowPercentage
        XCTAssertEqual(state.boostLevel, 1.0, accuracy: 1e-9)
        XCTAssertFalse(state.isBoostAllowed)

        settings.policy = .alwaysAllowOnBattery
        XCTAssertEqual(state.boostLevel, 1.4, accuracy: 1e-9)
        XCTAssertTrue(state.isBoostAllowed)
    }
}
