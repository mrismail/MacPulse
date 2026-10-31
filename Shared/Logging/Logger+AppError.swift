import MacPulseDomain
import OSLog

extension Logger {
    /// Logs an `AppError` without leaking personal data: the kind and the user-facing
    /// message are public, the technical detail (which can contain file paths and
    /// therefore the user's name) is private and redacted outside this Mac.
    public func log(_ error: AppError, context: String) {
        self.error(
            "\(context, privacy: .public): [\(error.kind.rawValue, privacy: .public)] \(error.userMessage, privacy: .public) \(error.technicalDetail ?? "", privacy: .private)"
        )
    }
}
