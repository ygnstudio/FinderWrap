import AppKit
import CoreServices
import Foundation

/// Worker-owned Apple Event reader. It never requests permission, writes Finder
/// state, or logs filenames. Direct events avoid running AppleScript on the UI
/// thread and do not invoke an interpreter process for every key.
public final class FinderSelectionReader {
    public struct Failure: Error, Equatable {
        public let code: OSStatus
        public let operation: String
    }

    public enum Selection: Equatable {
        case empty
        case multiple(Int)
        case single(URL)
    }

    public struct Window: Equatable {
        public let id: Int32
        public let viewCode: OSType
        public let directory: URL
        public var isIconView: Bool { viewCode == FinderSelectionReader.code("icnv") }
    }

    private let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
    private let permission: () -> OSStatus
    private let exchange: (NSAppleEventDescriptor, Int) throws -> NSAppleEventDescriptor
    private let timeoutTicks: Int

    public convenience init(timeoutTicks: Int = 60) {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        self.init(timeoutTicks: timeoutTicks, permission: {
            AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
        }, exchange: Self.exchange)
    }

    // The boundary is injectable so protocol failures can be tested without TCC,
    // Finder, or a fabricated successful fallback.
    init(timeoutTicks: Int = 60, permission: @escaping () -> OSStatus,
         exchange: @escaping (NSAppleEventDescriptor, Int) throws -> NSAppleEventDescriptor) {
        self.timeoutTicks = max(1, timeoutTicks)
        self.permission = permission
        self.exchange = exchange
    }

    public func permissionStatus() -> OSStatus {
        permission()
    }

    public func read() throws -> Selection {
        let permission = permissionStatus()
        guard permission == noErr else { throw Failure(code: permission, operation: "permission") }
        let selection = try Self.property(Self.code("sele"))
        // Resolve the list-valued property itself, then inspect its cardinality.
        let selected = try send(kAEGetData, object: selection, operation: "selection-list")
        guard selected.descriptorType == typeAEList else {
            throw Failure(code: OSStatus(errAECoercionFail), operation: "selection-list-type")
        }
        let count = selected.numberOfItems
        if count == 0 { return .empty }
        if count > 1 { return .multiple(count) }
        guard let first = selected.atIndex(1) else {
            throw Failure(code: OSStatus(errAEDescNotFound), operation: "selection-item")
        }
        let result = try send(kAEGetData, object: try Self.property(Self.code("pURL"), of: first), operation: "selection-url")
        guard let string = result.stringValue, let url = URL(string: string), url.isFileURL else {
            throw Failure(code: OSStatus(errAECoercionFail), operation: "selection-url-type")
        }
        // Selection may change between count and URL reads. The coordinator must
        // compare a second observation immediately before any eventual mutation.
        return .single(url.standardizedFileURL)
    }

    /// Read-only identity for worker captures; never use a window title as ID.
    public func frontWindow() throws -> Window {
        let permission = permissionStatus()
        guard permission == noErr else { throw Failure(code: permission, operation: "permission") }
        let front = try Self.object(want: Self.code("brow"), form: OSType(formAbsolutePosition),
                                    data: NSAppleEventDescriptor(int32: 1), container: .null())
        let identity = try send(kAEGetData, object: Self.property(Self.code("ID  "), of: front), operation: "window-id")
        guard let id = identity.coerce(toDescriptorType: typeSInt32), id.int32Value > 0 else {
            throw Failure(code: OSStatus(errAECoercionFail), operation: "window-id-type")
        }
        // Resolve later properties by the observed ID, not a mutable index.
        let window = try Self.object(want: Self.code("brow"), form: OSType(formUniqueID), data: id, container: .null())
        let view = try send(kAEGetData, object: Self.property(Self.code("pvew"), of: window), operation: "window-view")
        guard let viewCode = view.coerce(toDescriptorType: typeEnumerated) else {
            throw Failure(code: OSStatus(errAECoercionFail), operation: "window-view-type")
        }
        let directory = try send(kAEGetData, object: Self.property(Self.code("pURL"), of: Self.property(Self.code("fvtg"), of: window)),
                                 operation: "window-directory")
        guard let string = directory.stringValue, let url = URL(string: string), url.isFileURL else {
            throw Failure(code: OSStatus(errAECoercionFail), operation: "window-directory-type")
        }
        return Window(id: id.int32Value, viewCode: viewCode.enumCodeValue, directory: url.standardizedFileURL)
    }

    private func send(_ eventID: AEEventID, object: NSAppleEventDescriptor,
                      operation: String) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: kAECoreSuite, eventID: eventID,
                                          targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                          transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(object, forKeyword: keyDirectObject)
        let response: NSAppleEventDescriptor
        do { response = try exchange(event, timeoutTicks) }
        catch let error as Failure { throw Failure(code: error.code, operation: operation) }
        var remoteError: Int32 = 0
        if let raw = response.paramDescriptor(forKeyword: keyErrorNumber) {
            guard let number = raw.coerce(toDescriptorType: typeSInt32) else {
                throw Failure(code: OSStatus(errAECoercionFail), operation: "reply-error-type")
            }
            remoteError = number.int32Value
        }
        guard remoteError == 0 else { throw Failure(code: remoteError, operation: operation) }
        guard let result = response.paramDescriptor(forKeyword: keyDirectObject) else {
            throw Failure(code: OSStatus(errAEDescNotFound), operation: operation)
        }
        return result
    }

    private static func exchange(_ event: NSAppleEventDescriptor, timeout: Int) throws -> NSAppleEventDescriptor {
        var reply = AppleEvent()
        let status = AESendMessage(event.aeDesc, &reply, AESendMode(kAEWaitReply | kAENeverInteract), timeout)
        guard status == noErr else {
            AEDisposeDesc(&reply)
            throw Failure(code: status, operation: "send")
        }
        return NSAppleEventDescriptor(aeDescNoCopy: &reply)
    }

    static func property(_ property: OSType, of container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        try object(want: typeProperty, form: OSType(formPropertyID), data: NSAppleEventDescriptor(typeCode: property), container: container)
    }

    static func object(want: OSType, form: OSType, data: NSAppleEventDescriptor,
                       container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        guard var containerDesc = container.aeDesc?.pointee, var keyDesc = data.aeDesc?.pointee else {
            throw Failure(code: OSStatus(errAEDescNotFound), operation: "object-specifier-input")
        }
        var result = AEDesc()
        let status = CreateObjSpecifier(want, &containerDesc, form, &keyDesc, false, &result)
        guard status == noErr else { throw Failure(code: OSStatus(status), operation: "object-specifier") }
        return NSAppleEventDescriptor(aeDescNoCopy: &result)
    }

    static func code(_ string: String) -> OSType {
        precondition(string.utf8.count == 4)
        return string.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }
}
