import AppKit
import ApplicationServices
import Foundation

/// Exercises the new adapters together without installing an event tap, writing
/// selection, changing a view, or exporting file names/URLs/text.
@main
struct RebuildReadOnlyProbe {
    static func main() {
        var report: [String: Any] = ["schemaVersion": 1, "readOnly": true,
                                  "architecture": "visible-layout-and-official-selection"]
        let allowed = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/Fixtures/Synthetic").standardizedFileURL
        let reader = FinderSelectionReader()
        report["automationPermissionStatus"] = reader.permissionStatus()
        report["accessibility"] = AXIsProcessTrusted()
        guard reader.permissionStatus() == 0, AXIsProcessTrusted() else { emit(report); return }
        // Guard the only authorized directory before invoking the candidate.
        var error: NSDictionary?
        let scope = NSAppleScript(source: "tell application \"Finder\" to get POSIX path of (target of front Finder window as alias)")?
            .executeAndReturnError(&error).stringValue
        guard error == nil, scope.map({ URL(fileURLWithPath: $0).standardizedFileURL }) == allowed else {
            report["scopeUnavailable"] = true; emit(report); return
        }
        do {
            let window = try reader.frontWindow()
            guard window.directory == allowed, let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
                report["scopeUnavailable"] = true; emit(report); return
            }
            report["fixtureWindowConfirmed"] = true
            report["officialIconView"] = window.isIconView
            report["finderFrontmost"] = NSWorkspace.shared.frontmostApplication?.processIdentifier == finder.processIdentifier
            let selection = try reader.read()
            let context = try VisibleAXReader().capture(pid: finder.processIdentifier, officialWindow: window, allowedDirectory: allowed)
            report["captureMS"] = context.captureMS
            report["usedVisibleChildren"] = context.usesVisibleChildren
            report["coversFullWidth"] = context.layout.coversFullWidth
            report["sections"] = context.layout.sections.map { section in
                ["visibleItemCount": section.items.count, "gapCount": section.gaps.count,
                 "coverageKnown": section.coverageKnown, "firstEdgeKnown": section.startsAtFirstItem,
                 "lastEdgeKnown": section.endsAtLastItem,
                 "geometry": section.items.map { [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height] }] as [String: Any]
            }
            let afterSelection = try reader.read()
            let afterWindow = try reader.frontWindow()
            report["selectionStable"] = selection == afterSelection
            report["windowStable"] = window == afterWindow
            var boundaryCount = 0
            for item in context.layout.sections.flatMap(\.items) {
                for direction in [HorizontalDirection.left, .right] {
                    if case .wrap = LocalNavigation().decide(layout: context.layout, selection: .single(item.url), direction: direction) {
                        boundaryCount += 1
                    }
                }
            }
            report["geometryBoundaryCount"] = boundaryCount
            report["geometryOnlyNoInputExecuted"] = true
            let observer = try FinderChangeObserver(pid: finder.processIdentifier) { _ in }
            observer.attach(context)
            report["notificationRegistrations"] = observer.registrations.map {
                ["scope": $0.scope, "notification": $0.notification, "result": $0.result] as [String: Any]
            }
            observer.stop()
        } catch let error as FinderSelectionReader.Failure {
            report["errorCode"] = error.code; report["operation"] = error.operation
        } catch let error as AXReadFailure {
            report["axError"] = error.code.rawValue; report["operation"] = error.attribute
        } catch let error as VisibleAXReader.Failure {
            report["operation"] = String(describing: error)
        } catch { report["operation"] = "unexpected-error" }
        emit(report)
    }

    static func emit(_ report: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]) {
            FileHandle.standardOutput.write(data)
        }
    }
}
