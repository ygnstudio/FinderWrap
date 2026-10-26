import AppKit
import ApplicationServices
import Foundation

private struct ObservedContext: Equatable {
    let pid: pid_t
    let window: AXUIElement
    let collection: AXUIElement
    let viewport: AXUIElement

    init(_ context: VisibleAXContext, pid: pid_t) {
        self.pid = pid; window = context.window; collection = context.collection; viewport = context.viewport
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pid == rhs.pid && CFEqual(lhs.window, rhs.window) && CFEqual(lhs.collection, rhs.collection) && CFEqual(lhs.viewport, rhs.viewport)
    }
}

/// Preview monitor. An optional directory restricts automated test hosts; the
/// application uses the current ordinary Finder folder. All slow
/// capture work runs off the event-tap thread; the callback does local validation
/// and at most one write, with no key injection/replay path.
public final class CandidateMonitor: @unchecked Sendable {
    public struct Status {
        public var requestedEnabled = false
        public var state: NavigationSession.State = .paused
        public var reason = "paused"
        public var confirmed = 0
        public var uncertain = 0
        public var maximumCallbackMS = 0.0
        public var captureMS = 0.0
        public var registeredNotifications = 0
    }
    private let lock = NSLock()
    private let worker = DispatchQueue(label: "dev.finderwrap.rebuild.capture", qos: .userInitiated)
    private let directory: URL?
    private var session = NavigationSession()
    private var captures = CaptureWorkGate()
    private var observations = ObservationGate<ObservedContext>()
    private var prepared: PreparedNavigation?
    private var statusValue = Status()
    private var thread: Thread?
    private var loop: CFRunLoop?
    private var tap: CFMachPort?
    private var timer: Timer?
    private var observer: FinderChangeObserver?
    // The observer itself is owned by the main run loop; its readiness gate is
    // protected by lock. Registration never blocks the event-tap run loop.
    private var stopped = true
    private var lastContextID: Int32?
    private var lastRefreshStarted: TimeInterval = 0

    public init(syntheticDirectory: URL? = nil) {
        self.directory = syntheticDirectory?.standardizedFileURL
    }

