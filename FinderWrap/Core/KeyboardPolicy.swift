import CoreGraphics
import ApplicationServices
import Foundation

enum KeyboardPolicy {
    static func direction(keyCode: Int64, flags: CGEventFlags, fnKeyDown: Bool) -> NavigationDirection? {
        // Arrow keys themselves carry the function flag. It is not evidence that
        // Fn is held; query that key's state separately to preserve Fn shortcuts.
        let blocked: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskHelp]
        guard !fnKeyDown, flags.intersection(blocked).isEmpty else { return nil }
        switch keyCode { case 123: return .left; case 124: return .right; default: return nil }
    }
}

enum SelectionObservation { case target, original, other, unavailable }
enum SelectionCommitResult: Equatable {
    case committed, unchanged, indeterminate

    var consumesEvent: Bool { self != .unchanged }

    static func perform(write: () -> AXError, readback: () -> SelectionObservation) -> Self {
        let result = write()
        return resolve(writeResult: result, observation: readback())
    }

    static func resolve(writeResult: AXError, observation: SelectionObservation) -> Self {
        // A messaging error is not a rejection. Even an original-item readback
        // cannot rule out a late write, so never replay/pass that ambiguous key.
        switch observation {
        case .target: return .committed
        case .original:
            switch writeResult {
            case .illegalArgument, .attributeUnsupported, .invalidUIElement, .notImplemented, .apiDisabled:
                return .unchanged
            default: return .indeterminate
            }
        case .other, .unavailable: return .indeterminate
        }
    }
}

/// Closing waits for an already-started write; no new write can start after it returns.
/// Separate from the status lock so AX calls cannot deadlock status updates.
final class SelectionWriteGate: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false

    func open() { lock.withLock { enabled = true } }
    func close() { lock.withLock { enabled = false } }
    func perform(_ operation: () -> SelectionCommitResult) -> SelectionCommitResult? {
        lock.withLock { enabled ? operation() : nil }
    }
}
