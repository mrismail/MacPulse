import CoreFoundation
import Foundation
import IOKit.ps
import MacPulseDomain

/// Power-source change notifications from `IOPSNotificationCreateRunLoopSource`.
/// macOS calls back on plug/unplug and when battery values change.
public struct IOKitPowerSourceEvents: PowerSourceEventSource {
    public init() {}

    public func events() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let registration = Registration(continuation: continuation)
            guard registration.activate() else {
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in
                registration.deactivate()
            }
        }
    }
}

/// Owns the run-loop source and the callback context for one subscription.
/// Mutated only on creation and termination; `@unchecked Sendable` because CF types
/// are not annotated, and the run-loop calls are thread-safe.
private final class Registration: @unchecked Sendable {
    let continuation: AsyncStream<Void>.Continuation
    private var source: CFRunLoopSource?
    private let lock = NSLock()

    init(continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
    }

    func activate() -> Bool {
        let context = Unmanaged.passRetained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<Registration>.fromOpaque(context).takeUnretainedValue().continuation.yield()
        }
        guard let runLoopSource = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            Unmanaged<Registration>.fromOpaque(context).release()
            return false
        }
        lock.withLock { source = runLoopSource }
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        return true
    }

    func deactivate() {
        let removed: CFRunLoopSource? = lock.withLock {
            defer { source = nil }
            return source
        }
        guard let removed else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), removed, .defaultMode)
        CFRunLoopSourceInvalidate(removed)
        // Balance passRetained in activate().
        Unmanaged.passUnretained(self).release()
    }
}
