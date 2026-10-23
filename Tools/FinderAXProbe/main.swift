import Foundation

let usage = """
FinderAXProbe — read-only, no keyboard events, AX writes or permission prompts
Usage: FinderAXProbe [--scenario LABEL] [--output FILE]
                     [--max-nodes 1...2000] [--max-depth 1...24]
                     [--max-children 1...500] [--budget-seconds 0.1...30]
Labels: \(ProbeScenario.allCases.map(\.rawValue).joined(separator: ", "))
The label is supplied by the operator; it is never evidence of detected view mode.
Exit: 0 sampled (possibly partial), 2 arguments/output, 3 AX permission, 4 Finder absent.
"""

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] {
    print(usage)
    exit(0)
}
do {
    let options = try ProbeOptions.parse(arguments)
    let snapshot = FinderAXReader(options: options).run()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(snapshot)
    if let output = options.output {
        try data.write(to: URL(fileURLWithPath: output), options: .atomic)
    } else {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
    switch snapshot.status {
    case "blocked-accessibility-permission": exit(3)
    case "blocked-finder-not-running": exit(4)
    default: exit(0)
    }
} catch {
    // Never print arbitrary arguments or filesystem errors containing user paths.
    FileHandle.standardError.write(Data("Invalid arguments or unable to write JSON. Use --help.\n".utf8))
    exit(2)
}
