import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Event-tap driven wrap monitor.
///
/// Concurrency model:
/// - The tap thread owns the CGEvent tap and performs only bounded AX calls:
///   focused window/element, one selection read, two frame checks, one write and
///   one readback.
/// - A serial background queue owns the full grid capture and publishes an
///   immutable snapshot under a lock. Selection changes never invalidate it, so
///   continuous arrow navigation keeps a ready layout between key presses.
public final class FinderWrapMonitor {
    public enum State: String, Sendable {
        case paused, starting, ready, native, recovering, permissionRequired, listenerUnavailable
    }

    public struct Status {
        public var enabled = false
        public var state: State = .paused
        public var message = "已暂停"
        public var reason = "paused"
        public var wrapCount = 0
        public var rejectedCount = 0
        public var uncertainCount = 0
        public var itemCount = 0
        public var rowCount = 0
        public var captureMS = 0.0
        public var gridRole = "-"
        public var lastDecision = "none"
        public var accessibility = false
        public var inputMonitoring = false
        public var permissionReady: Bool { accessibility && inputMonitoring }
    }

    private enum WriteResult { case confirmed, rejected, uncertain }

    private let lock = NSLock()
    private let reader = GridReader()
    private let engine = WrapEngine()
    private let refreshQueue = DispatchQueue(label: "dev.finderwrap.grid", qos: .utility)

    private var statusValue = Status()
    private var snapshot: GridSnapshot?
    private var enabled = false
    private var tapThread: Thread?
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private var refreshTimer: DispatchSourceTimer?
    private var lastRefreshStarted: TimeInterval = 0
    private var decisionLog: [String] = []
    private var captureLog: [String] = []
    private var lastFailure = ""
    private var listTrace = ""
    private var listWrapEnabled = UserDefaults.standard.bool(forKey: "listWrapEnabled")
    private var galleryCycleEnabled = (UserDefaults.standard.object(forKey: "galleryCycleEnabled") as? Bool) ?? true

    public init() {}

    public var status: Status {
        lock.lock()
        defer { lock.unlock() }
        var value = statusValue
        value.enabled = enabled
        value.accessibility = AXIsProcessTrusted()
        value.inputMonitoring = CGPreflightListenEventAccess()
        return value
    }

    @discardableResult
    public func setEnabled(_ value: Bool) -> Bool {
        if !value {
            lock.lock()
            enabled = false
            stopLocked()
            statusValue.state = .paused
            statusValue.message = "已暂停"
            statusValue.reason = "paused"
            statusValue.lastDecision = "paused"
            lock.unlock()
            return true
        }
        let accessibility = AXIsProcessTrusted()
        let inputMonitoring = CGPreflightListenEventAccess()
        guard accessibility, inputMonitoring else {
            lock.lock()
            enabled = false
            statusValue.accessibility = accessibility
            statusValue.inputMonitoring = inputMonitoring
            statusValue.state = .permissionRequired
            statusValue.message = "等待系统权限"
            statusValue.reason = "permissions-required"
            lock.unlock()
            return false
        }
        lock.lock()
        statusValue.accessibility = accessibility
        statusValue.inputMonitoring = inputMonitoring
        guard !enabled, tapThread == nil else { lock.unlock(); return true }
        enabled = true
        statusValue.state = .starting
        statusValue.message = "正在准备图标布局"
        statusValue.reason = "starting"
        lock.unlock()
        startTap()
        startRefresh()
        return true
    }

    public func stop() {
        lock.lock()
        enabled = false
        stopLocked()
        statusValue.state = .paused
        statusValue.message = "已暂停"
        statusValue.reason = "paused"
        lock.unlock()
    }

    public func setListWrap(_ value: Bool) {
        lock.lock(); listWrapEnabled = value; lock.unlock()
    }

    public func setGalleryCycle(_ value: Bool) {
        lock.lock(); galleryCycleEnabled = value; lock.unlock()
    }

