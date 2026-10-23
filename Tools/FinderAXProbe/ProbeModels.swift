import Foundation

enum ProbeScenario: String, CaseIterable, Codable {
    case current = "current-state"
    case icons = "normal-icon-view"
    case list = "list-view"
    case columns = "column-view"
    case nameSort = "name-sort"
    case dateGroups = "date-groups"
    case kindGroups = "kind-groups"
    case freeArrangement = "free-arrangement"
    case singleSelection = "single-selection"
    case multipleSelection = "multiple-selection"
    case quickLook = "quick-look"
    case resized = "resized-window"
    case scrolling = "large-folder-scroll"
    case restarted = "finder-restarted"
    case desktop = "desktop"
}

struct ProbeOptions {
    var scenario: ProbeScenario = .current
    var output: String?
    var maxNodes = 500
    var maxDepth = 12
    var maxChildren = 150
    var budgetSeconds = 8.0

    enum ArgumentError: Error { case invalidArguments }

    static func parse(_ arguments: [String]) throws -> ProbeOptions {
        var result = ProbeOptions()
        var index = 0
        while index < arguments.count {
            guard index + 1 < arguments.count else { throw ArgumentError.invalidArguments }
            let value = arguments[index + 1]
            switch arguments[index] {
            case "--scenario":
                guard let scenario = ProbeScenario(rawValue: value) else { throw ArgumentError.invalidArguments }
                result.scenario = scenario
            case "--output": result.output = value
            case "--max-nodes":
                guard let count = Int(value), (1...2000).contains(count) else { throw ArgumentError.invalidArguments }
                result.maxNodes = count
            case "--max-depth":
                guard let depth = Int(value), (1...24).contains(depth) else { throw ArgumentError.invalidArguments }
                result.maxDepth = depth
            case "--max-children":
                guard let count = Int(value), (1...500).contains(count) else { throw ArgumentError.invalidArguments }
                result.maxChildren = count
            case "--budget-seconds":
                guard let seconds = Double(value), seconds.isFinite, (0.1...30).contains(seconds) else {
                    throw ArgumentError.invalidArguments
                }
                result.budgetSeconds = seconds
            default: throw ArgumentError.invalidArguments
            }
            index += 2
        }
        return result
    }
}

struct ProbePoint: Codable { let x: Double; let y: Double }
struct ProbeSize: Codable { let width: Double; let height: Double }

struct ProbeNode: Codable {
    let id: String
    var role: String?
    var subrole: String?
    var semanticIdentifier: String?
    var attributes: [String] = []
    var position: ProbePoint?
    var size: ProbeSize?
    var selected: Bool?
    var focused: Bool?
    var selectedSettable: Bool?
    var selectedChildrenSettable: Bool?
    var children: [String] = []
    var selectedChildren: [String] = []
    var visibleChildren: [String] = []
    var relationCounts: [String: Int] = [:]
    var truncatedRelations: [String] = []
    var inspected = false
}

struct ProbeError: Codable {
    let node: String
    let operation: String
    let code: Int32
    let elapsedMS: Double
}

struct ProbeCall: Codable {
    let node: String
    let operation: String
    let elapsedMS: Double
    let code: Int32
}

struct ProbeMeasurements: Codable {
    var elapsedMS = 0.0
    var callCount = 0
    var maximumCallMS = 0.0
    var p95CallMS = 0.0
    var messagingTimeoutSeconds = 0.15
    var budgetSeconds = 0.0
    var calls: [ProbeCall] = []
}

struct ProbeSnapshot: Encodable {
    let schemaVersion = 1
    var timestamp = ISO8601DateFormatter().string(from: Date())
    var osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    var finderVersion: String?
    var finderPID: Int32?
    var frontmostApplication = "unavailable"
    var frontmostPID: Int32?
    var accessibilityTrusted = false
    var scenario: ProbeScenario
    let scenarioSource = "operator-label-not-verified"
    var status = "not-started"
    var roots: [String: String] = [:]
    var windows: [String] = []
    var attributes: [String] = []
    var selectedItems: [String] = []
    var visibleItems: [String] = []
    var nodes: [ProbeNode] = []
    var errors: [ProbeError] = []
    var measurements = ProbeMeasurements()
    var truncationReasons: [String] = []
    let privacy = "No titles, filenames, URLs, paths, descriptions, values or item identifiers. Only allowlisted view identifiers. Node IDs are snapshot-local."
    let selectionWritePerformed = false
}

enum ProbePrivacy {
    /// Export framework vocabulary only; never serialize arbitrary AX values.
    static func frameworkToken(_ value: String) -> String? {
        guard value.count <= 80,
              value.range(of: "^AX[A-Za-z][A-Za-z0-9]*$", options: .regularExpression) != nil else { return nil }
        return value
    }

    static func percentile95(_ samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        return sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
    }
}
