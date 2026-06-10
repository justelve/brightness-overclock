import AppKit
import Combine
import OSLog

protocol BoostGammaControlling: AnyObject {
    func apply(factor: Double)
    func restore()
}

extension GammaBoostController: BoostGammaControlling {}

protocol BoostAnchoring: AnyObject {
    func show()
    func setEDRTarget(_ value: Double)
    func dismiss()
}

extension HDRAnchorWindow: BoostAnchoring {
    func dismiss() { orderOut(nil) }
}

struct BoostEngineDisplay {
    let displayID: CGDirectDisplayID
    let currentEDRHeadroom: () -> Double
    let makeAnchor: (_ edrTarget: Double) -> BoostAnchoring
}

struct BoostEngineEnvironment {
    var builtinDisplay: () -> BoostEngineDisplay?
    var makeGamma: (_ displayID: CGDirectDisplayID) -> BoostGammaControlling
    var scheduleFirstApply: (_ action: @escaping () -> Void) -> Void

    static let live = BoostEngineEnvironment(
        builtinDisplay: {
            guard let screen = BoostEngine.builtinScreen(),
                  let displayID = GammaBoostController.builtinDisplayID() else { return nil }
            return BoostEngineDisplay(
                displayID: displayID,
                currentEDRHeadroom: { Double(screen.maximumExtendedDynamicRangeColorComponentValue) },
                makeAnchor: { HDRAnchorWindow(screen: screen, edrTarget: $0) }
            )
        },
        makeGamma: { GammaBoostController(displayID: $0) },
        scheduleFirstApply: { action in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: action)
        }
    )
}

/// Drives gamma + anchor from BoostState. Components never call each other
/// directly; everything flows state -> engine -> (gamma, anchor).
public final class BoostEngine {
    public let state: BoostState

    private let logger = Logger(subsystem: "BrightnessOverclock", category: "BoostEngine")
    private let environment: BoostEngineEnvironment
    private var gamma: BoostGammaControlling?
    private var anchor: BoostAnchoring?
    private var cancellables = Set<AnyCancellable>()
    /// Generation counter invalidates pending delayed gamma applies.
    private var applyGeneration = 0

    public convenience init(state: BoostState) {
        self.init(state: state, environment: .live)
    }

    init(state: BoostState, environment: BoostEngineEnvironment) {
        self.state = state
        self.environment = environment

        state.$boostLevel
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in self?.apply(level: level) }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(reapply),
            name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(reapply),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    /// Call once after app launch to restore a persisted boost.
    public func applyPersisted() {
        apply(level: state.boostLevel)
    }

    /// Call on clean quit.
    public func shutdown() {
        teardown()
    }

    static func builtinScreen() -> NSScreen? {
        guard let builtinID = GammaBoostController.builtinDisplayID() else { return nil }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == builtinID
        }
    }

    private func apply(level: Double) {
        guard level > 1.0 else {
            teardown()
            return
        }
        guard let display = environment.builtinDisplay() else {
            logger.error("No built-in display found; boost unavailable")
            teardown()
            return
        }

        if gamma == nil {
            gamma = environment.makeGamma(display.displayID)
        }

        if anchor == nil {
            // First engagement: show the anchor, give the window server a beat
            // to engage EDR, then read the real current headroom (peak / current
            // SDR white) and apply gamma at the freshest level. Clamped to the
            // panel's peak/SDR ratio so a spurious reading can't blow out the screen.
            anchor = display.makeAnchor(state.maxFactor)
            anchor?.show()
            applyGeneration += 1
            let generation = applyGeneration
            environment.scheduleFirstApply { [weak self] in
                guard let self, self.applyGeneration == generation, self.state.boostLevel > 1.0 else { return }
                let panelRatio = BoostMath.peakNits / BoostMath.sdrReferenceNits
                let headroom = display.currentEDRHeadroom()
                if headroom > 1.0 { self.state.maxFactor = min(headroom, panelRatio) }
                // Re-clamp the level itself so an over-ceiling value is never
                // persisted when measured headroom is below the assumed ratio.
                if self.state.boostLevel > self.state.maxFactor { self.state.boostLevel = self.state.maxFactor }
                self.logger.info("EDR headroom: \(headroom, privacy: .public), maxFactor: \(self.state.maxFactor, privacy: .public), applying boost \(min(self.state.boostLevel, self.state.maxFactor), privacy: .public)")
                self.gamma?.apply(factor: min(self.state.boostLevel, self.state.maxFactor))
            }
        } else {
            // EDR already engaged: apply synchronously so held-key stepping
            // brightens progressively instead of jumping after a pause.
            anchor?.setEDRTarget(state.maxFactor)
            anchor?.show()
            gamma?.apply(factor: min(level, state.maxFactor))
        }
    }

    private func teardown() {
        applyGeneration += 1 // invalidate any pending first-engagement apply
        gamma?.restore()
        gamma = nil
        anchor?.dismiss()
        anchor = nil
    }

    @objc private func reapply() {
        guard state.isBoosted else { return }
        logger.info("Wake/screen-change: re-applying boost")
        // Tear down and rebuild: the anchor/gamma may be stale after wake.
        teardown()
        apply(level: state.boostLevel)
    }
}
