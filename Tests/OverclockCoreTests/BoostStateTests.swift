import XCTest
@testable import OverclockCore

final class BoostStateTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "BoostStateTests")!
        defaults.removePersistentDomain(forName: "BoostStateTests")
    }

    func testFreshStateIsNotBoosted() {
        let state = BoostState(defaults: defaults)
        XCTAssertEqual(state.boostLevel, 1.0)
        XCTAssertFalse(state.isBoosted)
    }

    func testToggleOnFirstUseGoesToMaxFactor() {
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6
        state.toggleOn()
        XCTAssertEqual(state.boostLevel, 1.6, accuracy: 1e-9)
        XCTAssertTrue(state.isBoosted)
    }

    func testToggleOffKillsBoostAndRemembersLevel() {
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6
        state.boostLevel = 1.3
        state.toggleOff()
        XCTAssertEqual(state.boostLevel, 1.0)
        state.toggleOn()
        XCTAssertEqual(state.boostLevel, 1.3, accuracy: 1e-9)
    }

    func testToggleOnClampsRememberedLevelToMaxFactor() {
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6
        state.boostLevel = 1.6
        state.toggleOff()
        state.maxFactor = 1.4 // headroom shrank
        state.toggleOn()
        XCTAssertEqual(state.boostLevel, 1.4, accuracy: 1e-9)
    }

    func testStepUpAndDownUseBoostMath() {
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6
        state.stepUp()
        XCTAssertEqual(state.boostLevel, BoostMath.level(forStep: 1, maxFactor: 1.6), accuracy: 1e-9)
        state.stepDown()
        XCTAssertEqual(state.boostLevel, 1.0, accuracy: 1e-9)
    }

    func testPersistenceRoundTrip() {
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6
        state.boostLevel = 1.45
        let reloaded = BoostState(defaults: defaults)
        XCTAssertEqual(reloaded.boostLevel, 1.45, accuracy: 1e-9)
        reloaded.toggleOff()
        let reloadedAgain = BoostState(defaults: defaults)
        XCTAssertEqual(reloadedAgain.boostLevel, 1.0)
        reloadedAgain.maxFactor = 1.6
        reloadedAgain.toggleOn()
        XCTAssertEqual(reloadedAgain.boostLevel, 1.45, accuracy: 1e-9)
    }

    func testMaxFactorBelowOneIsClampedAndCannotBreakInvariant() {
        let state = BoostState(defaults: defaults)
        state.boostLevel = 1.3
        state.maxFactor = 0.5 // bogus headroom reading
        state.toggleOff()
        state.toggleOn()
        XCTAssertEqual(state.boostLevel, 1.0, accuracy: 1e-9) // clamped maxFactor of 1.0 wins
        XCTAssertGreaterThanOrEqual(state.boostLevel, 1.0)
    }

    func testToggleOnTwiceIsIdempotent() {
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6
        state.boostLevel = 1.3
        state.toggleOn()
        let levelAfterFirst = state.boostLevel
        state.toggleOn()
        XCTAssertEqual(state.boostLevel, levelAfterFirst, accuracy: 1e-9)
    }

    func testBlockingBoostTurnsOffAndPreventsReenabling() {
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6
        state.boostLevel = 1.4

        state.setBoostDecision(.blocked("Battery too low"))

        XCTAssertEqual(state.boostLevel, 1.0, accuracy: 1e-9)
        XCTAssertFalse(state.isBoostAllowed)
        XCTAssertEqual(state.boostBlockReason, "Battery too low")

        state.toggleOn()
        XCTAssertEqual(state.boostLevel, 1.0, accuracy: 1e-9)

        state.setBoostDecision(.allowed)
        state.toggleOn()
        XCTAssertEqual(state.boostLevel, 1.4, accuracy: 1e-9)
    }

    func testBoostBlockedByBatteryRestoresWhenAllowedAgain() {
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6
        state.boostLevel = 1.4

        state.setBoostDecision(.blocked("Battery too low"))
        state.setBoostDecision(.blocked("Battery too low")) // repeated battery notifications should not forget restore intent
        state.setBoostDecision(.allowed)

        XCTAssertEqual(state.boostLevel, 1.4, accuracy: 1e-9)
        XCTAssertTrue(state.isBoostAllowed)
        XCTAssertNil(state.boostBlockReason)
    }

    func testBatteryAllowDoesNotEnableBoostIfItWasAlreadyOff() {
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6

        state.setBoostDecision(.blocked("Battery too low"))
        state.setBoostDecision(.allowed)

        XCTAssertEqual(state.boostLevel, 1.0, accuracy: 1e-9)
    }

    func testManualBoostStepTurnsOnToChosenStep() {
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6

        state.setBoostStep(4)

        XCTAssertEqual(state.currentBoostStep, 4)
        XCTAssertEqual(state.boostLevel, BoostMath.level(forStep: 4, maxFactor: 1.6), accuracy: 1e-9)
        XCTAssertTrue(state.isBoosted)
    }

    func testManualBoostStepIsBlockedByBatteryPolicy() {
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6
        state.setBoostDecision(.blocked("Battery too low"))

        state.setBoostStep(4)

        XCTAssertEqual(state.boostLevel, 1.0, accuracy: 1e-9)
        XCTAssertEqual(state.currentBoostStep, 0)
    }
}
