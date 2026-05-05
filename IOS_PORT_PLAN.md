# nvEnvy iOS Port — Architectural Plan

## Executive Summary

nvEnvy is well-positioned for an iOS port: the data, search, markdown, and storage logic already lives in a separate `NvEnvyCore` Swift package that is ~99% platform-agnostic. The macOS app layer (`nvEnvy/nvEnvy/`) is the part that needs significant rework — its editor (`NSTextView`-based with all incremental highlighting on `NSTextStorage`), preferences, scripting (`.sdef`), Services menu, Sparkle, status bar, and external editor integration are AppKit-bound. Key design decisions, with answers locked in:

- **Editor:** TextKit 2 + `UITextView` — preserves the incremental `NSTextStorage` highlighting work that already exists.
- **Storage:** file-picker only via `UIDocumentPickerViewController`, parity with the macOS model. No app-owned ubiquity container.
- **Tags:** frontmatter-only on iOS. `FinderTagService` becomes a no-op.
- **iCloud safety:** `NSFileCoordinator` adoption on iOS only; macOS path stays untouched to preserve hard-won read perf.
- **Migration:** macOS app writes a folder-name hint to `NSUbiquitousKeyValueStore`; iOS first-launch reads it and pre-navigates the picker.
- **Packaging:** add iOS targets to the existing XcodeGen `project.yml`. Single project, single SPM resolution.
- **Min target:** iOS 17, for `@Observable` parity with the macOS app.
- **Drops on iOS:** AppleScript / `.sdef`, Sparkle, KeyboardShortcuts (global hotkeys), Services menu, status bar item, external editor, "Open in Marked", Reveal in Finder, Finder tag mirroring, multi-window preview (deferred), `.docx` / `.rtfd` / `.webarchive` import.

Six phases. Phase 1 (core sanitization) and Phase 3 (editor + search) carry the most risk. Roughly 30–40% of macOS UI files are reusable as-is, ~30% need rewriting, ~30% need iOS reimagining.

---

## 1. Feature Triage

Classified against `README.md:9-26` and the shortcut table at `README.md:29-55`.

### 1a. Ports Cleanly

| Feature | Notes |
|---|---|
| Instant search / type-to-create | `NvEnvyCore/Sources/NvEnvyCore/SearchEngine.swift` is pure `String`/`[Note]`. |
| Plain-text Markdown + YAML frontmatter | `FrontmatterParser.swift` and `Note.swift` are pure Foundation+Yams. |
| Wikilinks (parsing + autocomplete) | `WikilinkParser.swift` is pure. Click-to-navigate logic moves to UIKit. |
| Tags (frontmatter only) | `NoteStore` tag flow is platform-agnostic. |
| Markdown preview HTML | `MarkdownRenderer.swift` is pure swift-markdown. CSS already has `prefers-color-scheme: dark` (`MarkdownRenderer.swift:55`). |
| Bookmarks (saved queries) | `BookmarkStore.swift` is pure. ⌘1–9 → `UIKeyCommand`. |
| URL schemes (`nvenvy://find`, `nvenvy://make`) | `URLSchemeHandler.swift` is pure. iOS scene's `onOpenURL` works identically. |
| App Intents / Shortcuts | `nvEnvy/nvEnvy/AppIntents.swift:1-76` is 100% reusable. |
| Crash recovery / WAL | `CrashRecoveryService.swift` uses `zlib` + Foundation only. |
| iCloud sync awareness | `ICloudStatusMonitor.swift` uses `NSMetadataQuery` / `NSFileVersion` — iOS-supported. |
| nvALT migration (read-only, per-file) | `NvALTImporter.swift`'s per-file path works; auto-detect at lines 8-21 is hidden on iOS. |
| Localization | `Localizable.xcstrings` is platform-neutral; bundle into iOS target. |

### 1b. Needs iOS Reimagining

