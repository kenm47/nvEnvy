# nvEnvy iOS — Drawer Redesign Plan (v2 UI)

> **Audience:** an implementing agent with zero prior context. Read this whole document before writing code. Every decision here is final unless marked **(open)**. When this plan and existing code comments disagree on *UI*, this plan wins; on *data safety / perf* behavior, the existing code comments win — preserve them.

---

## 0. TL;DR

Replace the iOS `NavigationSplitView` (list → push editor) with a **single full-screen, chrome-light editor** plus a **left drawer** holding search + the note list. The drawer opens from a top-left button or an edge swipe from the left, and slides in over the editor. Search behaves exactly like macOS (same engine, same Return semantics). Add a **Storage** settings screen (iCloud Drive default, Files folder, or On My iPhone) and make iOS read **the same file types** as the Mac.

Keep: everything in `NvEnvyCore`, `nvEnvyiOS/Editor/*`, `nvEnvyiOS/Storage/*`, `IOSPreferences`, `ConflictView`, `TagEditorSheet`, `BookmarksSheet`, `FontResolver`, the scene-phase/flush lifecycle in `nvEnvyiOSApp.swift`.
Replace: `UI/RootSplitView.swift`, `UI/NoteListView.swift`, `UI/NoteEditorView.swift` chrome, `Onboarding/FirstLaunchView.swift`, `Settings/SettingsView.swift` (restructure).

---

## 1. What exists today (inventory — verified)

### 1a. Repo layout
```
NvEnvyCore/                  SwiftPM package, platforms macOS 14 / iOS 17. Shared logic. Has tests.
nvEnvy/project.yml           XcodeGen spec. Targets: nvEnvy, nvEnvy-MAS (macOS), nvEnvyiOS.
nvEnvy/nvEnvy/               macOS app (reference for behavior; do NOT modify except §8).
nvEnvy/nvEnvyiOS/            iOS app (this plan's target).
docs/IOS_PORT_PLAN.md        Original port architecture (background reading).
docs/IOS_RELEASE_PLAN.md     iOS 1.0 hardening record (data-safety rationale — read §W0–W2).
```

### 1b. Core pieces you will use (do not re-implement)
| Type | File | Use |
|---|---|---|
| `NotesViewModel` (`@Observable`, `@MainActor`) | `NvEnvyCore/.../NotesViewModel.swift` | Single source of truth: `allNotes`, `sortedNotes`, `searchQuery` (150 ms debounce → `SearchActor`), `tagFilter`, `selectedNoteID`, `showCreateRow`, `createOrSelectNote(allowPrefixMatch:)`, `clearSearch()`, `updateNoteBody`, `tryRenameNote`, `deleteNote`, bookmarks, snapback, `reconcileFilesystem`, `flushBeforeQuit`, `syncHealthSummary`, `handleURL`. |
| `SearchEngine` / `SearchActor` | `SearchEngine.swift` | Tokenized + quoted-phrase search, tiered ranking (exact title → title prefix → title contains → body/tags). `exactTitleMatch`, `bestTitlePrefixMatch`. |
| `SearchHighlighting` | `SearchHighlighting.swift` | Ranges of query terms — use for list-row highlighting. |
| `FileStorageService` | `FileStorageService.swift` | Parallel vault scan, `allowedExtensions`, `isDataless` skip, encoding fallback, atomic writes, self-write detection, subfolder-relative `filename`. |
| `NoteStore` | `NoteStore.swift` | CRUD, `uniqueFilename`, dirty tracking, WAL, `reconcileWithFilesystem`, `reconcilePaths`. |
| `NSFileCoordinatorAdapter` | `NSFileCoordinatorAdapter.swift` | iOS file coordination (already wired in `nvEnvyiOSApp.attach`). |
| `Note` | `Note.swift` | `title` (= filename stem), `body` (frontmatter stripped), `tags`, `filename` (vault-relative incl. subfolder + ext), `createdDate`, `modifiedDate`, `syncStatus`, `cachedFirstLine`, `cachedModifiedString`. |
| `ImportExportService` | `ImportExportService.swift` | Plain/HTML export everywhere; RTF guarded by `canImport(AppKit)` (see §7.4). |

### 1c. iOS app pieces to keep
- `nvEnvyiOSApp.swift` — scene lifecycle: bookmark resolve, `attach()` with `NSFileCoordinatorAdapter`, `IOSFolderMonitor` start/stop, flush on `.background/.inactive` with background task, reconcile on `.active` (skips first). **Keep all of this logic**; only the root view and storage-resolution entry point change (§5, §6).
- `Storage/NotesFolderProvider.swift` — security-scoped bookmark lifecycle + `FolderPicker`. Extend (§6), don't rewrite.
- `Storage/IOSFolderMonitor.swift` — `NSMetadataQuery` watcher. Extend with a scope parameter (§6.4).
- `Editor/*` — `NoteUITextEditor` (TextKit 2 `UITextView`), `EditorCoordinator` (highlighting, auto-pair, lists, soft tabs, wikilink autocomplete, keyboard avoidance), `EditorAccessoryView`, `EditorKeyCommands` (⌘B/I/Y/]/[/L/J/K/N/⌫ via `NotificationCenter`).
- `Settings/IOSPreferences.swift` — add keys (§9); keep existing ones and their `nvenvy.iOS.` prefix.
- `UI/ConflictView.swift` (+ `ConflictBanner`, `SyncStatusIcon`, `TagPill`), `UI/TagEditorSheet.swift`, `UI/BookmarksSheet.swift`, `UI/FontResolver.swift`.

### 1d. Known gaps this plan fixes
1. ⌘L can't focus search on iOS 17 (`.searchable` focus is iOS 18+). Custom `TextField` fixes it.
2. iOS ignores the Mac's custom `allowedExtensions`; no UI to edit them.
3. Undownloaded iCloud files: `readAllNotes` uses `.skipsHiddenFiles`, so iOS `.Name.md.icloud` placeholders are invisible until `IOSFolderMonitor` happens to trigger a download. Notes can be missing on first load.
4. No app-owned iCloud location; first launch forces a Files picker even for brand-new users.
5. No note preview text in rows; no info/word count surface.

