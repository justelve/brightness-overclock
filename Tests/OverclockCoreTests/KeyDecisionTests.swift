import XCTest
@testable import OverclockCore

final class KeyDecisionTests: XCTestCase {
    func testUpBelowNativeMaxPassesThrough() {
        XCTAssertEqual(KeyDecision.action(for: .up, nativeBrightness: 0.5, boostLevel: 1.0), .passThrough)
        XCTAssertEqual(KeyDecision.action(for: .up, nativeBrightness: 0.93, boostLevel: 1.3), .passThrough)
    }

    func testUpAtNativeMaxStepsBoostUpEvenWhenOff() {
        XCTAssertEqual(KeyDecision.action(for: .up, nativeBrightness: 1.0, boostLevel: 1.0), .stepBoostUp)
    }

    func testNativeMaxThresholdBoundary() {
        XCTAssertEqual(KeyDecision.action(for: .up, nativeBrightness: 0.997, boostLevel: 1.0), .passThrough)
        XCTAssertEqual(KeyDecision.action(for: .up, nativeBrightness: 0.998, boostLevel: 1.0), .stepBoostUp)
    }

    func testUpAtNativeMaxWithBoostActiveStepsUp() {
        XCTAssertEqual(KeyDecision.action(for: .up, nativeBrightness: 1.0, boostLevel: 1.3), .stepBoostUp)
    }

    func testUpJustBelowOneCountsAsMax() {
        // DisplayServices can report 0.999... at max
        XCTAssertEqual(KeyDecision.action(for: .up, nativeBrightness: 0.999, boostLevel: 1.0), .stepBoostUp)
    }

    func testDownWithBoostActiveStepsBoostDown() {
        XCTAssertEqual(KeyDecision.action(for: .down, nativeBrightness: 1.0, boostLevel: 1.3), .stepBoostDown)
        // Boost steps down first even if native somehow dropped below max
        XCTAssertEqual(KeyDecision.action(for: .down, nativeBrightness: 0.8, boostLevel: 1.3), .stepBoostDown)
    }

    func testDownWithoutBoostPassesThrough() {
        XCTAssertEqual(KeyDecision.action(for: .down, nativeBrightness: 1.0, boostLevel: 1.0), .passThrough)
        XCTAssertEqual(KeyDecision.action(for: .down, nativeBrightness: 0.3, boostLevel: 1.0), .passThrough)
    }

    func testNilNativeBrightnessFailsOpen() {
        XCTAssertEqual(KeyDecision.action(for: .up, nativeBrightness: nil, boostLevel: 1.3), .passThrough)
        XCTAssertEqual(KeyDecision.action(for: .down, nativeBrightness: nil, boostLevel: 1.3), .stepBoostDown)
    }
}
