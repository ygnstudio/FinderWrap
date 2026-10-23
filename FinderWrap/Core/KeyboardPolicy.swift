import CoreGraphics

enum KeyboardPolicy {
    static func direction(keyCode: Int64, flags: CGEventFlags) -> NavigationDirection? {
        // CGEvent may carry non-modifier metadata bits, including on otherwise plain
        // system-posted keys. Test documented modifier semantics, not raw equality.
        let blocked: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn, .maskHelp]
        guard flags.intersection(blocked).isEmpty else { return nil }
        switch keyCode { case 123: return .left; case 124: return .right; default: return nil }
    }
}

enum SelectionObservation { case target, original, other, unavailable }
enum SelectionCommitResult: Equatable {
    case committed, unchanged, indeterminate

    static func resolve(writeSucceeded: Bool, observation: SelectionObservation) -> Self {
        // Actual readback outranks a transport return code. Success without readback
        // cannot justify swallowing a key, and a timeout does not prove no write occurred.
        switch observation {
        case .target: return .committed
        case .original: return .unchanged
        case .other, .unavailable: return .indeterminate
        }
    }
}
