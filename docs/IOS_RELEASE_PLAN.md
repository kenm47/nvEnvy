# nvEnvy iOS 1.0 — Primetime Release Plan

> **Status: implemented.** All workstreams below (W0–W7) have been applied to the codebase. This document is kept as a record of the design rationale; treat code comments and `git log` as the source of truth for current behavior. Manual QA items in Workstream 7's end-to-end script still need a pass on a physical device before App Store submission.

## Context

The iOS port (Phases 1–3 of `docs/IOS_PORT_PLAN.md`) shipped a working skeleton: folder onboarding with iCloud-KVS handoff, note list with search, TextKit 2 editor with wikilink/`@done`/search highlighting, auto-pair/auto-list/soft-tabs, and hardware-keyboard formatting. The shared `NvEnvyCore` package is fully iOS-ready (parallel load, off-main-actor search, reconcile engine, `FileAccessCoordinator` seam, `EditorFontDescriptor`/`RGBAColor` abstractions).

What's left is everything that separates a demo from a shippable app:

1. **Data safety** — no `scenePhase` handling (edits inside the 500ms debounce / 2s flush window are lost when iOS suspends the app), the `NSFileCoordinator` adapter is still a passthrough stub, security-scoped access is never released, and there's a **confirmed cross-platform bug**: `NotesViewModel.flushBeforeQuit()` cancels the pending body-debounce task without marking the note dirty, silently dropping the last ≤500ms of typing on quit.
2. **Sync blindness** — iOS never detects external changes. An edit made on the Mac never appears in a running iOS app, and a stale iOS save can clobber it. No conflict UI, no sync indicators, no handling of not-yet-downloaded (dataless) iCloud files.
3. **Missing basics** — no app icon, blank launch screen, no bundled fonts, no settings screen, no tag view/edit/filter, no rename, no sort control, no bookmarks UI, no snapback, dead ⌘L shortcut, no touch affordances beyond swipe-delete.
4. **App Store readiness** — no privacy manifest, no localization in the iOS target, no accessibility labels, `DEVELOPMENT_TEAM` unset.

**Scope decisions (locked with the user):** No widgets, no Share Extension (a "Copy Note" action suffices). No Markdown preview this release. Trimmed settings surface. Definition of done = App Store submission ready.

**Key files:**
- iOS app: `nvEnvy/nvEnvyiOS/` — `nvEnvyiOSApp.swift`, `UI/RootSplitView.swift`, `UI/NoteListView.swift`, `UI/NoteEditorView.swift`, `Editor/NoteUITextEditor.swift`, `Editor/EditorCoordinator.swift`, `Editor/EditorKeyCommands.swift`, `Storage/NotesFolderProvider.swift`, `Onboarding/FirstLaunchView.swift`
- Core: `NvEnvyCore/Sources/NvEnvyCore/NotesViewModel.swift`, `FileStorageService.swift`, `NoteStore.swift`, `EditorTheme.swift`
- macOS reference implementations ported from: `nvEnvy/nvEnvy/ICloudStatusMonitor.swift`, `ConflictResolutionView.swift`, `TagEditorPanel.swift`, `NoteListView.swift`, `PreferencesView.swift`
- Project spec: `nvEnvy/project.yml` (XcodeGen — regenerate with `xcodegen generate` from `nvEnvy/` after editing; verify by opening `nvEnvy.xcodeproj`)

---

## Workstream 0 — P0 Core bug: flushBeforeQuit loses the last edit (macOS + iOS)

`NotesViewModel.updateNoteBody` mutates `note.body` synchronously but defers `noteStore.updateBody` (which does `markDirty` + WAL append) behind a 500ms debounce. `flushBeforeQuit()` cancelled that task and then flushed — but the note was never marked dirty, so `flushDirtyNotes()` skipped it, silently losing the final keystrokes.

**Fix:** `NotesViewModel` now tracks `pendingBodyUpdate: (noteID: UUID, body: String)?`, set on every `updateNoteBody` call and cleared once the debounce fires. `flushBeforeQuit()` applies any still-pending update synchronously before flushing.

