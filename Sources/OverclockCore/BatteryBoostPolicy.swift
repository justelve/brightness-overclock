import Foundation

public enum BatteryBoostPolicy: String, CaseIterable, Identifiable {
    case alwaysAllowOnBattery
    case disableBelowPercentage
    case neverAllowOnBattery

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .alwaysAllowOnBattery:
            return "Allow boost on battery"
        case .disableBelowPercentage:
            return "Turn off below threshold"
        case .neverAllowOnBattery:
            return "Don’t allow boost on battery"
        }
    }
}

public struct BatteryStatus: Equatable {
    public enum PowerSource: Equatable {
        case ac
        case battery
        case unknown
    }

    public let powerSource: PowerSource
    public let batteryPresent: Bool
    public let percentage: Int?
    public let lowPowerModeEnabled: Bool

    public init(
        powerSource: PowerSource,
        batteryPresent: Bool,
        percentage: Int?,
        lowPowerModeEnabled: Bool = false
    ) {
        self.powerSource = powerSource
        self.batteryPresent = batteryPresent
        self.percentage = percentage
        self.lowPowerModeEnabled = lowPowerModeEnabled
    }

    public var isOnBattery: Bool {
        batteryPresent && powerSource == .battery
    }

    public var menuDescription: String {
        var parts: [String]
        if isOnBattery {
            parts = [percentage.map { "Battery: \($0)%" } ?? "Battery: Unknown"]
        } else {
            switch powerSource {
            case .ac:
                parts = ["Power: AC"]
            case .unknown:
                parts = ["Power: Unknown"]
            case .battery:
                parts = ["Battery"]
            }
            if batteryPresent, let percentage {
                parts.append("Battery: \(percentage)%")
            }
        }
        if lowPowerModeEnabled { parts.append("Low Power Mode") }
        return parts.joined(separator: " · ")
    }
}

public struct BatteryBoostDecision: Equatable {
    public let isAllowed: Bool
    public let reason: String?

    public static let allowed = BatteryBoostDecision(isAllowed: true, reason: nil)

    public static func blocked(_ reason: String) -> BatteryBoostDecision {
        BatteryBoostDecision(isAllowed: false, reason: reason)
    }
}

public enum BatteryBoostAuthorizer {
    public static func decision(
        policy: BatteryBoostPolicy,
        thresholdPercentage: Int,
        status: BatteryStatus
    ) -> BatteryBoostDecision {
        if status.lowPowerModeEnabled {
            return .blocked("Boost is disabled in Low Power Mode.")
        }

        guard status.isOnBattery else { return .allowed }

        switch policy {
        case .alwaysAllowOnBattery:
            return .allowed
        case .disableBelowPercentage:
            guard let percentage = status.percentage else { return .allowed }
            if percentage < thresholdPercentage {
                return .blocked("Boost is disabled below \(thresholdPercentage)% battery.")
            }
            return .allowed
        case .neverAllowOnBattery:
            return .blocked("Boost is disabled while on battery.")
        }
    }
}
