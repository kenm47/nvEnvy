import Foundation
import AppKit
import UniformTypeIdentifiers
import NvEnvyCore

private let kNotesFolderBookmarkKey = "notesFolderBookmark"
private let kEditorFontNameKey = "editorFontName"
private let kEditorFontSizeKey = "editorFontSize"
private let kSoftTabsKey = "softTabs"
private let kSpacesPerTabKey = "spacesPerTab"
private let kAutoPairKey = "autoPair"
private let kAutoIndentKey = "autoIndent"
private let kAutoListKey = "autoList"
private let kURLDetectionKey = "urlDetection"
private let kCheckSpellingKey = "checkSpelling"
private let kSearchHighlightKey = "searchHighlight"
private let kSearchHighlightColorKey = "searchHighlightColor"
private let kShowWordCountKey = "showWordCount"
private let kEditorFGColorKey = "editorFGColor"
private let kEditorBGColorKey = "editorBGColor"
private let kMaxBodyWidthKey = "maxBodyWidth"
private let kColorSchemeKey = "colorScheme"
private let kConfirmDeletionKey = "confirmDeletion"
private let kExternalEditorPathKey = "externalEditorPath"
private let kAutocompleteKey = "autocomplete"
private let kShowDockIconKey = "showDockIcon"
private let kTagFilterKey = "tagFilter"
private let kNoteListDisplayModeKey = "noteListDisplayMode"
private let kLayoutOrientationKey = "layoutOrientation"
private let kCloseActionKey = "closeAction"

@MainActor
@Observable
public final class AppState {
    public var searchQuery: String = "" {
        didSet { performSearch() }
    }
    public var allNotes: [Note] = []
    public var filteredNotes: [Note] = []
    public private(set) var notesFolderURL: URL?
    public var editorFont: NSFont
    public var selectedNoteID: Note.ID?

    // Editor preferences
    public var softTabs: Bool {
        didSet { UserDefaults.standard.set(softTabs, forKey: kSoftTabsKey) }
    }
    public var spacesPerTab: Int {
        didSet { UserDefaults.standard.set(spacesPerTab, forKey: kSpacesPerTabKey) }
    }
    public var autoPairEnabled: Bool {
        didSet { UserDefaults.standard.set(autoPairEnabled, forKey: kAutoPairKey) }
    }
    public var autoIndentEnabled: Bool {
        didSet { UserDefaults.standard.set(autoIndentEnabled, forKey: kAutoIndentKey) }
    }
    public var autoListEnabled: Bool {
        didSet { UserDefaults.standard.set(autoListEnabled, forKey: kAutoListKey) }
    }
    public var urlDetectionEnabled: Bool {
        didSet { UserDefaults.standard.set(urlDetectionEnabled, forKey: kURLDetectionKey) }
    }
    public var checkSpellingEnabled: Bool {
        didSet { UserDefaults.standard.set(checkSpellingEnabled, forKey: kCheckSpellingKey) }
    }
    public var searchHighlightEnabled: Bool {
        didSet { UserDefaults.standard.set(searchHighlightEnabled, forKey: kSearchHighlightKey) }
    }
    public var searchHighlightColor: NSColor {
        didSet { saveColor(searchHighlightColor, forKey: kSearchHighlightColorKey) }
    }
    public var showWordCount: Bool {
        didSet { UserDefaults.standard.set(showWordCount, forKey: kShowWordCountKey) }
    }

    // Fonts & Colors
    public var editorFGColor: NSColor {
        didSet { saveColor(editorFGColor, forKey: kEditorFGColorKey) }
    }
    public var editorBGColor: NSColor {
        didSet { saveColor(editorBGColor, forKey: kEditorBGColorKey) }
    }
    public var maxBodyWidth: Double {
        didSet { UserDefaults.standard.set(maxBodyWidth, forKey: kMaxBodyWidthKey) }
    }
    public var colorScheme: ColorScheme {
        didSet { applyColorScheme(colorScheme) }
    }

