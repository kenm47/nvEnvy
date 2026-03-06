import SwiftUI
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
        }

        CommandMenu("Notes") {
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
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        guard let appState = appState else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            await appState.flushBeforeQuit()
            semaphore.signal()
        }
        semaphore.wait(timeout: .now() + 5)
    }
}