**Test:** `NotesViewModelTests.testFlushBeforeQuit_persistsPendingBodyEdit_evenBeforeDebounceFires` — attaches to a temp folder, calls `updateNoteBody`, immediately calls `flushBeforeQuit()` (no 500ms wait), reads the file from disk, asserts the body persisted.

---

## Workstream 1 — Data safety & lifecycle (iOS)

### 1.1 Flush on scenePhase change

`nvEnvyiOSApp` observes `\.scenePhase`. On `.background`/`.inactive` it wraps `notesVM.flushBeforeQuit()` in a `UIApplication.beginBackgroundTask`/`endBackgroundTask` pair and stops the folder monitor. On `.active` it restarts the monitor and runs a full `reconcileFilesystem()`.

### 1.2 NSFileCoordinator adapter (fills the Phase-4 seam)

`NvEnvyCore/Sources/NvEnvyCore/NSFileCoordinatorAdapter.swift` implements `FileAccessCoordinator` using `NSFileCoordinator`. It's Foundation-only so it compiles on both platforms, but only iOS constructs one — macOS keeps the `PassthroughFileAccessCoordinator` default, so its read-perf characteristics are unchanged.

`NotesViewModel.attach` gained `coordinator: FileAccessCoordinator = PassthroughFileAccessCoordinator()` and `onInitialLoad: (() -> Void)?` parameters, both defaulted so existing macOS call sites are source-compatible. `FileStorageService.readAllNotes()`'s directory enumeration is now wrapped in a single `coordinator.coordinate(readingItemAt:)` call (the per-file parallel parse fan-out is unchanged).

iOS call site: `notesVM.attach(folderURL: url, coordinator: NSFileCoordinatorAdapter()) { ... }`.

### 1.3 Balanced security-scoped access

`NotesFolderProvider` is now the single owner of the security-scoped access grant: `resolveSavedBookmark()` starts access and records it; `adoptPickedFolder(_:)` (used by both first-launch and the Settings "Change Folder" flow) releases any previous grant via `stopAccessing()` before adopting the new one. Nothing calls `stopAccessing()` on backgrounding — iOS preserves the grant while suspended.

### 1.4 Persist selection across launches

`nvEnvyiOSApp` persists `notesVM.selectedNoteID` to `UserDefaults` on change and restores it via `attach`'s `onInitialLoad` callback once the initial vault load completes.

---

## Workstream 2 — External change detection & sync (iOS)

The reconcile engine (`NotesViewModel.reconcileFilesystem`, `NoteStore.reconcilePaths`/`reconcileWithFilesystem` with self-write suppression) was already fully cross-platform; iOS only needed triggers and UI.

### 2.1 Foreground + pull-to-refresh reconcile

`scenePhase == .active` triggers a full reconcile (1.1); `NoteListView` also has `.refreshable { await notesVM.reconcileFilesystem() }`.

### 2.2 Live monitor while active: `IOSFolderMonitor`

`nvEnvy/nvEnvyiOS/Storage/IOSFolderMonitor.swift` watches the notes folder via `NSMetadataQuery` with `NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope` — the scope meant for document-picker-granted iCloud folders. It mirrors the delta-processing shape of macOS's `ICloudStatusMonitor` (only touching `NSFileVersion` when a conflict flag is set) and additionally forwards raw changed paths so the caller can drive `reconcileFilesystem(changedPaths:)`. Started/stopped alongside scenePhase transitions and on folder change.

Non-iCloud folders (on-device or third-party providers) don't get live updates from the metadata query — the foreground and pull-to-refresh reconciles (2.1) cover that case.

### 2.3 Dataless iCloud files

`IOSFolderMonitor` calls `FileManager.default.startDownloadingUbiquitousItem(at:)` for any result whose downloading status isn't `.current`, so not-yet-downloaded notes pull themselves down automatically; the subsequent metadata update feeds `reconcileFilesystem`.

### 2.4 Sync indicators + conflict resolution UI

