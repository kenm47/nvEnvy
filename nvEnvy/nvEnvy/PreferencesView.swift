import SwiftUI
import CoreText
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
    @State private var selectedFont: String = "system-mono"
    @State private var fontSize: CGFloat = 14

    private static let fontOptions: [(id: String, displayName: String, postScriptName: String?)] = [
        ("system-mono", "System Mono", nil),
        ("atkinson", "Atkinson Hyperlegible", "AtkinsonHyperlegible-Regular"),
        ("opendyslexic", "OpenDyslexic", "OpenDyslexic-Regular"),
        ("custom", "Other...", nil),
    ]

    private static func fontID(for nsFont: NSFont) -> String {
        let name = nsFont.fontName
        if name.contains("SFMono") || name.contains("Menlo") {
            return "system-mono"
        }
        for opt in fontOptions where opt.postScriptName != nil {
            if name == opt.postScriptName { return opt.id }
        }
        return "custom"
    }

    private func applyFont(id: String, size: CGFloat) {
        switch id {
        case "system-mono":
            appState.setEditorFont(NSFont.monospacedSystemFont(ofSize: size, weight: .regular))
        case "custom":
            NSFontManager.shared.orderFrontFontPanel(nil)
            return
        default:
            if let opt = Self.fontOptions.first(where: { $0.id == id }),
               let psName = opt.postScriptName {
                if let font = NSFont(name: psName, size: size) {
                    appState.setEditorFont(font)
                } else {
                    // Font not registered by ATSApplicationFontsPath — register manually
                    Self.registerBundledFont(postScriptName: psName)
                    if let font = NSFont(name: psName, size: size) {
                        appState.setEditorFont(font)
                    }
                }
            }
        }
    }

    private static func registerBundledFont(postScriptName: String) {
        for ext in ["ttf", "otf"] {
            if let url = Bundle.main.url(forResource: postScriptName, withExtension: ext, subdirectory: "Fonts")
                ?? Bundle.main.url(forResource: postScriptName, withExtension: ext) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                return
            }
        }
    }

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Editor Font") {
                Picker("Font:", selection: $selectedFont) {
                    ForEach(Self.fontOptions, id: \.id) { opt in
                        Text(opt.displayName).tag(opt.id)
                    }
                }
                .onChange(of: selectedFont) { _, newID in
                    applyFont(id: newID, size: fontSize)
                }

                HStack {
                    Text("\(Int(fontSize))pt")
                        .foregroundStyle(.secondary)
                    Stepper("", value: $fontSize, in: 9...72, step: 1)
                        .onChange(of: fontSize) { _, newSize in
                            applyFont(id: selectedFont, size: newSize)
                        }
                    Spacer()
                    Button("System Font Panel...") {
                        NSFontManager.shared.orderFrontFontPanel(nil)
                    }
                    .controlSize(.small)
                }

                Text("Atkinson Hyperlegible — optimized for low-vision readers\nOpenDyslexic — weighted letterforms for dyslexic readers")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .onAppear {
                selectedFont = Self.fontID(for: appState.editorFont)
                fontSize = appState.editorFont.pointSize
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
    @State private var newExtension = ""

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

            Section("Allowed File Types") {
                ForEach(Array(appState.allowedExtensions.enumerated()), id: \.offset) { index, ext in
                    HStack {
                        Text(".\(ext)")
                        Spacer()
                        if appState.allowedExtensions.count > 1 {
                            Button(role: .destructive) {
                                appState.allowedExtensions.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    TextField("Extension", text: $newExtension)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Button {
                        let ext = newExtension.trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                            .replacingOccurrences(of: ".", with: "")
                        guard !ext.isEmpty, !appState.allowedExtensions.contains(ext) else { return }
                        appState.allowedExtensions.append(ext)
                        newExtension = ""
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .disabled(newExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
