import AppKit
import OSLog

/// CGEventTap on NX_SYSDEFINED (type 14) events. Always active; KeyDecision
/// determines pass-through vs. swallow-and-step per event.
public final class BrightnessKeyInterceptor {
    // NX_KEYTYPE_* from IOKit/hidsystem/ev_keymap.h
    private static let keyBrightnessUp: Int = 2
    private static let keyBrightnessDown: Int = 3
    private static let systemDefinedEventType: UInt32 = 14 // NX_SYSDEFINED
    private static let mediaKeySubtype: Int16 = 8

    private let logger = Logger(subsystem: "BrightnessOverclock", category: "KeyTap")
    private let nativeBrightness = NativeBrightness()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pairing = KeyEventPairing()

    /// Injected by the app: current boost level + step actions.
    public var boostLevelProvider: () -> Double = { 1.0 }
    public var onStepUp: () -> Void = {}
    public var onStepDown: () -> Void = {}

    public init() {}

    public static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Returns false if the tap could not be created (no permission).
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << Self.systemDefinedEventType)
        let callback: CGEventTapCallBack = { _, type, cgEvent, refcon in
            let interceptor = Unmanaged<BrightnessKeyInterceptor>
                .fromOpaque(refcon!).takeUnretainedValue()
            return interceptor.handle(type: type, cgEvent: cgEvent)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Failed to create event tap (missing Accessibility permission?)")
            return false
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Brightness key tap active")
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        tap = nil
    }

    private func handle(type: CGEventType, cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps it deems slow/stuck; re-enable and pass through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(cgEvent)
        }
        guard let event = NSEvent(cgEvent: cgEvent),
              event.subtype.rawValue == Self.mediaKeySubtype else {
            return Unmanaged.passUnretained(cgEvent)
        }
        let data1 = event.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0x0000_FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A
        let isRepeat = (keyFlags & 0x1) == 0x1

        let key: BrightnessKey
        switch keyCode {
        case Self.keyBrightnessUp: key = .up
        case Self.keyBrightnessDown: key = .down
        default: return Unmanaged.passUnretained(cgEvent)
        }

        let displayID = GammaBoostController.builtinDisplayID() ?? CGMainDisplayID()
        let native = nativeBrightness.current(displayID: displayID)
        let action = KeyDecision.action(for: key,
                                        nativeBrightness: native,
                                        boostLevel: boostLevelProvider())
        let passThrough = pairing.shouldPassThrough(keyCode: keyCode,
                                                    isKeyDown: isKeyDown,
                                                    isRepeat: isRepeat,
                                                    action: action)
        logger.debug("key=\(keyCode) down=\(isKeyDown) repeat=\(isRepeat) native=\(native.map(String.init(describing:)) ?? "nil", privacy: .public) boost=\(self.boostLevelProvider(), privacy: .public) action=\(String(describing: action), privacy: .public) pass=\(passThrough)")

        if isKeyDown {
            switch action {
            case .stepBoostUp: DispatchQueue.main.async { self.onStepUp() }
            case .stepBoostDown: DispatchQueue.main.async { self.onStepDown() }
            case .passThrough: break
            }
        }
        return passThrough ? Unmanaged.passUnretained(cgEvent) : nil
    }
}