    public var status: Status {
        lock.lock(); defer { lock.unlock() }
        var value = statusValue
        value.requestedEnabled = session.requestedEnabled; value.state = session.state
        return value
    }

    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard thread == nil else { return }
        stopped = false; session.setEnabled(true); statusValue.reason = "starting"
        let thread = Thread { [weak self] in self?.run() }
        self.thread = thread; thread.name = "FinderWrap Candidate"; thread.qualityOfService = .userInitiated
        thread.start()
    }

    public func stop() {
        lock.lock()
        stopped = true; session.setEnabled(false); prepared = nil; observations.reset()
        let currentLoop = loop
        lock.unlock()
        if let currentLoop { CFRunLoopStop(currentLoop) }
    }

    /// The host already polls its permission UI on the main thread. Feeding the
    /// result here keeps TCC IPC off the input run loop and allows restoration
    /// without gating the recovery check on the missing permission itself.
    public func updatePermissions(ready: Bool) {
        lock.lock()
        let shouldRestart = ready && session.state == .permissionRequired && session.requestedEnabled && thread == nil && !stopped
        session.permissionsChanged(ready: ready)
        if !ready { prepared = nil; observations.reset() }
        lock.unlock()
        if !ready {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let shouldClear = self.stopped || self.session.state == .permissionRequired
                self.lock.unlock()
                if shouldClear { self.observer?.stop(); self.observer = nil }
            }
        }
        if shouldRestart { start() }
    }

    private func run() {
        guard AXIsProcessTrusted(), CGPreflightListenEventAccess(), FinderSelectionReader().permissionStatus() == 0 else {
            lock.lock(); session.permissionsChanged(ready: false); statusValue.reason = "permissions-required"; thread = nil; lock.unlock()
            return
        }
        let mask = [CGEventType.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, pointer in
                guard let pointer else { return Unmanaged.passUnretained(event) }
                return Unmanaged<CandidateMonitor>.fromOpaque(pointer).takeUnretainedValue().handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            lock.lock(); statusValue.reason = "listener-unavailable"; thread = nil; session.listenerFailed(); lock.unlock()
            return
        }
        let runLoop = CFRunLoopGetCurrent()
        lock.lock(); loop = runLoop; tap = eventTap; let shouldRun = !stopped; lock.unlock()
        if shouldRun {
            CFRunLoopAddSource(runLoop, source, .commonModes)
            let refresh = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.refresh() }
            timer = refresh; RunLoop.current.add(refresh, forMode: .common)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            refresh.fire(); CFRunLoopRun()
            refresh.invalidate(); timer = nil
            DispatchQueue.main.async { [self] in
                observer?.stop(); observer = nil
            }
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        CFMachPortInvalidate(eventTap)
        lock.lock(); loop = nil; tap = nil; thread = nil; prepared = nil; observations.reset(); lock.unlock()
    }

    private func invalidate(_ reason: String) {
        lock.lock(); prepared = nil; session.invalidate(); statusValue.reason = reason; lock.unlock()
    }

    private func refresh() {
        guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == "com.apple.finder",
              let console = CGSessionCopyCurrentDictionary() as? [String: Any], console[kCGSessionOnConsoleKey as String] as? Bool == true else {
            invalidate("finder-not-active"); return
        }
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard !stopped, now - lastRefreshStarted >= 0.15, let ownerLoop = loop,
              let ticket = captures.begin(session: &session) else { lock.unlock(); return }
        lastRefreshStarted = now
        lock.unlock()
        let pid = front.processIdentifier
        worker.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let mayStart = self.captures.mayStart(ticket, session: self.session, stopped: self.stopped)
            if !mayStart { self.captures.finish(ticket) }
            self.lock.unlock()
            guard mayStart else { return }
            let reader = FinderSelectionReader(timeoutTicks: 30)
            let permissionReady = AXIsProcessTrusted() && CGPreflightListenEventAccess() && reader.permissionStatus() == 0
            let outcome: Result<PreparedNavigation, Error>
            if permissionReady {
                outcome = Result { try NavigationPreparer().prepare(reader: reader, pid: pid, allowedDirectory: self.directory) }
            } else { outcome = .failure(FinderSelectionReader.Failure(code: -1743, operation: "permission")) }
            // Release physical ownership even if stop has already ended the
            // destination run loop. Publication still requires the live ticket.
            self.lock.lock(); self.captures.finish(ticket); self.lock.unlock()
            CFRunLoopPerformBlock(ownerLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                defer { self.lock.unlock() }
                guard !self.stopped, self.session.accepts(ticket) else { return }
                guard permissionReady else {
                    self.session.permissionsChanged(ready: false)
                    self.prepared = nil; self.observations.reset()
                    self.statusValue.reason = "permissions-required"
                    return
                }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                    self.session.invalidate(); self.prepared = nil; self.statusValue.reason = "finder-not-active"
                    return
                }
                switch outcome {
                case .success(let capture):
                    if let previous = self.lastContextID, previous != capture.window.id {
                        self.session.invalidate(newContext: true)
                    }
                    self.lastContextID = capture.window.id
                    let observation = self.observations.require(ObservedContext(capture.context, pid: pid), now: ProcessInfo.processInfo.systemUptime)
                    switch observation {
                    case .install(let attempt):
                        self.prepared = nil
                        self.session.invalidate()
                        self.statusValue.reason = "preparing-selection-observer"
                        DispatchQueue.main.async { [weak self] in self?.observe(capture.context, attempt: attempt) }
                        return
                    case .pending, .retryLater:
                        self.prepared = nil
                        _ = self.session.complete(ticket, available: false)
                        self.statusValue.reason = observation == .pending ? "preparing-selection-observer" : "selection-observer-unavailable"
                        return
                    case .ready: break
                    }
                    let available = capture.canEnhance
                    guard self.session.complete(ticket, available: available) else { return }
                    self.prepared = capture; self.statusValue.captureMS = capture.context.captureMS
                    self.statusValue.reason = available ? "prepared-finder-folder" : (capture.writable ? "no-confirmed-boundary-or-single-selection" : "selection-not-writable")
                case .failure(let error):
                    self.prepared = nil
                    if let reason = error as? VisibleAXReader.Failure, case .nativeSurface = reason {
                        _ = self.session.complete(ticket, available: false)
                    } else if error is NavigationPreparer.Failure {
                        _ = self.session.complete(ticket, available: false)
                    } else { self.session.readFailed(ticket) }
                    if let error = error as? FinderSelectionReader.Failure { self.statusValue.reason = "\(error.operation):\(error.code)" }
                    else if let error = error as? AXReadFailure { self.statusValue.reason = "\(error.attribute):\(error.code.rawValue)" }
                    else if let error = error as? VisibleAXReader.Failure { self.statusValue.reason = String(describing: error) }
                    else { self.statusValue.reason = "scope-or-context-changed" }
                }
            }
            CFRunLoopWakeUp(ownerLoop)
        }
    }

    private func observe(_ context: VisibleAXContext, attempt: ObservationGate<ObservedContext>.Attempt) {
        lock.lock()
        let active = !stopped && session.requestedEnabled && session.state != .permissionRequired && observations.accepts(attempt)
        lock.unlock()
        guard active else { return }
        observer?.stop(); observer = nil
        let candidate = try? FinderChangeObserver(pid: attempt.context.pid) { [weak self] _ in self?.invalidate("finder-changed") }
        candidate?.attach(context)
        let selectedChildrenRegistered = candidate?.registrations.contains {
            $0.scope == "collection" && $0.notification == kAXSelectedChildrenChangedNotification && $0.result == 0
        } == true
        lock.lock()
        guard !stopped, session.requestedEnabled, session.state != .permissionRequired,
              observations.complete(attempt, selectedChildrenRegistered: selectedChildrenRegistered, now: ProcessInfo.processInfo.systemUptime) else {
            lock.unlock(); candidate?.stop(); return
        }
        // Never publish the capture that started registration, nor a capture
        // that raced registration. A later capture must observe the new epoch.
        prepared = nil; session.invalidate(native: !selectedChildrenRegistered)
        statusValue.registeredNotifications = selectedChildrenRegistered ? (candidate?.registrations.filter { $0.result == 0 }.count ?? 0) : 0
        statusValue.reason = selectedChildrenRegistered ? "observer-ready-awaiting-fresh-capture" : "selection-observer-unavailable"
        lock.unlock()
        if selectedChildrenRegistered { observer = candidate }
        else { candidate?.stop() }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let timedOut = type == .tapDisabledByTimeout
            lock.lock()
            prepared = nil
            let resume = session.listenerInterrupted(timedOut: timedOut)
            let currentTap = tap
            statusValue.reason = timedOut ? "listener-timeout" : "listener-disabled-by-system"
            lock.unlock()
            if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: resume) }
            return pass
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let blocked: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskHelp]
        guard type == .keyDown, code == 123 || code == 124, event.flags.intersection(blocked).isEmpty,
              !CGEventSource.keyState(.combinedSessionState, key: 63), !CGEventSource.keyState(.hidSystemState, key: 63) else {
            invalidate("interaction-changed"); return pass
        }
        let start = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer {
            statusValue.maximumCallbackMS = max(statusValue.maximumCallbackMS, (ProcessInfo.processInfo.systemUptime - start) * 1000)
            lock.unlock()
        }
        guard !stopped, session.state == .ready, let prepared,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
              let console = CGSessionCopyCurrentDictionary() as? [String: Any], console[kCGSessionOnConsoleKey as String] as? Bool == true else { return pass }
        guard case let .wrap(source, target) = prepared.decision(code == 123 ? .left : .right, now: start),
              source.deletingLastPathComponent().standardizedFileURL == prepared.window.directory,
              target.deletingLastPathComponent().standardizedFileURL == prepared.window.directory,
              directory == nil || directory == prepared.window.directory else { return pass }
        let writer = BoundaryWriter()
        guard BoundaryValidator().validate(prepared.context, from: source, to: target),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            self.prepared = nil; session.invalidate(); statusValue.reason = "boundary-changed"; return pass
        }
        let result = writer.commit(prepared.context, from: source, to: target)
        self.prepared = nil
        switch result {
        case .confirmed: statusValue.confirmed += 1; session.invalidate(); statusValue.reason = "confirmed"
        case .rejected: session.invalidate(); statusValue.reason = "write-rejected"
        case .uncertain: statusValue.uncertain += 1; session.commitUncertain(); statusValue.reason = "uncertain-write-context-quarantined"
        }
        return result.consumesKey ? nil : pass
    }
}