| Feature | macOS source | iOS approach |
|---|---|---|
| **Editor** | `EditorView.swift:66-742` (NSTextView + NSTextStorage) | TextKit 2 in a `UIViewRepresentable<UITextView>`. Incremental wikilink/`@done` highlighter (lines 414-500) ports nearly verbatim — `NSTextStorage` is shared between AppKit and UIKit. Auto-pair, auto-list, soft-tabs, `doCommandBy:` move to `UITextViewDelegate.textView(_:shouldChangeTextIn:replacementText:)`. |
| **Keyboard shortcuts** | `nvEnvyApp.swift:48-273` (SwiftUI `CommandGroup` + `.keyboardShortcut`) | SwiftUI `.keyboardShortcut` works on iOS for hardware keyboards when the view is in the responder chain. App-wide shortcuts (⌘L from anywhere) override `UIResponder.keyCommands` on the editor's UITextView subclass. |
| **Preferences** | `PreferencesView.swift` (357 lines, Settings scene) | In-app settings screen pushed onto the navigation stack. |
| **Note list + split view** | `MainView.swift`, `NoteListView.swift`, `ContentView.swift` | `NavigationSplitView` 2-column (list \| editor). On iPhone, auto-collapses to a `NavigationStack` push. Tag filtering on iPhone surfaces as a toolbar menu/sheet. |
| **Search field with type-to-create** | `SearchField.swift` | SwiftUI `.searchable(text:)` on the note list, with a "Create '\(query)'" row at the top of results when no exact match. |
| **Tag editor** | `TagEditorPanel.swift` (303 lines) | Sheet/popover with `TextField` + token list. Logic ports cleanly. |
| **Preview window** | `PreviewWindow.swift` (`WKWebView` + `NSPrintOperation` + `NSSavePanel`) | Same `WKWebView`; print via `UIPrintInteractionController`; save via `UIActivityViewController` (Share → Save to Files). Drop "Open in Marked." |
| **Conflict resolution UI** | `ConflictResolutionView.swift` | Logic ports; UI re-laid for narrower screen. |
| **Onboarding / folder picker** | (Phase 6.4 in macOS history) | `UIDocumentPickerViewController` (folder mode) + security-scoped bookmark — see §4. |
| **Import/Export** | `ImportExportService.swift` already has `#if canImport(AppKit)` guards (lines 185, 212, 232, 248, 263, 404) | Loosen guards to `#if canImport(AppKit) \|\| canImport(UIKit)` for RTF and HTML — those `NSAttributedString` APIs exist on both platforms. RTFD/DOC/DOCX/webarchive stay AppKit-only and surface as `unsupportedFormat` on iOS — final behavior. |

### 1c. Drop on iOS

| Feature | Reason |
|---|---|
| AppleScript / `nvEnvy.sdef` | No iOS equivalent. Replaced by `AppIntents.swift`. |
| Services menu (`NvEnvyServices.swift`, `Info.plist:33-41`) | No iOS Services. Replace with Share Extension. |
| Sparkle auto-update | App Store / TestFlight. Remove the `Sparkle` SPM dep, the `SUFeedURL` Info.plist key (`project.yml:30`), and the "Check for Updates…" command (`nvEnvyApp.swift:50-53`). |
| KeyboardShortcuts (sindresorhus) | Global system-wide hotkeys — no iOS equivalent. |
| Open in External Editor (ODB) | No analogue. |
| Open in Marked | Mac-only third-party app. |
| Status bar item (`StatusBarController.swift`) | No equivalent. |
| Dock icon toggle / `LSUIElement` | N/A. |
| Multi-window markdown preview | Deferred. |
| Finder tag mirroring | Pointless on iOS — neither Files nor iCloud Drive surface tags meaningfully cross-platform. Frontmatter is the sole tag source. `FinderTagService.swift` becomes a no-op stub on iOS. |
| Reveal in Finder | The file is already visible in the Files app. Drop the menu item. |
| `.docx` / `.rtfd` / `.webarchive` import | No clean Foundation API. Final behavior, not a TODO. |

