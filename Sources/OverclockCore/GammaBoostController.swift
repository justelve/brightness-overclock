import CoreGraphics

/// Applies/restores the gamma boost on one display.
/// Crash safety: the window server resets gamma when the process exits.
final class GammaBoostController {
    private let displayID: CGDirectDisplayID
    private var baseline: (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue])?

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    /// The built-in panel, or nil (e.g. clamshell mode with externals only).
    static func builtinDisplayID() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    func apply(factor: Double) {
        guard factor > 1.0 else {
            restore()
            return
        }
        captureBaselineIfNeeded()
        guard let base = baseline else { return }
        let boost = Float(factor)
        var red = base.red.map { $0 * boost }
        var green = base.green.map { $0 * boost }
        var blue = base.blue.map { $0 * boost }
        CGSetDisplayTransferByTable(displayID, UInt32(red.count), &red, &green, &blue)
    }

    func restore() {
        guard baseline != nil else { return }
        baseline = nil
        CGDisplayRestoreColorSyncSettings()
    }

    private func captureBaselineIfNeeded() {
        guard baseline == nil else { return }
        let capacity: UInt32 = 256
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = [CGGammaValue](repeating: 0, count: Int(capacity))
        var blue = [CGGammaValue](repeating: 0, count: Int(capacity))
        var sampleCount: UInt32 = 0
        guard CGGetDisplayTransferByTable(displayID, capacity, &red, &green, &blue, &sampleCount) == .success,
              sampleCount > 0 else { return }
        baseline = (Array(red.prefix(Int(sampleCount))),
                    Array(green.prefix(Int(sampleCount))),
                    Array(blue.prefix(Int(sampleCount))))
    }
}
