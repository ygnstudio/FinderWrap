import ApplicationServices
import XCTest
@testable import FinderBridge

final class AXBatchTests: XCTestCase {
    func testOptionalAttributeErrorDoesNotEraseRoleOrFrame() throws {
        var error = AXError.attributeUnsupported
        var point = CGPoint(x: 10, y: 20)
        var size = CGSize(width: 30, height: 40)
        let fields = AXBatchReader.decode(names: [kAXRoleAttribute, kAXSubroleAttribute, kAXPositionAttribute, kAXSizeAttribute], values: [
            "AXImage" as NSString, AXValueCreate(.axError, &error)!, AXValueCreate(.cgPoint, &point)!, AXValueCreate(.cgSize, &size)!
        ])
        XCTAssertEqual(fields.string(kAXRoleAttribute), "AXImage")
        XCTAssertNil(fields.string(kAXSubroleAttribute))
        XCTAssertEqual(fields.frame, CGRect(x: 10, y: 20, width: 30, height: 40))
        XCTAssertThrowsError(try fields.values[kAXSubroleAttribute]?.get())
    }
    func testNullAndWrongGeometryTypesAreUnavailable() {
        let fields = AXBatchReader.decode(names: [kAXPositionAttribute, kAXSizeAttribute], values: [NSNull(), "30,40" as NSString])
        XCTAssertNil(fields.frame)
    }
}
