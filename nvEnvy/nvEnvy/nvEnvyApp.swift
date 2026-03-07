import SwiftUI
import UniformTypeIdentifiers
import NvEnvyCore
import KeyboardShortcuts

@main
struct nvEnvyApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onAppear {
                    delegate.appState = appState
                }
                .onOpenURL { url in
                    appState.handleURL(url)
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)
        .commands {
            nvEnvyCommands(appState: appState)
        }

        Window("Markdown Preview", id: "preview") {
            PreviewWindow()
                .environment(appState)
        }
        .defaultSize(width: 600, height: 500)

        Settings {
            PreferencesView()
                .environment(appState)
        }
    }
}

// MARK: - Menu Commands

struct nvEnvyCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Import Files...") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = true
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowedContentTypes = [.plainText, .rtf, .html, .text,
                    .init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!,
                    .init(filenameExtension: "mmd")!]
                guard panel.runModal() == .OK else { return }
                appState.importFiles(urls: panel.urls)
            }

            Button("Import Folder...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let url = panel.url else { return }
                appState.importDirectory(url: url)
            }

            Divider()

            Button("Export...") {
                if let id = appState.selectedNoteID {
                    appState.exportNote(noteID: id)
                }
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(appState.selectedNoteID == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print...") {
                if let id = appState.selectedNoteID {
                    appState.printNote(noteID: id)
                }
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(appState.selectedNoteID == nil)
        }

        CommandGroup(after: .pasteboard) {
            Button("Paste as Markdown Link") {
                NotificationCenter.default.post(name: .nvEnvyPasteAsMarkdownLink, object: nil)
            }
            .keyboardShortcut("v", modifiers: [.command, .option])

            Button("Copy Note Link") {
                if let id = appState.selectedNoteID {
                    appState.copyNoteLink(noteID: id)
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(appState.selectedNoteID == nil)
        }

        CommandGroup(after: .textFormatting) {
            Button("Bold") {
                postFormattingCommand(.bold)
            }
            .keyboardShortcut("b", modifiers: .command)

            Button("Italic") {
                postFormattingCommand(.italic)
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("Strikethrough") {
                postFormattingCommand(.strikethrough)
            }
            .keyboardShortcut("y", modifiers: .command)

            Divider()

            Button("Increase Indent") {
                postFormattingCommand(.indent)
            }
            .keyboardShortcut("]", modifiers: .command)

            Button("Decrease Indent") {
                postFormattingCommand(.outdent)
            }
            .keyboardShortcut("[", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Word Count") {
                appState.showWordCount.toggle()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Button("Toggle Layout") {
                appState.layoutOrientation = appState.layoutOrientation == .horizontal ? .vertical : .horizontal
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            Picker("Note List Style", selection: Binding(
                get: { appState.noteListDisplayMode },
                set: { appState.noteListDisplayMode = $0 }
            )) {
                ForEach(AppState.NoteListDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        }

        CommandMenu("Notes") {
            Button("Open in External Editor") {
                if let id = appState.selectedNoteID {
                    appState.openInExternalEditor(noteID: id)
                }
            }
            .disabled(appState.selectedNoteID == nil)

            Divider()

            Button("Tag Note...") {
                NotificationCenter.default.post(name: .nvEnvyShowTagEditor, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button("Reveal in Finder") {
                if let id = appState.selectedNoteID {
                    appState.revealInFinder(noteID: id)
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Delete Note") {
                if let id = appState.selectedNoteID {
                    if appState.confirmDeletion {
                        NotificationCenter.default.post(name: .nvEnvyConfirmDeleteNote, object: id)
                    } else {
                        appState.deleteNote(noteID: id)
                    }
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)

            Divider()

            Button("Next Note") {
                appState.selectNextNote()
            }
            .keyboardShortcut("j", modifiers: .command)

            Button("Previous Note") {
                appState.selectPreviousNote()
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Deselect") {
                appState.deselectNote()
            }
            .keyboardShortcut("d", modifiers: .command)
        }

        CommandMenu("Bookmarks") {
            Button("Save Bookmark") {
                appState.saveBookmark()
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Show Bookmarks") {
                NotificationCenter.default.post(name: .nvEnvyShowBookmarks, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            ForEach(Array(appState.bookmarkStore.bookmarks.prefix(9).enumerated()), id: \.element.id) { index, bookmark in
                Button(bookmark.name) {
                    appState.restoreBookmark(index: index)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }

    private func postFormattingCommand(_ command: FormattingCommand) {
        NotificationCenter.default.post(name: .nvEnvyFormatting, object: command)
    }
}

enum FormattingCommand {
    case bold, italic, strikethrough, indent, outdent
}

extension Notification.Name {
    static let nvEnvyFormatting = Notification.Name("nvEnvyFormatting")
    static let nvEnvyShowTagEditor = Notification.Name("nvEnvyShowTagEditor")
    static let nvEnvyPasteAsMarkdownLink = Notification.Name("nvEnvyPasteAsMarkdownLink")
    static let nvEnvyNoExternalEditor = Notification.Name("nvEnvyNoExternalEditor")
    static let nvEnvyShowBookmarks = Notification.Name("nvEnvyShowBookmarks")
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    private let servicesProvider = NvEnvyServices()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let appState = appState {
            AppIntentsBridge.shared.appState = appState
            servicesProvider.appState = appState
        }
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        appState?.closeAction == .quit
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let appState = appState else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            await appState.flushBeforeQuit()
            semaphore.signal()
        }
        semaphore.wait(timeout: .now() + 5)
    }

    // MARK: - AppleScript Support

    func application(_ sender: NSApplication, delegateHandlesKey key: String) -> Bool {
        key == "scriptingSearch" || key == "scriptingCreateNote"
    }

    @objc var scriptingSearch: String {
        get {
            DispatchQueue.main.sync { appState?.searchQuery ?? "" }
        }
        set {
            DispatchQueue.main.async { [weak self] in
                self?.appState?.searchQuery = newValue
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
