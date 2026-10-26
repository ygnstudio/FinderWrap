import ApplicationServices
import Foundation

/// Must be created, attached, and stopped on the same run-loop thread. Callback
/// work is limited to invalidation; AX/Apple Event reads belong on the worker.
public final class FinderChangeObserver {
    public struct Registration: Codable {
        public let scope: String
        public let notification: String
        public let result: Int32
    }
    private let observer: AXObserver
    private let changed: (String) -> Void
    private let runLoop: CFRunLoop
    private var entries: [(AXUIElement, String)] = []
    public private(set) var registrations = [Registration]()

    public init(pid: pid_t, onChange: @escaping (String) -> Void) throws {
        var raw: AXObserver?
        let error = AXObserverCreate(pid, { _, _, notification, pointer in
            guard let pointer else { return }
            Unmanaged<FinderChangeObserver>.fromOpaque(pointer).takeUnretainedValue().changed(notification as String)
        }, &raw)
        guard error == .success, let raw else { throw AXReadFailure(code: error, attribute: "observer-create") }
        self.observer = raw; self.changed = onChange; self.runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(raw), .commonModes)
    }

    public func attach(_ context: VisibleAXContext) {
        clear()
        for name in [kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification, kAXWindowCreatedNotification] {
            register(context.application, name, "application")
        }
        for name in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
            register(context.window, name, "window")
        }
        for name in [kAXSelectedChildrenChangedNotification, kAXLayoutChangedNotification, kAXValueChangedNotification] {
            register(context.collection, name, "collection")
        }
        register(context.viewport, kAXValueChangedNotification, "viewport")
    }

    private func register(_ element: AXUIElement, _ name: String, _ scope: String) {
        let result = AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        registrations.append(Registration(scope: scope, notification: name, result: result.rawValue))
        if result == .success { entries.append((element, name)) }
    }

    private func clear() {
        for (element, name) in entries { AXObserverRemoveNotification(observer, element, name as CFString) }
        entries.removeAll(); registrations.removeAll()
    }

    public func stop() {
        clear()
        CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(observer), .commonModes)
    }

    deinit { stop() }
}
