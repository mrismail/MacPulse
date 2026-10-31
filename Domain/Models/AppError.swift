import Foundation

/// The single error type that crosses module boundaries into the UI.
///
/// `userMessage` is safe to display. `technicalDetail` is for diagnostics and logs and
/// must not contain file contents.
public struct AppError: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case permissionDenied
        case notFound
        case unsupported
        case cancelled
        case io
        case unexpected
    }

    public let kind: Kind
    public let userMessage: String
    public let technicalDetail: String?

    public init(kind: Kind, userMessage: String, technicalDetail: String? = nil) {
        self.kind = kind
        self.userMessage = userMessage
        self.technicalDetail = technicalDetail
    }

    public var description: String {
        if let technicalDetail {
            return "[\(kind.rawValue)] \(userMessage) — \(technicalDetail)"
        }
        return "[\(kind.rawValue)] \(userMessage)"
    }

    /// Converts any thrown error into an `AppError`, classifying common Foundation
    /// and POSIX failures. An existing `AppError` is returned unchanged.
    public static func wrapping(_ error: any Error, userMessage: String) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        if error is CancellationError {
            return AppError(kind: .cancelled, userMessage: userMessage, technicalDetail: "Operation was cancelled")
        }
        return AppError(
            kind: classify(error),
            userMessage: userMessage,
            technicalDetail: String(describing: error)
        )
    }

    private static func classify(_ error: any Error) -> Kind {
        if let cocoa = error as? CocoaError {
            switch cocoa.code {
            case .fileReadNoPermission, .fileWriteNoPermission:
                return .permissionDenied
            case .fileNoSuchFile, .fileReadNoSuchFile:
                return .notFound
            case .userCancelled:
                return .cancelled
            case .featureUnsupported:
                return .unsupported
            default:
                return cocoa.isFileError ? .io : .unexpected
            }
        }
        if let posix = error as? POSIXError {
            switch posix.code {
            case .EACCES, .EPERM:
                return .permissionDenied
            case .ENOENT:
                return .notFound
            case .ENOTSUP:
                return .unsupported
            case .ECANCELED:
                return .cancelled
            default:
                return .io
            }
        }
        return .unexpected
    }
}
