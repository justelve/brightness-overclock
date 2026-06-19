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

    func testLowPowerModeBlocksEvenWhenBatteryBoostIsAlwaysAllowed() {
        let status = BatteryStatus(
            powerSource: .battery,
            batteryPresent: true,
            percentage: 80,
            lowPowerModeEnabled: true
        )

        let decision = BatteryBoostAuthorizer.decision(
            policy: .alwaysAllowOnBattery,
            thresholdPercentage: 30,
            status: status
        )

        XCTAssertFalse(decision.isAllowed)
        XCTAssertEqual(decision.reason, "Boost is disabled in Low Power Mode.")
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

    func testBatteryStatusMenuDescriptionShowsPowerAndLowPowerMode() {
        XCTAssertEqual(
            BatteryStatus(powerSource: .battery, batteryPresent: true, percentage: 42).menuDescription,
            "Battery: 42%"
        )
        XCTAssertEqual(
            BatteryStatus(
                powerSource: .battery,
                batteryPresent: true,
                percentage: 42,
                lowPowerModeEnabled: true
            ).menuDescription,
            "Battery: 42% · Low Power Mode"
        )
        XCTAssertEqual(
            BatteryStatus(powerSource: .ac, batteryPresent: true, percentage: 90).menuDescription,
            "Power: AC · Battery: 90%"
        )
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

    func testControllerDisablesAndRestoresBoostForLowPowerMode() {
        let suiteName = "BatteryBoostLowPowerControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = BatteryBoostSettings(defaults: defaults)
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6
        state.boostLevel = 1.4
        var lowPowerModeEnabled = true

        let controller = BatteryBoostController(
            state: state,
            settings: settings,
            statusProvider: {
                BatteryStatus(
                    powerSource: .battery,
                    batteryPresent: true,
                    percentage: 80,
                    lowPowerModeEnabled: lowPowerModeEnabled
                )
            }
        )
        controller.start()
        defer { controller.stop() }

        XCTAssertEqual(state.boostLevel, 1.0, accuracy: 1e-9)
        XCTAssertFalse(state.isBoostAllowed)
        XCTAssertEqual(state.boostBlockReason, "Boost is disabled in Low Power Mode.")

        lowPowerModeEnabled = false
        controller.refresh()

        XCTAssertEqual(state.boostLevel, 1.4, accuracy: 1e-9)
        XCTAssertTrue(state.isBoostAllowed)
    }

    func testControllerPublishesCurrentBatteryStatusForMenuDisplay() {
        let suiteName = "BatteryBoostStatusDisplayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = BatteryBoostSettings(defaults: defaults)
        let state = BoostState(defaults: defaults)
        let controller = BatteryBoostController(
            state: state,
            settings: settings,
            statusProvider: {
                BatteryStatus(
                    powerSource: .battery,
                    batteryPresent: true,
                    percentage: 42,
                    lowPowerModeEnabled: true
                )
            }
        )

        controller.start()
        defer { controller.stop() }

        XCTAssertEqual(settings.currentStatus.menuDescription, "Battery: 42% · Low Power Mode")
    }
}
