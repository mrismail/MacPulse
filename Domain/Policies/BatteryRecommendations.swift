import Foundation

/// A suggestion shown on the Overview.
public struct Recommendation: Identifiable, Sendable, Equatable {
    public enum Severity: Sendable, Equatable, Comparable {
        case info
        case warning
    }

    public let id: String
    public let title: String
    public let detail: String
    public let severity: Severity

    public init(id: String, title: String, detail: String, severity: Severity) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
    }
}

/// Derives recommendations from the current battery status. Rules only use values
/// that are available; estimates are worded as estimates.
public enum BatteryRecommendations {
    public static let lowChargeThreshold = 20.0
    public static let reducedHealthThreshold = 80.0
    public static let warmTemperatureThreshold = 40.0

    public static func make(for status: BatteryStatus?) -> [Recommendation] {
        guard let status, status.reading.hasBattery else { return [] }
        let reading = status.reading
        var result: [Recommendation] = []

        if let issue = status.historyIssue {
            result.append(Recommendation(
                id: "history",
                title: "Battery history isn't being saved",
                detail: issue.userMessage,
                severity: .warning
            ))
        }

        if case .serviceRecommended(let text)? = reading.condition.value {
            result.append(Recommendation(
                id: "condition",
                title: "Your battery may need service",
                detail: "macOS reports the battery condition as “\(text)”. Consider checking it with Apple Support.",
                severity: .warning
            ))
        }

        if reading.powerSource.value == .battery,
           let charge = reading.charge.value, reading.charge.isMeasured,
           charge <= lowChargeThreshold {
            result.append(Recommendation(
                id: "lowCharge",
                title: "Battery is low",
                detail: "Connect to power soon.",
                severity: .warning
            ))
        }

        if let health = reading.healthPercentage.value, health < reducedHealthThreshold {
            result.append(Recommendation(
                id: "health",
                title: "Battery capacity has dropped",
                detail: "Estimated health is \(Int(health.rounded()))% of the original capacity, so a full charge lasts less than it used to.",
                severity: .info
            ))
        }

        if let temperature = reading.temperatureCelsius.value, temperature >= warmTemperatureThreshold {
            result.append(Recommendation(
                id: "temperature",
                title: "Battery is warm",
                detail: "Heat ages batteries faster. Avoid heavy work on soft surfaces or in direct sun.",
                severity: .info
            ))
        }

        return result.sorted { $0.severity > $1.severity }
    }
}
