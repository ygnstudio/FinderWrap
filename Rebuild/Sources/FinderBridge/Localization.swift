import Foundation

/// Tiny two-language lookup driven by the stored display language.
struct L10n {
    let chinese: Bool

    func t(_ zh: String, _ en: String) -> String {
        chinese ? zh : en
    }

    static var current: L10n {
        let raw = UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? AppLanguage.system.rawValue
        return L10n(chinese: AppLanguage.resolved(raw).isChinese)
    }
}