`nvEnvy/nvEnvyiOS/UI/ConflictView.swift` ports `SyncStatusIcon` (per-row indicator) and the `ConflictBanner`/`ConflictListView`/`ConflictResolutionView` trio from the macOS `ConflictResolutionView.swift`, with the layout changed from `HSplitView` to a scrollable `VStack` for narrow screens. Resolution actions (Keep Current / Use This Version / Keep Both) are unchanged.

---

## Workstream 3 — Note list & touch UX

All in `nvEnvy/nvEnvyiOS/UI/NoteListView.swift` plus supporting sheets.

- **Toolbar:** settings gear (leading), snapback button (conditional), sort menu, filter/bookmarks menu (trailing).
- **Sort menu:** picker over `NotesViewModel.SortField`, persisted to `IOSPreferences`.
- **Filter/bookmarks menu:** tag list with checkmark on active filter, save-search-as-bookmark, per-bookmark restore, "Edit Bookmarks…" → `BookmarksSheet.swift`.
- **Row affordances:** trailing swipe = delete (confirmation-gated), leading swipe = rename, context menu = rename/edit tags/copy note/copy note link/delete, tag pills + sync icon inline.
- **Search:** `.searchable` + `.onSubmit(of: .search)` for create-or-select; `.nvEnvyFocusSearch` notification drives `@FocusState` (guarded behind `if #available(iOS 18, *)` since `.searchFocused` is iOS 18+ — on iOS 17 the notification is a harmless no-op).
- **Tag editor sheet:** `TagEditorSheet.swift`, porting the macOS `TagEditorPanel` single-note editor (including its `FlowLayout`).
- **Editor toolbar:** `NoteEditorView.swift` has an ellipsis menu (Edit Tags / Rename / Copy Note / Copy Note Link / Delete) replacing the old lone trash button.
- **Keyboard shortcuts:** `EditorKeyCommands.swift` adds ⌘N (new) and ⌘⌫ (delete) alongside the existing ⌘B/I/Y, ⌘]/[, ⌘L, ⌘J/K; every declared notification now has an observer.
- **Shared helper:** `NoteLinkBuilder` moved into `NvEnvyCore` so the `nvenvy://find/<title>` link format can't drift between platforms; macOS `AppState.copyNoteLink` now calls it too.

---

## Workstream 4 — Editor feel

- **Keyboard avoidance:** `EditorCoordinator` observes `UIResponder.keyboardWillChangeFrameNotification` and adjusts `textView.contentInset.bottom`/`verticalScrollIndicatorInsets.bottom` by the keyboard overlap, since the editor ignores the bottom safe area and a raw `UITextView` doesn't auto-adjust the way `UIScrollView` does with `keyboardLayoutGuide`.
- **Input accessory bar:** `EditorAccessoryView.swift` — a `UIToolbar`-based `inputAccessoryView` with wikilink/bold/italic/strikethrough/indent/outdent/dismiss buttons, swapped for a horizontal wikilink-suggestion row while the caret sits inside an unclosed `[[prefix`.
- **Wikilink autocomplete:** `EditorCoordinator.updateWikilinkAutocompleteState` detects the unclosed-`[[` case on every text change (gated on `IOSPreferences.autoSuggestWikilinks`); suggestions come from `notesVM.sortedNotes` filtered by title prefix.
- **Font/prefs plumbing:** `FontResolver.swift` resolves `EditorFontDescriptor` to a `UIFont`, scaling named fonts through `UIFontMetrics` so Dynamic Type still applies. `EditorCoordinator` reads `IOSPreferences` for soft-tabs/spaces-per-tab/auto-pair/auto-indent/auto-list/`@done` strikethrough/search-highlight/spell-check instead of hard-coded constants.

---

## Workstream 5 — Settings screen (trimmed set)

`nvEnvy/nvEnvyiOS/Settings/IOSPreferences.swift` — `@Observable`, `UserDefaults`-backed, keys prefixed `nvenvy.iOS.*`. Exposes font choice/size, appearance override, sort field/direction, and the editing-behavior toggles listed above, plus `confirmDeletion`.

`nvEnvy/nvEnvyiOS/Settings/SettingsView.swift` — a `Form` with Notes Folder (view + Change Folder…), Font (picker + size stepper + live preview), Appearance, Editing, Notes, and About sections. Folder changes are posted via `.nvEnvyFolderChanged` notification so `nvEnvyiOSApp`'s single `attach(url:)` code path (which also restarts the folder monitor) handles them, rather than duplicating that logic in the settings view.

Appearance override is applied via `.preferredColorScheme(prefs.appearance.colorScheme)` on the app's root view.

---

## Workstream 6 — App Store readiness

- **App icon:** `nvEnvyiOS/Assets.xcassets/AppIcon.appiconset/` — single 1024×1024 universal entry, sourced from the existing macOS icon art.
- **Accent color:** `AccentColor.colorset` added; `AppIcon`/`AccentColor` wired via `ASSETCATALOG_COMPILER_APPICON_NAME`/`ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` in `project.yml`.
- **Launch screen:** `LaunchBackground.colorset` (white/black by appearance) referenced from `UILaunchScreen.UIColorName` in the iOS target's Info.plist properties.
- **Bundled fonts:** the existing `nvEnvy/Fonts/` folder is added as an iOS target resource; `UIAppFonts` lists all eight Atkinson Hyperlegible / OpenDyslexic files.
- **Privacy manifest:** `nvEnvyiOS/PrivacyInfo.xcprivacy` declares `NSPrivacyAccessedAPICategoryUserDefaults` and `NSPrivacyAccessedAPICategoryFileTimestamp` (the two API categories actually used), no tracking, no collected data types. A matching `nvEnvy/PrivacyInfo.xcprivacy` was added to the macOS target too.
- **Localization:** `nvEnvy/Localizable.xcstrings` added as an iOS target resource.
- **Accessibility:** row/toolbar/button `.accessibilityLabel`s added throughout the new iOS UI.
- **Signing:** `DEVELOPMENT_TEAM` in `project.yml`'s iOS target is still empty — needs a real team ID before archiving for TestFlight/App Store.

---

## Workstream 7 — Tests & verification

### Automated (done)

- `NvEnvyCoreTests`: 200 tests, same 16 pre-existing failures as pre-change `main` (confirmed via `git stash` comparison — unrelated to this work), 2 new passing tests (the W0 regression test and an `NSFileCoordinatorAdapter` round-trip test).
- iOS build: `xcodebuild -project nvEnvy.xcodeproj -scheme nvEnvyiOS -destination 'platform=iOS Simulator,id=<sim>' build` → **BUILD SUCCEEDED**.
- macOS build: `xcodebuild -project nvEnvy.xcodeproj -scheme "nvEnvy (Direct Download)" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` → **BUILD SUCCEEDED**.
- Smoke test: app installed and launched on an iOS 26.5 simulator; onboarding screen renders correctly with the new accent color and icon.

### Manual (still needed before submission)

1. Fresh install → onboarding → pick an iCloud Drive folder with existing notes → all notes appear (including previously-undownloaded ones after a beat).
2. Type in a note, immediately swipe to app switcher, kill the app, relaunch → last keystrokes present.
3. Edit a note on the Mac (or in Files app) while iOS app is foregrounded → change appears within seconds; while backgrounded → appears on foreground.
4. Create a conflict (edit same note both sides offline) → banner appears → resolve each of the three ways.
5. Rename, tag-edit, tag-filter, sort, bookmark save/restore, snapback after wikilink navigation, Copy Note / Copy Note Link (paste link in Safari → app opens the note).
6. Settings: each font renders, appearance override applies immediately, soft-tab/auto-pair toggles change editor behavior.
7. Hardware keyboard (iPad): ⌘L focuses search, ⌘J/K navigate, ⌘B/I/Y format, ⌘N new, ⌘⌫ delete.
8. VoiceOver sweep of list + editor toolbar; Dynamic Type at AX3.
9. Set a real `DEVELOPMENT_TEAM`, archive, and run through TestFlight before App Store submission.
