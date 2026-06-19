import Foundation
import Combine

/// Single source of truth. Boost is ON iff boostLevel > 1.0.
///
/// Threading: main thread only. All mutations (menu UI, key-tap callbacks)
/// must be dispatched to the main queue; enforced by asserts in debug builds.
public final class BoostState: ObservableObject {
    private enum Keys {
        static let boostLevel = "boostLevel"
        static let rememberedLevel = "rememberedLevel"
    }

    @Published public internal(set) var boostLevel: Double {
        didSet {
            assert(Thread.isMainThread, "BoostState must only be mutated on the main thread")
            if boostLevel > 1.0 { rememberedLevel = boostLevel }
            defaults.set(boostLevel, forKey: Keys.boostLevel)
        }
    }

    @Published public private(set) var boostBlockReason: String?

    /// Last boost level > 1.0 the user chose; 0 means "never boosted yet".
    private(set) var rememberedLevel: Double {
        didSet { defaults.set(rememberedLevel, forKey: Keys.rememberedLevel) }
    }

    /// Max gamma boost factor (EDR headroom). Refreshed at runtime by BoostEngine.
    /// Clamped to >= 1.0 so a bogus headroom reading can never push boostLevel below 1.0.
    var maxFactor: Double = 1.6 {
        didSet { if maxFactor < 1.0 { maxFactor = 1.0 } }
    }

    public var isBoosted: Bool { boostLevel > 1.0 }
    public var isBoostAllowed: Bool { boostBlockReason == nil }
    public var currentBoostStep: Int { BoostMath.step(forLevel: boostLevel, maxFactor: maxFactor) }
    public var boostStepCount: Int { BoostMath.stepCount }

    private let defaults: UserDefaults
    private var restoreBoostWhenAllowed = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedLevel = defaults.double(forKey: Keys.boostLevel)
        let storedRemembered = defaults.double(forKey: Keys.rememberedLevel)
        self.boostLevel = storedLevel > 1.0 ? storedLevel : 1.0
        self.rememberedLevel = storedRemembered > 1.0 ? storedRemembered : 0
    }

    public func setBoostDecision(_ decision: BatteryBoostDecision) {
        if decision.isAllowed {
            boostBlockReason = nil
            if restoreBoostWhenAllowed {
                restoreBoostWhenAllowed = false
                toggleOn()
            }
            return
        }

        if isBoostAllowed && isBoosted {
            restoreBoostWhenAllowed = true
        }
        boostBlockReason = decision.reason
        toggleOff()
    }

    /// Menu toggle ON: restore remembered level (first use: max headroom).
    public func toggleOn() {
        guard isBoostAllowed else { return }
        boostLevel = rememberedLevel > 1.0 ? min(rememberedLevel, maxFactor) : maxFactor
    }

    /// Menu toggle OFF: kill switch. rememberedLevel was already captured by didSet.
    public func toggleOff() {
        boostLevel = 1.0
    }

    public func setBoostStep(_ step: Int) {
        guard isBoostAllowed else { return }
        boostLevel = BoostMath.level(forStep: step, maxFactor: maxFactor)
    }

    public func approximateNits(forBoostStep step: Int) -> Int {
        BoostMath.approximateNits(level: BoostMath.level(forStep: step, maxFactor: maxFactor))
    }

    public func stepUp() {
        guard isBoostAllowed else { return }
        boostLevel = BoostMath.stepUp(from: boostLevel, maxFactor: maxFactor)
    }

    public func stepDown() {
        boostLevel = BoostMath.stepDown(from: boostLevel, maxFactor: maxFactor)
    }
}
