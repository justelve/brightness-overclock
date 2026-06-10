import Foundation

/// Keeps key-down/key-up treatment consistent per key so macOS never sees an
/// orphaned press or release. An orphaned down leaves the system's media-key
/// state machine thinking the key is still held, after which it ignores the
/// opposite brightness key (the "can't dim below native max after boosting" bug).
///
/// Rules:
/// - A release is swallowed iff its (non-repeat) press was swallowed.
/// - A swallowed repeat never marks the press swallowed.
/// - If repeats flip from swallowed to passed mid-hold, the swallow mark is
///   cleared so the eventual release passes too.
struct KeyEventPairing {
    private var swallowedDownKeys: Set<Int> = []

    init() {}

    /// - Returns: true = pass the event through to macOS, false = swallow it.
    mutating func shouldPassThrough(keyCode: Int,
                                    isKeyDown: Bool,
                                    isRepeat: Bool,
                                    action: KeyAction) -> Bool {
        guard isKeyDown else {
            if swallowedDownKeys.contains(keyCode) {
                swallowedDownKeys.remove(keyCode)
                return false
            }
            return true
        }
        switch action {
        case .passThrough:
            swallowedDownKeys.remove(keyCode)
            return true
        case .stepBoostUp, .stepBoostDown:
            if !isRepeat { swallowedDownKeys.insert(keyCode) }
            return false
        }
    }
}
