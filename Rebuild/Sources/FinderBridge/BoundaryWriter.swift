import ApplicationServices
import Foundation

public enum BoundaryWriteResult: Equatable {
    case confirmed, rejected, uncertain
    public var consumesKey: Bool { self != .rejected }

    static func resolve(error: AXError, sourceSelected: Bool?, targetSelected: Bool?, onlyTarget: Bool) -> Self {
        if targetSelected == true && sourceSelected == false && onlyTarget { return .confirmed }
        if sourceSelected == true && targetSelected == false {
            switch error {
            case .illegalArgument, .attributeUnsupported, .invalidUIElement, .notImplemented, .apiDisabled: return .rejected
            default: break
            }
        }
        // Timeout and missing readback are not proof of rejection. Never replay
        // the original event or retry this write after returning uncertain.
        return .uncertain
    }
}

public struct BoundaryWriter {
    public init() {}
    public func isWritable(_ context: VisibleAXContext) -> Bool {
        AXUIElementSetMessagingTimeout(context.collection, 0.008)
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(context.collection, kAXSelectedChildrenAttribute as CFString, &result) == .success && result.boolValue
    }
    public func commit(_ context: VisibleAXContext, from: URL, to: URL) -> BoundaryWriteResult {
        guard let source = context.bindings[from], let target = context.bindings[to] else { return .rejected }
        let result = AXUIElementSetAttributeValue(context.collection, kAXSelectedChildrenAttribute as CFString, [target.wrapper] as CFArray)
        let ax = AXBatchReader(deadline: ProcessInfo.processInfo.systemUptime + 0.025)
        let original = try? ax.fields(source.image, [kAXSelectedAttribute])
        let destination = try? ax.fields(target.image, [kAXSelectedAttribute])
        let selected = try? ax.children(context.collection, attribute: kAXSelectedChildrenAttribute)
        let onlyTarget = selected?.count == 1 && selected?.contains(where: { CFEqual($0, target.wrapper) || CFEqual($0, target.image) }) == true
        return .resolve(error: result, sourceSelected: original?.value(kAXSelectedAttribute) as? Bool,
                        targetSelected: destination?.value(kAXSelectedAttribute) as? Bool, onlyTarget: onlyTarget)
    }
}
