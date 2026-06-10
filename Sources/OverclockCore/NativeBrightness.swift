import CoreGraphics
import Darwin

/// Reads the native backlight level (0...1) via the private DisplayServices
/// framework (same call MonitorControl/Lunar use). Fails soft: nil if the
/// framework or symbol is unavailable.
final class NativeBrightness {
    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private let getFn: GetBrightnessFn?

    init() {
        if let handle = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_LAZY),
           let symbol = dlsym(handle, "DisplayServicesGetBrightness") {
            getFn = unsafeBitCast(symbol, to: GetBrightnessFn.self)
        } else {
            getFn = nil
        }
    }

    func current(displayID: CGDirectDisplayID) -> Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        guard getFn(displayID, &value) == 0 else { return nil }
        return value
    }
}
