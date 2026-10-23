import ApplicationServices
import Foundation
import XCTest

final class LayoutCacheTests: XCTestCase {
    private func context(createdAt: TimeInterval = ProcessInfo.processInfo.systemUptime) -> FinderContext {
        let element = AXUIElementCreateApplication(getpid()) // Reference only; no AX reads/writes.
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        return FinderContext(pid: getpid(), application: element, window: element, collection: element,
                             viewport: element, windowFrame: frame, viewportFrame: frame,
                             groups: [], items: [], sectionCounts: [], mode: .unsupported,
                             allowedDirectories: nil, createdAt: createdAt)
    }

    func testFreshSnapshotKeepsItsGeneration() {
        let cache = LayoutCache(), snapshot = context()
        cache.store(snapshot, epoch: cache.beginRefresh())
        XCTAssertEqual(cache.current()?.generation, snapshot.generation)
    }

    func testInvalidateRejectsAnInFlightRefresh() {
        let cache = LayoutCache(), epoch = cache.beginRefresh()
        cache.invalidate()
        cache.store(context(), epoch: epoch)
        XCTAssertNil(cache.current())
    }

    func testFailedRefreshClearsPriorContext() {
        let cache = LayoutCache()
        cache.store(context(), epoch: cache.beginRefresh())
        XCTAssertNotNil(cache.current())
        cache.store(nil, epoch: cache.beginRefresh())
        XCTAssertNil(cache.current())
    }

    func testExpiredReferencesAreNeverReturned() {
        let cache = LayoutCache()
        cache.store(context(createdAt: ProcessInfo.processInfo.systemUptime - 1), epoch: cache.beginRefresh())
        XCTAssertNil(cache.current())
    }
}
