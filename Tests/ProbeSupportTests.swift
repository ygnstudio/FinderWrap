import XCTest

final class ProbeSupportTests: XCTestCase {
    func testRejectsArbitraryScenarioRatherThanPersistingPrivateLabels() {
        XCTAssertThrowsError(try ProbeOptions.parse(["--scenario", "/Users/private/secret"]))
    }

    func testRejectsUnboundedOrNonFiniteBudgets() {
        for value in ["0", "-1", "31", "nan", "inf"] {
            XCTAssertThrowsError(try ProbeOptions.parse(["--budget-seconds", value]))
        }
        for option in ["--max-nodes", "--max-depth", "--max-children"] {
            XCTAssertThrowsError(try ProbeOptions.parse([option, "0"]))
            XCTAssertThrowsError(try ProbeOptions.parse([option, "999999999"]))
        }
    }

    func testRejectsUnknownOrMissingArguments() {
        XCTAssertThrowsError(try ProbeOptions.parse(["--request-permission", "yes"]))
        XCTAssertThrowsError(try ProbeOptions.parse(["--output"]))
    }

    func testParsesAReproducibleBoundedScenario() throws {
        let options = try ProbeOptions.parse(["--scenario", "quick-look", "--max-nodes", "100", "--budget-seconds", "2.5"])
        XCTAssertEqual(options.scenario, .quickLook)
        XCTAssertEqual(options.maxNodes, 100)
        XCTAssertEqual(options.budgetSeconds, 2.5)
    }

    func testPrivacyFilterRejectsContentAndPaths() {
        for value in ["Secret.txt", "/Users/test", "AXWindow secret", "AX窗口", "", "AXTitle\nsecret"] {
            XCTAssertNil(ProbePrivacy.frameworkToken(value))
        }
        XCTAssertEqual(ProbePrivacy.frameworkToken("AXSelectedChildren"), "AXSelectedChildren")
    }

    func testSnapshotDoesNotClaimWritesOrVerifiedScenario() throws {
        let data = try JSONEncoder().encode(ProbeSnapshot(scenario: .icons))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["selectionWritePerformed"] as? Bool, false)
        XCTAssertEqual(json["scenarioSource"] as? String, "operator-label-not-verified")
        XCTAssertNil(json["filename"])
        XCTAssertNil(json["path"])
        XCTAssertNil(json["title"])
    }

    func testLatencyPercentileUsesNearestRankAndHandlesEmpty() {
        XCTAssertEqual(ProbePrivacy.percentile95([]), 0)
        XCTAssertEqual(ProbePrivacy.percentile95([2]), 2)
        XCTAssertEqual(ProbePrivacy.percentile95(Array(1...100).map(Double.init)), 95)
    }
}
