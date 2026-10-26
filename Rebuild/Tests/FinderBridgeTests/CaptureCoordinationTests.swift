import XCTest
@testable import FinderBridge

final class CaptureCoordinationTests: XCTestCase {
    func testRepeatedInvalidationCannotQueueBehindASlowPhysicalRead() throws {
        var session = NavigationSession(); session.setEnabled(true)
        var gate = CaptureWorkGate()
        let slowRead = try XCTUnwrap(gate.begin(session: &session))
        XCTAssertTrue(gate.mayStart(slowRead, session: session, stopped: false))

        // Model a read that has not returned while the user keeps scrolling.
        // Invalidation must revoke its result, not release its physical slot.
        for _ in 0..<1_000 {
            session.invalidate()
            XCTAssertNil(gate.begin(session: &session))
        }
        XCTAssertFalse(session.complete(slowRead, available: true))
        gate.finish(slowRead)
        let latest = try XCTUnwrap(gate.begin(session: &session))
        XCTAssertTrue(gate.mayStart(latest, session: session, stopped: false))
        gate.finish(latest)
        XCTAssertTrue(session.complete(latest, available: true))
        XCTAssertEqual(session.state, .ready)
    }

    func testStoppedOrInvalidatedQueuedReadDoesNotStart() throws {
        var session = NavigationSession(); session.setEnabled(true)
        var gate = CaptureWorkGate()
        let queued = try XCTUnwrap(gate.begin(session: &session))
        XCTAssertFalse(gate.mayStart(queued, session: session, stopped: true))
        session.setEnabled(false)
        XCTAssertFalse(gate.mayStart(queued, session: session, stopped: false))
        session.setEnabled(true)
        XCTAssertFalse(gate.mayStart(queued, session: session, stopped: false))
        XCTAssertNil(gate.begin(session: &session))
        gate.finish(queued)
        let resumed = try XCTUnwrap(gate.begin(session: &session))
        XCTAssertTrue(gate.mayStart(resumed, session: session, stopped: false))
    }

    func testLateDuplicateFinishCannotReleaseNewRead() throws {
        var session = NavigationSession(); session.setEnabled(true)
        var gate = CaptureWorkGate()
        let old = try XCTUnwrap(gate.begin(session: &session))
        session.invalidate(); gate.finish(old)
        let current = try XCTUnwrap(gate.begin(session: &session))
        gate.finish(old)
        session.invalidate()
        XCTAssertNil(gate.begin(session: &session))
        gate.finish(current)
        XCTAssertNotNil(gate.begin(session: &session))
    }

    func testObserverInstallationRequiresANewCaptureAfterRegistration() throws {
        var observations = ObservationGate<String>()
        var session = NavigationSession(); session.setEnabled(true)
        let beforeInstallation = try XCTUnwrap(session.beginRefresh())
        guard case .install(let attempt) = observations.require("window-A", now: 0) else {
            return XCTFail("First observation must install before any publication")
        }
        XCTAssertNil(observations.readyContext)
        session.invalidate()
        XCTAssertFalse(session.complete(beforeInstallation, available: true))

        // A read started while the main run loop registers notifications must
        // also be discarded, even when installation ultimately succeeds.
        let duringInstallation = try XCTUnwrap(session.beginRefresh())
        XCTAssertEqual(observations.require("window-A", now: 0.1), .pending)
        XCTAssertTrue(observations.complete(attempt, selectedChildrenRegistered: true, now: 0.2))
        session.invalidate()
        XCTAssertFalse(session.complete(duringInstallation, available: true))
        XCTAssertEqual(observations.require("window-A", now: 0.3), .ready)
        XCTAssertTrue(session.complete(try XCTUnwrap(session.beginRefresh()), available: true))
    }

    func testFailedCreationOrMissingSelectionNotificationRetriesSameContextWithBackoff() {
        var observations = ObservationGate<String>(retryDelay: 1)
        guard case .install(let first) = observations.require("same-window", now: 0) else {
            return XCTFail("Expected installation")
        }
        XCTAssertTrue(observations.complete(first, selectedChildrenRegistered: false, now: 0.1))
        XCTAssertNil(observations.readyContext)
        for now in stride(from: 0.1, to: 1.1, by: 0.05) {
            XCTAssertEqual(observations.require("same-window", now: now), .retryLater)
        }
        guard case .install(let retry) = observations.require("same-window", now: 1.1) else {
            return XCTFail("Failed creation must retry the same collection")
        }
        XCTAssertNotEqual(first, retry)
        XCTAssertTrue(observations.complete(retry, selectedChildrenRegistered: true, now: 1.2))
        XCTAssertEqual(observations.require("same-window", now: 1.3), .ready)
    }

    func testStaleObserverCompletionCannotAuthorizeAnotherWindowOrRestart() {
        var observations = ObservationGate<String>()
        guard case .install(let old) = observations.require("old-window", now: 0),
              case .install(let current) = observations.require("new-window", now: 0.1) else {
            return XCTFail("Expected separate attempts")
        }
        XCTAssertFalse(observations.complete(old, selectedChildrenRegistered: true, now: 0.2))
        XCTAssertNil(observations.readyContext)
        observations.reset()
        XCTAssertFalse(observations.complete(current, selectedChildrenRegistered: true, now: 0.3))
        XCTAssertNil(observations.readyContext)
        guard case .install(let restarted) = observations.require("new-window", now: 0.4) else {
            return XCTFail("Reset must require fresh registration")
        }
        XCTAssertNotEqual(current, restarted)
    }

    func testObserverNativeFallbackPreservesUserIntentAndFailureStates() {
        var session = NavigationSession(); session.setEnabled(true)
        session.invalidate(native: true)
        XCTAssertTrue(session.requestedEnabled)
        XCTAssertEqual(session.state, .native)
        session.commitUncertain(); session.invalidate(native: true)
        XCTAssertEqual(session.state, .uncertainCommit)
        session.permissionsChanged(ready: false); session.invalidate(native: true)
        XCTAssertEqual(session.state, .permissionRequired)
        session.setEnabled(false); session.invalidate(native: true)
        XCTAssertEqual(session.state, .paused)
    }
}
