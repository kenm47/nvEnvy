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
private let kMirrorFinderTagsKey = "mirrorFinderTags"
private let kShowStatusBarItemKey = "showStatusBarItem"
private let kSortFieldKey = "sortField"
private let kSortAscendingKey = "sortAscending"
private let kTableFontSizeKey = "tableFontSize"
private let kShowGridLinesKey = "showGridLines"
private let kAlternatingRowColorsKey = "alternatingRowColors"
private let kShowTagsColumnKey = "showTagsColumn"
private let kShowModifiedColumnKey = "showModifiedColumn"
private let kShowCreatedColumnKey = "showCreatedColumn"
private let kDoneStrikethroughKey = "doneStrikethrough"
private let kAutoSuggestWikilinksKey = "autoSuggestWikilinks"
private let kAppearanceOverrideKey = "appearanceOverride"
private let kNoteListCollapsedKey = "noteListCollapsed"
private let kUseReadabilityKey = "useReadabilityForURLImport"
private let kConvertHTMLToMarkdownKey = "convertHTMLToMarkdown"
private let kRightToLeftTextKey = "rightToLeftText"
private let kAllowedExtensionsKey = "allowedExtensions"

@MainActor
@Observable
public final class AppState {
    /// Platform-agnostic notes view model. iOS uses `NotesViewModel` directly;
    /// `AppState` is the macOS shell that adds AppKit-coupled prefs and
    /// system integrations on top.
    public let notes = NotesViewModel()

    public typealias SortField = NotesViewModel.SortField

    public var editorFont: NSFont
    public private(set) var notesFolderURL: URL? {
        didSet {
            if let url = notesFolderURL {
                notes.attach(folderURL: url, allowedExtensions: Set(allowedExtensions))
            }
        }
    }

    // MARK: - Editor preferences

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

    // MARK: - Fonts & Colors

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

    // MARK: - General preferences

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

    // MARK: - Display mode & layout

    public var noteListDisplayMode: NoteListDisplayMode {
        didSet { UserDefaults.standard.set(noteListDisplayMode.rawValue, forKey: kNoteListDisplayModeKey) }
    }
    public var layoutOrientation: LayoutOrientation {
        didSet { UserDefaults.standard.set(layoutOrientation.rawValue, forKey: kLayoutOrientationKey) }
    }
    public var closeAction: CloseAction {
        didSet { UserDefaults.standard.set(closeAction.rawValue, forKey: kCloseActionKey) }
    }
    public var mirrorFinderTags: Bool {
        didSet { UserDefaults.standard.set(mirrorFinderTags, forKey: kMirrorFinderTagsKey) }
    }
    public var showStatusBarItem: Bool {
        didSet {
            UserDefaults.standard.set(showStatusBarItem, forKey: kShowStatusBarItemKey)
            if showStatusBarItem {
                statusBarController?.show()
            } else {
                statusBarController?.hide()
            }
        }
    }

    var statusBarController: StatusBarController?

    // MARK: - Note list preferences

