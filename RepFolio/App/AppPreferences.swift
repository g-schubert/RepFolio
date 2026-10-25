import SwiftUI

/// In-app UI language. Stored in UserDefaults (device preference, not part of backups).
enum AppLanguage: String, CaseIterable, Identifiable {
    case de, en

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .de: Locale(identifier: "de_DE")
        case .en: Locale(identifier: "en_US")
        }
    }

    /// The stored choice, or – on first launch – the localization iOS picked for the device language.
    static var current: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: storageKey), let lang = AppLanguage(rawValue: raw) {
            return lang
        }
        return Bundle.main.preferredLocalizations.first == "en" ? .en : .de
    }
}

/// Light / dark mode override.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appAppearance"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Looks up a localized string in the in-app language. Use for strings built outside of `Text`
/// (alerts messages, notifications, computed labels); SwiftUI `Text` literals resolve via `\.locale`.
func L(_ resource: LocalizedStringResource) -> String {
    var resource = resource
    resource.locale = AppLanguage.current.locale
    return String(localized: resource)
}

/// Applies the in-app language and appearance to the whole view hierarchy.
struct AppPreferencesModifier: ViewModifier {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.current.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    func body(content: Content) -> some View {
        let language = AppLanguage(rawValue: languageRaw) ?? .de
        content
            .environment(\.locale, language.locale)
            .preferredColorScheme(AppAppearance(rawValue: appearanceRaw)?.colorScheme)
            // Rebuild the hierarchy so strings computed via `L()` pick up the new language immediately.
            .id(language)
    }
}
