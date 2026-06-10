import XCTest
@testable import OverclockCore

final class BoostEngineLifecycleTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suiteName = "BoostEngineLifecycleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testBoostEngagementShowsAnchorThenAppliesGammaAfterEDRSettles() {
        let harness = BoostEngineHarness()
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6
        let engine = BoostEngine(state: state, environment: harness.environment)
        drainMainQueue()

        state.boostLevel = 1.4
        drainMainQueue()

        XCTAssertEqual(harness.anchors.count, 1)
        XCTAssertEqual(harness.anchors[0].initialTarget, 1.6, accuracy: 1e-9)
        XCTAssertEqual(harness.anchors[0].showCount, 1)
        XCTAssertEqual(harness.gammas.count, 1)
        XCTAssertEqual(harness.gammas[0].appliedFactors, [])

        harness.scheduler.runAll()

        XCTAssertEqual(harness.gammas[0].appliedFactors, [1.4])
        engine.shutdown()
    }

    func testTurningOffBeforeDelayedFirstApplyRestoresAndCancelsPendingGammaApply() {
        let harness = BoostEngineHarness()
        let state = BoostState(defaults: defaults)
        let engine = BoostEngine(state: state, environment: harness.environment)
        drainMainQueue()

        state.boostLevel = 1.4
        drainMainQueue()
        XCTAssertEqual(harness.scheduler.pendingCount, 1)

        state.toggleOff()
        drainMainQueue()

        XCTAssertEqual(harness.gammas[0].restoreCount, 1)
        XCTAssertEqual(harness.anchors[0].dismissCount, 1)

        harness.scheduler.runAll()

        XCTAssertEqual(harness.gammas[0].appliedFactors, [])
        engine.shutdown()
    }

    func testMeasuredHeadroomClampsBoostBeforeApplyingGamma() {
        let harness = BoostEngineHarness()
        harness.headroom = 1.3
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6
        let engine = BoostEngine(state: state, environment: harness.environment)
        drainMainQueue()

        state.boostLevel = 1.6
        drainMainQueue()
        harness.scheduler.runAll()

        XCTAssertEqual(state.maxFactor, 1.3, accuracy: 1e-9)
        XCTAssertEqual(state.boostLevel, 1.3, accuracy: 1e-9)
        XCTAssertEqual(harness.gammas[0].appliedFactors, [1.3])
        engine.shutdown()
    }

    func testLosingBuiltinDisplayTearsDownExistingBoost() {
        let harness = BoostEngineHarness()
        let state = BoostState(defaults: defaults)
        state.maxFactor = 1.6
        let engine = BoostEngine(state: state, environment: harness.environment)
        drainMainQueue()

        state.boostLevel = 1.4
        drainMainQueue()
        harness.scheduler.runAll()

        harness.displayAvailable = false
        state.stepUp()
        drainMainQueue()

        XCTAssertEqual(harness.gammas[0].restoreCount, 1)
        XCTAssertEqual(harness.anchors[0].dismissCount, 1)
        engine.shutdown()
    }

    func testScreenChangeRebuildsAnchorForActiveBoost() {
        let harness = BoostEngineHarness()
        let state = BoostState(defaults: defaults)
        let engine = BoostEngine(state: state, environment: harness.environment)
        drainMainQueue()

        state.boostLevel = 1.4
        drainMainQueue()
        harness.scheduler.runAll()

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        XCTAssertEqual(harness.gammas.count, 2)
        XCTAssertEqual(harness.gammas[0].restoreCount, 1)
        XCTAssertEqual(harness.anchors.count, 2)
        XCTAssertEqual(harness.anchors[0].dismissCount, 1)
        XCTAssertEqual(harness.anchors[1].showCount, 1)
        engine.shutdown()
    }

    private func drainMainQueue(file: StaticString = #filePath, line: UInt = #line) {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1.0)
    }
}

private final class BoostEngineHarness {
    var displayAvailable = true
    var headroom = 1.6
    let scheduler = ManualFirstApplyScheduler()
    var gammas: [FakeGamma] = []
    var anchors: [FakeAnchor] = []

    var environment: BoostEngineEnvironment {
        BoostEngineEnvironment(
            builtinDisplay: { [weak self] in
                guard let self, self.displayAvailable else { return nil }
                return BoostEngineDisplay(
                    displayID: 42,
                    currentEDRHeadroom: { [weak self] in self?.headroom ?? 1.0 },
                    makeAnchor: { [weak self] target in
                        let anchor = FakeAnchor(initialTarget: target)
                        self?.anchors.append(anchor)
                        return anchor
                    }
                )
            },
            makeGamma: { [weak self] _ in
                let gamma = FakeGamma()
                self?.gammas.append(gamma)
                return gamma
            },
            scheduleFirstApply: { [scheduler] action in scheduler.schedule(action) }
        )
    }
}

private final class ManualFirstApplyScheduler {
    private var actions: [() -> Void] = []

    var pendingCount: Int { actions.count }

    func schedule(_ action: @escaping () -> Void) {
        actions.append(action)
    }

    func runAll() {
        let actionsToRun = actions
        actions.removeAll()
        actionsToRun.forEach { $0() }
    }
}

private final class FakeGamma: BoostGammaControlling {
    var appliedFactors: [Double] = []
    var restoreCount = 0

    func apply(factor: Double) {
        appliedFactors.append(factor)
    }

    func restore() {
        restoreCount += 1
    }
}

private final class FakeAnchor: BoostAnchoring {
    let initialTarget: Double
    var showCount = 0
    var setTargets: [Double] = []
    var dismissCount = 0

    init(initialTarget: Double) {
        self.initialTarget = initialTarget
    }

    func show() {
        showCount += 1
    }

    func setEDRTarget(_ value: Double) {
        setTargets.append(value)
    }

    func dismiss() {
        dismissCount += 1
    }
}
