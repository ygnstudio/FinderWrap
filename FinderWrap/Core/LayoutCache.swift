import Foundation

/// Only immutable context references cross the worker/tap boundary.
final class LayoutCache: @unchecked Sendable {
    private let lock = NSLock()
    private var value: FinderContext?
    private var epoch: UInt64 = 0

    func beginRefresh() -> UInt64 { lock.withLock { epoch } }
    func store(_ context: FinderContext?, epoch expected: UInt64) {
        lock.withLock { if epoch == expected { value = context } }
    }
    func invalidate() { lock.withLock { epoch &+= 1; value = nil } }
    func current() -> FinderContext? {
        lock.withLock {
            guard let value, ProcessInfo.processInfo.systemUptime - value.createdAt <= 0.35 else { return nil }
            return value
        }
    }
}