---

## 2. Core Extraction (`NvEnvyCore`)

### 2a. Already shared-ready

`Note.swift`, `FrontmatterParser.swift`, `WikilinkParser.swift`, `DoneLineDetector.swift`, `MarkdownRenderer.swift`, `SearchEngine.swift`, `BookmarkStore.swift`, `URLSchemeHandler.swift`, `NvALTImporter.swift`, `CrashRecoveryService.swift`, `NoteStore.swift`, `FileStorageService.swift`. Only `Package.swift` needs `platforms:` updated (see §6).

### 2b. Has guarded AppKit code; needs minor fix

`ImportExportService.swift` is the only file with `import AppKit` (verified via grep). All AppKit code is inside `#if canImport(AppKit)`. Action: loosen guards to `#if canImport(AppKit) || canImport(UIKit)` for RTF and HTML import/export only. Other formats stay AppKit-only.

### 2c. Accidentally platform-coupled, must be lifted

Currently in app layer, should move to Core:

- **Color scheme + appearance logic** in `AppState.swift:123-125,240-258,403-407` references `NSColor` directly. Lift to a Core-level `EditorTheme` value type using RGBA tokens. `NSColor`/`UIColor` adapters live in the app layer.
- **Editor font** (`AppState.swift:78,389-392`) uses `NSFont`. Lift to `EditorFontDescriptor { name: String, size: CGFloat, useDynamicType: Bool }` in Core; resolve to `NSFont`/`UIFont` per platform. The `useDynamicType` case binds to `UIFont.preferredFont(forTextStyle: .body)` on iOS.
- **Color persistence** — `AppState.loadColor`/`saveColor` use `NSKeyedArchiver` of `NSColor`. Replace with explicit RGBA serialization in Core.
- **`AppState`** itself (1096 lines) — split per the optimization plan's item #14 into:
  - `NotesViewModel` (Core or shared package, `@Observable`): notes, filtered, sorted, selection, search, snapback, bookmarks, sync health.
  - `EditorPreferences` (Core, theme-token based).
  - `AppShellState` (per-platform): activation policy, status bar, dock icon, NSWindow behaviors.

### 2d. New platform-abstraction seams

| Seam | Why | macOS impl | iOS impl |
|---|---|---|---|
| `NotesFolderProvider` | Resolve & open a notes directory | `bookmarkData(.withSecurityScope)` (`AppState.swift:493-524`) | `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])` + `bookmarkData(.minimalBookmark)` |
| `FileAccessCoordinator` | Wrap reads/writes for iCloud safety | passthrough (no-op) | `NSFileCoordinator` adapter |
| `PasteboardBridge` | "Paste as Markdown link", "Copy note link" | `NSPasteboard` | `UIPasteboard.general` |
| `Sharing` | "Share note", "Save HTML" | `NSSavePanel` / `NSSharingService` | `UIActivityViewController` |
| `Printing` | Print note | `NSPrintOperation` (`PreviewWindow.swift:122-134`) | `UIPrintInteractionController` |
| `ExternalAppLauncher` | "Open in Marked", "Reveal in Finder" | `NSWorkspace` | no-op |
| `TagMirror` | Finder Tags ↔ frontmatter | `FinderTagService.swift` | no-op |
| `EditorTextView` | Hosts NSTextView/UITextView with incremental highlighting | NSViewRepresentable | UIViewRepresentable |

These live in thin platform packages (`NvEnvyAppKit` / `NvEnvyUIKit`), with shared protocols defined in Core.

---

## 3. iOS-Specific Surface Area

### 3a. Editor — TextKit 2 + UITextView

The existing macOS editor in `EditorView.swift:127-500` is built around mutating `NSTextStorage` attributes for wikilinks (`.link`), `@done` strikethrough, and search highlights. `NSTextStorage` is shared between AppKit and UIKit, so the highlighter functions (`highlightWikilinksIncremental`, `applyDoneStrikethroughIncremental`) port nearly verbatim.

