import Foundation

/// Display language. `.system` follows the first preferred system language.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case chinese
    case english

    public static let storageKey = "displayLanguage"

    public static func resolved(_ raw: String) -> AppLanguage {
        AppLanguage(rawValue: raw) ?? .system
    }

    public static var systemPrefersChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
    }

    public var isChinese: Bool {
        switch self {
        case .chinese: return true
        case .english: return false
        case .system: return Self.systemPrefersChinese
        }
    }
}

/// App appearance. `.system` follows the current macOS appearance.
public enum AppAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public static let storageKey = "appAppearance"

    public static func resolved(_ raw: String) -> AppAppearance {
        AppAppearance(rawValue: raw) ?? .system
    }

    /// `nil` means no forced appearance.
    public var forcedDark: Bool? {
        switch self {
        case .system: return nil
        case .light: return false
        case .dark: return true
        }
    }
}
