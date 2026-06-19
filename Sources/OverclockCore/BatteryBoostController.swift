import AppKit
import Combine
import IOKit.ps

public final class BatteryBoostSettings: ObservableObject {
    private enum Keys {
        static let policy = "batteryBoostPolicy"
        static let minimumBatteryPercentage = "minimumBatteryPercentage"
    }

    public static let defaultMinimumBatteryPercentage = 30
    public static let allowedMinimumBatteryPercentages = stride(from: 10, through: 100, by: 10).map { $0 }

    @Published public var policy: BatteryBoostPolicy {
        didSet { defaults.set(policy.rawValue, forKey: Keys.policy) }
    }

    @Published public private(set) var minimumBatteryPercentage: Int

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let rawPolicy = defaults.string(forKey: Keys.policy),
           let storedPolicy = BatteryBoostPolicy(rawValue: rawPolicy) {
            self.policy = storedPolicy
        } else {
            self.policy = .alwaysAllowOnBattery
        }

        let storedMinimum = defaults.integer(forKey: Keys.minimumBatteryPercentage)
        self.minimumBatteryPercentage = storedMinimum > 0
            ? Self.normalizeMinimumBatteryPercentage(storedMinimum)
            : Self.defaultMinimumBatteryPercentage
    }

    public func setMinimumBatteryPercentage(_ value: Int) {
        minimumBatteryPercentage = Self.normalizeMinimumBatteryPercentage(value)
        defaults.set(minimumBatteryPercentage, forKey: Keys.minimumBatteryPercentage)
    }

    private static func normalizeMinimumBatteryPercentage(_ value: Int) -> Int {
        let clamped = min(100, max(10, value))
        return ((clamped + 5) / 10) * 10
    }
}

public enum BatteryStatusReader {
    public static func current() -> BatteryStatus {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let powerSourceType = IOPSGetProvidingPowerSourceType(snapshot)?
            .takeUnretainedValue() as String?

        let powerSource: BatteryStatus.PowerSource
        if powerSourceType == kIOPSACPowerValue as String {
            powerSource = .ac
        } else if powerSourceType == kIOPSBatteryPowerValue as String {
            powerSource = .battery
        } else {
            powerSource = .unknown
        }

        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [AnyObject]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let isPresent = description[kIOPSIsPresentKey as String] as? Bool ?? false
            guard isPresent else { continue }

            let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int
            let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Int
            let percentage: Int?
            if let currentCapacity, let maxCapacity, maxCapacity > 0 {
                percentage = Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
            } else {
                percentage = nil
            }

            return BatteryStatus(powerSource: powerSource, batteryPresent: true, percentage: percentage)
        }

        return BatteryStatus(powerSource: powerSource, batteryPresent: false, percentage: nil)
    }
}

public final class BatteryBoostController {
    private let state: BoostState
    private let settings: BatteryBoostSettings
    private let statusProvider: () -> BatteryStatus
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var powerSourceRunLoopSource: CFRunLoopSource?

    public convenience init(state: BoostState, settings: BatteryBoostSettings) {
        self.init(state: state, settings: settings, statusProvider: BatteryStatusReader.current)
    }

    init(
        state: BoostState,
        settings: BatteryBoostSettings,
        statusProvider: @escaping () -> BatteryStatus
    ) {
        self.state = state
        self.settings = settings
        self.statusProvider = statusProvider
    }

    deinit {
        stop()
    }

    public func start() {
        refresh()

        settings.$policy
            .combineLatest(settings.$minimumBatteryPercentage)
            .sink { [weak self] policy, minimumBatteryPercentage in
                self?.refresh(policy: policy, thresholdPercentage: minimumBatteryPercentage)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(refreshFromNotification),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        installPowerSourceNotification()
    }

    public func stop() {
        cancellables.removeAll()
        timer?.invalidate()
        timer = nil
        if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .commonModes)
            self.powerSourceRunLoopSource = nil
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    public func refresh() {
        refresh(
            policy: settings.policy,
            thresholdPercentage: settings.minimumBatteryPercentage
        )
    }

    private func refresh(policy: BatteryBoostPolicy, thresholdPercentage: Int) {
        let decision = BatteryBoostAuthorizer.decision(
            policy: policy,
            thresholdPercentage: thresholdPercentage,
            status: statusProvider()
        )

        if Thread.isMainThread {
            state.setBoostDecision(decision)
        } else {
            DispatchQueue.main.async { [state] in state.setBoostDecision(decision) }
        }
    }

    private func installPowerSourceNotification() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let controller = Unmanaged<BatteryBoostController>
                .fromOpaque(context)
                .takeUnretainedValue()
            controller.refresh()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerSourceRunLoopSource = source
        } else {
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    @objc private func refreshFromNotification() {
        refresh()
    }
}
