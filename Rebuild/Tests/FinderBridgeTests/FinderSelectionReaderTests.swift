import AppKit
import CoreServices
import XCTest
@testable import FinderBridge

final class FinderSelectionReaderTests: XCTestCase {
    private func reply(_ result: NSAppleEventDescriptor?) -> NSAppleEventDescriptor {
        let value = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: kAEAnswer,
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: 0)
        if let result { value.setParam(result, forKeyword: keyDirectObject) }
        return value
    }

    private func list(_ count: Int) throws -> NSAppleEventDescriptor {
        let value = NSAppleEventDescriptor.list()
        for index in 0..<count {
            value.insert(try FinderSelectionReader.object(want: FinderSelectionReader.code("cobj"),
                form: OSType(formAbsolutePosition), data: NSAppleEventDescriptor(int32: Int32(index + 1)),
                container: .null()), at: index + 1)
        }
        return value
    }

    func testPropertySpecifierIsStructuredNotFlattenedBytes() throws {
        let spec = try FinderSelectionReader.property(FinderSelectionReader.code("sele"))
        XCTAssertEqual(spec.descriptorType, typeObjectSpecifier)
        let record = try XCTUnwrap(spec.coerce(toDescriptorType: typeAERecord))
        XCTAssertEqual(record.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue, typeProperty)
        XCTAssertEqual(record.forKeyword(AEKeyword(keyAEKeyForm))?.enumCodeValue, OSType(formPropertyID))
        XCTAssertEqual(record.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue, FinderSelectionReader.code("sele"))
        XCTAssertEqual(record.forKeyword(AEKeyword(keyAEContainer))?.descriptorType, typeNull)
    }

    func testEmptySelectionRequiresAnActualEmptyList() throws {
        let reader = FinderSelectionReader(permission: { 0 }, exchange: { _, _ in self.reply(.list()) })
        XCTAssertEqual(try reader.read(), .empty)
    }

    func testMultiSelectionDoesNotReadItemURLs() throws {
        for count in [2, 36, 1000] {
            var calls = 0
            let reader = FinderSelectionReader(permission: { 0 }, exchange: { _, _ in
                calls += 1
                return self.reply(try self.list(count))
            })
            XCTAssertEqual(try reader.read(), .multiple(count))
            XCTAssertEqual(calls, 1)
        }
    }

    func testSingleSelectionUsesReturnedObjectForURLQuery() throws {
        let selected = try list(1)
        var requests = [NSAppleEventDescriptor]()
        let reader = FinderSelectionReader(permission: { 0 }, exchange: { event, _ in
            requests.append(event)
            return self.reply(requests.count == 1 ? selected : NSAppleEventDescriptor(string: "file:///fixture/A.txt"))
        })
        XCTAssertEqual(try reader.read(), .single(URL(fileURLWithPath: "/fixture/A.txt")))
        XCTAssertEqual(requests.count, 2)
        let spec = try XCTUnwrap(requests[1].paramDescriptor(forKeyword: keyDirectObject)?.coerce(toDescriptorType: typeAERecord))
        XCTAssertEqual(spec.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue, FinderSelectionReader.code("pURL"))
        XCTAssertEqual(spec.forKeyword(AEKeyword(keyAEContainer))?.data, selected.atIndex(1)?.data)
        XCTAssertTrue(requests.allSatisfy { $0.eventClass == kAECoreSuite && $0.eventID == kAEGetData })
    }

    func testDeniedPermissionSendsNothing() {
        var sends = 0
        let reader = FinderSelectionReader(permission: { OSStatus(errAEEventNotPermitted) }, exchange: { _, _ in
            sends += 1; return self.reply(.list())
        })
        XCTAssertThrowsError(try reader.read()) { error in
            XCTAssertEqual((error as? FinderSelectionReader.Failure)?.code, OSStatus(errAEEventNotPermitted))
        }
        XCTAssertEqual(sends, 0)
    }

    func testMissingReplyIsNotEmptySelection() {
        let reader = FinderSelectionReader(permission: { 0 }, exchange: { _, _ in self.reply(nil) })
        XCTAssertThrowsError(try reader.read())
    }

    func testNullAndWrongTypeAreNotEmptySelection() {
        for result in [NSAppleEventDescriptor.null(), NSAppleEventDescriptor(string: ""), NSAppleEventDescriptor(int32: 0)] {
            let reader = FinderSelectionReader(permission: { 0 }, exchange: { _, _ in self.reply(result) })
            XCTAssertThrowsError(try reader.read())
        }
    }

    func testRemoteErrorIsPreservedWithoutReadingErrorText() {
        let reader = FinderSelectionReader(permission: { 0 }, exchange: { _, _ in
            let result = self.reply(.list())
            result.setParam(NSAppleEventDescriptor(int32: -1728), forKeyword: keyErrorNumber)
            result.setParam(NSAppleEventDescriptor(string: "private item details"), forKeyword: keyErrorString)
            return result
        })
        XCTAssertThrowsError(try reader.read()) { error in
            XCTAssertEqual((error as? FinderSelectionReader.Failure)?.code, -1728)
            XCTAssertFalse(String(describing: error).contains("private"))
        }
    }

    func testTransportTimeoutIsNotEmptyOrRetried() {
        var sends = 0
        let reader = FinderSelectionReader(permission: { 0 }, exchange: { _, ticks in
            XCTAssertEqual(ticks, 60)
            sends += 1
            throw FinderSelectionReader.Failure(code: -1712, operation: "send")
        })
        XCTAssertThrowsError(try reader.read()) { error in
            XCTAssertEqual((error as? FinderSelectionReader.Failure)?.code, -1712)
            XCTAssertEqual((error as? FinderSelectionReader.Failure)?.operation, "selection-list")
        }
        XCTAssertEqual(sends, 1)
    }

    func testDisappearingSingleSelectionDoesNotFallBackToAnotherItem() throws {
        var sends = 0
        let reader = FinderSelectionReader(permission: { 0 }, exchange: { _, _ in
            sends += 1
            if sends == 2 { throw FinderSelectionReader.Failure(code: -1728, operation: "send") }
            return self.reply(try self.list(1))
        })
        XCTAssertThrowsError(try reader.read())
        XCTAssertEqual(sends, 2)
    }

    func testSingleSelectionMustResolveToFileURL() throws {
        for string in ["https://example.invalid/item", "not a URL", ""] {
            var sends = 0
            let reader = FinderSelectionReader(permission: { 0 }, exchange: { _, _ in
                sends += 1
                return self.reply(sends == 1 ? try self.list(1) : NSAppleEventDescriptor(string: string))
            })
            XCTAssertThrowsError(try reader.read())
        }
    }

    func testWindowPropertiesBindToObservedIDInsteadOfMovingFrontIndex() throws {
        var requests = [NSAppleEventDescriptor]()
        let responses = [NSAppleEventDescriptor(int32: 47), NSAppleEventDescriptor(enumCode: FinderSelectionReader.code("icnv")),
                         NSAppleEventDescriptor(string: "file:///fixture/")]
        let reader = FinderSelectionReader(permission: { 0 }, exchange: { event, _ in
            requests.append(event)
            return self.reply(responses[requests.count - 1])
        })
        let window = try reader.frontWindow()
        XCTAssertEqual(window.id, 47); XCTAssertTrue(window.isIconView)
        XCTAssertEqual(window.directory, URL(fileURLWithPath: "/fixture", isDirectory: true))
        let view = try XCTUnwrap(requests[1].paramDescriptor(forKeyword: keyDirectObject)?.coerce(toDescriptorType: typeAERecord))
        let container = try XCTUnwrap(view.forKeyword(AEKeyword(keyAEContainer))?.coerce(toDescriptorType: typeAERecord))
        XCTAssertEqual(container.forKeyword(AEKeyword(keyAEKeyForm))?.enumCodeValue, OSType(formUniqueID))
        XCTAssertEqual(container.forKeyword(AEKeyword(keyAEKeyData))?.int32Value, 47)
    }
}
