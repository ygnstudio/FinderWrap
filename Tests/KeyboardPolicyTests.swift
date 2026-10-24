import XCTest
import CoreGraphics
import ApplicationServices

final class KeyboardPolicyTests: XCTestCase {
    func testHardwareArrowFunctionMetadataIsNotAHeldFnModifier() {
        // macOS marks navigation keys as function/numeric-pad keys even when
        // the physical Fn key is up. Clearing flags in synthetic tests hid this.
        for flags: CGEventFlags in [[.maskNumericPad, .maskSecondaryFn], CGEventFlags(rawValue: 0xa00100)] {
            XCTAssertEqual(KeyboardPolicy.direction(keyCode: 123, flags: flags, fnKeyDown: false), .left)
            XCTAssertEqual(KeyboardPolicy.direction(keyCode: 124, flags: flags, fnKeyDown: false), .right)
        }
    }
    func testTransportTimeoutWithOriginalReadbackIsNotProofOfNoWrite() {
        // Finder may apply the timed-out request after this readback. Passing the
        // original key here would move a second time when that request completes.
        XCTAssertEqual(SelectionCommitResult.resolve(writeResult: .cannotComplete, observation: .original), .indeterminate)
    }
    func testOnlyUnmodifiedHorizontalArrowsAreCandidates() {
        XCTAssertNotNil(KeyboardPolicy.direction(keyCode: 123, flags: [], fnKeyDown: false))
        XCTAssertNotNil(KeyboardPolicy.direction(keyCode: 124, flags: [.maskNumericPad], fnKeyDown: false))
        for code in [Int64(0), 49, 63, 115, 116, 119, 121, 125, 126] { XCTAssertNil(KeyboardPolicy.direction(keyCode: code, flags: [], fnKeyDown: false)) }
    }
    func testEverySystemModifierPassesThrough() {
        for flag: CGEventFlags in [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskHelp] {
            for key: Int64 in [123, 124] { XCTAssertNil(KeyboardPolicy.direction(keyCode: key, flags: flag, fnKeyDown: false)) }
        }
    }
    func testHeldFnAlwaysPassesThroughEvenWithMissingEventFlag() {
        for flags: CGEventFlags in [[], .maskSecondaryFn, [.maskNumericPad, .maskSecondaryFn]] {
            for key: Int64 in [123, 124] {
                XCTAssertNil(KeyboardPolicy.direction(keyCode: key, flags: flags, fnKeyDown: true))
            }
        }
    }
    func testFunctionMetadataDoesNotHideHeldShortcutModifiers() {
        for flag: CGEventFlags in [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskHelp] {
            for key: Int64 in [123, 124] {
                XCTAssertNil(KeyboardPolicy.direction(keyCode: key, flags: [.maskNumericPad, .maskSecondaryFn, flag], fnKeyDown: false))
            }
        }
    }
    func testFunctionMetadataWithoutNumericPadIsStillAnArrow() {
        XCTAssertEqual(KeyboardPolicy.direction(keyCode: 124, flags: .maskSecondaryFn, fnKeyDown: false), .right)
    }
    func testCapsLockDoesNotChangeArrowMeaning() {
        XCTAssertNotNil(KeyboardPolicy.direction(keyCode: 124, flags: [.maskAlphaShift, .maskNumericPad, .maskSecondaryFn], fnKeyDown: false))
    }
    func testAcknowledgementWithoutTargetReadbackSuspendsInterception() {
        XCTAssertEqual(SelectionCommitResult.resolve(writeResult: .success, observation: .unavailable), .indeterminate)
        XCTAssertEqual(SelectionCommitResult.resolve(writeResult: .success, observation: .original), .indeterminate)
    }
    func testExplicitRejectionWithUnchangedSelectionPassesThrough() {
        for error: AXError in [.illegalArgument, .attributeUnsupported, .invalidUIElement, .notImplemented, .apiDisabled] {
            let result = SelectionCommitResult.resolve(writeResult: error, observation: .original)
            XCTAssertEqual(result, .unchanged)
            XCTAssertFalse(result.consumesEvent)
        }
    }
    func testObservedTargetConfirmsCommitEvenAfterTransportError() {
        XCTAssertEqual(SelectionCommitResult.resolve(writeResult: .cannotComplete, observation: .target), .committed)
        XCTAssertEqual(SelectionCommitResult.resolve(writeResult: .success, observation: .target), .committed)
    }
    func testExternalSelectionChangeSuspendsInterception() {
        XCTAssertEqual(SelectionCommitResult.resolve(writeResult: .cannotComplete, observation: .other), .indeterminate)
    }
    func testWriteAppliedButReadbackLostDoesNotAlsoDeliverNativeKey() {
        var selection = 6
        var writes = 0
        let result = SelectionCommitResult.perform(write: {
            writes += 1
            selection = 7
            return .cannotComplete
        }, readback: { .unavailable })
        if !result.consumesEvent { selection += 1 }
        XCTAssertEqual(selection, 7)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(result, .indeterminate)
    }
    func testDelayedWriteAfterStaleReadbackDoesNotDoubleMove() {
        var selection = 6
        let result = SelectionCommitResult.perform(write: { .cannotComplete }, readback: { .original })
        selection = 7 // Simulate Finder completing the timed-out request later.
        if !result.consumesEvent { selection += 1 }
        XCTAssertEqual(selection, 7)
        XCTAssertEqual(result, .indeterminate)
    }
    func testRejectedWriteDeliversExactlyOneNativeKey() {
        var selection = 6
        let result = SelectionCommitResult.perform(write: { .attributeUnsupported }, readback: { .original })
        if !result.consumesEvent { selection += 1 }
        XCTAssertEqual(selection, 7)
        XCTAssertEqual(result, .unchanged)
    }
    func testUnknownErrorCannotBeTreatedAsRejection() {
        for error: AXError in [.failure, .cannotComplete, .noValue] {
            for observation: SelectionObservation in [.original, .unavailable, .other] {
                let result = SelectionCommitResult.resolve(writeResult: error, observation: observation)
                XCTAssertEqual(result, .indeterminate)
                XCTAssertTrue(result.consumesEvent)
            }
        }
    }
    func testBurstStopsWritingAfterFirstAmbiguousTransaction() {
        let gate = SelectionWriteGate()
        gate.open()
        var writes = 0
        var nativeKeys = 0
        for index in 0..<200 {
            let result = gate.perform {
                SelectionCommitResult.perform(write: { writes += 1; return .success },
                                              readback: { index == 5 ? .unavailable : .target })
            }
            if result == .indeterminate { gate.close() }
            if result?.consumesEvent != true { nativeKeys += 1 }
        }
        XCTAssertEqual(writes, 6)
        XCTAssertEqual(nativeKeys, 194) // Later input remains usable while paused.
    }
    func testClosedGateNeverStartsSelectionWrite() {
        let gate = SelectionWriteGate()
        var writes = 0
        XCTAssertNil(gate.perform { writes += 1; return .committed })
        gate.open()
        XCTAssertEqual(gate.perform { writes += 1; return .committed }, .committed)
        gate.close()
        for _ in 0..<100 { XCTAssertNil(gate.perform { writes += 1; return .committed }) }
        XCTAssertEqual(writes, 1)
    }
    func testStopWaitsForAlreadyStartedWriteBeforeReturning() {
        let gate = SelectionWriteGate()
        gate.open()
        let entered = DispatchSemaphore(value: 0)
        let releaseWrite = DispatchSemaphore(value: 0)
        let closing = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = gate.perform {
                entered.signal()
                _ = releaseWrite.wait(timeout: .now() + 2)
                return .committed
            }
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            closing.signal()
            gate.close()
            stopped.signal()
        }
        XCTAssertEqual(closing.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(stopped.wait(timeout: .now() + 0.05), .timedOut)
        releaseWrite.signal()
        XCTAssertEqual(stopped.wait(timeout: .now() + 2), .success)
        XCTAssertNil(gate.perform { XCTFail("Write after stop"); return .committed })
    }

}