    /// Sort field. Drives `notes.sortField`; persisted here.
    public var sortField: SortField {
        didSet {
            UserDefaults.standard.set(sortField.rawValue, forKey: kSortFieldKey)
            notes.sortField = sortField
        }
    }
    public var sortAscending: Bool {
        didSet {
            UserDefaults.standard.set(sortAscending, forKey: kSortAscendingKey)
            notes.sortAscending = sortAscending
        }
    }
    public var tableFontSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(tableFontSize), forKey: kTableFontSizeKey) }
    }
    public var showGridLines: Bool {
        didSet { UserDefaults.standard.set(showGridLines, forKey: kShowGridLinesKey) }
    }
    public var alternatingRowColors: Bool {
        didSet { UserDefaults.standard.set(alternatingRowColors, forKey: kAlternatingRowColorsKey) }
    }
    public var showTagsColumn: Bool {
        didSet { UserDefaults.standard.set(showTagsColumn, forKey: kShowTagsColumnKey) }
    }
    public var showModifiedColumn: Bool {
        didSet { UserDefaults.standard.set(showModifiedColumn, forKey: kShowModifiedColumnKey) }
    }
    public var showCreatedColumn: Bool {
        didSet { UserDefaults.standard.set(showCreatedColumn, forKey: kShowCreatedColumnKey) }
    }

    public var doneStrikethroughEnabled: Bool {
        didSet { UserDefaults.standard.set(doneStrikethroughEnabled, forKey: kDoneStrikethroughKey) }
    }

    public var autoSuggestWikilinks: Bool {
        didSet { UserDefaults.standard.set(autoSuggestWikilinks, forKey: kAutoSuggestWikilinksKey) }
    }

    public var useReadabilityForURLImport: Bool {
        didSet { UserDefaults.standard.set(useReadabilityForURLImport, forKey: kUseReadabilityKey) }
    }
    public var convertHTMLToMarkdown: Bool {
        didSet { UserDefaults.standard.set(convertHTMLToMarkdown, forKey: kConvertHTMLToMarkdownKey) }
    }

    public var rightToLeftText: Bool {
        didSet { UserDefaults.standard.set(rightToLeftText, forKey: kRightToLeftTextKey) }
    }

    public var allowedExtensions: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(allowedExtensions) {
                UserDefaults.standard.set(data, forKey: kAllowedExtensionsKey)
            }
        }
    }

    public var noteListCollapsed: Bool {
        didSet { UserDefaults.standard.set(noteListCollapsed, forKey: kNoteListCollapsedKey) }
    }

    public var appearanceOverride: AppearanceOverride {
        didSet {
            UserDefaults.standard.set(appearanceOverride.rawValue, forKey: kAppearanceOverrideKey)
            applyAppearanceOverride(appearanceOverride)
        }
    }

    public enum AppearanceOverride: Int, CaseIterable {
        case system = 0
        case light = 1
        case dark = 2

        public var displayName: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
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

    private var fileMonitor: FileSystemMonitor?
    private var icloudMonitor: ICloudStatusMonitor?

    // MARK: - Forwarding to NotesViewModel
    //
    // These preserve the existing public API of AppState so the macOS UI
    // doesn't change. SwiftUI's Observation tracks reads through the
    // forwarding accessors to the underlying @Observable storage on `notes`.

    public var allNotes: [Note] {
        get { notes.allNotes }
        set { notes.allNotes = newValue }
    }
    public var filteredNotes: [Note] {
        get { notes.filteredNotes }
        set { notes.filteredNotes = newValue }
    }
    public var sortedNotes: [Note] { notes.sortedNotes }
    public var selectedNoteID: Note.ID? {
        get { notes.selectedNoteID }
        set { notes.selectedNoteID = newValue }
    }
    public var searchQuery: String {
        get { notes.searchQuery }
        set { notes.searchQuery = newValue }
    }
    public var tagFilter: String? {
        get { notes.tagFilter }
        set { notes.tagFilter = newValue }
    }
    public var snapbackStack: [Note.ID] {
        get { notes.snapbackStack }
        set { notes.snapbackStack = newValue }
    }
    public var hasSnapback: Bool { notes.hasSnapback }
    public var bookmarkStore: BookmarkStore {
        get { notes.bookmarkStore }
        set { notes.bookmarkStore = newValue }
    }
    public var allKnownTags: [String] { notes.allKnownTags }
    public var syncHealthSummary: String { notes.syncHealthSummary }
    public var showPreview: Bool {
        get { notes.showPreview }
        set { notes.showPreview = newValue }
    }
    public var previewStickyNoteID: Note.ID? {
        get { notes.previewStickyNoteID }
        set { notes.previewStickyNoteID = newValue }
    }
    public var isRenaming: Bool {
        get { notes.isRenaming }
        set { notes.isRenaming = newValue }
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
        self.mirrorFinderTags = ud.object(forKey: kMirrorFinderTagsKey) as? Bool ?? true
        self.showStatusBarItem = ud.bool(forKey: kShowStatusBarItemKey)
        self.sortField = SortField(rawValue: ud.integer(forKey: kSortFieldKey)) ?? .modifiedDate
        self.sortAscending = ud.object(forKey: kSortAscendingKey) as? Bool ?? false
        self.tableFontSize = CGFloat(ud.object(forKey: kTableFontSizeKey) as? Double ?? 13)
        self.showGridLines = ud.bool(forKey: kShowGridLinesKey)
        self.alternatingRowColors = ud.object(forKey: kAlternatingRowColorsKey) as? Bool ?? true
        self.showTagsColumn = ud.object(forKey: kShowTagsColumnKey) as? Bool ?? true
        self.showModifiedColumn = ud.object(forKey: kShowModifiedColumnKey) as? Bool ?? true
        self.showCreatedColumn = ud.bool(forKey: kShowCreatedColumnKey)
        self.doneStrikethroughEnabled = ud.object(forKey: kDoneStrikethroughKey) as? Bool ?? true
        self.autoSuggestWikilinks = ud.object(forKey: kAutoSuggestWikilinksKey) as? Bool ?? true
        self.useReadabilityForURLImport = ud.object(forKey: kUseReadabilityKey) as? Bool ?? true
        self.convertHTMLToMarkdown = ud.object(forKey: kConvertHTMLToMarkdownKey) as? Bool ?? true
        self.rightToLeftText = ud.bool(forKey: kRightToLeftTextKey)
        if let extData = ud.data(forKey: kAllowedExtensionsKey),
           let exts = try? JSONDecoder().decode([String].self, from: extData) {
            self.allowedExtensions = exts
        } else {
            self.allowedExtensions = ["md", "markdown", "mmd", "txt", "text"]
        }
        self.noteListCollapsed = ud.bool(forKey: kNoteListCollapsedKey)
        self.appearanceOverride = AppearanceOverride(rawValue: ud.integer(forKey: kAppearanceOverrideKey)) ?? .system

        // Push initial sort prefs into the VM (didSet wouldn't fire from init).
        notes.sortField = sortField
        notes.sortAscending = sortAscending
        notes.allowedExtensions = allowedExtensions

        // Hooks: macOS-side reactions to VM events.
        notes.onTagsChanged = { [weak self] note in
            guard let self, self.mirrorFinderTags else { return }
            self.writeFinderTags(for: note)
        }
        notes.onURLActivation = {
            NSApp.activate(ignoringOtherApps: true)
        }

        restoreNotesFolder()
        DispatchQueue.main.async { [self] in
            applyAppearanceOverride(appearanceOverride)
        }

        let controller = StatusBarController(appState: self)
        self.statusBarController = controller
        if showStatusBarItem {
            controller.show()
        }
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
            break
        }
    }

    // MARK: - Folder Management

    public func setNotesFolder(_ url: URL) {
        notesFolderURL?.stopAccessingSecurityScopedResource()

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: kNotesFolderBookmarkKey)
        } catch {
            // URL from NSOpenPanel still has temporary access; fall through.
        }

        _ = url.startAccessingSecurityScopedResource()
        notesFolderURL = url
        setupMonitors(url: url)
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
        setupMonitors(url: url)
    }

    private func setupMonitors(url: URL) {
        fileMonitor?.stop()
        fileMonitor = FileSystemMonitor(directory: url) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.notes.reconcileFilesystem()
            }
        }
        fileMonitor?.start()

        icloudMonitor?.stop()
        icloudMonitor = ICloudStatusMonitor(notesDirectory: url, appState: self)
        icloudMonitor?.start()
    }

    // MARK: - Search / CRUD passthroughs

    public func clearSearch() { notes.clearSearch() }
    public func createOrSelectNote() { notes.createOrSelectNote() }
    public func note(for id: UUID) -> Note? { notes.note(for: id) }
    public func updateNoteBody(noteID: UUID, body: String) {
        notes.updateNoteBody(noteID: noteID, body: body)
    }
    public func updateNoteTags(noteID: UUID, tags: [String]) {
        notes.updateNoteTags(noteID: noteID, tags: tags)
    }
    public func deleteNote(noteID: UUID) { notes.deleteNote(noteID: noteID) }
    public func renameNote(noteID: UUID, newTitle: String) {
        notes.renameNote(noteID: noteID, newTitle: newTitle)
    }
    public func navigateToWikilink(title: String) {
        notes.navigateToWikilink(title: title)
    }
    public func snapback() { notes.snapback() }
    public func selectNextNote() { notes.selectNextNote() }
    public func selectPreviousNote() { notes.selectPreviousNote() }
    public func deselectNote() { notes.deselectNote() }
    public func startRename() { notes.startRename() }
    public func commitRename() { notes.commitRename() }
    public func saveBookmark() { notes.saveBookmark() }
    public func restoreBookmark(index: Int) { notes.restoreBookmark(index: index) }
    public func batchAddTag(_ tag: String, to noteIDs: Set<UUID>) {
        notes.batchAddTag(tag, to: noteIDs)
    }
    public func batchRemoveTag(_ tag: String, from noteIDs: Set<UUID>) {
        notes.batchRemoveTag(tag, from: noteIDs)
    }
    public func updateSyncStatus(filename: String, status: SyncStatus) {
        notes.updateSyncStatus(filename: filename, status: status)
    }
    public func createNoteFromIntent(title: String, body: String, tags: [String]) {
        notes.createNoteFromIntent(title: title, body: body, tags: tags)
    }

    // MARK: - macOS-only system integrations

    public func revealInFinder(noteID: UUID) {
        guard let note = note(for: noteID),
              let url = notesFolderURL else { return }
        let fileURL = url.appendingPathComponent(note.filename + ".md")
        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
    }

    public func writeFinderTags(for note: Note) {
        guard let url = notesFolderURL else { return }
        let fileURL = url.appendingPathComponent(note.filename + ".md")
        FinderTagService.writeFinderTags(note.tags, to: fileURL)
    }

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

    public func setEditorFont(_ font: NSFont) {
        editorFont = font
        UserDefaults.standard.set(font.fontName, forKey: kEditorFontNameKey)
        UserDefaults.standard.set(Double(font.pointSize), forKey: kEditorFontSizeKey)
    }

    // MARK: - Import

    public func importFiles(urls: [URL]) {
        Task {
            let service = ImportExportService()
            var imported: [ImportedNote] = []
            for url in urls {
                if let item = try? await service.importFile(at: url) {
                    imported.append(item)
                }
            }
            notes.importNotes(imported)
        }
    }

    public func importDirectory(url: URL) {
        Task {
            let service = ImportExportService()
            let imported = (try? await service.importDirectory(at: url)) ?? []
            notes.importNotes(imported)
        }
    }

    public func importPasteboardItems(_ items: [NSPasteboardItem]) {
        Task {
            let service = ImportExportService()
            let dateStr = ISO8601DateFormatter().string(from: Date())
            var imported: [ImportedNote] = []

            for item in items {
                let note: ImportedNote?
                if let rtfData = item.data(forType: .rtf) {
                    note = await service.importRTFData(rtfData, title: "Imported \(dateStr)")
                } else if let html = item.string(forType: .html) {
                    note = await service.importHTMLString(html, title: "Imported \(dateStr)")
                } else if let text = item.string(forType: .string) {
                    note = await service.importPlainText(text, title: "Imported \(dateStr)")
                } else {
                    note = nil
                }
                if let note { imported.append(note) }
            }
            notes.importNotes(imported)
        }
    }

    public func importNvALTNote(_ imported: ImportedNote) {
        notes.importNote(imported)
    }

    // MARK: - Export

    public func exportNote(noteID: UUID) {
        guard let note = note(for: noteID) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .rtf, .html, UTType(filenameExtension: "doc")!]
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
            case "doc":
                if let data = await service.exportAsWord(note) {
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

    // MARK: - URL Scheme

    public func handleURL(_ url: URL) { notes.handleURL(url) }

    // MARK: - Appearance

    private func applyAppearanceOverride(_ override: AppearanceOverride) {
        guard let app = NSApp else { return }
        switch override {
        case .system:
            app.appearance = nil
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        case .dark:
            app.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Flush on quit

    public func flushBeforeQuit() async {
        await notes.flushBeforeQuit()
    }
}
