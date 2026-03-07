import AppKit

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    var isVisible: Bool {
        statusItem != nil
    }

    func show() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "nvEnvy")
        }
        item.menu = buildMenu()
        statusItem = item
    }

    func hide() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    func rebuild() {
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let newNote = NSMenuItem(title: "New Note", action: #selector(newNoteAction(_:)), keyEquivalent: "")
        newNote.target = self
        menu.addItem(newNote)

        let search = NSMenuItem(title: "Search...", action: #selector(searchAction(_:)), keyEquivalent: "")
        search.target = self
        menu.addItem(search)

        menu.addItem(.separator())

        // Recent notes (last 5)
        if let appState = appState {
            let recent = appState.allNotes
                .sorted { $0.modifiedDate > $1.modifiedDate }
                .prefix(5)
            for note in recent {
                let item = NSMenuItem(title: note.title, action: #selector(openNoteAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = note.id
                menu.addItem(item)
            }
            if !recent.isEmpty {
                menu.addItem(.separator())
            }
        }

        let open = NSMenuItem(title: "Open nvEnvy", action: #selector(openAppAction(_:)), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let quit = NSMenuItem(title: "Quit", action: #selector(quitAction(_:)), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func newNoteAction(_ sender: Any) {
        NSApp.activate(ignoringOtherApps: true)
        appState?.searchQuery = ""
        // Focus search field by posting notification
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func searchAction(_ sender: Any) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func openNoteAction(_ sender: NSMenuItem) {
        guard let noteID = sender.representedObject as? UUID else { return }
        NSApp.activate(ignoringOtherApps: true)
        appState?.selectedNoteID = noteID
        appState?.searchQuery = ""
    }

    @objc private func openAppAction(_ sender: Any) {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quitAction(_ sender: Any) {
        NSApp.terminate(nil)
    }
}