    /// Called with the lock held.
    private func stopLocked() {
        snapshot = nil
        refreshTimer?.cancel()
        refreshTimer = nil
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    // MARK: - Tap

    private func startTap() {
        let thread = Thread { [weak self] in self?.runTap() }
        thread.name = "FinderWrap Keys"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
    }

    private func runTap() {
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                return Unmanaged<FinderWrapMonitor>.fromOpaque(info).takeUnretainedValue().handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            lock.lock()
            enabled = false
            tapThread = nil
            statusValue.state = .listenerUnavailable
            statusValue.message = "监听不可用，请暂停后重新启用"
            statusValue.reason = "listener-unavailable"
            lock.unlock()
            return
        }
        let loop = CFRunLoopGetCurrent()
        lock.lock()
        runLoop = loop
        tap = eventTap
        let shouldRun = enabled
        lock.unlock()
        if shouldRun {
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            CFRunLoopRun()
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        CFMachPortInvalidate(eventTap)
        lock.lock()
        runLoop = nil
        tap = nil
        tapThread = nil
        lock.unlock()
    }

    // MARK: - Refresh

    private func startRefresh() {
        refreshQueue.async { [weak self] in self?.refresh() }
        lock.lock()
        refreshTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: refreshQueue)
        timer.schedule(deadline: .now() + .milliseconds(350), repeating: .milliseconds(350), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.refresh() }
        refreshTimer = timer
        lock.unlock()
        timer.resume()
    }

    private func forceRefresh() {
        lock.lock()
        lastRefreshStarted = 0
        lock.unlock()
        refreshQueue.async { [weak self] in self?.refresh() }
    }