- **SwiftUI `TextEditor`**: rejected — no API to access the underlying storage / apply attributes incrementally. The performance work in commits `b39b512` and `9a29d9a` would all be lost.
- **TextKit 1 `UITextView`**: works, but Apple's direction is TextKit 2.
- **TextKit 2**: enable via `UITextView.textLayoutManager`. Existing attribute-mutation code applies. Auto-pair / auto-list / soft-tab logic moves into `UITextViewDelegate.textView(_:shouldChangeTextIn:replacementText:)`. `doCommandBy:` semantics → `UIKeyCommand` overrides on the text view.

### 3b. Navigation

- **iPad:** 2-column `NavigationSplitView` (list \| editor).
- **iPhone:** same `NavigationSplitView` auto-collapses to a `NavigationStack`. Tap a note → editor pushes; back button returns to list.
- **Search:** `.searchable` on the note list, with a "Create '\(query)'" row at the top when no exact match exists.
- **Tag filtering on iPhone:** toolbar menu/sheet, not a column.

### 3c. Hardware keyboard support

- App-wide commands: `Menu` with `.keyboardShortcut` modifiers in the SwiftUI scene — surface in iPad's discoverability HUD. ⌘L (focus search), ⌘J/K (next/prev), ⌘B/I/Y (formatting), ⌘0-9 (bookmarks), ⌘E (export), ⌘P (print). Drop ⌘⇧R (reveal), ⌘⌃P (preview window — replace with toggle), ⌘⌃M (Marked).
- For commands that fire while editor has focus, override `UIResponder.keyCommands` on the editor's `UITextView` subclass.

### 3d. Share Extension + Action Extension

- **Share Extension** (`NSExtensionPointIdentifier=com.apple.share-services`): accepts `public.text`, `public.url`, `public.html`. Writes a new note into the app group container; the host app picks it up on next launch (or via Darwin notification if running).
- **Action Extension**: optional, for in-place text transforms. Defer.
- Replaces the macOS Services entry at `project.yml:33-41`.

### 3e. App Intents / Shortcuts

`AppIntents.swift:6-68` is reusable as-is. The `AppIntentsBridge` singleton (`AppIntents.swift:73-76`) works identically. Add:
- `OpenNoteIntent(noteID:)` for Spotlight / widget tap targets.
- `CaptureQuickNoteIntent` for Lock Screen / Action Button.

### 3f. Widgets

- Quick-capture widget (deep-links into a "compose" sheet).
- Recent notes widget (3-5 most recent).
- Saved-search widget (counts matching a bookmark).

WidgetKit target shares `NvEnvyCore` and reads via the App Group's bookmark-resolved folder.

### 3g. URL scheme

Register `nvenvy` and `nv` in iOS Info.plist `CFBundleURLTypes` (same shape as `project.yml:42-46`). Handle in `Scene.onOpenURL` as macOS already does (`nvEnvyApp.swift:19-21`).

### 3h. Files app integration

The user picks a folder via `UIDocumentPickerViewController`. The folder lives wherever they keep it — iCloud Drive, on-device, third-party providers (Dropbox, etc.) all expose through the same picker. No app-owned ubiquity container.

---

## 4. Sync & Storage

The macOS app lets the user pick any folder via `NSOpenPanel` and saves a security-scoped bookmark to UserDefaults (`AppState.swift:493-524`). The iOS port uses the same model:

