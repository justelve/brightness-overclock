import Foundation

enum BrightnessKey {
    case up
    case down
}

enum KeyAction: Equatable {
    case passThrough
    case stepBoostUp
    case stepBoostDown
}

/// Pure decision logic for the brightness-key event tap.
enum KeyDecision {
    /// Threshold treating DisplayServices float jitter (0.999...) as "at max".
    static let nativeMaxThreshold: Float = 0.998

    /// - nativeBrightness: 0...1 from DisplayServices, nil if unreadable.
    static func action(for key: BrightnessKey,
                       nativeBrightness: Float?,
                       boostLevel: Double) -> KeyAction {
        switch key {
        case .up:
            // Fail open: if we can't read native brightness, never hijack the key.
            guard let native = nativeBrightness else { return .passThrough }
            return native >= nativeMaxThreshold ? .stepBoostUp : .passThrough
        case .down:
            // Boost walks down first regardless of native level.
            return boostLevel > 1.0 ? .stepBoostDown : .passThrough
        }
    }
}
