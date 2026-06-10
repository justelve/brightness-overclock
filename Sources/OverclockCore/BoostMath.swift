import Foundation

/// Pure math for the 8-step boost scale. Levels are gamma boost factors
/// (1.0 = native max brightness; maxFactor = full EDR headroom).
public enum BoostMath {
    static let stepCount = 8
    /// SDR reference for the UI nits estimate (M4 Pro XDR panel).
    public static let sdrReferenceNits = 1000.0
    static let peakNits = 1600.0

    static func level(forStep step: Int, maxFactor: Double) -> Double {
        let clamped = min(max(step, 0), stepCount)
        return 1.0 + (maxFactor - 1.0) * Double(clamped) / Double(stepCount)
    }

    static func step(forLevel level: Double, maxFactor: Double) -> Int {
        guard maxFactor > 1.0 else { return 0 }
        let fraction = (level - 1.0) / (maxFactor - 1.0)
        return min(max(Int((fraction * Double(stepCount)).rounded()), 0), stepCount)
    }

    static func stepUp(from level: Double, maxFactor: Double) -> Double {
        self.level(forStep: step(forLevel: level, maxFactor: maxFactor) + 1, maxFactor: maxFactor)
    }

    static func stepDown(from level: Double, maxFactor: Double) -> Double {
        self.level(forStep: step(forLevel: level, maxFactor: maxFactor) - 1, maxFactor: maxFactor)
    }

    /// Rough nits readout for the menu (estimate, not a measurement).
    public static func approximateNits(level: Double) -> Int {
        Int(min(peakNits, sdrReferenceNits * level).rounded())
    }
}