---

## 2. Target UX (spec)

Inspired by Drafts; **do not copy its icons, layout pixel-for-pixel, tab names (Inbox/Archive/Flagged/Trash), or colors.** Use SF Symbols and the app's `AccentColor`.

### 2a. Editor screen (default, full screen)
```
┌───────────────────────────────────────────┐
│ [≡]  [+]                     128w  [ⓘ]    │  ← top bar, 44pt, no title, no background fill
│                                           │
│  (UITextView — full bleed, generous       │
│   insets: 20pt horizontal on iPhone,      │
│   readable-width centered on iPad)        │
│                                           │
│                                           │
│ [↩︎ snapback]                 [Aa]  [⚙︎]    │  ← bottom bar, only when keyboard hidden
└───────────────────────────────────────────┘
```
- **Top-left `[≡]`** (`sidebar.left`): opens drawer **and focuses search** (keyboard up). Accessibility: "Notes and search".
- **`[+]`** (`plus`): new blank note (§2d). Long-press → menu: "New Note", "New from Clipboard".
- **Word/char counter** (right side, `.footnote`, `.secondary`, monospaced digits): shows `"{w}w"`; tap cycles `w → c → w+c → hidden` (persist in prefs `counterMode`). Selection active → counts the selection.
- **`[ⓘ]`** (`info.circle`): Note Info sheet (§2f). Disabled (dimmed) when blank scratch note.
- **Bottom bar** (hidden while keyboard is up; the existing `EditorAccessoryView` covers that state): snapback button (only when `notesVM.hasSnapback`), `Aa` → small popover (font choice, size stepper, appearance) bound to `IOSPreferences`, `⚙︎` → Settings sheet.
- No navigation title. No separators. Background `.systemBackground`. Top/bottom bar icons `.tint` at 70% opacity; disabled `.tertiary`.
- iPad regular width: text column max width 720pt, centered.

