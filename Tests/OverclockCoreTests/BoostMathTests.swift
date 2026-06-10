import XCTest
@testable import OverclockCore

final class BoostMathTests: XCTestCase {
    let maxFactor = 1.6

    func testLevelForStepEndpoints() {
        XCTAssertEqual(BoostMath.level(forStep: 0, maxFactor: maxFactor), 1.0, accuracy: 1e-9)
        XCTAssertEqual(BoostMath.level(forStep: 8, maxFactor: maxFactor), 1.6, accuracy: 1e-9)
        XCTAssertEqual(BoostMath.level(forStep: 4, maxFactor: maxFactor), 1.3, accuracy: 1e-9)
    }

    func testLevelForStepClampsOutOfRange() {
        XCTAssertEqual(BoostMath.level(forStep: -3, maxFactor: maxFactor), 1.0, accuracy: 1e-9)
        XCTAssertEqual(BoostMath.level(forStep: 99, maxFactor: maxFactor), 1.6, accuracy: 1e-9)
    }

    func testStepForLevelIsInverseOfLevelForStep() {
        for step in 0...BoostMath.stepCount {
            let level = BoostMath.level(forStep: step, maxFactor: maxFactor)
            XCTAssertEqual(BoostMath.step(forLevel: level, maxFactor: maxFactor), step)
        }
    }

    func testStepUpAndDown() {
        XCTAssertEqual(BoostMath.stepUp(from: 1.0, maxFactor: maxFactor),
                       BoostMath.level(forStep: 1, maxFactor: maxFactor), accuracy: 1e-9)
        XCTAssertEqual(BoostMath.stepUp(from: 1.6, maxFactor: maxFactor), 1.6, accuracy: 1e-9) // clamped
        XCTAssertEqual(BoostMath.stepDown(from: 1.6, maxFactor: maxFactor),
                       BoostMath.level(forStep: 7, maxFactor: maxFactor), accuracy: 1e-9)
        XCTAssertEqual(BoostMath.stepDown(from: 1.0, maxFactor: maxFactor), 1.0, accuracy: 1e-9) // clamped
    }

    func testStepForLevelWithDegenerateMaxFactor() {
        XCTAssertEqual(BoostMath.step(forLevel: 1.0, maxFactor: 1.0), 0)
    }

    func testApproximateNits() {
        XCTAssertEqual(BoostMath.approximateNits(level: 1.0), 1000)
        XCTAssertEqual(BoostMath.approximateNits(level: 1.3), 1300)
        XCTAssertEqual(BoostMath.approximateNits(level: 1.6), 1600)
        XCTAssertEqual(BoostMath.approximateNits(level: 2.4), 1600) // capped
    }

    func testStepUpFromOffGridLevelSnapsToNearestStepFirst() {
        // 1.43 sits between steps 5 (1.375) and 6 (1.45); nearest is 6 -> stepUp lands on 7
        XCTAssertEqual(BoostMath.stepUp(from: 1.43, maxFactor: maxFactor),
                       BoostMath.level(forStep: 7, maxFactor: maxFactor), accuracy: 1e-9)
    }

    func testStepDownFromOffGridLevelSnapsToNearestStepFirst() {
        XCTAssertEqual(BoostMath.stepDown(from: 1.43, maxFactor: maxFactor),
                       BoostMath.level(forStep: 5, maxFactor: maxFactor), accuracy: 1e-9)
    }

    func testStepUpAndDownWithOutOfRangeLevelsClampSafely() {
        // Below range: snaps to step 0 first
        XCTAssertEqual(BoostMath.stepDown(from: 0.9, maxFactor: maxFactor), 1.0, accuracy: 1e-9)
        XCTAssertEqual(BoostMath.stepUp(from: 0.9, maxFactor: maxFactor),
                       BoostMath.level(forStep: 1, maxFactor: maxFactor), accuracy: 1e-9)
        // Above range: snaps to step 8 first
        XCTAssertEqual(BoostMath.stepUp(from: 1.7, maxFactor: maxFactor), 1.6, accuracy: 1e-9)
        XCTAssertEqual(BoostMath.stepDown(from: 1.7, maxFactor: maxFactor),
                       BoostMath.level(forStep: 7, maxFactor: maxFactor), accuracy: 1e-9)
    }

    func testStepUpAndDownWithDegenerateMaxFactorStayAtOne() {
        XCTAssertEqual(BoostMath.stepUp(from: 1.0, maxFactor: 1.0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(BoostMath.stepDown(from: 1.0, maxFactor: 1.0), 1.0, accuracy: 1e-9)
    }
}
