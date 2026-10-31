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
///
/// The callback runs on the main thread. Teardown is also performed on the main
/// thread, so the context pointer can never be released while a callback is using it.
/// `@unchecked Sendable` because CF types are not annotated; `source` is guarded by a lock.
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
        // Common modes keep events flowing while menus are open or windows are resized.
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        return true
    }

    func deactivate() {
        DispatchQueue.main.async {
            self.deactivateOnMain()
        }
    }

    private func deactivateOnMain() {
        let removed: CFRunLoopSource? = lock.withLock {
            defer { source = nil }
            return source
        }
        guard let removed else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), removed, .commonModes)
        CFRunLoopSourceInvalidate(removed)
        // Balance passRetained in activate().
        Unmanaged.passUnretained(self).release()
    }
}