    // General preferences
    public var confirmDeletion: Bool {
        didSet { UserDefaults.standard.set(confirmDeletion, forKey: kConfirmDeletionKey) }
    }
    public var externalEditorPath: String? {
        didSet { UserDefaults.standard.set(externalEditorPath, forKey: kExternalEditorPathKey) }
    }
    public var autocompleteEnabled: Bool {
        didSet { UserDefaults.standard.set(autocompleteEnabled, forKey: kAutocompleteKey) }
    }
    public var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: kShowDockIconKey)
            NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        }
    }

    // Display mode & layout
    public var noteListDisplayMode: NoteListDisplayMode {
        didSet { UserDefaults.standard.set(noteListDisplayMode.rawValue, forKey: kNoteListDisplayModeKey) }
    }
    public var layoutOrientation: LayoutOrientation {
        didSet { UserDefaults.standard.set(layoutOrientation.rawValue, forKey: kLayoutOrientationKey) }
    }
    public var closeAction: CloseAction {
        didSet { UserDefaults.standard.set(closeAction.rawValue, forKey: kCloseActionKey) }
    }

    public enum NoteListDisplayMode: Int, CaseIterable {
        case standard = 0
        case preview = 1

        public var displayName: String {
            switch self {
            case .standard: return "Standard"
            case .preview: return "Preview"
            }
        }
    }

    public enum LayoutOrientation: Int, CaseIterable {
        case horizontal = 0
        case vertical = 1

        public var displayName: String {
            switch self {
            case .horizontal: return "Side by Side"
            case .vertical: return "Stacked"
            }
        }
    }

    public enum CloseAction: Int, CaseIterable {
        case quit = 0
        case hide = 1

        public var displayName: String {
            switch self {
            case .quit: return "Quit"
            case .hide: return "Hide"
            }
        }
    }

    // Tag filtering
    public var tagFilter: String? {
        didSet { performSearch() }
    }

    // Preview
    public var showPreview: Bool = false
    public var previewStickyNoteID: Note.ID?

    // All known tags (derived from all notes)
    public var allKnownTags: [String] {
        let tagSets = allNotes.flatMap(\.tags)
        return Array(Set(tagSets)).sorted()
    }

    // Snapback stack for URL navigation
    public var snapbackStack: [Note.ID] = []
    public var hasSnapback: Bool { !snapbackStack.isEmpty }

    // Bookmarks
    public var bookmarkStore = BookmarkStore()

    private var noteStore: NoteStore?
    private var storageService: FileStorageService?
    private var searchEngine = SearchEngine()
    private var fileMonitor: FileSystemMonitor?

    public enum ColorScheme: Int, CaseIterable {
        case blackWhite = 0
        case lowContrast = 1
        case custom = 2

        public var displayName: String {
            switch self {
            case .blackWhite: return "B/W"
            case .lowContrast: return "Low Contrast"
            case .custom: return "Custom"
            }
        }
    }

    public init() {
        let savedName = UserDefaults.standard.string(forKey: kEditorFontNameKey)
        let savedSize = UserDefaults.standard.double(forKey: kEditorFontSizeKey)
        if let name = savedName, savedSize > 0,
           let font = NSFont(name: name, size: savedSize) {
            self.editorFont = font
        } else {
            self.editorFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        }

        let ud = UserDefaults.standard
        self.softTabs = ud.object(forKey: kSoftTabsKey) as? Bool ?? true
        self.spacesPerTab = ud.object(forKey: kSpacesPerTabKey) as? Int ?? 4
        self.autoPairEnabled = ud.object(forKey: kAutoPairKey) as? Bool ?? true
        self.autoIndentEnabled = ud.object(forKey: kAutoIndentKey) as? Bool ?? true
        self.autoListEnabled = ud.object(forKey: kAutoListKey) as? Bool ?? true
        self.urlDetectionEnabled = ud.object(forKey: kURLDetectionKey) as? Bool ?? true
        self.checkSpellingEnabled = ud.object(forKey: kCheckSpellingKey) as? Bool ?? true
        self.searchHighlightEnabled = ud.object(forKey: kSearchHighlightKey) as? Bool ?? true
        self.searchHighlightColor = AppState.loadColor(forKey: kSearchHighlightColorKey) ?? .systemYellow
        self.showWordCount = ud.bool(forKey: kShowWordCountKey)
        self.editorFGColor = AppState.loadColor(forKey: kEditorFGColorKey) ?? .textColor
        self.editorBGColor = AppState.loadColor(forKey: kEditorBGColorKey) ?? .textBackgroundColor
        self.maxBodyWidth = ud.object(forKey: kMaxBodyWidthKey) as? Double ?? 0
        self.colorScheme = ColorScheme(rawValue: ud.integer(forKey: kColorSchemeKey)) ?? .custom
        self.confirmDeletion = ud.object(forKey: kConfirmDeletionKey) as? Bool ?? true
        self.externalEditorPath = ud.string(forKey: kExternalEditorPathKey)
        self.autocompleteEnabled = ud.object(forKey: kAutocompleteKey) as? Bool ?? false
        self.showDockIcon = ud.object(forKey: kShowDockIconKey) as? Bool ?? true
        self.noteListDisplayMode = NoteListDisplayMode(rawValue: ud.integer(forKey: kNoteListDisplayModeKey)) ?? .standard
        self.layoutOrientation = LayoutOrientation(rawValue: ud.integer(forKey: kLayoutOrientationKey)) ?? .horizontal
        self.closeAction = CloseAction(rawValue: ud.integer(forKey: kCloseActionKey)) ?? .quit

        restoreNotesFolder()
    }

    // MARK: - Color Persistence

    private static func loadColor(forKey key: String) -> NSColor? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) else {
            return nil
        }
        return color
    }

    private func saveColor(_ color: NSColor, forKey key: String) {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Color Schemes

    private func applyColorScheme(_ scheme: ColorScheme) {
        UserDefaults.standard.set(scheme.rawValue, forKey: kColorSchemeKey)
        switch scheme {
        case .blackWhite:
            editorFGColor = .black
            editorBGColor = .white
        case .lowContrast:
            editorFGColor = NSColor(white: 0.25, alpha: 1)
            editorBGColor = NSColor(white: 0.92, alpha: 1)
        case .custom:
            break // keep user's colors
        }
    }

    // MARK: - Folder Management

    public func setNotesFolder(_ url: URL) {
        // Stop accessing old folder if any
        notesFolderURL?.stopAccessingSecurityScopedResource()

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: kNotesFolderBookmarkKey)
        } catch {
            // Fall through — URL from NSOpenPanel still has temporary access
        }

        // Ensure security-scoped access for bookmark-resolved URLs
        _ = url.startAccessingSecurityScopedResource()
        notesFolderURL = url
        setupStorage(url: url)
    }

    private func restoreNotesFolder() {
        guard let data = UserDefaults.standard.data(forKey: kNotesFolderBookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        if isStale {
            if let newData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(newData, forKey: kNotesFolderBookmarkKey)
            }
        }

        guard url.startAccessingSecurityScopedResource() else { return }
        notesFolderURL = url
        setupStorage(url: url)
    }

    private func setupStorage(url: URL) {
        let storage = FileStorageService(notesDirectory: url)
        self.storageService = storage
        let store = NoteStore(storage: storage)
        self.noteStore = store

        fileMonitor?.stop()
        fileMonitor = FileSystemMonitor(directory: url) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.reconcileFilesystem()
            }
        }
        fileMonitor?.start()

        Task {
            try? await store.loadAll()
            self.allNotes = await store.allNotes()
            self.filteredNotes = self.allNotes
        }
    }

    // MARK: - Search

    private func performSearch() {
        var results = searchEngine.filter(notes: allNotes, query: searchQuery)
        if let tag = tagFilter {
            results = results.filter { $0.tags.contains(tag) }
        }
        filteredNotes = results
    }

    public func clearSearch() {
        searchQuery = ""
        tagFilter = nil
    }

    public func createOrSelectNote() {
        guard !searchQuery.isEmpty else { return }

        if let match = searchEngine.exactTitleMatch(notes: allNotes, query: searchQuery) {
            filteredNotes = [match]
            selectedNoteID = match.id
            return
        }

        let title = searchQuery
        Task {
            guard let store = noteStore else { return }
            let note = try await store.createNote(title: title)
            allNotes.append(note)
            filteredNotes = [note]
            selectedNoteID = note.id
            searchQuery = ""
        }
    }

    // MARK: - Note Operations

    public func note(for id: UUID) -> Note? {
        allNotes.first { $0.id == id }
    }

    public func updateNoteBody(noteID: UUID, body: String) {
        guard let note = note(for: noteID) else { return }
        note.body = body
        note.modifiedDate = Date()
        note.invalidateSearchCache()

        Task {
            await noteStore?.updateBody(noteID: noteID, body: body)
        }
    }

    public func updateNoteTags(noteID: UUID, tags: [String]) {
        guard let note = note(for: noteID) else { return }
        note.tags = tags
        note.modifiedDate = Date()
        note.invalidateSearchCache()

        Task {
            await noteStore?.updateTags(noteID: noteID, tags: tags)
        }
    }

    public func deleteNote(noteID: UUID) {
        Task {
            try? await noteStore?.deleteNote(noteID: noteID)
            allNotes.removeAll { $0.id == noteID }
            if selectedNoteID == noteID {
                selectedNoteID = nil
            }
            performSearch()
        }
    }

    public func renameNote(noteID: UUID, newTitle: String) {
        Task {
            try? await noteStore?.updateTitle(noteID: noteID, title: newTitle)
            if let note = note(for: noteID) {
                note.title = newTitle
                note.invalidateSearchCache()
            }
            performSearch()
        }
    }

    public func revealInFinder(noteID: UUID) {
        guard let note = note(for: noteID),
              let url = notesFolderURL else { return }
        let fileURL = url.appendingPathComponent(note.filename + ".md")
        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
    }

    // MARK: - Wikilink Navigation

    public func navigateToWikilink(title: String) {
        if let current = selectedNoteID {
            snapbackStack.append(current)
        }
        let lowerTitle = title.lowercased()
        if let match = allNotes.first(where: { $0.cachedLowercaseTitle == lowerTitle }) {
            selectedNoteID = match.id
            searchQuery = ""
            filteredNotes = allNotes
        } else {
            searchQuery = title
        }
    }

    // MARK: - Note Selection

    public func selectNextNote() {
        guard !filteredNotes.isEmpty else { return }
        if let current = selectedNoteID,
           let idx = filteredNotes.firstIndex(where: { $0.id == current }) {
            let nextIdx = filteredNotes.index(after: idx)
            if nextIdx < filteredNotes.endIndex {
                selectedNoteID = filteredNotes[nextIdx].id
            }
        } else {
            selectedNoteID = filteredNotes.first?.id
        }
    }

    public func selectPreviousNote() {
        guard !filteredNotes.isEmpty else { return }
        if let current = selectedNoteID,
           let idx = filteredNotes.firstIndex(where: { $0.id == current }) {
            if idx > filteredNotes.startIndex {
                selectedNoteID = filteredNotes[filteredNotes.index(before: idx)].id
            }
        } else {
            selectedNoteID = filteredNotes.last?.id
        }
    }

    public func deselectNote() {
        if hasSnapback {
            snapback()
        } else {
            selectedNoteID = nil
        }
    }

    // MARK: - File System Reconciliation

    private func reconcileFilesystem() async {
        guard let store = noteStore else { return }
        try? await store.reconcileWithFilesystem()
        allNotes = await store.allNotes()
        performSearch()
    }

    // MARK: - Finder Tags

    public func writeFinderTags(for note: Note) {
        guard let url = notesFolderURL else { return }
        let fileURL = url.appendingPathComponent(note.filename + ".md")
        try? (fileURL as NSURL).setResourceValue(note.tags, forKey: .tagNamesKey)
    }

    // MARK: - External Editor

    public func openInExternalEditor(noteID: UUID) {
        guard let note = note(for: noteID),
              let folderURL = notesFolderURL else { return }

        guard let editorPath = externalEditorPath else {
            NotificationCenter.default.post(name: .nvEnvyNoExternalEditor, object: nil)
            return
        }

        let fileURL = folderURL.appendingPathComponent(note.filename + ".md")
        let editorURL = URL(fileURLWithPath: editorPath)

        NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: editorURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    // MARK: - Font

    public func setEditorFont(_ font: NSFont) {
        editorFont = font
        UserDefaults.standard.set(font.fontName, forKey: kEditorFontNameKey)
        UserDefaults.standard.set(Double(font.pointSize), forKey: kEditorFontSizeKey)
    }

    // MARK: - Import

    public func importFiles(urls: [URL]) {
        Task {
            guard let store = noteStore else { return }
            let service = ImportExportService()
            for url in urls {
                if let imported = try? await service.importFile(at: url) {
                    let note = try? await store.addImportedNote(
                        title: imported.title, body: imported.body, tags: imported.tags
                    )
                    if let note { allNotes.append(note) }
                }
            }
            performSearch()
        }
    }

    public func importDirectory(url: URL) {
        Task {
            guard let store = noteStore else { return }
            let service = ImportExportService()
            let imported = (try? await service.importDirectory(at: url)) ?? []
            for item in imported {
                let note = try? await store.addImportedNote(
                    title: item.title, body: item.body, tags: item.tags
                )
                if let note { allNotes.append(note) }
            }
            performSearch()
        }
    }

    public func importPasteboardItems(_ items: [NSPasteboardItem]) {
        Task {
            guard let store = noteStore else { return }
            let service = ImportExportService()
            let dateStr = ISO8601DateFormatter().string(from: Date())

            for item in items {
                let imported: ImportedNote?
                if let rtfData = item.data(forType: .rtf) {
                    imported = await service.importRTFData(rtfData, title: "Imported \(dateStr)")
                } else if let html = item.string(forType: .html) {
                    imported = await service.importHTMLString(html, title: "Imported \(dateStr)")
                } else if let text = item.string(forType: .string) {
                    imported = await service.importPlainText(text, title: "Imported \(dateStr)")
                } else {
                    imported = nil
                }

                if let imported {
                    let note = try? await store.addImportedNote(
                        title: imported.title, body: imported.body, tags: imported.tags
                    )
                    if let note { allNotes.append(note) }
                }
            }
            performSearch()
        }
    }

    // MARK: - Export

    public func exportNote(noteID: UUID) {
        guard let note = note(for: noteID) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .rtf, .html]
        panel.nameFieldStringValue = note.title
        panel.canSelectHiddenExtension = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            let service = ImportExportService()
            let ext = url.pathExtension.lowercased()

            switch ext {
            case "html", "htm":
                let html = await service.exportAsHTML(note)
                try? html.write(to: url, atomically: true, encoding: .utf8)
            case "rtf":
                if let data = await service.exportAsRTF(note) {
                    try? data.write(to: url)
                }
            default:
                let text = await service.exportAsPlainText(note)
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Print

    public func printNote(noteID: UUID) {
        guard let note = note(for: noteID) else { return }

        let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        printView.string = note.body
        printView.font = editorFont

        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic

        let op = NSPrintOperation(view: printView, printInfo: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }

    // MARK: - Copy Note Link

    public func copyNoteLink(noteID: UUID) {
        guard let note = note(for: noteID) else { return }
        let encoded = note.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? note.title
        let link = "nvenvy://find/\(encoded)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    // MARK: - Rename

    public var isRenaming: Bool = false

    public func startRename() {
        guard let noteID = selectedNoteID, let note = note(for: noteID) else { return }
        isRenaming = true
        searchQuery = note.title
    }

    public func commitRename() {
        guard isRenaming, let noteID = selectedNoteID, !searchQuery.isEmpty else {
            isRenaming = false
            return
        }
        isRenaming = false
        renameNote(noteID: noteID, newTitle: searchQuery)
        searchQuery = ""
    }

    // MARK: - Bookmarks

    public func saveBookmark() {
        let name = searchQuery.isEmpty ? "Bookmark \(bookmarkStore.bookmarks.count + 1)" : searchQuery
        let bookmark = Bookmark(name: name, searchQuery: searchQuery, noteID: selectedNoteID)
        bookmarkStore.add(bookmark)
    }

    public func restoreBookmark(index: Int) {
        guard let bookmark = bookmarkStore.bookmark(at: index) else { return }
        searchQuery = bookmark.searchQuery
        if let noteID = bookmark.noteID,
           allNotes.contains(where: { $0.id == noteID }) {
            selectedNoteID = noteID
        }
    }

    // MARK: - URL Scheme

    public func handleURL(_ url: URL) {
        guard let action = URLSchemeHandler.parse(url) else { return }

        switch action.kind {
        case .find(let searchTerm, let noteID):
            // Push current note onto snapback stack
            if let current = selectedNoteID {
                snapbackStack.append(current)
            }

            if let noteID, let match = allNotes.first(where: { $0.id == noteID }) {
                selectedNoteID = match.id
                searchQuery = ""
                filteredNotes = allNotes
            } else if !searchTerm.isEmpty {
                searchQuery = searchTerm
                if let match = searchEngine.exactTitleMatch(notes: allNotes, query: searchTerm) {
                    selectedNoteID = match.id
                }
            }

            NSApp.activate(ignoringOtherApps: true)

        case .make(let title, let body, let tags):
            let noteTitle = title ?? "Untitled"
            Task {
                guard let store = noteStore else { return }
                let note = try await store.addImportedNote(
                    title: noteTitle,
                    body: body ?? "",
                    tags: tags
                )
                allNotes.append(note)
                performSearch()
                selectedNoteID = note.id
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func snapback() {
        guard let previousID = snapbackStack.popLast() else { return }
        selectedNoteID = previousID
        searchQuery = ""
        filteredNotes = allNotes
    }

    // MARK: - Intent Support

    public func createNoteFromIntent(title: String, body: String, tags: [String]) {
        Task {
            guard let store = noteStore else { return }
            let note = try await store.addImportedNote(title: title, body: body, tags: tags)
            allNotes.append(note)
            performSearch()
            selectedNoteID = note.id
        }
    }

    // MARK: - Flush on quit

    public func flushBeforeQuit() async {
        await noteStore?.flushDirtyNotes()
    }
}