- **Folder pick:** `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])` returns a security-scoped URL. Store via `URL.bookmarkData(options: .minimalBookmark)`. Wrap reads/writes in `startAccessingSecurityScopedResource()` / `stop…`.
- **`NSFileCoordinator` adoption — iOS only.** A `FileAccessCoordinator` protocol is added to `FileStorageService.swift`. macOS uses a passthrough impl (no-op, zero behavior change, preserves the read perf wins from `b39b512`). iOS uses an `NSFileCoordinatorAdapter` that wraps reads in `coordinate(readingItemAt:options:.withoutChanges, ...)` and writes in `coordinate(writingItemAt:options:.forReplacing, ...)`. Selected via `#if os(iOS)` at construction.
- **Conflict resolution:** `NSFileVersion.unresolvedConflictVersionsOfItem(at:)` works on iOS (`ICloudStatusMonitor.swift:66-69`). Existing `ConflictResolutionView.swift` UI ports.
- **Tag mirroring — drop.** `FinderTagService.swift` is no-op on iOS. Tags stay in YAML frontmatter only. `mirrorFinderTags` preference is hidden on iOS.
- **`FSEventStream`** in `FileSystemMonitor.swift` does not exist on iOS. Wrap that file in `#if os(macOS)` and add a sibling `iOSFolderMonitor` using `NSMetadataQuery` (already used by `ICloudStatusMonitor`).

### Migration: existing macOS folder detection

iOS cannot read iCloud Drive without going through the picker, so detection is done via a handoff hint in `NSUbiquitousKeyValueStore`:

- **macOS side:** when the user picks their notes folder, write the folder's display name and path string to `NSUbiquitousKeyValueStore` under `lastPickedNotesFolderPath`. ~10 lines added near `AppState.swift:493-498`.
- **iOS side:** first-launch onboarding reads the same key. If present: *"Looks like you're using a notes folder named 'Notes' on your Mac. Tap below to open it."* The "Open Folder" button launches `UIDocumentPickerViewController` with `directoryURL:` set as close to the folder as possible. The user still tap-confirms (Apple's security model). If the key is absent (new user, or macOS app hasn't been run since iOS shipped), show the generic *"Choose where to keep your notes"* screen.

`NSUbiquitousKeyValueStore` requires the iCloud KV-store entitlement on both targets but no ubiquity container — it's a separate 1MB key/value bucket.

**Tracked risk:** `NSUbiquitousKeyValueStore` propagation is "typically a few seconds, occasionally minutes." Race-condition users (pick on Mac, open iOS immediately) just fall through to the generic flow. Document, don't engineer around.

---

## 5. Things With No iOS Equivalent

| macOS feature | iOS replacement |
|---|---|
| Sparkle auto-update | App Store / TestFlight. Remove dep. |
| AppleScript + `.sdef` | App Intents. Drop `nvEnvy.sdef`, `OSAScriptingDefinition` Info.plist key. |
| Services menu | Share Extension. |
| Multi-window preview | Sheet on iPhone; deferred on iPad. |
| Print | `UIPrintInteractionController` from preview. |
| Font bundling (`ATSApplicationFontsPath`) | `UIAppFonts` Info.plist key, same `Fonts/` folder. |
| Status bar item | Drop. |
| Global hotkey | Drop. |
| External editor (ODB) | Drop. |
| Reveal in Finder | Drop. |

---

## 6. Project Structure

Extend `nvEnvy/project.yml` to a multi-platform XcodeGen spec — single project, additional iOS targets.

```
nvEnvy/
  project.yml                       (extended: iOS deployment target, new targets)
  nvEnvy/                           (existing macOS sources)
  nvEnvyiOS/                        (new — iOS app)
    nvEnvyiOSApp.swift
    Info.plist
    Entitlements.plist              (icloud-services KVS, app groups)
    UI/                             (NavigationSplitView, search, list, editor wrapper)
    Editor/                         (UITextView-based editor)
    Onboarding/                     (FirstLaunchView with KVS handoff)
    Preferences/
    Extensions/
      ShareExtension/               (separate target)
      Widget/                       (separate target)
  nvEnvyShared/                     (new — cross-platform SwiftUI components)
    NotesViewModel.swift
    EditorTheme.swift
NvEnvyCore/
  Package.swift                     (.platforms: macOS(.v14), iOS(.v17))
  Sources/NvEnvyCore/...
```

