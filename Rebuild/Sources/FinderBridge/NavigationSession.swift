import Foundation

/// One serial coordinator owns this state. Epochs reject worker results that
/// complete after a mouse/key/window/focus change, including an enable/disable
/// cycle that happens while a read is in flight.
public struct NavigationSession {
    public enum State: Equatable {
        case paused, preparing, ready, native, recovering, permissionRequired, listenerUnavailable
        case uncertainCommit
    }
    public struct Ticket: Equatable {
        fileprivate let generation: UInt64
        fileprivate let request: UInt64
    }
    public private(set) var requestedEnabled = false
    public private(set) var state: State = .paused
    private var generation: UInt64 = 0
    private var request: UInt64 = 0
    private var timeoutCount = 0
    private var pending: Ticket?
    private var permissionReady = true
    private var listenerUnavailable = false
    // An uncertain AX write can complete late; a timer or a second selection
    // read cannot prove it finished. Only a new context or explicit user resume
    // can release the old context quarantine.
    private var quarantined = false

    public init() {}
    public mutating func setEnabled(_ enabled: Bool) {
        requestedEnabled = enabled; generation &+= 1; pending = nil; timeoutCount = 0; listenerUnavailable = false
        if !enabled { state = .paused; return }
        quarantined = false
        state = permissionReady ? .preparing : .permissionRequired
    }
    public mutating func permissionsChanged(ready: Bool) {
        guard ready != permissionReady else { return }
        permissionReady = ready; generation &+= 1; pending = nil
        state = requestedEnabled ? (ready ? usableState : .permissionRequired) : .paused
    }
    public mutating func invalidate(newContext: Bool = false, native: Bool = false) {
        generation &+= 1; pending = nil
        if newContext { quarantined = false }
        guard requestedEnabled, permissionReady else { return }
        state = native && usableState == .preparing ? .native : usableState
    }
    public mutating func beginRefresh() -> Ticket? {
        guard requestedEnabled, permissionReady, !quarantined, !listenerUnavailable, pending == nil else { return nil }
        request &+= 1
        let ticket = Ticket(generation: generation, request: request)
        pending = ticket
        return ticket
    }
    public func accepts(_ ticket: Ticket) -> Bool {
        pending == ticket && ticket.generation == generation && requestedEnabled && permissionReady && !quarantined && !listenerUnavailable
    }
    @discardableResult public mutating func complete(_ ticket: Ticket, available: Bool) -> Bool {
        guard accepts(ticket) else { return false }
        pending = nil; state = available ? .ready : .native
        return true
    }
    public mutating func readFailed(_ ticket: Ticket) {
        guard pending == ticket, ticket.generation == generation else { return }
        pending = nil
        if requestedEnabled && permissionReady && !quarantined { state = .recovering }
    }
    public mutating func commitUncertain() {
        generation &+= 1; pending = nil; quarantined = true
        if requestedEnabled { state = permissionReady ? .uncertainCommit : .permissionRequired }
    }
    public mutating func listenerFailed() {
        generation &+= 1; pending = nil; listenerUnavailable = true
        if requestedEnabled { state = .listenerUnavailable }
    }
    /// A system tap-control event is not the user's application toggle. Only
    /// timeouts can recover automatically; other disables wait for explicit
    /// resume while preserving the requested setting.
    public mutating func listenerInterrupted(timedOut: Bool) -> Bool {
        if timedOut { return tapTimedOut() }
        listenerFailed()
        return false
    }
    /// At most two automatic re-enables in one context. A successful capture does
    /// not reset this counter, or a repeated timeout could create an endless loop.
    public mutating func tapTimedOut() -> Bool {
        guard requestedEnabled, permissionReady, !quarantined, !listenerUnavailable else { return false }
        generation &+= 1; pending = nil; timeoutCount += 1; state = .recovering
        if timeoutCount > 2 { listenerUnavailable = true; state = .listenerUnavailable; return false }
        return true
    }

    private var usableState: State {
        listenerUnavailable ? .listenerUnavailable : (quarantined ? .uncertainCommit : .preparing)
    }
}
