import Foundation

/// The callback never builds a layout. This immutable handoff is accepted only
/// after two equal official observations bracket a worker capture, and is
/// revoked immediately by interaction/context invalidation.
public struct PreparedNavigation {
    public let context: VisibleAXContext
    public let selection: FinderSelectionReader.Selection
    public let preparedAt: TimeInterval
    public let window: FinderSelectionReader.Window
    public let writable: Bool
    public let canEnhance: Bool
    private static func supportsBoundary(_ context: VisibleAXContext, selection: FinderSelectionReader.Selection, writable: Bool) -> Bool {
        guard writable, case .single = selection else { return false }
        return context.layout.sections.flatMap(\.items).contains { item in
            for direction in [HorizontalDirection.left, .right] {
                if case .wrap = LocalNavigation().decide(layout: context.layout, selection: .single(item.url), direction: direction) { return true }
            }
            return false
        }
    }

    init(context: VisibleAXContext, selection: FinderSelectionReader.Selection,
         window: FinderSelectionReader.Window, preparedAt: TimeInterval, writable: Bool) {
        self.context = context; self.selection = selection; self.window = window; self.preparedAt = preparedAt
        self.writable = writable
        self.canEnhance = Self.supportsBoundary(context, selection: selection, writable: writable)
    }

    public func decision(_ direction: HorizontalDirection, now: TimeInterval) -> LocalDecision {
        guard writable, now >= preparedAt, now - preparedAt <= 0.3 else { return .native }
        return LocalNavigation().decide(layout: context.layout, selection: selection, direction: direction)
    }
}

public struct NavigationPreparer {
    public enum Failure: Error { case changed, outsideScope }
    public init() {}

    /// Invoked on a worker with a session ticket. Completion still has to pass
    /// NavigationSession.complete; equal endpoints alone cannot detect an ABA
    /// focus/selection transition that happened during these requests.
    public func prepare(reader: FinderSelectionReader, pid: pid_t, allowedDirectory: URL? = nil) throws -> PreparedNavigation {
        let beforeWindow = try reader.frontWindow()
        if let allowedDirectory, beforeWindow.directory != allowedDirectory.standardizedFileURL { throw Failure.outsideScope }
        let beforeSelection = try reader.read()
        let context = try VisibleAXReader().capture(pid: pid, officialWindow: beforeWindow, allowedDirectory: beforeWindow.directory)
        let afterSelection = try reader.read()
        let afterWindow = try reader.frontWindow()
        guard beforeWindow == afterWindow, beforeSelection == afterSelection else { throw Failure.changed }
        return PreparedNavigation(context: context, selection: afterSelection, window: afterWindow,
                                  preparedAt: ProcessInfo.processInfo.systemUptime, writable: BoundaryWriter().isWritable(context))
    }
}