Specific changes:
- `project.yml` — add `iOS: "17.0"` to `deploymentTarget`. Add `nvEnvyiOS`, `nvEnvyShareExt`, `nvEnvyWidget` targets, each with its own `platform:` and `info` block.
- `NvEnvyCore/Package.swift:6` — change `platforms: [.macOS(.v14)]` to `[.macOS(.v14), .iOS(.v17)]`.

---

## 7. Dependency Audit

| Dep | Source | iOS | Action |
|---|---|---|---|
| Yams | `NvEnvyCore/Package.swift:11` | ✅ | keep |
| swift-markdown | `NvEnvyCore/Package.swift:12` | ✅ | keep |
| KeyboardShortcuts | `nvEnvy/project.yml:13` | ❌ macOS only | drop on iOS target |
| Sparkle | `nvEnvy/project.yml:15` | ❌ macOS only | drop on iOS target |

No new third-party deps required.

---

## 8. Localization, Accessibility, Dynamic Type, Dark Mode

- **Localization:** `Localizable.xcstrings` is platform-agnostic; include in iOS target. Existing locales (en/de/fr/it/pt-BR/zh) carry over. Add Share Extension display name strings.
- **Accessibility:** existing macOS code already has `.accessibilityLabel` / `.accessibilityAddTraits` (e.g. `EditorView.swift:43-44`). On iOS, add VoiceOver labels for note list rows, the create-from-search row, and the editor.
- **Dynamic Type — default-on.** The default editor font binds to `UIFont.preferredFont(forTextStyle: .body)` with `adjustsFontForContentSizeCategory = true` on the `UITextView`. The `editorFont` preference is a *secondary* override. `EditorFontDescriptor` (§2c) carries a `useDynamicType` case alongside named-font-with-size.
- **Dark Mode:** `MarkdownRenderer.defaultCSS` already has `prefers-color-scheme: dark` (`MarkdownRenderer.swift:55-61`). Default editor foreground/background to `.label` / `.systemBackground` so they auto-adapt. The `appearanceOverride` enum (`AppState.swift:247-258`) ports via `UIWindow.overrideUserInterfaceStyle`.

---

## 9. Risks & Unknowns

| Risk | Mitigation |
|---|---|
| **Editor scroll/jitter regressions** under TextKit 2. The current `fix/editor-scroll-jitter` work shows scroll stability is fragile. `UITextView`'s contentOffset preservation differs from `NSScrollView`'s. | Spike a TextKit 2 prototype with a 50KB note and the existing incremental highlighter. Benchmark scroll behavior on a real device before committing to Phase 3. |
| **`NSUbiquitousKeyValueStore` propagation latency.** Pick on Mac, open iOS immediately → hint not yet propagated. | Onboarding falls through to generic flow. Document, don't engineer around. |
| **iOS RTF/HTML import via `NSAttributedString`.** `#if canImport(AppKit)` guards in `ImportExportService.swift` are conservative; some calls actually work on iOS. | Quick test: try `NSAttributedString(url:options:[.documentType:.rtf]...)` on iOS in a unit test before loosening guards. |
| **Sandboxed extensions sharing storage.** Share Extension and Widget need a shared App Group; current macOS sandbox entitlements (`project.yml:107-111`) don't include groups. | Add `com.apple.security.application-groups` entitlement; refactor `FileStorageService` initialization to accept an app-group-resolved URL. |
| **Crash recovery WAL location.** `CrashRecoveryService.swift:19` uses `FileManager.default.urls(for: .cachesDirectory)` — per-process on iOS. | Add an init parameter for the app-group cache URL on iOS. |
| **Apple Developer signing.** Solo dev, no team yet. | Standard personal team sign-up; ensure entitlements (App Groups, iCloud KVS) are provisioned. |

---

## 10. Phased Delivery Plan

### Phase 1 — Core sanitization & abstraction seams