### 2b. Drawer (search + list)
```
┌──────────────────────────────┬────┐
│ [+]  Sort: Modified ▾    [✕] │░░░░│  ← header
│ ┌──────────────────────────┐ │░░░░│
│ │🔍 Search or Create       │ │░░░░│  ← always-visible search field
│ └──────────────────────────┘ │░░░░│
│ (All) (★ work) (★ todo) (#…) │░░░░│  ← horizontal chip row
├──────────────────────────────┤░░░░│  ← dimmed editor (scrim)
│ ⊕ Create "foo"               │░░░░│  ← only when notesVM.showCreateRow
│ Title (semibold, 1 line)     │░░░░│
│ preview line 1 (secondary)   │░░░░│
│ preview line 2               │░░░░│
│               Modified: 11/5 │░░░░│
├──────────────────────────────┤░░░░│
│ …                            │░░░░│
├──────────────────────────────┤░░░░│
│ 1,284 notes · All synced  [⚙︎] │░░░░│  ← footer
└──────────────────────────────┴────┘
```
- **Geometry:** iPhone width = `min(screenWidth * 0.86, 420)`. iPad: 380pt overlay in compact; in **regular width** the drawer can be **pinned** as a persistent left column (toggle via header pin button and ⌘⇧C; default pinned on iPad landscape). When pinned, no scrim, editor resizes.
- **Motion:** slides from x = -width to 0, scrim opacity 0 → 0.25 black. Spring `response: 0.32, dampingFraction: 0.86`. Respect Reduce Motion → 0.15 s cross-fade, no slide.
- **Open triggers:** (1) `[≡]` button → open + focus search; (2) left-edge swipe on editor → open interactively, finger-tracked, **no** search focus; (3) ⌘L → open + focus search + select all text in field; (4) ⌘N → open + focus search with empty query (nvALT "type to create").
- **Close triggers:** tap scrim; swipe left on drawer (interactive); `[✕]`; selecting a note; Return in search (after commit); Escape with empty query; ⌘L again does **not** close.
- **Header:** `[+]` new blank note; "Sort: {field} ▾" menu (Title / Date Modified / Date Created / Tags + Ascending/Descending — bind to `prefs.sortField/sortAscending` and mirror into `notesVM` exactly like today's `sortMenu`); pin (iPad regular only); close.
- **Search field:** custom `UITextField`-backed or SwiftUI `TextField` with `@FocusState` (SwiftUI is fine on iOS 17 — focus works for `TextField`, it's only `.searchable` that lacks it). Placeholder "Search or Create". `returnKeyType = .go`, autocorrection off, autocapitalization `.sentences`, clear button. See §4 for behavior.
- **Chip row** (horizontal `ScrollView`, 32pt chips): `All` (selected when no tag filter and query not equal to a bookmark), one chip per **bookmark** (`bookmarkStore.bookmarks`, `bookmark` icon prefix), then `#Tags…` chip → sheet listing `notesVM.allKnownTags` with counts (tap sets `tagFilter`, shows checkmark; active tag shows as a dismissible chip `#tag ✕`). Long-press bookmark chip → Rename/Delete/Edit Bookmarks…. Trailing `+` chip "Save Search" enabled when query non-empty → `notesVM.saveBookmark()`.
- **List:** `List` with `.listStyle(.plain)`, `LazyVStack` semantics, row separators full-width hairline. Selection highlight = `.tint.opacity(0.12)` background for `selectedNoteID`.
- **Row** (§3 for preview text):
  - Title: `.headline` (17 semibold), 1 line, tail truncation. Search terms highlighted (bold + `.tint`) via `SearchHighlighting`.
  - Preview: `.subheadline`, `.secondary`, up to **2 lines** (pref `previewLines` 0–3, default 2). Search terms highlighted.
  - Footer: right-aligned `.caption`, italic, `.tertiary`: `"Modified: {cachedModifiedString}"`, or `"Created: …"` when sort field is Date Created. Left side of footer: `SyncStatusIcon` only when status ∉ {`.current`, `.local`, `.synced`}; up to 2 `TagPill`s when pref `showTagsInList` (default off).
  - Vertical padding 10pt; horizontal 16pt.
  - Swipe trailing: Delete (respect `prefs.confirmDeletion`). Swipe leading: Rename, Tags. Context menu: Rename, Edit Tags…, Copy Note, Copy Note Link, Share…, Delete.
- **Footer bar:** `"{n} notes"` (or `"{filtered} of {n}"` when filtering) · `notesVM.syncHealthSummary`; gear → Settings. Tap summary when conflicts exist → `ConflictView`.
- **Empty states:** vault empty → "No notes yet. Type above to create one." Search with no results → only the Create row + "No matches".
- `ConflictBanner` stays: render it under the chip row when `notesVM.conflictedNotes` non-empty.
- Pull-to-refresh → `await notesVM.reconcileFilesystem()`.

### 2c. Gestures — exact implementation
SwiftUI has no screen-edge pan, and `UITextView`'s own pan must not steal the swipe. Implement in UIKit:
1. New file `UI/Drawer/EdgePanInstaller.swift`: a `UIViewRepresentable` placed as a zero-size background of the root that, in `didMoveToWindow`, adds a `UIScreenEdgePanGestureRecognizer(edges: .left)` to the **window's root view** (store weakly; remove on dismantle).
2. Its delegate: `gestureRecognizerShouldBegin` → false when drawer already open or pinned, or when a sheet is presented. `shouldRecognizeSimultaneouslyWith` → false. `shouldBeRequiredToFailBy other` → return `true` when `other` is the editor `UITextView`'s `panGestureRecognizer` (so the edge pan wins).
3. Translation drives a shared `DrawerState.progress` (0…1, `@Observable`). On `.ended`: open if `progress > 0.35` or velocity.x > 500, else close; animate remainder with the spring above.
4. Closing swipe: a SwiftUI `DragGesture(minimumDistance: 12)` on the drawer panel **and** scrim, horizontal-only (ignore if `abs(dy) > abs(dx)` so list scroll works), driving `progress` the same way.
5. RTL: mirror edges (`.right`) when `layoutDirection == .rightToLeft`.
6. Haptic: `UIImpactFeedbackGenerator(.light)` once on open commit.
7. Dismiss the keyboard (`resignFirstResponder` on editor) as soon as an open gesture begins.

### 2d. New note & the blank "scratch" note
The editor is never "empty with a placeholder screen" — when nothing is selected it shows a **blank scratch note** you can type into.
- **State:** `ScratchNote` (app-layer, `@Observable`): `text: String`, not on disk.
- Editor shows scratch when `selectedNoteID == nil`. Typing goes into `scratch.text`.
- **Commit to disk** when `scratch.text` has a non-whitespace character **and** any of: 1.5 s idle; drawer opens; app goes `.inactive/.background`; `[+]` tapped; ⌘N/⌘L; another note selected.
- Commit = `notesVM.createNote(title:body:)` (new Core API, §7.1) where `title = ScratchNote.deriveTitle(text)`: first non-empty line, trimmed, leading `#`s and whitespace stripped, wikilink brackets removed, truncated to 80 chars on a word boundary; empty → `"Untitled {yyyy-MM-dd HHmm}"`. `body = text` (full text, first line included — matches what a Mac user sees as the body; no data loss).
- After commit: `selectedNoteID = newID`, editor continues seamlessly (same text, caret preserved — pass the current `selectedRange` and set `note.selectedRange`). Subsequent edits go through `updateNoteBody`. Title is **not** auto-renamed later (title = filename on Mac; churn would break wikilinks). Rename via Info.
- `[+]` / ⌘N: commit scratch if dirty, then `selectedNoteID = nil`, fresh empty scratch, focus editor (keyboard up).
- **Launch behavior** (pref `launchBehavior`): `.blankNote` (default — matches requested "blank and clean") or `.lastNote` (restore `lastSelectedNoteID`, existing logic). Also: if app returns to foreground after > 15 min (pref `blankAfterMinutes`, default 15, 0 = never) and `launchBehavior == .blankNote`, show a fresh scratch.
- Scratch text survives backgrounding without commit only if empty; otherwise it's committed. Never lose typed text.

### 2e. Selecting a note
Tap row → (commit scratch) → `selectedNoteID = id` → close drawer → editor shows note scrolled to its saved `selectedRange` (else top). **Do not** raise the keyboard (reading-first); tap text to edit. Exception: a note just created via Return / Create row → focus editor with caret at end.

### 2f. Note Info sheet (`ⓘ`)
`.presentationDetents([.medium, .large])`. Sections:
- **Title** — editable field; commit via `notesVM.tryRenameNote` (show its error string inline).
- **Tags** — inline `TagEditorSheet` content (refactor its body into a reusable `TagEditorContent` view).
- **Details** — Created, Modified (`.dateTime`), Words, Characters, Lines, Reading time (words/230), File (`note.filename`), Location (folder display name), Encoding (`fileEncoding` description), Sync status (`SyncStatusIcon` + text).
- **Actions** — Copy Note Link (`NoteLinkBuilder`), Share… (`ShareLink` of plain text + `.md` file URL), Export as HTML / Plain Text / RTF (§7.4) via `ShareLink` of a temp file, Delete (destructive, confirm per pref).

### 2g. Hardware keyboard (iPad / Magic Keyboard)
Keep existing `EditorKeyCommands`. Add/redefine at the root (`.keyboardShortcut` on hidden buttons or `UIKeyCommand` on a root `UIHostingController` subclass — prefer the existing NotificationCenter pattern):
| Key | Action |
|---|---|
| ⌘L | Open drawer, focus search, select all |
| ⌘N | New blank note (commit scratch first) |
| ⌘J / ⌘K | Next / previous in `sortedNotes` (works with drawer closed) |
| ⌘⇧C | Toggle drawer (pin toggle on iPad regular) |
| ⌘I with ⌥ (⌥⌘I) | Note Info |
| ⌘⌫ | Delete current note |
| ⌘1–9 | Restore bookmark N |
| ⌘S | Save search as bookmark |
| ⌘D | Deselect / snapback (`notesVM.deselectNote()`) |
| Esc (in search) | Clear query; if already empty, close drawer |
| ↓ (in search) | Move focus to list, select first row; ↑/↓ moves; Return opens |
| ⌘Return (in search) | Force create (`createOrSelectNote(allowPrefixMatch: false)`) |

---

## 3. Row preview text (Core change)

Add to `Note` (`NvEnvyCore/Sources/NvEnvyCore/Note.swift`):
```swift
@ObservationIgnored public var cachedPreview: String
public static func preview(title: String, body: String, maxLines: Int = 3, maxChars: Int = 240) -> String
```
Rules, in order:
1. Iterate lines lazily (don't `components(separatedBy:)` the whole body — notes can be MBs).
2. Skip blank lines.
3. Skip the **first** non-blank line if, after stripping leading `#`s/whitespace, it equals `title` case-insensitively (avoids "Beer / # Beer").
4. Strip leading Markdown markers per line: `#{1,6} `, `> `, `- [ ] `, `- [x] `, `- `, `* `, `+ `, `1. `; collapse `[[x]]` → `x`, `[text](url)` → `text`, `**`/`__`/`` ` `` removed.
5. Take up to `maxLines` lines joined with `"\n"`, total ≤ `maxChars` (truncate on a character boundary, append `…`).
6. Compute in `init` and in `invalidateSearchCache()` alongside `cachedFirstLine` (same debounce discipline — do **not** recompute per keystroke).

Tests (`NoteCacheTests.swift`): title-duplicate skip, heading strip, list/checkbox strip, link collapse, blank-only body → `""`, 10 MB body completes < 5 ms, invalidation refreshes.

---

## 4. Search — parity with macOS (must match exactly)

Mac reference: `nvEnvy/nvEnvy/SearchField.swift`, `MainView.swift:34-60`. Engine is shared, so parity is about **wiring**:
| Behavior | Implementation |
|---|---|
| Live filtering as you type | Bind field to `notesVM.searchQuery` (VM debounces 150 ms, runs off-main). Do **not** add a second debounce. |
| Ranking | Untouched — `notesVM.sortedNotes` already preserves relevance order when query non-empty and applies sort otherwise. |
| Quoted phrases, multi-token AND | Engine already does it. |
| Return | If query empty → close drawer, focus editor. Else `notesVM.createOrSelectNote()` (exact title → best title prefix → create). Close the drawer in `notesVM.onNoteCommitted` (set this hook in the root; creation is async — never close based on the call returning). Focus editor, caret at end. |
| "Create "query"" row | Visible iff `notesVM.showCreateRow`; tap → `createOrSelectNote(allowPrefixMatch: false)`. |
| ⌘Return | Same as Create row. |
| Esc / clear button | `notesVM.clearSearch()` (clears tag filter too — matches Mac). |
| Tag filter | `notesVM.tagFilter`. |
| Bookmarks | `saveBookmark()`, `restoreBookmark(index:)`. |
| Highlight in editor | Existing `prefs.searchHighlight` + `EditorCoordinator.highlightSearchTerms`. Query persists after closing drawer so highlights remain; clearing search removes them. |
| Live title auto-select | `notesVM.autoSelectTitleMatch` stays **false** on iOS (the editor is covered by the drawer; auto-selecting would swap the note under the user). |
| Query persistence | Query is kept when drawer closes/reopens; cleared on Esc/clear button or when a new blank note is started via `[+]`. |

**Parity test:** run the same queries on Mac and iOS against the same vault (§11.4) and compare ordered result titles — must be identical.

---

## 5. Root composition (new files)

Create `nvEnvy/nvEnvyiOS/UI/Drawer/`:
| File | Responsibility |
|---|---|
| `DrawerState.swift` | `@MainActor @Observable final class DrawerState { var progress: CGFloat; var isOpen: Bool { progress == 1 }; var isPinned: Bool; var focusSearchOnOpen: Bool; func open(focusSearch:) ; func close() }`. |
| `RootView.swift` | Replaces `RootSplitView`. `ZStack(alignment: .leading)`: `EditorScreen` (offset by pinned width when pinned) → scrim (`Color.black.opacity(0.25 * progress)`, tap closes, hidden when pinned) → `DrawerView` (offset `-(1-progress)*width`). Hosts `EdgePanInstaller`, `onNoteCommitted` hook, root key commands, sheets (Settings, Info, Conflicts). |
| `DrawerView.swift` | Header, `SearchBar`, `ChipRow`, `ConflictBanner`, `NoteList`, footer. |
| `SearchBar.swift` | TextField + focus + key handling (`.onKeyPress` for Esc/↓/⌘Return works for hardware keyboards on iOS 17). |
| `ChipRow.swift` | All / bookmarks / tag chips. |
| `NoteRow.swift` | Row per §2b/§3. Must be cheap: read only `title`, `cachedPreview`, `cachedModifiedString`, `syncStatus`, `tags`. No body access in `body`. |
| `NoteListActions.swift` | Move rename/delete/tag alerts out of the old `NoteListView` (reuse its code verbatim where possible: `requestDelete`, `beginRename`, `commitRename`). |
| `EdgePanInstaller.swift` | §2c. |

Create `nvEnvy/nvEnvyiOS/UI/Editor/`:
| File | Responsibility |
|---|---|
| `EditorScreen.swift` | Top bar, `NoteUITextEditor` (or scratch editor), bottom bar. |
| `ScratchNote.swift` | §2d model + `deriveTitle`. |
| `WordCounter.swift` | Pure function `count(_ text: String) -> (words, chars, lines)` using `enumerateSubstrings(.byWords)`; run off-main for > 50 k chars, debounced 300 ms. |
| `NoteInfoSheet.swift` | §2f. |
| `QuickTypePopover.swift` | `Aa` popover. |

**Editor for scratch:** generalize `NoteUITextEditor` to take a `EditorSource` enum (`.note(Note)` / `.scratch(ScratchNote)`). In `EditorCoordinator.textViewDidChange`, route to `notesVM.updateNoteBody` or `scratch.text = …`. When scratch commits, switch source to `.note` **without** resetting `textView.text` (set `coordinator.currentNoteID = newID` before SwiftUI re-renders so `isNoteSwitch` is false). This is the one subtle bit — write a UI test for caret continuity (§11.3).

Delete after migration: `UI/RootSplitView.swift`, `UI/NoteListView.swift`, `UI/NoteEditorView.swift`. Run `xcodegen generate` (sources are folder-globbed; no yml edit needed for new Swift files).

`nvEnvyiOSApp.swift` changes: replace `RootSplitView()` with `RootView()`; inject `DrawerState`, `ScratchNote`; on `.background/.inactive` call `scratch.commitIfNeeded()` **before** `flushBeforeQuit()`; implement `launchBehavior`.

---

## 6. Storage location ("where sync is done") — iCloud by default

### 6.1 Decision
Three location kinds, persisted as `StorageLocation` (Codable, in `UserDefaults` key `nvenvy.iOS.storageLocation`):
```swift
enum StorageLocationKind: String, Codable { case iCloudApp, folder, onDevice }
```
1. **iCloud Drive › nvEnvy** (`.iCloudApp`) — **default for new users.** App ubiquity container `iCloud.com.nvenvy.app`, `Documents/` subfolder, published to iCloud Drive as a folder named "nvEnvy". Zero pickers. The Mac can open the same folder via its existing folder chooser (it appears in Finder under iCloud Drive › nvEnvy).
2. **A folder in Files** (`.folder`) — existing `UIDocumentPickerViewController` + security-scoped bookmark flow (`NotesFolderProvider`). For existing Mac users whose vault is elsewhere in iCloud Drive (incl. Obsidian vaults), and third-party providers (Dropbox, etc. — supported but no live change monitoring; reconcile on foreground + pull-to-refresh only; show a footnote saying so).
3. **On My iPhone/iPad** (`.onDevice`) — `FileManager.default.urls(for: .documentDirectory)` + `/Notes`. No sync; show warning "Notes stay on this device." Visible in Files (§6.5).

### 6.2 Entitlements & project.yml
Add to `nvEnvy/nvEnvyiOS/Entitlements.plist` (keep the existing KVS key):
```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.com.nvenvy.app</string></array>
<key>com.apple.developer.ubiquity-container-identifiers</key>
<array><string>iCloud.com.nvenvy.app</string></array>
<key>com.apple.developer.icloud-services</key>
<array><string>CloudDocuments</string></array>
```
Add to the `nvEnvyiOS` `info.properties` in `project.yml`:
```yaml
NSUbiquitousContainers:
  iCloud.com.nvenvy.app:
    NSUbiquitousContainerIsDocumentScopePublic: true
    NSUbiquitousContainerName: nvEnvy
    NSUbiquitousContainerSupportedFolderLevels: Any
UIFileSharingEnabled: true
LSSupportsOpeningDocumentsInPlace: true
```
**Human prerequisite (flag in PR):** the iCloud container `iCloud.com.nvenvy.app` must be created in the Apple Developer portal and enabled on App ID `com.nvenvy.app.ios` (team `B35T5FY8RZ`). Automatic signing will then pick it up. Bump `CFBundleVersion` when shipping so iCloud Drive republishes the container folder.

### 6.3 Resolution (new `Storage/StorageLocationResolver.swift`)
```swift
@MainActor @Observable final class StorageLocationResolver {
  var current: StorageLocation?
  func resolve() async -> URL?        // by kind
  func setICloudApp() async throws -> URL
  func setFolder(_ url: URL)          // delegates to NotesFolderProvider.adoptPickedFolder
  func setOnDevice() throws -> URL
  var iCloudAvailable: Bool           // FileManager.default.ubiquityIdentityToken != nil
}
```
- `.iCloudApp`: call `FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.nvenvy.app")` on a **background** task (it can block), append `Documents`, `createDirectory(withIntermediateDirectories: true)`. No security scope needed. If nil (signed out of iCloud) → show "iCloud is off" banner with buttons "Open Settings" and "Use On My iPhone instead"; do **not** silently fall back.
- `.folder`: existing `folderProvider.resolveSavedBookmark()`.
- `.onDevice`: create `Documents/Notes`.
- Observe `NSUbiquityIdentityDidChange` → re-resolve; if identity changed, flush, detach, re-attach.
- **Migration of existing installs:** if `NotesFolderProvider.bookmarkKey` exists and no `storageLocation` saved → set `.folder`. Existing users see zero change.

### 6.4 Monitoring
`IOSFolderMonitor` gets `init(folderURL:scope:)`:
- `.iCloudApp` → `NSMetadataQueryUbiquitousDocumentsScope`
- `.folder` → `NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope` (current)
- `.onDevice` → no metadata query; rely on foreground reconcile only.
Keep its delta-processing and download-kick logic unchanged.

### 6.5 Settings › Storage screen (`Settings/StorageSettingsView.swift`)
- **Current:** icon (`icloud` / `folder` / `iphone`), display name, path breadcrumb (path relative to iCloud Drive root when possible), note count, `syncHealthSummary`, last reconcile time.
- **Location** picker (radio list): iCloud Drive › nvEnvy (Recommended) · Choose Folder… · On My iPhone. Disabled iCloud row with explanation when `!iCloudAvailable`.
- **Switching** shows a dialog: "Move notes" (copy all vault files incl. subfolders, coordinated, then switch; never delete source) / "Just switch" (open the new location as-is) / Cancel. Implement copy with `NSFileCoordinator` write per file; show progress; on any error abort and stay on old location.
- **File Types** row → §7.2 editor.
- **Mac hint** row (when KVS `lastPickedNotesFolderPath` exists and differs from current): "Your Mac uses '{name}'. Open it…" → Files picker pre-navigated (reuse `FirstLaunchView.startingDirectory` logic).
- "Reload All Notes" button → `reconcileFilesystem()`.

### 6.6 First launch (rewrite `Onboarding/FirstLaunchView.swift`)
- If KVS hint exists → primary button **"Open your Mac notes folder ('{name}')"** (Files picker), secondary "Start fresh in iCloud Drive".
- Else if iCloud available → primary **"Keep notes in iCloud Drive"** (one tap, no picker), secondary "Choose a folder…", tertiary text button "Keep on this iPhone only".
- Else → "Choose a folder…" / "Keep on this iPhone only" + note that iCloud is off.
- Keep `NSUbiquitousKeyValueStore.default.synchronize()` on appear, and also observe `NSUbiquitousKeyValueStore.didChangeExternallyNotification` to update the hint live.

---

## 7. File-type & sync parity with macOS

### 7.1 Core API additions (`NotesViewModel`)
```swift
public func createNote(title: String, body: String) async -> Note.ID?   // uses NoteStore.addImportedNote(title:body:tags: []), appends, performSearch, returns id; does NOT change selection
public func setAllowedExtensions(_ exts: [String])                       // normalizes (lowercase, strip dots, dedupe, non-empty), updates storage, triggers full reload
```
`setAllowedExtensions` needs `FileStorageService.allowedExtensions` to be settable from the VM (it's a `var` on the actor — add `func setAllowedExtensions(_:)` on the actor) then `reconcileFilesystem()`. Unit-test both.

### 7.2 Allowed extensions — identical defaults, Mac-synced, editable
- Defaults: `["md", "markdown", "mmd", "txt", "text"]` (= `FileStorageService.defaultAllowedExtensions` and Mac `AppState` default). Use the Core constant, don't duplicate the literal.
- New pref `IOSPreferences.allowedExtensions: [String]` (key `nvenvy.iOS.allowedExtensions`) + `followMacFileTypes: Bool` (default **true**).
- **Mac → iOS sync:** Mac writes its list to KVS key `allowedExtensions` (§8). When `followMacFileTypes` is on, iOS uses the KVS value if present, else defaults; re-apply on `didChangeExternallyNotification`.
- Pass the effective set into `notesVM.attach(folderURL:allowedExtensions:coordinator:onInitialLoad:)` (currently not passed on iOS — fix).
- Editor UI (`Settings/FileTypesView.swift`): list with swipe-delete, add field, can't delete last one, "Match my Mac" toggle (disables manual editing when on), "Reset to Defaults".
- **New notes** are always created as `.md` (matches Mac `NoteStore.createNote`).

### 7.3 Make sure every Mac-readable note loads on iOS
1. **Subfolders:** Core already recurses and uses vault-relative `filename`. Verify with fixture (§11.2).
2. **Encodings:** Core `decodeWithFallback` (UTF-8, UTF-16 BOMs, Windows-1252/MacRoman fallback) — unchanged; writes preserve `fileEncoding`. Verify.
3. **Frontmatter:** unknown fields round-trip (`unknownFrontmatterFields`) — verify an Obsidian note with `aliases:` survives an iOS edit byte-for-byte outside the body.
4. **Undownloaded iCloud files (gap #3):** In `FileStorageService.readAllNotes`, during enumeration, collect hidden files matching `^\.(.+)\.icloud$` whose inner name's extension is allowed (the enumerator must **not** use `.skipsHiddenFiles` for this; instead filter hidden files manually: skip names starting with `.` unless they match the placeholder pattern, and still skip `.git`, `.obsidian`, `.trash` directories via `skipDescendants()`). For each placeholder: `try? FileManager.default.startDownloadingUbiquitousItem(at: realURL)` where realURL = sibling without the dot/suffix, and return the list to the VM as `pendingDownloads: Int`. Do this inside the existing coordinated enumeration. Keep the `isDataless` skip for macOS-style dataless files. Expose `NotesViewModel.pendingDownloadCount` and show "Downloading {n} notes…" in the drawer footer; `IOSFolderMonitor` already reconciles each as it lands.
   - Guard: on macOS the enumerator behavior must not change — gate the placeholder handling with `#if os(iOS)` or a `handlesICloudPlaceholders` init flag defaulting false; iOS passes true.
5. **Line endings:** CRLF bodies must display and save without converting (verify; Core reads as-is).
6. **Filenames:** iOS-created titles go through `Note.sanitizedFilename` (Core) — same as Mac; `/` and `:` handled. Verify a title with `:` created on iOS shows correctly on Mac.
7. **Tags:** frontmatter only on iOS (Finder tags are not readable on iOS — expected; documented in `IOS_PORT_PLAN.md`). Tags written by Mac with Finder-tag mirroring are also in frontmatter, so they appear.
8. **Conflicts:** existing `NSFileVersion` conflict flow + `ConflictView` — reachable from drawer footer and banner.

### 7.4 Export / import parity (small Core change)
In `ImportExportService.swift`, widen RTF + HTML-attributed guards from `#if canImport(AppKit)` to `#if canImport(AppKit) || canImport(UIKit)` for `exportAsRTF` and `importRTFData` / `convertRTFToPlainText` only (`NSAttributedString` RTF document types exist on UIKit). Leave Word/RTFD/webarchive/PDF AppKit-only. Add an iOS-compiled test path (see §11.1 — core tests run on an iOS simulator destination too).
"Import…" in drawer header overflow: `fileImporter` for `.plainText, .rtf, .html, .markdown` → `ImportExportService.importFile` → `notesVM.importNote`.

---

## 8. Required macOS changes (minimal, isolated)
Only these, in `nvEnvy/nvEnvy/AppState.swift`:
1. In the `allowedExtensions` `didSet` and once at launch: `NSUbiquitousKeyValueStore.default.set(allowedExtensions, forKey: "allowedExtensions")`.
2. Leave the existing `lastPickedNotesFolderPath` KVS write (line ~506) as is.
No other Mac change. Mac does **not** adopt the ubiquity container in this pass (it can already open that folder via its folder chooser). **(open)** Future: add a "Use iCloud Drive › nvEnvy" button in Mac Preferences.

---

## 9. Preferences added to `IOSPreferences`
| Key (`nvenvy.iOS.` prefix) | Type | Default |
|---|---|---|
| `launchBehavior` | `.blankNote / .lastNote` | `.blankNote` |
| `blankAfterMinutes` | Int | 15 |
| `counterMode` | `.words/.chars/.both/.hidden` | `.words` |
| `previewLines` | Int 0–3 | 2 |
| `showTagsInList` | Bool | false |
| `drawerPinnedOnIPad` | Bool | true |
| `allowedExtensions` | [String] | Core defaults |
| `followMacFileTypes` | Bool | true |
| `storageLocation` | `StorageLocation` (Codable JSON) | nil → onboarding |

Settings screen restructure (`SettingsView.swift`): sections **Storage** (→ `StorageSettingsView`), **Editor** (font, size, appearance, editing toggles — existing), **Notes List** (preview lines, show tags, sort default, confirm deletion), **Launch** (launch behavior, blank-after), **About**.

---

## 10. Implementation order (each step builds & passes tests before the next)
1. **Core:** `Note.cachedPreview` + tests; `NotesViewModel.createNote(title:body:)`, `setAllowedExtensions` + tests; placeholder detection in `readAllNotes` (iOS-gated) + tests; RTF guard widening. `swift test --parallel` green.
2. **Storage:** `StorageLocation`, `StorageLocationResolver`, entitlements/plist, monitor scope, migration of existing bookmark. App still uses old UI — verify existing users still load.
3. **Drawer shell:** `DrawerState`, `RootView`, `DrawerView` with old list content moved into `NoteRow`; button open/close only.
4. **Gestures:** `EdgePanInstaller`, interactive open/close, keyboard dismissal, RTL.
5. **Search bar parity** (§4) incl. hardware keys and `onNoteCommitted` close.
6. **Editor screen + scratch note** (§2a, §2d), word counter, launch behavior.
7. **Info sheet, chips, bookmarks, tag sheet, footer, conflicts entry.**
8. **Settings:** Storage, File Types, new prefs; first-launch rewrite.
9. **Mac KVS write** (§8).
10. **Delete old views**, `xcodegen generate`, full test pass (§11), screenshots.
Commit after each step with a descriptive message. Do not bump marketing version (owner does that in release).

---

## 11. Testing & verification

### 11.1 Automated — Core (must pass, CI)
```bash
cd NvEnvyCore && swift test --parallel
# Also compile + run Core tests for iOS (catches UIKit-guard mistakes):
xcodebuild test -scheme NvEnvyCore -destination 'platform=iOS Simulator,name=iPhone 16' -skipPackagePluginValidation
```
New tests (add to existing files):
- `NoteCacheTests`: preview rules (§3).
- `NotesViewModelTests`: `createNote(title:body:)` writes file with exact body, unique filename on collision (`Beer.md` exists → `Beer 2.md` per `uniqueFilename` scheme), doesn't change selection; `setAllowedExtensions` → after reload a `.txt`-only vault shows/hides notes accordingly; Return semantics unchanged (exact → prefix → create) — existing tests cover, keep green.
- `FileStorageServiceTests`: placeholder `.Foo.md.icloud` counted as pending and not as a note; `.Foo.png.icloud` ignored; `.obsidian/` skipped; macOS path unaffected.
- `ImportExportServiceTests`: RTF export/import round-trip compiles & passes on iOS destination.
- `SearchEngineTests`: add a **parity fixture** test — fixed 30-note corpus, 15 queries (single token, multi-token, quoted phrase, tag text, unicode/diacritics, prefix-of-title, empty) with expected ordered titles. This file is the contract the Mac and iOS both satisfy.

### 11.2 Fixture vault (create `NvEnvyCore/Tests/Fixtures/ParityVault/` + script)
Contents: `Beer.md` (body starts `# Beer`), `Christmas presents 2026.md`, `Daily/2026-11-05.md` (subfolder), `notes.txt`, `legacy.text`, `outline.mmd`, `readme.markdown`, `cp1252.txt` (Windows-1252 bytes "café"), `utf16.md` (UTF-16LE BOM), `crlf.md` (CRLF), `obsidian.md` (frontmatter with `aliases`, `tags`, custom key), `image.png` (must be ignored), `.obsidian/workspace.json` (ignored), `Title: colon.md` (if filesystem allows; else `Title- colon.md`), a 2 MB note, and 2,000 generated small notes (`scripts/gen_fixture.sh` — generated, not committed).
Expected note count = 11 + 2,000 (+ colon file).

### 11.3 Automated — iOS UI tests (new target)
Add an `nvEnvyiOSUITests` target to `project.yml` (`type: bundle.ui-testing`, platform iOS, `dependencies: [target: nvEnvyiOS]`) and add it to the `nvEnvyiOS` scheme's `test` action. Support launch args in the app:
- `-uiTestVault <path>`: bypass onboarding, use `.onDevice`-style attach to a copy of the fixture vault copied into the app sandbox at launch (copy from the test bundle).
- `-uiTestReset`: wipe defaults.
Add `accessibilityIdentifier`s: `drawer`, `drawer.search`, `drawer.close`, `noteRow.<filename>`, `editor.text`, `editor.openDrawer`, `editor.new`, `editor.info`, `editor.counter`, `createRow`.

Test cases:
1. **Notes load:** launch with fixture → open drawer → assert footer reads "{expected} notes" and rows `Beer`, `2026-11-05`, `notes`, `legacy`, `outline`, `readme`, `cp1252`, `utf16`, `crlf`, `obsidian` exist; `image` does not.
2. **Preview:** `Beer` row preview does not start with "Beer".
3. **Open via button focuses search:** tap `editor.openDrawer` → `drawer.search` has keyboard focus.
4. **Edge swipe opens without focus:** `coordinate(withNormalizedOffset: (0.0, 0.5))` press-drag to (0.6, 0.5) → drawer visible, keyboard not shown.
5. **Swipe/scrim close:** swipe left on drawer → hidden; open again, tap scrim → hidden.
6. **Search parity:** type each parity query → read visible row titles in order → equal to the `SearchEngineTests` fixture expectations (shared JSON file `ParityQueries.json` used by both tests).
7. **Return opens prefix match:** type `chris` → Return → editor shows "Christmas presents 2026" body; drawer closed.
8. **Create row:** type `brand new note` → tap `createRow` → file `brand new note.md` exists in sandbox vault; editor focused.
9. **Scratch note:** cold launch (`launchBehavior=blankNote`) → type "Groceries\nmilk" → wait 2 s → open drawer → row `Groceries` exists; continue typing → caret didn't jump (assert `editor.text` value ends with typed suffix).
10. **Background commit:** type in scratch → `XCUIDevice.shared.press(.home)` → relaunch → note exists with full text.
11. **Delete + rename + tags** via swipe/context menu; file renamed/removed on disk.
12. **Hardware keys** (iPad sim): ⌘L opens + focuses; ⌘J/⌘K changes note; Esc clears then closes.
13. **File types:** Settings → File Types → remove `txt` → `notes` row disappears; Reset → returns.
14. **Encodings round-trip:** open `cp1252`, append "x", background app; test reads file bytes → still Windows-1252, ends with "x".
15. **Performance:** `measure(metrics: [XCTClockMetric()])` cold launch to first row visible with 2,000-note vault: < 1.5 s on iPhone 16 simulator; drawer open animation hitch-free (`XCTOSSignpostMetric.scrollingAndDecelerationMetric` on list scroll).

Run:
```bash
cd nvEnvy && xcodegen generate
xcodebuild test -project nvEnvy.xcodeproj -scheme nvEnvyiOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  CODE_SIGNING_ALLOWED=NO
```

### 11.4 CI
Add a job `ios-build-test` to `.github/workflows/ci.yml` (runner `macos-15`): install XcodeGen → generate → `xcodebuild build` the `nvEnvyiOS` scheme for `generic/platform=iOS Simulator` with `CODE_SIGNING_ALLOWED=NO` → run UI tests on iPhone 16 sim. Keep the existing jobs untouched. (Entitlements with iCloud containers are ignored when signing is disabled — fine for CI.)

### 11.5 Manual device QA (owner runs; agent writes this checklist into the PR description)
Two devices: Mac (nvEnvy 1.3.x) + iPhone (TestFlight/dev build), same Apple ID.
1. **Fresh install, iCloud default:** onboarding → "Keep notes in iCloud Drive" → create note "Sync test A" → within 60 s it appears on Mac after pointing Mac at iCloud Drive › nvEnvy; in Files app it's under iCloud Drive › nvEnvy.
2. **Existing Mac vault:** on Mac pick a folder in iCloud Drive with ≥500 notes incl. `.txt` and subfolder notes and a custom extension (add `org` in Mac prefs). iPhone fresh install → hint shown → open folder → **note count matches Mac exactly**; `.org` notes appear (Match my Mac on).
3. **Undownloaded files:** on iPhone, Files › long-press the vault folder › Remove Download; relaunch app → footer shows "Downloading n…", count converges to Mac's count without user action.
4. **Live sync both ways:** edit on Mac → appears on iPhone while app open (< 30 s); edit on iPhone → appears on Mac.
5. **Conflict:** airplane-mode iPhone, edit same note on both, reconnect → conflict banner → resolve → both devices show the chosen text.
6. **Kill safety:** type quickly, immediately swipe app away → relaunch → last characters present.
7. **Storage switch:** Settings › Storage → On My iPhone → "Move notes" → count identical, iCloud copy untouched.
8. **iCloud signed out:** Settings app → sign out iCloud → reopen → clear banner, no crash, no data loss.
9. **Gesture feel:** edge swipe works while keyboard is up, while text is selected, and doesn't fire when a sheet is up; list scroll never triggers close.
10. **Dynamic Type XXXL, VoiceOver, Dark mode, RTL (Arabic) locale, iPad Split View/Stage Manager widths, landscape.**
11. **Search parity spot check:** same 10 queries on Mac and iPhone produce the same top results in the same order.

---

## 12. Acceptance criteria (definition of done)
- [ ] App launches into a clean, full-screen editor (blank note by default); no list visible.
- [ ] Drawer opens via top-left button (search focused) and left-edge swipe (not focused); closes via scrim tap, swipe left, selection, Return.
- [ ] Rows show title, ≤2 preview lines (title duplicate removed), date footer matching sort field.
- [ ] Search results/order identical to macOS for the parity fixture; Return/Create/⌘Return/Esc semantics identical.
- [ ] Storage screen offers iCloud Drive (default), Files folder, On My iPhone; switching works with Move/Just switch; existing installs unaffected.
- [ ] iOS loads every extension the Mac loads (defaults + Mac custom via KVS), subfolders, all encodings, and undownloaded iCloud files converge automatically.
- [ ] No regression in data-safety behavior (flush on background, WAL, coordinated IO).
- [ ] `swift test --parallel` green; iOS UI tests green on iPhone + iPad simulators; CI job added.
- [ ] Old `RootSplitView`/`NoteListView`/`NoteEditorView` deleted; no dead code; all new strings in `Localizable.xcstrings`.
- [ ] Accessibility: every control labeled; drawer is an accessibility modal (`.accessibilityAddTraits(.isModal)` when overlay), VoiceOver escape (two-finger Z) closes it.

## 13. Risks & mitigations
| Risk | Mitigation |
|---|---|
| Edge-pan vs `UITextView` pan/selection gestures | `require(toFail:)` on text view pan; test with selection handles near left edge. |
| Ubiquity container needs portal setup | Flag in PR; app still works via Files/On-device if container missing (resolver returns nil → banner). |
| Scratch→note switch resets the text view | Set `coordinator.currentNoteID` before re-render; UI test #9. |
| Large vaults + drawer animation jank | Rows read only cached fields; no body access; measure (#15). |
| Placeholder handling changes macOS load | iOS-gated flag; macOS tests unchanged. |
| Third-party providers (Dropbox) don't emit metadata updates | Documented; foreground reconcile + pull-to-refresh. |
