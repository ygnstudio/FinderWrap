import AppKit
import ApplicationServices
import Foundation

/// Revalidates only the focus, viewport, source and target. It deliberately has
/// no directory enumeration or Apple Event calls. This is not a full-selection
/// proof; the caller must hold an unexpired, non-invalidated official proof.
public struct BoundaryValidator {
    public init() {}
    public func validate(_ context: VisibleAXContext, from: URL, to: URL,
                         budget: TimeInterval = 0.025) -> Bool {
        guard let source = context.bindings[from], let target = context.bindings[to], from != to else { return false }
        let ax = AXBatchReader(deadline: ProcessInfo.processInfo.systemUptime + budget)
        for element in [context.application, context.window, context.viewport, source.image, target.image] {
            AXUIElementSetMessagingTimeout(element, 0.008)
        }
        do {
            let focus = try ax.fields(context.application, [kAXFocusedUIElementAttribute, kAXFocusedWindowAttribute])
            // A fresh focus must be the exact collection. An item-specific focus
            // is left native until an adapter can demonstrate its ownership.
            guard let focused = focus.element(kAXFocusedUIElementAttribute), CFEqual(focused, context.collection),
                  let window = focus.element(kAXFocusedWindowAttribute), CFEqual(window, context.window),
                  try ax.fields(window, AXBatchReader.geometry).frame == context.windowFrame,
                  try ax.fields(context.viewport, AXBatchReader.geometry).frame == context.viewportFrame else { return false }
            let original = try ax.fields(source.image, AXBatchReader.itemFields + [kAXWindowAttribute])
            let destination = try ax.fields(target.image, AXBatchReader.itemFields + [kAXWindowAttribute])
            guard original.url == from, original.frame == source.frame, original.value(kAXSelectedAttribute) as? Bool == true,
                  destination.url == to, destination.frame == target.frame, destination.value(kAXSelectedAttribute) as? Bool == false,
                  let owner = original.element(kAXWindowAttribute), CFEqual(owner, context.window),
                  let destinationOwner = destination.element(kAXWindowAttribute), CFEqual(destinationOwner, context.window) else { return false }
            return ax.withinBudget
        } catch { return false }
    }
}