**Touches:**
- `NvEnvyCore/Package.swift:6` — add iOS platform.
- `NvEnvyCore/Sources/NvEnvyCore/ImportExportService.swift` — loosen `#if canImport(AppKit)` to `|| canImport(UIKit)` for RTF/HTML.
- `NvEnvyCore/Sources/NvEnvyCore/FileSystemMonitor.swift` — `#if os(macOS)` wrap.
- `NvEnvyCore/Sources/NvEnvyCore/FinderTagService.swift` — `#if os(macOS)` wrap.
- `NvEnvyCore/Sources/NvEnvyCore/FileStorageService.swift` — add `FileAccessCoordinator` protocol; macOS = passthrough impl. No behavior change on macOS.
- New: `NvEnvyCore/Sources/NvEnvyCore/EditorTheme.swift` — `EditorFontDescriptor`, `RGBAColor`.
- New: `NvEnvyCore/Sources/NvEnvyCore/NotesViewModel.swift` — extracted from app-side `AppState`, `@Observable`.
- `nvEnvy/nvEnvy/AppState.swift` — refactored to wrap `NotesViewModel` + macOS-specific shell state. Public API preserved.

**Exit criteria:** `swift build` succeeds on macOS and iOS triples. macOS app still builds, all 168 existing `NvEnvyCoreTests` pass. macOS scroll/jitter behavior unchanged.

### Phase 2 — Minimum-viable iOS reader + onboarding

**Touches:**
- `nvEnvy/project.yml` — add `nvEnvyiOS` target, iOS deployment target.
- New: `nvEnvy/nvEnvyiOS/nvEnvyiOSApp.swift` — Scene with `WindowGroup`, `onOpenURL`.
- New: `nvEnvy/nvEnvyiOS/UI/RootSplitView.swift` — `NavigationSplitView` skeleton.
- New: `nvEnvy/nvEnvyiOS/UI/NoteListView.swift` — list bound to `NotesViewModel.sortedNotes`.
- New: `nvEnvy/nvEnvyiOS/UI/NoteReaderView.swift` — read-only `Text(note.body)` + `MarkdownRenderer` HTML in `WKWebView`.
- New: `nvEnvy/nvEnvyiOS/Storage/NotesFolderProvider.swift` — `UIDocumentPickerViewController` + bookmark.
- New: `nvEnvy/nvEnvyiOS/Onboarding/FirstLaunchView.swift` — checks `NSUbiquitousKeyValueStore` for `lastPickedNotesFolderPath`; branches between "we found your Mac folder" and generic copy.
- New on macOS: ~10 lines in `AppState.swift` near line 498 to write the path to `NSUbiquitousKeyValueStore` after a successful folder pick.
- Both targets gain `com.apple.developer.icloud-services` entitlement with `KeyValueStore`.
- New: `nvEnvyiOS/Entitlements.plist`.

**Exit criteria:** app launches on iOS simulator, onboarding handoff works (or falls through cleanly), picks/uses a notes folder, lists notes, displays a selected note (read-only). URL scheme `nvenvy://find/foo` opens the app and runs a search.

### Phase 3 — Editor + search

**Touches:**
- New: `nvEnvy/nvEnvyiOS/Editor/NoteUITextEditor.swift` — `UIViewRepresentable<UITextView>` with TextKit 2.
- New: `nvEnvy/nvEnvyiOS/Editor/EditorCoordinator.swift` — port of `EditorView.Coordinator` (lines 187-742): `textViewDidChange`, `shouldChangeTextIn` (auto-pair, auto-list, soft-tabs), incremental wikilink/done highlighter (lines 414-500 lift cleanly).
- New: `nvEnvy/nvEnvyiOS/Editor/EditorKeyCommands.swift` — `UIKeyCommand` overrides for ⌘B/I/Y, ⌘[ ⌘], ⌘L, ⌘J/K, ⌘D.
- New: `nvEnvy/nvEnvyiOS/UI/SearchableNoteList.swift` — `.searchable(text:)`, type-to-create row, debounced query (300ms — match macOS `searchDebounceTask` at `AppState.swift:53-64`).

