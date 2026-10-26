import Foundation

/// A logical invalidation revokes publication, but does not cancel a synchronous
/// Apple Event already in flight. Keep its physical slot until the worker exits
/// so repeated interaction cannot enqueue an unbounded sequence of obsolete reads.
struct CaptureWorkGate {
    private var inFlight: NavigationSession.Ticket?

    mutating func begin(session: inout NavigationSession) -> NavigationSession.Ticket? {
        guard inFlight == nil, let ticket = session.beginRefresh() else { return nil }
        inFlight = ticket
        return ticket
    }

    func mayStart(_ ticket: NavigationSession.Ticket, session: NavigationSession, stopped: Bool) -> Bool {
        !stopped && inFlight == ticket && session.accepts(ticket)
    }

    mutating func finish(_ ticket: NavigationSession.Ticket) {
        guard inFlight == ticket else { return }
        inFlight = nil
    }
}

/// Installation readiness is distinct from a layout capture. A capture that
/// requests installation is discarded; only a later capture may use the ready
/// context. Failed creation/registration records a retry deadline, never readiness.
struct ObservationGate<Context: Equatable> {
    struct Attempt: Equatable {
        fileprivate let serial: UInt64
        let context: Context
    }
    enum Requirement: Equatable {
        case ready, pending, retryLater
        case install(Attempt)
    }

    private(set) var readyContext: Context?
    private var pending: Attempt?
    private var failedContext: Context?
    private var retryAt: TimeInterval = 0
    private var serial: UInt64 = 0
    private let retryDelay: TimeInterval

    init(retryDelay: TimeInterval = 1) { self.retryDelay = max(0, retryDelay) }

    mutating func require(_ context: Context, now: TimeInterval) -> Requirement {
        if readyContext == context { return .ready }
        readyContext = nil
        if let pending, pending.context == context { return .pending }
        pending = nil
        if failedContext == context, now < retryAt { return .retryLater }
        serial &+= 1
        let attempt = Attempt(serial: serial, context: context)
        pending = attempt
        return .install(attempt)
    }

    func accepts(_ attempt: Attempt) -> Bool { pending == attempt }

    @discardableResult
    mutating func complete(_ attempt: Attempt, selectedChildrenRegistered: Bool, now: TimeInterval) -> Bool {
        guard accepts(attempt) else { return false }
        pending = nil
        if selectedChildrenRegistered {
            readyContext = attempt.context
            failedContext = nil
        } else {
            readyContext = nil
            failedContext = attempt.context
            retryAt = now + retryDelay
        }
        return true
    }

    mutating func reset() {
        readyContext = nil; pending = nil; failedContext = nil; retryAt = 0
    }
}
