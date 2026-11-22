import Foundation

enum L10n {
    static var language: String {
        Bundle.main.preferredLocalizations.first == "ru" ? "ru" : "en"
    }

    static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }
}
