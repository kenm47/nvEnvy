import SwiftUI
import NvEnvyCore
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let activateApp = Self("activateApp")
}

struct PreferencesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            EditingPreferencesView()
                .tabItem { Label(String(localized: "Editing"), systemImage: "pencil") }
            FontsColorsPreferencesView()
                .tabItem { Label(String(localized: "Fonts & Colors"), systemImage: "paintpalette") }
            DatabasePreferencesView()
                .tabItem { Label(String(localized: "Database"), systemImage: "folder") }
        }
        .frame(width: 500, height: 380)
    }
}

// MARK: - General

struct GeneralPreferencesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Search") {
                Toggle("Autocomplete note titles", isOn: $appState.autocompleteEnabled)
            }

            Section("Global Hotkey") {
                KeyboardShortcuts.Recorder("Activate nvEnvy:", name: .activateApp)
            }

            Section("External Editor") {
                HStack {
                    Text(appState.externalEditorPath ?? "None")
                        .foregroundStyle(appState.externalEditorPath == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose...") { pickExternalEditor() }
                }
            }

            Section("Appearance") {
                Picker("Appearance:", selection: $appState.appearanceOverride) {
                    ForEach(AppState.AppearanceOverride.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Toggle("Show dock icon", isOn: $appState.showDockIcon)
                Toggle("Show status bar item", isOn: $appState.showStatusBarItem)

                Picker("Note list style:", selection: $appState.noteListDisplayMode) {
                    ForEach(AppState.NoteListDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("Layout:", selection: $appState.layoutOrientation) {
                    ForEach(AppState.LayoutOrientation.allCases, id: \.self) { o in
                        Text(o.displayName).tag(o)
                    }
                }
            }

            Section("Window") {
                Picker("Close behavior:", selection: $appState.closeAction) {
                    ForEach(AppState.CloseAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func pickExternalEditor() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.externalEditorPath = url.path
    }
}

// MARK: - Editing

struct EditingPreferencesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Tabs") {
                Toggle("Soft tabs (use spaces)", isOn: $appState.softTabs)
                Stepper("Spaces per tab: \(appState.spacesPerTab)", value: $appState.spacesPerTab, in: 1...8)
            }

            Section("Auto-behaviors") {
                Toggle("Check spelling as you type", isOn: $appState.checkSpellingEnabled)
                Toggle("Auto-pair brackets/quotes", isOn: $appState.autoPairEnabled)
                Toggle("Auto-indent new lines", isOn: $appState.autoIndentEnabled)
                Toggle("Auto-format list bullets", isOn: $appState.autoListEnabled)
                Toggle("Make URLs clickable", isOn: $appState.urlDetectionEnabled)
                Toggle("Strikethrough @done lines", isOn: $appState.doneStrikethroughEnabled)
                Toggle("Auto-suggest wikilinks", isOn: $appState.autoSuggestWikilinks)
                Toggle("Right-to-left text direction", isOn: $appState.rightToLeftText)
            }

            Section("Search Highlighting") {
                Toggle("Highlight search terms in editor", isOn: $appState.searchHighlightEnabled)
                if appState.searchHighlightEnabled {
                    ColorPicker("Highlight color:", selection: Binding(
                        get: { Color(nsColor: appState.searchHighlightColor) },
                        set: { appState.searchHighlightColor = NSColor($0) }
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Fonts & Colors

struct FontsColorsPreferencesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Editor Font") {
                HStack {
                    Text(appState.editorFont.displayName ?? "System Font")
                    Text("\(Int(appState.editorFont.pointSize))pt")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Change...") {
                        NSFontManager.shared.orderFrontFontPanel(nil)
                    }
                }
            }

            Section("Colors") {
                ColorPicker("Text color:", selection: Binding(
                    get: { Color(nsColor: appState.editorFGColor) },
                    set: { appState.editorFGColor = NSColor($0) }
                ))
                ColorPicker("Background color:", selection: Binding(
                    get: { Color(nsColor: appState.editorBGColor) },
                    set: { appState.editorBGColor = NSColor($0) }
                ))
            }

            Section("Color Scheme") {
                Picker("Scheme:", selection: $appState.colorScheme) {
                    ForEach(AppState.ColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.displayName).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Note List") {
                HStack {
                    Text("Table font size:")
                    Slider(value: $appState.tableFontSize, in: 9...20, step: 1) {
                        Text("Size")
                    }
                    Text("\(Int(appState.tableFontSize))pt")
                        .frame(width: 40)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show grid lines", isOn: $appState.showGridLines)
                Toggle("Alternating row colors", isOn: $appState.alternatingRowColors)
            }

            Section("Layout") {
                HStack {
                    Text("Max body width:")
                    Slider(value: $appState.maxBodyWidth, in: 0...1200, step: 50) {
                        Text("Width")
                    }
                    Text(appState.maxBodyWidth == 0 ? "Unlimited" : "\(Int(appState.maxBodyWidth))pt")
                        .frame(width: 80)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Database

struct DatabasePreferencesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Notes Folder") {
                HStack {
                    if let url = appState.notesFolderURL {
                        Text(url.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.head)
                    } else {
                        Text("No folder selected")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change...") { pickFolder() }
                }
            }

            Section("Storage") {
                Text("Format: Markdown (.md)")
                    .foregroundStyle(.secondary)
            }

            Section("Finder Tags") {
                Toggle("Mirror tags to Finder", isOn: $appState.mirrorFinderTags)
            }

            Section("URL Import") {
                Toggle("Extract article content (Readability)", isOn: $appState.useReadabilityForURLImport)
                Toggle("Convert HTML to Markdown", isOn: $appState.convertHTMLToMarkdown)
            }

            Section("Behavior") {
                Toggle("Confirm note deletion", isOn: $appState.confirmDeletion)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder for your notes"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.setNotesFolder(url)
    }
}
