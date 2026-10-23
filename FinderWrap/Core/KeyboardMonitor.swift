import ApplicationServices
import Foundation
import OSLog

struct MonitorStatus: Codable, Sendable {
    var running = false
    var message = "已暂停"
    var committed = 0
    var unchanged = 0
    var indeterminate = 0
    var maximumCallbackMS = 0.0
    var lastCallbackMS = 0.0
    var arrowEvents = 0
    var lastArrowFlags: UInt64 = 0
    var captureDiagnostic = "not-started"
    var cacheReady = false
    var failure: String?
    var lastDecision = "none"
}

final class KeyboardMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private let cache = LayoutCache()
    private let worker = DispatchQueue(label: "dev.finderwrap.layout", qos: .userInitiated)
    private var refreshTimer: DispatchSourceTimer?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var stopping = true
    private var state = MonitorStatus()
    private let logger = Logger(subsystem: "dev.finderwrap", category: "navigation")
    private let allowedDirectories: Set<String>?

    init(allowedDirectories: Set<String>? = nil) { self.allowedDirectories = allowedDirectories }

    var status: MonitorStatus { lock.withLock { state } }

    func start() {
        guard lock.withLock({ thread == nil }) else { return }
        guard AXIsProcessTrusted() else { fail("需要辅助功能权限"); return }
        guard CGPreflightListenEventAccess() else { fail("需要输入监控权限"); return }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.01)
        lock.withLock { stopping = false; state.message = "正在启动" }
        let timer = DispatchSource.makeTimerSource(queue: worker)
        timer.schedule(deadline: .now(), repeating: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            guard let self, !self.lock.withLock({ self.stopping }) else { return }
            let epoch = self.cache.beginRefresh()
            let context = FinderAccessibility().capture(allowedDirectories: self.allowedDirectories) { reason in
                self.lock.withLock { self.state.captureDiagnostic = reason }
            }
            self.lock.withLock { self.state.cacheReady = context != nil }
            self.cache.store(context, epoch: epoch)
        }
        refreshTimer = timer
        timer.resume()
        let newThread = Thread { [weak self] in self?.runTap() }
        newThread.name = "FinderWrap Keyboard"
        newThread.qualityOfService = .userInteractive
        lock.withLock { thread = newThread }
        newThread.start()
    }

    func stop() {
        let loop = lock.withLock { stopping = true; state.running = false; state.message = "已暂停"; return runLoop }
        refreshTimer?.cancel(); refreshTimer = nil
        cache.invalidate()
        if let loop { CFRunLoopStop(loop) }
    }

    private func fail(_ message: String) {
        lock.withLock { state.message = message; state.failure = message }
    }

    private func runTap() {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask,
                                         callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return Unmanaged<KeyboardMonitor>.fromOpaque(info).takeUnretainedValue().handle(type, event)
        }, userInfo: pointer), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            lock.withLock {
                stopping = true; thread = nil
                state.message = "无法创建键盘监听，请检查权限"
                state.failure = state.message
            }
            return
        }
        let loop = CFRunLoopGetCurrent()
        let shouldRun = lock.withLock { () -> Bool in
            guard !stopping else { return false }
            runLoop = loop; state.running = true; state.message = "运行中，等待可支持的 Finder 图标视图"
            return true
        }
        if shouldRun {
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        lock.withLock { runLoop = nil; thread = nil; state.running = false }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.withLock {
                stopping = true; state.running = false
                state.message = "系统暂停了监听，请重新启用"
                state.failure = state.message
            }
            cache.invalidate()
            CFRunLoopStop(CFRunLoopGetCurrent())
            return pass
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown, keyCode == 123 || keyCode == 124 {
            lock.withLock { state.arrowEvents += 1; state.lastArrowFlags = event.flags.rawValue }
        }
        guard type == .keyDown, !lock.withLock({ stopping }),
              let direction = KeyboardPolicy.direction(keyCode: keyCode, flags: event.flags) else {
            cache.invalidate()
            return pass
        }
        guard let context = cache.current() else {
            lock.withLock { state.lastDecision = "no-fresh-cache" }
            return pass
        }
        let start = ProcessInfo.processInfo.systemUptime
        defer {
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
            lock.withLock { state.lastCallbackMS = elapsed; state.maximumCallbackMS = max(state.maximumCallbackMS, elapsed) }
        }
        let ax = AXAccess(deadline: start + 0.02)
        let adapter = FinderAccessibility()
        guard let selected = adapter.liveSelection(in: context, ax: ax), selected.count == 1 else {
            lock.withLock { state.lastDecision = "context-changed-multiselection-or-AX-timeout" }
            cache.invalidate(); return pass
        }
        let snapshot = LayoutSnapshot(generation: context.generation, mode: context.mode, groups: context.groups,
                                      selected: selected, complete: true)
        lock.withLock { state.lastDecision = "native-or-uncertain-layout" }
        guard case let .selectTarget(id) = NavigationEngine().decide(snapshot: snapshot, direction: direction),
              let target = context.items.first(where: { $0.model.id == id }),
              let original = context.items.first(where: { selected.contains($0.model.id) }),
              ax.withinBudget, FinderSession.activePID == context.pid else { return pass }
        switch adapter.commit(target: target, original: original, in: context) {
        case .committed:
            lock.withLock { state.committed += 1; state.message = "已完成跨行选择"; state.lastDecision = "committed" }
            return nil
        case .unchanged:
            lock.withLock { state.unchanged += 1; state.message = "选中项未改变，已放行按键" }
            cache.invalidate(); return pass
        case .indeterminate:
            lock.withLock {
                stopping = true; state.running = false; state.indeterminate += 1
                state.message = "选择结果不确定，已暂停并放行按键"
                state.failure = state.message
            }
            logger.error("Indeterminate AX selection result; monitor paused and original event passed through.")
            cache.invalidate()
            CFRunLoopStop(CFRunLoopGetCurrent())
            return pass
        }
    }
}
