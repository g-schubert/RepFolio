import SwiftUI

/// Dashboard card: light/dark mode and app language, side by side.
struct PreferencesCard: View {
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.current.rawValue

    var body: some View {
        Card(title: "Darstellung & Sprache", symbol: "paintbrush") {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Modus").font(.caption).foregroundStyle(.secondary)
                    Picker("Modus", selection: $appearanceRaw) {
                        ForEach(AppAppearance.allCases) { option in
                            Image(systemName: option.symbol)
                                .accessibilityLabel(Text(option.title))
                                .tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sprache").font(.caption).foregroundStyle(.secondary)
                    Picker("Sprache", selection: $languageRaw) {
                        ForEach(AppLanguage.allCases) { lang in
                            // Language names are shown in their own language, never translated.
                            Text(verbatim: lang.shortName)
                                .accessibilityLabel(Text(verbatim: lang.nativeName))
                                .tag(lang.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}

extension AppAppearance {
    var title: LocalizedStringKey {
        switch self {
        case .system: "Automatisch"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}

extension AppLanguage {
    var shortName: String { rawValue.uppercased() }

    var nativeName: String {
        switch self {
        case .de: "Deutsch"
        case .en: "English"
        }
    }
}

#Preview("Light") {
    PreferencesCard().padding().background(Color(.systemGroupedBackground))
}

#Preview("Dark") {
    PreferencesCard().padding().background(Color(.systemGroupedBackground))
        .preferredColorScheme(.dark)
}
