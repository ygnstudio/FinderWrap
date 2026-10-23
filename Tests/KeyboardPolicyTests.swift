import XCTest
import CoreGraphics

final class KeyboardPolicyTests: XCTestCase {
    func testOnlyUnmodifiedHorizontalArrowsAreCandidates() {
        XCTAssertNotNil(KeyboardPolicy.direction(keyCode: 123, flags: []))
        XCTAssertNotNil(KeyboardPolicy.direction(keyCode: 124, flags: [.maskNumericPad]))
        for code in [Int64(0), 49, 125, 126] { XCTAssertNil(KeyboardPolicy.direction(keyCode: code, flags: [])) }
    }
    func testEverySystemModifierPassesThrough() {
        for flag: CGEventFlags in [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn, .maskHelp] {
            for key: Int64 in [123, 124] { XCTAssertNil(KeyboardPolicy.direction(keyCode: key, flags: flag)) }
        }
    }
    func testCapsLockDoesNotChangeArrowMeaning() {
        XCTAssertNotNil(KeyboardPolicy.direction(keyCode: 124, flags: [.maskAlphaShift, .maskNumericPad]))
    }
    func testSuccessfulReturnWithoutReadbackNeverConsumesInput() {
        XCTAssertEqual(SelectionCommitResult.resolve(writeSucceeded: true, observation: .unavailable), .indeterminate)
        XCTAssertEqual(SelectionCommitResult.resolve(writeSucceeded: true, observation: .original), .unchanged)
    }
    func testFailedWriteWithUnchangedSelectionPassesThrough() {
        XCTAssertEqual(SelectionCommitResult.resolve(writeSucceeded: false, observation: .original), .unchanged)
    }
    func testObservedTargetConfirmsCommitEvenAfterTransportError() {
        XCTAssertEqual(SelectionCommitResult.resolve(writeSucceeded: false, observation: .target), .committed)
        XCTAssertEqual(SelectionCommitResult.resolve(writeSucceeded: true, observation: .target), .committed)
    }
    func testExternalSelectionChangeSuspendsInterception() {
        XCTAssertEqual(SelectionCommitResult.resolve(writeSucceeded: false, observation: .other), .indeterminate)
    }
}
