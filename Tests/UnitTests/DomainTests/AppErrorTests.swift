import Foundation
import Testing
@testable import MacPulseDomain

@Suite("AppError")
struct AppErrorTests {
    @Test func existingAppErrorIsReturnedUnchanged() {
        let original = AppError(kind: .unsupported, userMessage: "Original", technicalDetail: "detail")
        let wrapped = AppError.wrapping(original, userMessage: "Replacement")
        #expect(wrapped == original)
    }

    @Test func cancellationIsClassified() {
        let wrapped = AppError.wrapping(CancellationError(), userMessage: "Scan stopped")
        #expect(wrapped.kind == .cancelled)
        #expect(wrapped.userMessage == "Scan stopped")
    }

    @Test(arguments: [
        (CocoaError.Code.fileReadNoPermission, AppError.Kind.permissionDenied),
        (.fileWriteNoPermission, .permissionDenied),
        (.fileNoSuchFile, .notFound),
        (.fileReadNoSuchFile, .notFound),
        (.userCancelled, .cancelled),
        (.featureUnsupported, .unsupported),
        (.fileReadCorruptFile, .io),
    ])
    func cocoaErrorsAreClassified(code: CocoaError.Code, expected: AppError.Kind) {
        let wrapped = AppError.wrapping(CocoaError(code), userMessage: "msg")
        #expect(wrapped.kind == expected)
    }

    @Test(arguments: [
        (POSIXErrorCode.EACCES, AppError.Kind.permissionDenied),
        (.EPERM, .permissionDenied),
        (.ENOENT, .notFound),
        (.ENOTSUP, .unsupported),
        (.ECANCELED, .cancelled),
        (.EIO, .io),
    ])
    func posixErrorsAreClassified(code: POSIXErrorCode, expected: AppError.Kind) {
        let wrapped = AppError.wrapping(POSIXError(code), userMessage: "msg")
        #expect(wrapped.kind == expected)
    }

    @Test func unknownErrorsAreUnexpected() {
        struct Custom: Error {}
        let wrapped = AppError.wrapping(Custom(), userMessage: "msg")
        #expect(wrapped.kind == .unexpected)
        #expect(wrapped.technicalDetail != nil)
    }

    @Test func descriptionIncludesKindAndMessage() {
        let error = AppError(kind: .io, userMessage: "Couldn't read", technicalDetail: "EIO")
        #expect(error.description == "[io] Couldn't read — EIO")
        #expect(AppError(kind: .notFound, userMessage: "Gone").description == "[notFound] Gone")
    }
}
