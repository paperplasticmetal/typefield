import AppKit
import SwiftUI

/// Storage identifiers are independent of translated labels and project data.
enum TypefieldLanguage: String, CaseIterable, Identifiable {
    case system, en, fr, es, de, ja, hi
    case simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant"
    case portuguese = "pt-BR", it, ko
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .system: return "System language"
        case .en: return "English"
        case .fr: return "Français"
        case .es: return "Español"
        case .de: return "Deutsch"
        case .ja: return "日本語"
        case .hi: return "हिन्दी"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .portuguese: return "Português (Brasil)"
        case .it: return "Italiano"
        case .ko: return "한국어"
        }
    }
    static func resolve(_ selection: String, preferred: [String] = Locale.preferredLanguages) -> TypefieldLanguage {
        if let explicit = Self(rawValue: selection), explicit != .system { return explicit }
        for identifier in preferred {
            let parts = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").map(String.init)
            guard let base = parts.first else { continue }
            if base == "zh" {
                if parts.contains("hant") { return .traditionalChinese }
                if parts.contains("hans") { return .simplifiedChinese }
                return parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? .traditionalChinese : .simplifiedChinese
            }
            if base == "pt" { return .portuguese }
            if let match = Self(rawValue: base), match != .system { return match }
        }
        return .en
    }
}

final class TypefieldLanguageSettings: ObservableObject {
    static let shared: TypefieldLanguageSettings = {
        // Interactive QA may switch languages freely without changing real preferences.
        if CommandLine.arguments.contains("--window-qa") || CommandLine.arguments.contains("--language-snapshots") {
            return TypefieldLanguageSettings(defaults: UserDefaults(suiteName: "Typefield.LanguageQA." + UUID().uuidString)!)
        }
        return TypefieldLanguageSettings()
    }()
    static let key = "typefield.language"
    static let changed = Notification.Name("TypefieldLanguageChanged")
    private let defaults: UserDefaults
    @Published private(set) var selection: String
    @Published private(set) var effective: TypefieldLanguage
    private var localeObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, preferred: [String] = Locale.preferredLanguages, observeSystem: Bool = true) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.key) ?? "system"
        let initial = TypefieldLanguage(rawValue: stored)?.rawValue ?? "system"
        selection = initial
        effective = TypefieldLanguage.resolve(initial, preferred: preferred)
        if observeSystem {
            localeObserver = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
    }
    deinit { if let localeObserver { NotificationCenter.default.removeObserver(localeObserver) } }
    func select(_ value: String, preferred: [String] = Locale.preferredLanguages) {
        guard TypefieldLanguage(rawValue: value) != nil else { return }
        selection = value
        defaults.set(value, forKey: Self.key)
        refresh(preferred: preferred)
    }
    private func refresh(preferred: [String] = Locale.preferredLanguages) {
        effective = TypefieldLanguage.resolve(selection, preferred: preferred)
        NotificationCenter.default.post(name: Self.changed, object: self)
    }
    var locale: Locale { Locale(identifier: effective.rawValue) }
}

enum TypefieldL10n {
    static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
    static func text(_ key: String, language: TypefieldLanguage = TypefieldLanguageSettings.shared.effective) -> String {
        guard let path = resourceBundle.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Use only for app-owned labels. Font names and user-authored content stay verbatim.
func localizedKey(_ label: String) -> LocalizedStringKey { LocalizedStringKey(label) }

private struct TypefieldLanguageEnvironment: ViewModifier {
    @ObservedObject private var language = TypefieldLanguageSettings.shared
    func body(content: Content) -> some View {
        content.environment(\.locale, language.locale)
    }
}
extension View {
    func typefieldLocalized() -> some View { modifier(TypefieldLanguageEnvironment()) }

    // macOS creates an independent environment for presented content. Inject the
    // live locale at that boundary as well, without resetting presentation state.
    func typefieldSheet<Presented: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                         @ViewBuilder content: @escaping () -> Presented) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) { content().typefieldLocalized() }
    }
    func typefieldSheet<Item: Identifiable, Presented: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                            @ViewBuilder content: @escaping (Item) -> Presented) -> some View {
        sheet(item: item, onDismiss: onDismiss) { value in content(value).typefieldLocalized() }
    }
    func typefieldPopover<Presented: View>(isPresented: Binding<Bool>, arrowEdge: Edge = .top,
                                           @ViewBuilder content: @escaping () -> Presented) -> some View {
        popover(isPresented: isPresented, arrowEdge: arrowEdge) { content().typefieldLocalized() }
    }
}

struct TypefieldLanguagePicker: View {
    @ObservedObject private var language = TypefieldLanguageSettings.shared
    var body: some View {
        Picker(selection: Binding(get: { language.selection }, set: { language.select($0) })) {
            ForEach(TypefieldLanguage.allCases) { choice in
                if choice == .system {
                    Text("System language").tag(choice.rawValue)
                } else {
                    Text(verbatim: choice.nativeName).tag(choice.rawValue)
                }
            }
        } label: {
            Label("Language", systemImage: "globe")
        }
        .accessibilityIdentifier("typefield-language-picker")
    }
}
