import AppIntents
import Foundation

// MARK: - Search Notes Intent

struct SearchNotesIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Notes"
    static var description = IntentDescription("Search for notes matching a query")

    @Parameter(title: "Query")
    var query: String

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let titles = await MainActor.run {
            guard let appState = AppIntentsBridge.shared.appState else { return [String]() }
            let results = appState.allNotes.filter { note in
                note.cachedLowercaseTitle.contains(query.lowercased()) ||
                note.cachedLowercaseBody.contains(query.lowercased())
            }
            return results.map(\.title)
        }
        return .result(value: titles)
    }
}

// MARK: - Create Note Intent

struct CreateNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Note"
    static var description = IntentDescription("Create a new note in nvEnvy")

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Body", default: "")
    var body: String

    @Parameter(title: "Tags", default: "")
    var tags: String

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            guard let appState = AppIntentsBridge.shared.appState else { return }
            let tagList = tags.isEmpty ? [String]() : tags.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            appState.createNoteFromIntent(title: title, body: body, tags: tagList)
        }
        return .result()
    }
}

// MARK: - Shortcuts Provider

struct NvEnvyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SearchNotesIntent(),
            phrases: ["Search \(.applicationName)", "Find notes in \(.applicationName)"],
            shortTitle: "Search Notes",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: ["Create note in \(.applicationName)", "New note in \(.applicationName)"],
            shortTitle: "Create Note",
            systemImageName: "square.and.pencil"
        )
    }
}

// MARK: - Bridge for AppIntents to access AppState

@MainActor
final class AppIntentsBridge {
    static let shared = AppIntentsBridge()
    weak var appState: AppState?
}
