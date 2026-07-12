import SwiftUI
import NvEnvyCore

enum FontChoice: String, CaseIterable, Identifiable {
    case dynamicType
    case systemMono
    case atkinson
    case openDyslexic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dynamicType: return "Dynamic Type (Recommended)"
        case .systemMono: return "System Mono"
        case .atkinson: return "Atkinson Hyperlegible"
        case .openDyslexic: return "OpenDyslexic"
        }
    }
}

enum AppearanceOverride: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// iOS-only settings surface (trimmed relative to the macOS `PreferencesView`).
/// Persisted via `UserDefaults`, keys prefixed `nvenvy.iOS.` so they never
/// collide with the macOS app's own preference keys (they don't share a
/// defaults suite, but the prefix keeps intent obvious).
@MainActor
@Observable
final class IOSPreferences {
    private enum Keys {
        static let fontChoice = "nvenvy.iOS.fontChoice"
        static let fontSize = "nvenvy.iOS.fontSize"
        static let appearance = "nvenvy.iOS.appearance"
        static let softTabs = "nvenvy.iOS.softTabs"
        static let spacesPerTab = "nvenvy.iOS.spacesPerTab"
        static let autoPair = "nvenvy.iOS.autoPair"
        static let autoIndent = "nvenvy.iOS.autoIndent"
        static let autoList = "nvenvy.iOS.autoList"
        static let doneStrikethrough = "nvenvy.iOS.doneStrikethrough"
        static let checkSpelling = "nvenvy.iOS.checkSpelling"
        static let searchHighlight = "nvenvy.iOS.searchHighlight"
        static let confirmDeletion = "nvenvy.iOS.confirmDeletion"
        static let autoSuggestWikilinks = "nvenvy.iOS.autoSuggestWikilinks"
        static let sortField = "nvenvy.iOS.sortField"
        static let sortAscending = "nvenvy.iOS.sortAscending"
    }

    private let defaults = UserDefaults.standard

    var fontChoice: FontChoice {
        didSet { defaults.set(fontChoice.rawValue, forKey: Keys.fontChoice); fontGeneration += 1 }
    }
    var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize); fontGeneration += 1 }
    }
    var appearance: AppearanceOverride {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    var softTabs: Bool {
        didSet { defaults.set(softTabs, forKey: Keys.softTabs) }
    }
    var spacesPerTab: Int {
        didSet { defaults.set(spacesPerTab, forKey: Keys.spacesPerTab) }
    }
    var autoPair: Bool {
        didSet { defaults.set(autoPair, forKey: Keys.autoPair) }
    }
    var autoIndent: Bool {
        didSet { defaults.set(autoIndent, forKey: Keys.autoIndent) }
    }
    var autoList: Bool {
        didSet { defaults.set(autoList, forKey: Keys.autoList) }
    }
    var doneStrikethrough: Bool {
        didSet { defaults.set(doneStrikethrough, forKey: Keys.doneStrikethrough) }
    }
    var checkSpelling: Bool {
        didSet { defaults.set(checkSpelling, forKey: Keys.checkSpelling) }
    }
    var searchHighlight: Bool {
        didSet { defaults.set(searchHighlight, forKey: Keys.searchHighlight) }
    }
    var confirmDeletion: Bool {
        didSet { defaults.set(confirmDeletion, forKey: Keys.confirmDeletion) }
    }
    var autoSuggestWikilinks: Bool {
        didSet { defaults.set(autoSuggestWikilinks, forKey: Keys.autoSuggestWikilinks) }
    }
    var sortField: NotesViewModel.SortField {
        didSet { defaults.set(sortField.rawValue, forKey: Keys.sortField) }
    }
    var sortAscending: Bool {
        didSet { defaults.set(sortAscending, forKey: Keys.sortAscending) }
    }

    /// Bumped whenever the font choice/size changes, so editor views can tell
    /// a font-relevant preference update apart from an unrelated Observation
    /// tick and re-apply the font without redoing unrelated work.
    private(set) var fontGeneration = 0

    init() {
        fontChoice = FontChoice(rawValue: defaults.string(forKey: Keys.fontChoice) ?? "") ?? .dynamicType
        fontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 17
        appearance = AppearanceOverride(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        softTabs = defaults.object(forKey: Keys.softTabs) as? Bool ?? true
        spacesPerTab = defaults.object(forKey: Keys.spacesPerTab) as? Int ?? 4
        autoPair = defaults.object(forKey: Keys.autoPair) as? Bool ?? true
        autoIndent = defaults.object(forKey: Keys.autoIndent) as? Bool ?? true
        autoList = defaults.object(forKey: Keys.autoList) as? Bool ?? true
        doneStrikethrough = defaults.object(forKey: Keys.doneStrikethrough) as? Bool ?? true
        checkSpelling = defaults.object(forKey: Keys.checkSpelling) as? Bool ?? true
        searchHighlight = defaults.object(forKey: Keys.searchHighlight) as? Bool ?? true
        confirmDeletion = defaults.object(forKey: Keys.confirmDeletion) as? Bool ?? true
        autoSuggestWikilinks = defaults.object(forKey: Keys.autoSuggestWikilinks) as? Bool ?? true
        if let raw = defaults.object(forKey: Keys.sortField) as? Int,
           let field = NotesViewModel.SortField(rawValue: raw) {
            sortField = field
        } else {
            sortField = .modifiedDate
        }
        sortAscending = defaults.object(forKey: Keys.sortAscending) as? Bool ?? false
    }

    var fontDescriptor: EditorFontDescriptor {
        switch fontChoice {
        case .dynamicType:
            return .dynamicType
        case .systemMono:
            return .systemMonospaced(size: fontSize)
        case .atkinson:
            return .named(postScriptName: "AtkinsonHyperlegible-Regular", size: fontSize)
        case .openDyslexic:
            return .named(postScriptName: "OpenDyslexic-Regular", size: fontSize)
        }
    }
}