**Exit criteria:** full read/write/create/delete on iPhone and iPad. Wikilinks tappable. `@done` strikethrough applied. Search filters as you type. Hardware keyboard shortcuts work.

### Phase 4 — Sync hardening (iOS)

**Touches:**
- New: iOS impl of `FileAccessCoordinator` using `NSFileCoordinator`. Wired in `FileStorageService` via `#if os(iOS)`.
- New: `nvEnvy/nvEnvyiOS/Storage/iOSFolderMonitor.swift` — `NSMetadataQuery` + `NSFilePresenter`.
- Port `nvEnvy/nvEnvy/ICloudStatusMonitor.swift` to shared.
- Port `nvEnvy/nvEnvy/ConflictResolutionView.swift` UI to iOS sheet.
- New: `nvEnvy/nvEnvyiOS/Storage/AppGroupContainer.swift` — for sharing storage with extensions/widgets.
- `CrashRecoveryService.swift` init gains app-group cache URL parameter on iOS.

**Exit criteria:** iCloud changes from macOS reach iOS within seconds (and vice versa). Conflict UI works. WAL crash recovery validated. macOS perf unchanged.

### Phase 5 — Extensions + intents

**Touches:**
- New target: `nvEnvyShareExt/` — Share Extension, writes new note via shared storage service.
- New target: `nvEnvyWidget/` — Recent notes + Quick Capture widget.
- Port `nvEnvy/nvEnvy/AppIntents.swift` to be cross-platform (already is — just include in iOS target).
- Add `OpenNoteIntent`, `CaptureQuickNoteIntent`.
- `nvEnvyiOS/Info.plist` — `CFBundleURLTypes`, `UIAppFonts`, app-group entitlement.

**Exit criteria:** long-press Share on a webpage → "Save to nvEnvy" works. Widget shows recent notes. Siri/Shortcuts can search and create notes.

### Phase 6 — Polish

- Preferences screen (full port of `PreferencesView.swift`).
- Localization audit.
- Dynamic Type validation across screens.
- Print via `UIPrintInteractionController`.
- Dark Mode default theme.
- Accessibility audit (VoiceOver labels for all rows and editor).
- TestFlight beta + App Store screenshots.

**Exit criteria:** feature parity (minus §1c drops) confirmed against the README feature list, beta cohort feedback addressed, App Store submission ready.

---

## Test Coverage

- Port `NvEnvyCoreTests` cross-platform — all 168 existing tests run on both macOS and iOS triples.
- iOS-only tests for the storage seam:
  - Bookmark resolution after relaunch.
  - `FileAccessCoordinator` adapter under simulated concurrent access (using a test mock coordinator).
  - `NSUbiquitousKeyValueStore` handoff (write on macOS-style path, read on iOS-style path within a single test).
- Skip UI snapshot tests for v1.

---

## Locked Decisions Index

1. iOS deployment target = 17.0.
2. Storage = file picker only, parity with macOS. No ubiquity container.
3. Tags = frontmatter only on iOS.
4. `NSFileCoordinator` = iOS only. macOS unchanged to preserve read perf.
5. Migration = `NSUbiquitousKeyValueStore` handoff hint + "where do I put my notes" first-launch screen.
6. Editor = TextKit 2 + `UITextView`.
7. Search = `.searchable` + "Create '<query>'" row.
8. Navigation = 2-column `NavigationSplitView`, auto-collapses to `NavigationStack` on iPhone.
9. Dynamic Type = default-on, with secondary font override.
10. Multi-window preview = deferred.
11. `.docx` / `.rtfd` / `.webarchive` import = dropped on iOS (final).
12. Share Extension + Widget = in v1.
13. Single XcodeGen project, new iOS targets added to `project.yml`.
14. AppleScript, Sparkle, KeyboardShortcuts, Services, status bar, external editor, "Open in Marked", Reveal in Finder = dropped on iOS only; macOS retains.