    private func refresh() {
        lock.lock()
        let isEnabled = enabled
        let now = ProcessInfo.processInfo.systemUptime
        guard isEnabled, now - lastRefreshStarted >= 0.2 else { lock.unlock(); return }
        lastRefreshStarted = now
        lock.unlock()

        let front = NSWorkspace.shared.frontmostApplication
        let frontBundle = front?.bundleIdentifier
        let finderFront = frontBundle == "com.apple.finder"
        let quickLookFront = frontBundle?.lowercased().contains("quicklook") == true
        guard finderFront || quickLookFront,
              let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            lock.lock()
            statusValue.state = .native
            statusValue.message = "Finder 不在前台"
            statusValue.reason = "finder-not-active"
            lock.unlock()
            return
        }
        let started = ProcessInfo.processInfo.systemUptime
        do {
            let fresh = try reader.capture(pid: finder.processIdentifier)
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            lock.lock()
            guard enabled else { lock.unlock(); return }
            snapshot = fresh
            appendCaptureLog("ok(rows=\(fresh.layout.rows.count),cells=\(fresh.layout.cells.count) quickLook=\(fresh.quickLook))")
            lastFailure = ""
            statusValue.state = .ready
            statusValue.message = fresh.quickLook
                ? "Quick Look：\(fresh.layout.rows.count) 行 · \(fresh.layout.cells.count) 个图标"
                : "已就绪：\(fresh.layout.rows.count) 行 · \(fresh.layout.cells.count) 个图标"
            statusValue.reason = "ready"
            statusValue.itemCount = fresh.layout.cells.count
            statusValue.rowCount = fresh.layout.rows.count
            statusValue.captureMS = elapsed
            statusValue.gridRole = fresh.gridRole
            lock.unlock()
        } catch let failure as GridFailure {
            lock.lock()
            snapshot = nil
            appendCaptureLog("fail(\(failure.stage))")
            lastFailure = failure.detail
            if failure.stage == "grid" {
                statusValue.state = .native
                statusValue.message = "当前不是可换行的图标视图"
                statusValue.reason = "not-icon-view"
            } else {
                statusValue.state = .recovering
                statusValue.message = "读取暂时失败，正在重试"
                statusValue.reason = "read-failed"
            }
            statusValue.itemCount = 0
            statusValue.rowCount = 0
            lock.unlock()
        } catch {
            lock.lock()
            snapshot = nil
            appendCaptureLog("fail(unknown)")
            statusValue.state = .recovering
            statusValue.message = "读取暂时失败，正在重试"
            statusValue.reason = "read-failed"
            lock.unlock()
        }
    }

    // MARK: - Keys

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let currentTap = tap
            statusValue.reason = "listener-interrupted"
            lock.unlock()
            if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: true) }
            return pass
        }
        guard type == .keyDown else { return pass }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard code == 123 || code == 124 else { return pass }
        let blocked: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskHelp]
        guard event.flags.intersection(blocked).isEmpty,
              !CGEventSource.keyState(.combinedSessionState, key: 63),
              !CGEventSource.keyState(.hidSystemState, key: 63) else { return pass }
        let direction: HorizontalDirection = code == 123 ? .left : .right

        let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let finderFront = frontBundle == "com.apple.finder"
        let quickLookFront = frontBundle?.lowercased().contains("quicklook") == true
        guard finderFront || quickLookFront else {
            record("not-finder:\(frontBundle ?? "?")")
            return pass
        }

        // List view is an outline, not a grid. When its switch is on, left/right
        // become previous/next item with wraparound; up/down stay native.
        if handleListKey(direction) { return nil }

        lock.lock()
        let current = snapshot
        let now = ProcessInfo.processInfo.systemUptime
        lock.unlock()
        guard let current, now - current.capturedAt <= 1.5 else {
            record("no-layout")
            return pass
        }

        if current.quickLook {
            guard let focusedWindow = AX.element(current.application, kAXFocusedWindowAttribute),
                  GridReader.isQuickLookWindow(focusedWindow) else {
                record("quicklook-gone")
                return pass
            }
        } else {
            guard focusBelongsToGrid(current) else {
                record("focus-outside-grid")
                return pass
            }
        }

        guard let selection = reader.selection(for: current) else {
            record("selection-unavailable")
            return pass
        }

        if current.gridIdentifier == "GalleryView" {
            return handleGalleryKey(current, selection: selection, direction: direction) ? nil : pass
        }
        let decision = engine.decide(layout: current.layout, selection: selection, direction: direction)
        guard case let .wrap(from, to) = decision else {
            record("native")
            return pass
        }
        guard let source = current.cells.first(where: { $0.url == from }),
              let target = current.cells.first(where: { $0.url == to }) else {
            record("stale-cells")
            return pass
        }
        guard framesMatch(source: source, target: target) else {
            record("frames-moved")
            forceRefresh()
            return pass
        }
        return performGridWrap(current, source: source, target: target) ? nil : pass
    }

    /// Finer-style takeover for gallery view: every left/right press is computed
    /// from the AX selection and written back, so Finder's own keyboard cursor
    /// never has to agree with the highlight. Writes the selected-children
    /// collection, then focuses it (Finer's setSelection does the same) and
    /// reveals the target.
    private func handleGalleryKey(_ current: GridSnapshot, selection: GridSelection,
                                  direction: HorizontalDirection) -> Bool {
        lock.lock()
        let enabled = galleryCycleEnabled
        lock.unlock()
        guard enabled, let row = current.layout.rows.first, row.count > 1,
              case let .single(selectedURL) = selection,
              let index = row.firstIndex(where: { $0.url == selectedURL }) else { return false }
        let targetIndex = (index + (direction == .right ? 1 : -1) + row.count) % row.count
        guard let target = current.cells.first(where: { $0.url == row[targetIndex].url }) else { return false }

        AX.setTimeout(current.grid, 0.1)
        _ = AXUIElementSetAttributeValue(current.grid, kAXSelectedChildrenAttribute as CFString, [target.wrapper] as CFArray)
        Thread.sleep(forTimeInterval: 0.02)
        let readback = AX.elements(current.grid, kAXSelectedChildrenAttribute)
        let confirmed = readback.count == 1 && (CFEqual(readback[0], target.wrapper) || CFEqual(readback[0], target.image))
        guard confirmed else {
            record("gallery-write-failed idx=\(index)/\(row.count)")
            return false
        }
        if AX.isSettable(current.grid, kAXFocusedAttribute) {
            _ = AXUIElementSetAttributeValue(current.grid, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        scrollToVisible(target.wrapper, children: [target.image])
        lock.lock()
        statusValue.wrapCount += 1
        statusValue.reason = "gallery-stepped"
        statusValue.lastDecision = "gallery-stepped"
        lock.unlock()
        record("gallery-step \(index)->\(targetIndex)/\(row.count)")
        return true
    }

    private func performGridWrap(_ current: GridSnapshot, source: BoundGridCell, target: BoundGridCell) -> Bool {
        let result = commit(current, source: source, target: target)
        if result == .confirmed {
            scrollToVisible(target.wrapper, children: [target.image])
        }
        lock.lock()
        switch result {
        case .confirmed:
            statusValue.wrapCount += 1
            statusValue.reason = "wrapped"
            statusValue.lastDecision = "wrapped"
        case .rejected:
            statusValue.rejectedCount += 1
            statusValue.reason = "write-rejected"
            statusValue.lastDecision = "write-rejected"
        case .uncertain:
            statusValue.uncertainCount += 1
            statusValue.reason = "write-uncertain"
            statusValue.lastDecision = "write-uncertain"
        }
        lock.unlock()
        return result != .rejected
    }

    /// List view is linear, so left/right become previous/next row (native Up /
    /// Down), and the ends delegate to Home / End. Everything is a native key
    /// press: Finder scrolls and keeps its own selection intact. No AX write can
    /// drop the selection.
    /// List view: left/right stay a native previous/next row (Up/Down) while the
    /// option is on. The two document ends are consumed deliberately: passing the
    /// key through would make Finder expand/collapse a folder, which felt random.
    /// Wrapping the ends is not supported (Finder 26 clears the selection when a
    /// non-visible row is written through AX).
    private func handleListKey(_ direction: HorizontalDirection) -> Bool {
        lock.lock()
        let enabled = listWrapEnabled
        lock.unlock()
        guard enabled,
              let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            return false
        }
        let application = AXUIElementCreateApplication(finder.processIdentifier)
        AX.setTimeout(application, 0.05)
        guard let focused = AX.element(application, kAXFocusedUIElementAttribute),
              AX.role(focused) == "AXOutline",
              AX.string(focused, kAXIdentifierAttribute) == "ListView" else { return false }
        AX.setTimeout(focused, 0.2)

        var rows = AX.elements(focused, kAXRowsAttribute)
        if rows.isEmpty {
            rows = AX.children(focused, kAXChildrenAttribute, limit: 4000).filter { AX.role($0) == "AXRow" }
        }
        guard rows.count > 1 else { return false }

        var selectedIndex: Int?
        if let selected = AX.elements(focused, kAXSelectedRowsAttribute).first {
            selectedIndex = rows.firstIndex(where: { CFEqual($0, selected) })
        }
        if selectedIndex == nil {
            selectedIndex = rows.firstIndex { (AX.value($0, kAXSelectedAttribute) as? Bool) == true }
        }
        guard let index = selectedIndex else { return false }

        if direction == .right && index + 1 == rows.count {
            record("list-end")
            return true
        }
        if direction == .left && index == 0 {
            record("list-start")
            return true
        }
        postNativeKey(direction == .right ? 125 : 126)   // native Down / Up
        setListTrace("rows=\(rows.count) index=\(index)")
        record("list-step \(index)")
        return true
    }

    private func postNativeKey(_ keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Selection changes do not always scroll the new item into view; ask the
    /// provider to reveal it explicitly after a confirmed write.
    private func scrollToVisible(_ element: AXUIElement, children: [AXUIElement] = []) {
        if AXUIElementPerformAction(element, "AXScrollToVisible" as CFString) == .success { return }
        for child in children {
            if AXUIElementPerformAction(child, "AXScrollToVisible" as CFString) == .success { return }
        }
    }

    private func setListTrace(_ text: String) {
        lock.lock()
        listTrace = text
        lock.unlock()
    }

    private func valueShape(_ raw: CFTypeRef?) -> String {
        guard let raw else { return "nil" }
        let type = CFGetTypeID(raw)
        if type == CFArrayGetTypeID() { return "array(\(CFArrayGetCount(raw as! CFArray)))" }
        if type == AXUIElementGetTypeID() { return "element" }
        return "type=\(type)"
    }

    private func selectedFlag(_ row: AXUIElement) -> Bool {
        if (AX.value(row, kAXSelectedAttribute) as? Bool) == true { return true }
        for child in AX.children(row, kAXChildrenAttribute, limit: 4) {
            if (AX.value(child, kAXSelectedAttribute) as? Bool) == true { return true }
        }
        return false
    }

    private func focusBelongsToGrid(_ snapshot: GridSnapshot) -> Bool {
        guard let focused = AX.element(snapshot.application, kAXFocusedUIElementAttribute) else { return false }
        if CFEqual(focused, snapshot.grid) { return true }
        var node: AXUIElement? = AX.parent(focused)
        for _ in 0..<10 {
            guard let current = node else { return false }
            if CFEqual(current, snapshot.grid) { return true }
            node = AX.parent(current)
        }
        return false
    }

    private func framesMatch(source: BoundGridCell, target: BoundGridCell) -> Bool {
        guard let sourceFrame = AX.frame(source.image), let targetFrame = AX.frame(target.image) else { return false }
        return sourceFrame == source.frame && targetFrame == target.frame
    }

    private func commit(_ snapshot: GridSnapshot, source: BoundGridCell, target: BoundGridCell) -> WriteResult {
        AX.setTimeout(snapshot.grid, 0.05)
        let collectionError = AXUIElementSetAttributeValue(
            snapshot.grid, kAXSelectedChildrenAttribute as CFString, [target.wrapper] as CFArray)

        if snapshot.selectedChildrenSupported {
            let selected = AX.children(snapshot.grid, kAXSelectedChildrenAttribute, limit: 2)
            let targetSelected = selected.contains { CFEqual($0, target.wrapper) || CFEqual($0, target.image) }
            let sourceSelected = selected.contains { CFEqual($0, source.wrapper) || CFEqual($0, source.image) }
            if targetSelected, !sourceSelected, selected.count == 1 { return .confirmed }
            if sourceSelected, !targetSelected, Self.isHardRejection(collectionError) {
                // The collection refuses writes; try per-item selection below.
            } else {
                return .uncertain
            }
        } else if collectionError == .success {
            return .uncertain
        }

        // Per-item fallback: some surfaces (the desktop icon group) do not
        // expose a settable selected-children collection but do expose the
        // selected state on the icon elements.
        let setTarget = AXUIElementSetAttributeValue(target.image, kAXSelectedAttribute as CFString, kCFBooleanTrue)
        let clearSource = AXUIElementSetAttributeValue(source.image, kAXSelectedAttribute as CFString, kCFBooleanFalse)
        let targetOn = (AX.value(target.image, kAXSelectedAttribute) as? Bool) == true
        let sourceOff = CFEqual(source.image, target.image)
            ? true
            : (AX.value(source.image, kAXSelectedAttribute) as? Bool) == false
        if targetOn, sourceOff { return .confirmed }
        if Self.isHardRejection(setTarget), Self.isHardRejection(clearSource) { return .rejected }
        return .uncertain
    }

    private static func isHardRejection(_ error: AXError) -> Bool {
        switch error {
        case .illegalArgument, .attributeUnsupported, .invalidUIElement, .notImplemented, .apiDisabled:
            return true
        default:
            return false
        }
    }

    private func record(_ decision: String) {
        lock.lock()
        statusValue.lastDecision = decision
        decisionLog.append(decision)
        if decisionLog.count > 10 { decisionLog.removeFirst(decisionLog.count - 10) }
        lock.unlock()
    }

    /// Called with the lock held.
    private func appendCaptureLog(_ entry: String) {
        captureLog.append(entry)
        if captureLog.count > 6 { captureLog.removeFirst(captureLog.count - 6) }
    }

    // MARK: - Diagnostics

    public func diagnostics() -> String {
        lock.lock()
        let status = statusValue
        let current = snapshot
        let log = decisionLog
        let captures = captureLog
        let failure = lastFailure
        let listTraceValue = listTrace
        let enabledNow = enabled
        lock.unlock()

        var lines: [String] = []
        lines.append("FinderWrap 1.0.5 (rebuild)")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Enabled: \(enabledNow)")
        lines.append("State: \(status.state.rawValue) reason=\(status.reason)")
        lines.append("Accessibility: \(AXIsProcessTrusted())  Input monitoring: \(CGPreflightListenEventAccess())")
        lines.append("Wraps: \(status.wrapCount)  rejected: \(status.rejectedCount)  uncertain: \(status.uncertainCount)")
        lines.append("List wrap: \(listWrapEnabled)  gallery cycle: \(galleryCycleEnabled)")
        lines.append("Message: \(status.message)")
        lines.append("Frontmost: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            lines.append("Finder AX dump:")
            lines.append(reader.describeFinder(pid: finder.processIdentifier))
        }
        if let current {
            lines.append("QuickLook: \(current.quickLook)  gallery=\(current.gridIdentifier == "GalleryView")")
            lines.append("Grid role: \(current.gridRole)/\(current.gridSubrole)/\(current.gridIdentifier)  selectedChildren=\(current.selectedChildrenSupported)  cells: \(current.layout.cells.count)  rows: \(current.layout.rows.count)")
            lines.append("Row widths: \(current.layout.rows.map(\.count).map(String.init).joined(separator: ","))")
            lines.append("Window frame: \(current.windowFrame)  viewport: \(current.viewportFrame)")
            let age = (ProcessInfo.processInfo.systemUptime - current.capturedAt) * 1000
            lines.append("Capture: \(String(format: "%.0f", age)) ms ago  \(String(format: "%.1f", status.captureMS)) ms")
            switch reader.selection(for: current) {
            case .single: lines.append("Selection: single")
            case .multiple(let urls): lines.append("Selection: multiple(\(urls.count))")
            case .empty: lines.append("Selection: empty")
            case nil: lines.append("Selection: unavailable")
            }
        } else {
            lines.append("Grid: none")
        }
        if !log.isEmpty { lines.append("Recent decisions: " + log.joined(separator: " | ")) }
        if !captures.isEmpty { lines.append("Recent captures: " + captures.joined(separator: " | ")) }
        if !failure.isEmpty { lines.append("Last capture failure: " + String(failure.prefix(900))) }
        if !listTraceValue.isEmpty { lines.append("List trace: " + listTraceValue) }
        lines.append("Frontmost: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
        lines.append("No filenames, paths or keyboard contents included.")
        return lines.joined(separator: "\n")
    }
}
