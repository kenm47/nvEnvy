import SwiftUI
import WebKit
import NvEnvyCore

struct PreviewWindow: View {
    @Environment(AppState.self) private var appState
    @State private var showSource = false
    @State private var stickyMode = false
    @State private var renderedHTML: String = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var cachedCustomCSS: String?
    @State private var customCSSLastLoaded: Date?

    private var noteID: Note.ID? {
        stickyMode ? appState.previewStickyNoteID : appState.selectedNoteID
    }

    private var note: Note? {
        guard let id = noteID else { return nil }
        return appState.note(for: id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Toggle("Sticky", isOn: $stickyMode)
                    .toggleStyle(.checkbox)
                    .onChange(of: stickyMode) { _, newValue in
                        if newValue {
                            appState.previewStickyNoteID = appState.selectedNoteID
                        } else {
                            appState.previewStickyNoteID = nil
                        }
                    }

                Spacer()

                Picker("View", selection: $showSource) {
                    Text("Preview").tag(false)
                    Text("Source").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()

                Button("Save HTML...") {
                    saveHTML()
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Button("Print...") {
                    printPreview()
                }

                Button("Open in Marked") {
                    openInMarked()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if showSource {
                ScrollView {
                    Text(renderedHTML)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                PreviewWebView(html: renderedHTML)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onChange(of: note?.body) { _, _ in scheduleRender() }
        .onChange(of: noteID) { _, _ in renderNow() }
        .onAppear { renderNow() }
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvyTogglePreviewSource)) { _ in
            showSource.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nvEnvySavePreviewHTML)) { _ in
            saveHTML()
        }
    }

    private func scheduleRender() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            renderNow()
        }
    }

    private func renderNow() {
        guard let note = note else {
            renderedHTML = "<html><body><p>No note selected</p></body></html>"
            return
        }
        let customCSS = loadCustomCSS()
        renderedHTML = MarkdownRenderer.renderHTML(from: note.body, title: note.title, customCSS: customCSS)
    }

    /// Caches the loaded CSS for up to 5s so re-rendering on the preview's
    /// 300ms typing debounce doesn't do synchronous disk I/O on every
    /// keystroke. Users editing `custom.css` in an external editor still see
    /// the change within a few seconds.
    private func loadCustomCSS() -> String? {
        let now = Date()
        if let lastLoaded = customCSSLastLoaded, now.timeIntervalSince(lastLoaded) < 5 {
            return cachedCustomCSS
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let css = appSupport
            .map { $0.appendingPathComponent("nvEnvy/custom.css") }
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        cachedCustomCSS = css
        customCSSLastLoaded = now
        return css
    }

    private func saveHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = (note?.title ?? "preview") + ".html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? renderedHTML.write(to: url, atomically: true, encoding: .utf8)
    }

    private func printPreview() {
        guard let note = note else { return }
        let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        printView.string = note.body
        printView.font = appState.editorFont
        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        let op = NSPrintOperation(view: printView, printInfo: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }

    private func openInMarked() {
        guard let note = note,
              let folderURL = appState.notesFolderURL else { return }
        let fileURL = folderURL.appendingPathComponent(note.filename + ".md")

        // Try Marked 2 first, then Marked
        let markedBundles = ["com.brettterpstra.marked2", "com.brettterpstra.marked"]
        for bundleID in markedBundles {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.open(
                    [fileURL],
                    withApplicationAt: appURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                return
            }
        }
    }
}

struct PreviewWebView: NSViewRepresentable {
    let html: String

    final class Coordinator {
        var lastLoadedHTML: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.lastLoadedHTML = html
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // The 300ms preview debounce fires on cursor movement and no-op
        // edits too, not just body changes -- skip the reload (DOM teardown,
        // CSS re-parse, scroll reset, visible white flash) when the rendered
        // HTML hasn't actually changed.
        guard html != context.coordinator.lastLoadedHTML else { return }
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.lastLoadedHTML = html
    }
}
