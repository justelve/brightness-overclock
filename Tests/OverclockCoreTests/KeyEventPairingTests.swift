import XCTest
@testable import OverclockCore

final class KeyEventPairingTests: XCTestCase {
    let key = 3 // brightness down

    func testSwallowedPressSwallowsItsRelease() {
        var pairing = KeyEventPairing()
        XCTAssertFalse(pairing.shouldPassThrough(keyCode: key, isKeyDown: true, isRepeat: false, action: .stepBoostDown))
        // By release time the decision may have flipped to passThrough — release must still be swallowed.
        XCTAssertFalse(pairing.shouldPassThrough(keyCode: key, isKeyDown: false, isRepeat: false, action: .passThrough))
    }

    func testPassedPressPassesItsRelease() {
        var pairing = KeyEventPairing()
        XCTAssertTrue(pairing.shouldPassThrough(keyCode: key, isKeyDown: true, isRepeat: false, action: .passThrough))
        XCTAssertTrue(pairing.shouldPassThrough(keyCode: key, isKeyDown: false, isRepeat: false, action: .passThrough))
    }

    func testHoldEnteringBoostPassesReleaseBecauseDownWasPassed() {
        var pairing = KeyEventPairing()
        // Hold F2 from below max: initial down passes through to macOS.
        XCTAssertTrue(pairing.shouldPassThrough(keyCode: key, isKeyDown: true, isRepeat: false, action: .passThrough))
        // Native hits max mid-hold: repeats are swallowed (boost steps) but must NOT mark the press swallowed.
        XCTAssertFalse(pairing.shouldPassThrough(keyCode: key, isKeyDown: true, isRepeat: true, action: .stepBoostUp))
        XCTAssertFalse(pairing.shouldPassThrough(keyCode: key, isKeyDown: true, isRepeat: true, action: .stepBoostUp))
        // Release: macOS saw the down, it must see the up.
        XCTAssertTrue(pairing.shouldPassThrough(keyCode: key, isKeyDown: false, isRepeat: false, action: .stepBoostUp))
    }

    func testHoldLeavingBoostFlipsToPassAndReleasePasses() {
        var pairing = KeyEventPairing()
        // Hold F1 while boosted: down swallowed.
        XCTAssertFalse(pairing.shouldPassThrough(keyCode: key, isKeyDown: true, isRepeat: false, action: .stepBoostDown))
        XCTAssertFalse(pairing.shouldPassThrough(keyCode: key, isKeyDown: true, isRepeat: true, action: .stepBoostDown))
        // Boost reaches 1.0 mid-hold: repeats flip to passThrough — forget the swallow.
        XCTAssertTrue(pairing.shouldPassThrough(keyCode: key, isKeyDown: true, isRepeat: true, action: .passThrough))
        // Release now passes so macOS's stream stays consistent.
        XCTAssertTrue(pairing.shouldPassThrough(keyCode: key, isKeyDown: false, isRepeat: false, action: .passThrough))
    }

    func testHoldFullyInBoostSwallowsEverything() {
        var pairing = KeyEventPairing()
        XCTAssertFalse(pairing.shouldPassThrough(keyCode: key, isKeyDown: true, isRepeat: false, action: .stepBoostDown))
        XCTAssertFalse(pairing.shouldPassThrough(keyCode: key, isKeyDown: true, isRepeat: true, action: .stepBoostDown))
        XCTAssertFalse(pairing.shouldPassThrough(keyCode: key, isKeyDown: false, isRepeat: false, action: .stepBoostDown))
    }

    func testIndependentKeysTrackedSeparately() {
        var pairing = KeyEventPairing()
        let up = 2, down = 3
        XCTAssertFalse(pairing.shouldPassThrough(keyCode: up, isKeyDown: true, isRepeat: false, action: .stepBoostUp))
        XCTAssertTrue(pairing.shouldPassThrough(keyCode: down, isKeyDown: true, isRepeat: false, action: .passThrough))
        XCTAssertFalse(pairing.shouldPassThrough(keyCode: up, isKeyDown: false, isRepeat: false, action: .stepBoostUp))
        XCTAssertTrue(pairing.shouldPassThrough(keyCode: down, isKeyDown: false, isRepeat: false, action: .passThrough))
    }
}
