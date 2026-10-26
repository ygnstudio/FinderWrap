import ApplicationServices
import XCTest
@testable import FinderBridge

final class BoundaryWriterTests: XCTestCase {
    func testConfirmedTargetConsumesEvenIfWriteReportedTimeout() {
        for error in [AXError.success, .cannotComplete] {
            let result = BoundaryWriteResult.resolve(error: error, sourceSelected: false, targetSelected: true, onlyTarget: true)
            XCTAssertEqual(result, .confirmed); XCTAssertTrue(result.consumesKey)
        }
    }
    func testExplicitRejectionAndUnchangedSelectionPermitOriginalKey() {
        for error in [AXError.illegalArgument, .attributeUnsupported, .invalidUIElement, .notImplemented, .apiDisabled] {
            let result = BoundaryWriteResult.resolve(error: error, sourceSelected: true, targetSelected: false, onlyTarget: false)
            XCTAssertEqual(result, .rejected); XCTAssertFalse(result.consumesKey)
        }
    }
    func testTimeoutWithOriginalSelectionCannotAuthorizeReplay() {
        let result = BoundaryWriteResult.resolve(error: .cannotComplete, sourceSelected: true, targetSelected: false, onlyTarget: false)
        XCTAssertEqual(result, .uncertain); XCTAssertTrue(result.consumesKey)
    }
    func testMissingOrMultipleReadbackCannotClaimConfirmation() {
        for state in [(nil, true, true), (false, nil, true), (true, true, false), (false, true, false)] as [(Bool?, Bool?, Bool)] {
            XCTAssertEqual(BoundaryWriteResult.resolve(error: .success, sourceSelected: state.0, targetSelected: state.1, onlyTarget: state.2), .uncertain)
        }
    }
}
