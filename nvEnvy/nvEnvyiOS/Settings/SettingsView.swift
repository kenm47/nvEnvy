import SwiftUI
import NvEnvyCore

struct SettingsView: View {
    @Environment(NotesViewModel.self) private var notesVM
    @Environment(IOSPreferences.self) private var prefs
    @Environment(NotesFolderProvider.self) private var folderProvider
    @Environment(\.dismiss) private var dismiss
    @State private var showingFolderPicker = false

    var body: some View {
        @Bindable var prefs = prefs
        NavigationStack {
            Form {
                Section("Notes Folder") {
                    HStack {
                        Text(notesVM.notesFolderURL?.lastPathComponent ?? "Not Set")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Change…") { showingFolderPicker = true }
                    }
                }

                Section("Font") {
                    Picker("Font", selection: $prefs.fontChoice) {
                        ForEach(FontChoice.allCases) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    if prefs.fontChoice != .dynamicType {
                        Stepper("Size: \(Int(prefs.fontSize))pt", value: $prefs.fontSize, in: 9...72)
                    }
                    Text("Sample Text")
                        .font(previewFont)
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $prefs.appearance) {
                        ForEach(AppearanceOverride.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }

                Section("Editing") {
                    Toggle("Soft Tabs", isOn: $prefs.softTabs)
                    if prefs.softTabs {
                        Stepper("Spaces per Tab: \(prefs.spacesPerTab)", value: $prefs.spacesPerTab, in: 1...8)
                    }
                    Toggle("Auto-Pair Brackets & Quotes", isOn: $prefs.autoPair)
                    Toggle("Auto-Indent", isOn: $prefs.autoIndent)
                    Toggle("Auto-Format Lists", isOn: $prefs.autoList)
                    Toggle("Strikethrough @done Lines", isOn: $prefs.doneStrikethrough)
                    Toggle("Check Spelling", isOn: $prefs.checkSpelling)
                    Toggle("Highlight Search Terms", isOn: $prefs.searchHighlight)
                    Toggle("Suggest Wikilinks", isOn: $prefs.autoSuggestWikilinks)
                }

                Section("Notes") {
                    Toggle("Confirm Before Deleting", isOn: $prefs.confirmDeletion)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    Link("Privacy Policy", destination: URL(string: "https://github.com/kenm47/nvEnvy/blob/main/PRIVACY.md")!)
                    Link("Source on GitHub", destination: URL(string: "https://github.com/kenm47/nvEnvy")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingFolderPicker) {
            FolderPicker { url in
                changeFolder(to: url)
                showingFolderPicker = false
            } onCancel: {
                showingFolderPicker = false
            }
            .ignoresSafeArea()
        }
    }

    private var previewFont: Font {
        switch prefs.fontChoice {
        case .dynamicType: return .body
        case .systemMono: return .system(size: prefs.fontSize, design: .monospaced)
        case .atkinson: return .custom("AtkinsonHyperlegible-Regular", size: prefs.fontSize)
        case .openDyslexic: return .custom("OpenDyslexic-Regular", size: prefs.fontSize)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func changeFolder(to url: URL) {
        folderProvider.adoptPickedFolder(url)
        NotificationCenter.default.post(name: .nvEnvyFolderChanged, object: url)
    }
}
