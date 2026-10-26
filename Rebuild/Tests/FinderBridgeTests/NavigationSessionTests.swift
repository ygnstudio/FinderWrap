import XCTest
@testable import FinderBridge

final class NavigationSessionTests: XCTestCase {
    func testOldRefreshCannotPublishAfterSelectionChanges() throws {
        var session = NavigationSession(); session.setEnabled(true)
        let ticket = try XCTUnwrap(session.beginRefresh())
        session.invalidate()
        XCTAssertFalse(session.complete(ticket, available: true))
        XCTAssertEqual(session.state, .preparing)
    }
    func testDisableThenEnableRejectsPreviouslyStartedWork() throws {
        var session = NavigationSession(); session.setEnabled(true)
        let ticket = try XCTUnwrap(session.beginRefresh())
        session.setEnabled(false); session.setEnabled(true)
        XCTAssertFalse(session.complete(ticket, available: true))
    }
    func testSingleWorkerRequestAndNoDuplicateCompletion() throws {
        var session = NavigationSession(); session.setEnabled(true)
        let ticket = try XCTUnwrap(session.beginRefresh())
        XCTAssertNil(session.beginRefresh())
        XCTAssertTrue(session.complete(ticket, available: true))
        XCTAssertFalse(session.complete(ticket, available: false))
        XCTAssertEqual(session.state, .ready)
    }
    func testTemporaryReadFailureDoesNotSwitchUserPreferenceOff() throws {
        var session = NavigationSession(); session.setEnabled(true)
        session.readFailed(try XCTUnwrap(session.beginRefresh()))
        XCTAssertTrue(session.requestedEnabled)
        XCTAssertEqual(session.state, .recovering)
        XCTAssertTrue(session.complete(try XCTUnwrap(session.beginRefresh()), available: true))
        XCTAssertEqual(session.state, .ready)
    }
    func testPermissionLossNeverStartsWorkButPreservesPreference() throws {
        var session = NavigationSession(); session.setEnabled(true)
        let ticket = try XCTUnwrap(session.beginRefresh())
        session.permissionsChanged(ready: false)
        XCTAssertTrue(session.requestedEnabled)
        XCTAssertFalse(session.complete(ticket, available: true))
        XCTAssertNil(session.beginRefresh())
        XCTAssertEqual(session.state, .permissionRequired)
        session.permissionsChanged(ready: true)
        XCTAssertNotNil(session.beginRefresh())
    }
    func testUncertainWriteCannotBeRecoveredByTimerOrSelectionRead() {
        var session = NavigationSession(); session.setEnabled(true)
        session.commitUncertain(); session.invalidate()
        XCTAssertEqual(session.state, .uncertainCommit)
        XCTAssertNil(session.beginRefresh())
        XCTAssertFalse(session.tapTimedOut())
        XCTAssertTrue(session.requestedEnabled)
        session.invalidate(newContext: true)
        XCTAssertNotNil(session.beginRefresh())
    }
    func testTapTimeoutRecoveryIsBoundedEvenWhenCapturesSucceed() throws {
        var session = NavigationSession(); session.setEnabled(true)
        XCTAssertTrue(session.tapTimedOut())
        XCTAssertTrue(session.complete(try XCTUnwrap(session.beginRefresh()), available: true))
        XCTAssertTrue(session.tapTimedOut())
        XCTAssertFalse(session.tapTimedOut())
        XCTAssertTrue(session.requestedEnabled)
        XCTAssertEqual(session.state, .listenerUnavailable)
        XCTAssertNil(session.beginRefresh())
        session.invalidate(newContext: true)
        XCTAssertNil(session.beginRefresh())
        session.setEnabled(false); session.setEnabled(true)
        XCTAssertNotNil(session.beginRefresh())
    }
    func testExplicitPauseCannotAutomaticallyRestart() {
        var session = NavigationSession(); session.setEnabled(true); session.setEnabled(false)
        session.invalidate(newContext: true)
        session.permissionsChanged(ready: false); session.permissionsChanged(ready: true)
        XCTAssertFalse(session.tapTimedOut())
        XCTAssertNil(session.beginRefresh())
        XCTAssertEqual(session.state, .paused)
    }
    func testSystemListenerDisablePreservesPreferenceAndRequiresExplicitResume() throws {
        var session = NavigationSession(); session.setEnabled(true)
        let ticket = try XCTUnwrap(session.beginRefresh())
        XCTAssertFalse(session.listenerInterrupted(timedOut: false))
        XCTAssertTrue(session.requestedEnabled)
        XCTAssertEqual(session.state, .listenerUnavailable)
        XCTAssertFalse(session.listenerInterrupted(timedOut: true))
        XCTAssertEqual(session.state, .listenerUnavailable)
        XCTAssertFalse(session.complete(ticket, available: true))
        session.invalidate(newContext: true)
        session.permissionsChanged(ready: false); session.permissionsChanged(ready: true)
        XCTAssertNil(session.beginRefresh())
        session.setEnabled(false); session.setEnabled(true)
        XCTAssertNotNil(session.beginRefresh())
    }
    func testListenerControlDoesNotEnableAnExplicitlyPausedSession() {
        var session = NavigationSession()
        XCTAssertFalse(session.listenerInterrupted(timedOut: false))
        XCTAssertFalse(session.listenerInterrupted(timedOut: true))
        XCTAssertFalse(session.requestedEnabled)
        XCTAssertEqual(session.state, .paused)
    }
}
