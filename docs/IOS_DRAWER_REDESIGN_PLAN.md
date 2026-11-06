# nvEnvy iOS — Drawer Redesign Plan (v2 UI)

> **Audience:** an implementing agent with zero prior context. Read this whole document before writing code. Every decision here is final unless marked **(open)**. When this plan and existing code comments disagree on *UI*, this plan wins; on *data safety / perf* behavior, the existing code comments win — preserve them.

---

## 0. TL;DR

Replace the iOS `NavigationSplitView` (list → push editor) with a **single full-screen, chrome-light editor** plus a **left drawer** holding search + the note list. The drawer opens from a top-left button or an edge swipe from the left, and slides in over the editor. Search behaves exactly like macOS (same engine, same Return semantics). Add a **Storage** settings screen (iCloud Drive › nvEnvy as the default for brand-new users, a Files folder, or On My iPhone) and make iOS read **the same file types** as the Mac.

Keep: everything in `NvEnvyCore`, `nvEnvyiOS/Editor/*`, `nvEnvyiOS/Storage/*`, `IOSPreferences`, `ConflictView`, `TagEditorSheet`, `BookmarksSheet`, `FontResolver`, the scene-phase/flush lifecycle in `nvEnvyiOSApp.swift`.
Replace: `UI/RootSplitView.swift`, `UI/NoteListView.swift`, `UI/NoteEditorView.swift` chrome, `Onboarding/FirstLaunchView.swift`, `Settings/SettingsView.swift` (restructure).

**Delivery:** everything in this document ships as **one PR** on one branch, built in the stage order of §10 (A → B → C → D) with a commit per step. Each stage must build and pass tests before the next begins, so the branch is never broken mid-way.

---

## 0.1 Decision log (owner review, 2026-11-06) — read this first

These decisions were made after review of the first draft and override anything older. They are already reflected in the sections below; this list exists so you understand *why*.

| # | Decision | Where |
|---|---|---|
| D1 | One PR, staged internally A (file parity) → B (drawer) → C (editor/scratch) → D (storage). Storage is last because it is the riskiest change; A–C work on the existing folder-bookmark storage. | §10 |
| D2 | **No idle auto-commit** of the scratch note. Commit only on explicit events (drawer open, `+`, ⌘N/⌘L, selecting another note, backgrounding). | §2d |
| D3 | Scratch text is persisted continuously to an **app-private recovery draft** (not the vault) so a hard kill never loses text and never creates junk notes. | §2d.1 |
| D4 | **Never create `Untitled …` files.** If the scratch text has no usable title line, it stays a draft. | §2d |
| D5 | A newly committed note's title is **provisional** until the editor first loses focus; one automatic rename is allowed if the first line changed. After that, title is fixed (rename via Info). | §2d.2 |
| D6 | Default `launchBehavior` is **`.lastNote`** (today's behavior). `.blankNote` is an opt-in setting. | §2d, §9 |
| D7 | **Edge-swipe is spiked first** (§10 step B0) on a physical device before building the rest of the drawer. Edge zone is 20pt. Documented fallback if it fights text selection. | §2c |
| D8 | **iPad pinned sidebar is deferred.** Drawer is an overlay on iPhone and iPad alike. No pin button, no `drawerPinnedOnIPad` pref, no ⌘⇧C pin toggle. | §2b, §5, §9 |
| D9 | **`Aa` popover is cut** from this pass. Font/size/appearance stay in Settings. | §2a, §5 |
| D10 | File types: iOS follows the Mac's list via KVS (fallback: Core defaults). **No editable File Types screen** in this pass — Settings shows a read-only row listing active extensions. | §7.2 |
| D11 | iCloud Drive › nvEnvy is the default **only for new users with no Mac folder hint**. A Mac hint makes "Open your Mac notes folder" primary. Existing installs are untouched. | §6.6 |
| D12 | The iCloud container `iCloud.com.nvenvy.app` **already exists** in the Apple Developer portal (owner confirmed). Still verify it end-to-end in stage D (§10 D0). | §6.2 |
| D13 | UI tests: a **required core set** runs in CI; the remaining scenarios are covered by the manual QA checklist. Performance is a manual check, not CI. | §11 |

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
│ [↩︎ snapback]                       [⚙︎]    │  ← bottom bar, only when keyboard hidden
└───────────────────────────────────────────┘
```
- **Top-left `[≡]`** (`sidebar.left`): opens drawer **and focuses search** (keyboard up). Accessibility: "Notes and search".
- **`[+]`** (`plus`): new blank note (§2d). Long-press → menu: "New Note", "New from Clipboard".
- **Word/char counter** (right side, `.footnote`, `.secondary`, monospaced digits): shows `"{w}w"`; tap cycles `w → c → w+c → hidden` (persist in prefs `counterMode`). Selection active → counts the selection.
- **`[ⓘ]`** (`info.circle`): Note Info sheet (§2f). Disabled (dimmed) when blank scratch note.
- **Bottom bar** (hidden while keyboard is up; the existing `EditorAccessoryView` covers that state): snapback button (only when `notesVM.hasSnapback`), `⚙︎` → Settings sheet. (No `Aa` quick-type popover in this pass — D9; font/size/appearance live in Settings › Editor.)
- No navigation title. No separators. Background `.systemBackground`. Top/bottom bar icons `.tint` at 70% opacity; disabled `.tertiary`.
- iPad regular width: text column max width 720pt, centered.

### 2b. Drawer (search + list)
```
┌──────────────────────────────┬────┐
│ [+]  Sort: Modified ▾  […][✕]│░░░░│  ← header ([…] = overflow: Import…)
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
- **Geometry:** iPhone width = `min(screenWidth * 0.86, 420)`. iPad (all size classes): 380pt overlay. The drawer is **always an overlay** with a scrim — no pinned/persistent sidebar mode in this pass (D8). Do not add pin state, but keep `DrawerView` free of overlay-specific assumptions (it takes its width as a parameter) so pinning can be added later.
- **Motion:** slides from x = -width to 0, scrim opacity 0 → 0.25 black. Spring `response: 0.32, dampingFraction: 0.86`. Respect Reduce Motion → 0.15 s cross-fade, no slide.
- **Open triggers:** (1) `[≡]` button → open + focus search; (2) left-edge swipe on editor → open interactively, finger-tracked, **no** search focus; (3) ⌘L → open + focus search + select all text in field. (⌘N does **not** open the drawer; it starts a new blank note — §2g. An earlier draft said otherwise; §2g wins.)
- **Close triggers:** tap scrim; swipe left on drawer (interactive); `[✕]`; selecting a note; Return in search (after commit); Escape with empty query; ⌘L again does **not** close.
- **Header:** `[+]` new blank note; "Sort: {field} ▾" menu (Title / Date Modified / Date Created / Tags + Ascending/Descending — bind to `prefs.sortField/sortAscending` and mirror into `notesVM` exactly like today's `sortMenu`); overflow `…` menu (Import… — §7.4); close.
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
SwiftUI has no screen-edge pan, and `UITextView`'s own pan must not steal the swipe. This is the highest-UX-risk piece, so it is **built first as a spike** (§10 step B0) before the rest of the drawer.

**Spike (B0) — do this before anything else in stage B:**
- Build only `EdgePanInstaller` + `DrawerState` + a placeholder drawer (a colored rectangle) over the **real** `NoteUITextEditor` with a long note loaded.
- Verify on a **physical iPhone** if one is attached to the build machine (`xcrun devicectl list devices`); otherwise on the simulator, and write in the PR description "edge-swipe verified on simulator only — owner must verify on device" as a top-of-checklist item.
- Pass criteria: (a) swipe from the left edge opens the drawer with the keyboard up, keyboard down, and with a text selection active; (b) long-press-to-select and selection-handle drags within 30pt of the left edge still work; (c) the caret can still be placed at the start of a line by tapping; (d) vertical scrolling of the text view never opens the drawer.
- **Fallback if (b) or (c) fails:** restrict recognition to touches whose start point is in the **top two-thirds** of the editor (reject in `gestureRecognizerShouldBegin` based on `location(in:)`), and re-test. If it still fails, ship with the edge swipe disabled behind `IOSPreferences.edgeSwipeOpensDrawer` (default false), keep `[≡]` as the primary entry, and note it in the PR description. Either way, `[≡]` is always present.
- Commit the spike as its own commit, then build the real drawer on top of it.

Implementation:
1. New file `UI/Drawer/EdgePanInstaller.swift`: a `UIViewRepresentable` placed as a zero-size background of the root that, in `didMoveToWindow`, adds a `UIScreenEdgePanGestureRecognizer(edges: .left)` to the **window's root view** (store weakly; remove on dismantle). Only touches starting within **20pt** of the leading edge may begin the gesture (check `location(in:).x <= 20` in `gestureRecognizerShouldBegin`; the system edge recognizer's own zone is wider on some devices).
2. Its delegate: `gestureRecognizerShouldBegin` → false when drawer already open, when a sheet is presented, or when `edgeSwipeOpensDrawer` is false. `shouldRecognizeSimultaneouslyWith` → false. `shouldBeRequiredToFailBy other` → return `true` when `other` is the editor `UITextView`'s `panGestureRecognizer` (so the edge pan wins).
3. Translation drives a shared `DrawerState.progress` (0…1, `@Observable`). On `.ended`: open if `progress > 0.35` or velocity.x > 500, else close; animate remainder with the spring above.
4. Closing swipe: a SwiftUI `DragGesture(minimumDistance: 12)` on the drawer panel **and** scrim, horizontal-only (ignore if `abs(dy) > abs(dx)` so list scroll works), driving `progress` the same way.
5. RTL: mirror edges (`.right`) when `layoutDirection == .rightToLeft` (the 20pt zone is then measured from the right edge).
6. Haptic: `UIImpactFeedbackGenerator(.light)` once on open commit.
7. Dismiss the keyboard (`resignFirstResponder` on editor) as soon as an open gesture begins.

### 2d. New note & the blank "scratch" note
The editor is never "empty with a placeholder screen" — when nothing is selected it shows a **blank scratch note** you can type into.
- **State:** `ScratchNote` (app-layer, `@MainActor @Observable`): `text: String`, `provisionalNoteID: Note.ID?` (§2d.2). Not in the vault.
- Editor shows scratch when `selectedNoteID == nil`. Typing goes into `scratch.text`.
- **Title derivation** — `static func deriveTitle(_ text: String) -> String?`: walk lines lazily; for each non-blank line, trim, strip leading Markdown markers (`#{1,6}`, `>`, `- [ ]`, `- [x]`, `-`, `*`, `+`, `1.`) and whitespace, collapse `[[x]]` → `x`, then run Core's `Note.sanitizedFilename`. The first line that yields a non-empty result wins; truncate to 80 chars on a word boundary (hard cut at 80 if no boundary). If no line yields a non-empty result → return `nil`. **Never** synthesize an `"Untitled …"` title (D4).
- **Commit to the vault** only on these explicit events (D2 — there is **no idle timer**), and only when `deriveTitle(scratch.text) != nil`:
  1. the drawer opens (button, edge swipe, ⌘L);
  2. `[+]` tapped or ⌘N;
  3. another note is selected (row tap, ⌘J/⌘K, wikilink, URL scheme);
  4. scene phase → `.inactive` or `.background`.
- If an event fires and `deriveTitle` is `nil` (e.g. the text is only `# ` or `- [ ]`), do **not** commit: the text stays in the scratch + recovery draft (§2d.1) and is shown again the next time the scratch is visible. `[+]`/⌘N with an uncommittable non-empty scratch just focuses the scratch (never discard text).
- Commit = `notesVM.createNote(title:body:)` (new Core API, §7.1) with `body = scratch.text` (full text, first line included — matches what a Mac user sees; no data loss). `createNote` uses `uniqueFilename`, so a colliding title gets the Core collision suffix.
- After commit: `selectedNoteID = newID`, `scratch.provisionalNoteID = newID`, `scratch.text = ""`, clear the recovery draft. The editor continues seamlessly (same text, caret preserved — pass the current `selectedRange` and set `note.selectedRange`). Subsequent edits go through `updateNoteBody`.
- `[+]` / ⌘N: commit scratch if committable, then `selectedNoteID = nil`, fresh empty scratch, clear search query, focus editor (keyboard up).
- **Launch behavior** (pref `launchBehavior`, D6): `.lastNote` (**default** — today's behavior: restore `lastSelectedNoteID` via the existing logic in `nvEnvyiOSApp.swift`; if none or it no longer exists → scratch) or `.blankNote` (opt-in: always start on a fresh scratch). With `.blankNote` only: if the app returns to foreground after > `blankAfterMinutes` (default 15, 0 = never) in the background, show a fresh scratch.
- **Recovery overrides launch behavior:** if a non-empty recovery draft exists at launch (§2d.1), show the scratch with that text regardless of `launchBehavior`.

#### 2d.1 Recovery draft (D3) — crash/kill safety without junk notes
- File: `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]/nvEnvy/ScratchDraft.json` (create the directory; this is **not** the vault and not visible in Files). Contents: `{"text": String, "updatedAt": ISO8601 date}`.
- Write on every `scratch.text` change, debounced **300 ms**, atomic write (`Data.write(to:options: .atomic)`), off the main actor. Also write **synchronously** at the start of the `.inactive/.background` handler, *before* attempting the commit, so text survives even if the commit or the background task is cut short.
- Clear (delete the file) only **after** `createNote` returns a non-nil ID.
- At launch, if the file exists and `text` is non-whitespace: restore into `scratch.text`. **Duplicate guard:** if any loaded note's `body` equals the draft text exactly (the app was killed between commit and clear), delete the draft instead of restoring it. Run this check after the initial load completes (`onInitialLoad`).
- Unit-test `ScratchDraftStore` (write/read/clear/duplicate-guard) in an app-level test or by putting the pure logic in a small type that takes a directory URL.

#### 2d.2 Provisional title (D5)
The title is derived the moment the note is committed — often from a half-typed first line. Allow **one** automatic correction:
- While `scratch.provisionalNoteID == note.id`, the title is provisional.
- At the **first focus-loss after the commit** — the editor's `textViewDidEndEditing` that follows at least one edit made after the commit, or selecting another note, or backgrounding — compute `deriveTitle(note.body)`. If non-nil and different from `note.title`, call `notesVM.tryRenameNote`. On any error (collision, filesystem), keep the existing title silently. Then set `provisionalNoteID = nil`.
- Also set `provisionalNoteID = nil` (without renaming) if the user renames manually via Info, or deletes the note.
- After that the title is fixed (title = filename on the Mac; repeated churn would break wikilinks). Further renames go through Info.
- Note: a commit triggered by opening the drawer will usually be followed by the user closing the drawer and continuing to type in the same note — that continued session is exactly what the provisional rename is for.

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
| ⌘⇧C | Toggle drawer open/closed (no pin mode — D8) |
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
| `DrawerState.swift` | `@MainActor @Observable final class DrawerState { var progress: CGFloat; var isOpen: Bool { progress == 1 }; var focusSearchOnOpen: Bool; var onWillOpen: (() -> Void)?; func open(focusSearch:) ; func close() }`. `onWillOpen` is how the root commits the scratch note (§2d trigger 1) — call it once when an open begins (button, ⌘L, or edge-pan `.began`). No pin state (D8). |
| `RootView.swift` | Replaces `RootSplitView`. `ZStack(alignment: .leading)`: `EditorScreen` → scrim (`Color.black.opacity(0.25 * progress)`, tap closes) → `DrawerView(width:)` (offset `-(1-progress)*width`). Hosts `EdgePanInstaller`, `onNoteCommitted` hook, root key commands, sheets (Settings, Info, Conflicts). |
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
| `ScratchNote.swift` | §2d model, `deriveTitle`, `commitIfPossible() async`, provisional-title logic (§2d.2). |
| `ScratchDraftStore.swift` | §2d.1 recovery draft: `write(_:)` (debounced), `writeNow(_:)`, `load() -> String?`, `clear()`. Takes the directory URL in `init` so it's testable. |
| `WordCounter.swift` | Pure function `count(_ text: String) -> (words, chars, lines)` using `enumerateSubstrings(.byWords)`; run off-main for > 50 k chars, debounced 300 ms. |
| `NoteInfoSheet.swift` | §2f. |

(No `QuickTypePopover` — D9.)

**Editor for scratch:** generalize `NoteUITextEditor` to take a `EditorSource` enum (`.note(Note)` / `.scratch(ScratchNote)`). In `EditorCoordinator.textViewDidChange`, route to `notesVM.updateNoteBody` or `scratch.text = …`. When scratch commits, switch source to `.note` **without** resetting `textView.text` (set `coordinator.currentNoteID = newID` before SwiftUI re-renders so `isNoteSwitch` is false). This is the one subtle bit — write a UI test for caret continuity (§11.3).

Delete after migration: `UI/RootSplitView.swift`, `UI/NoteListView.swift`, `UI/NoteEditorView.swift`. Run `xcodegen generate` (sources are folder-globbed; no yml edit needed for new Swift files).

`nvEnvyiOSApp.swift` changes: replace `RootSplitView()` with `RootView()`; inject `DrawerState`, `ScratchNote`; on `.background/.inactive`, inside the **existing** background task and in this order: (1) `ScratchDraftStore.writeNow(scratch.text)` synchronously, (2) `await scratch.commitIfPossible()`, (3) provisional-title check (§2d.2), (4) the existing `flushBeforeQuit()`. Implement `launchBehavior` and recovery-draft restore (§2d.1) next to the existing `lastSelectedNoteID` restore.

---

## 6. Storage location ("where sync is done") — iCloud by default

### 6.1 Decision
Three location kinds, persisted as `StorageLocation` (Codable, in `UserDefaults` key `nvenvy.iOS.storageLocation`):
```swift
enum StorageLocationKind: String, Codable { case iCloudApp, folder, onDevice }
```
1. **iCloud Drive › nvEnvy** (`.iCloudApp`) — **default only for new users with no Mac folder hint** (D11; see §6.6). This is a **new, separate folder** — it does not contain any notes the user already has elsewhere in iCloud Drive. All UI copy that offers it must say so. App ubiquity container `iCloud.com.nvenvy.app`, `Documents/` subfolder, published to iCloud Drive as a folder named "nvEnvy". Zero pickers. The Mac can open the same folder via its existing folder chooser (it appears in Finder under iCloud Drive › nvEnvy).
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
**Portal status (D12):** the owner has **already created** the iCloud container `iCloud.com.nvenvy.app` in the Apple Developer portal. Do not ask about it or flag it as a prerequisite. You must still verify it works end-to-end as the first step of stage D (§10 D0):
1. Add only the entitlements + `project.yml` keys above, `xcodegen generate`, and build the `nvEnvyiOS` scheme **with signing enabled** (automatic signing, team `B35T5FY8RZ`) for a generic iOS device: `xcodebuild -project nvEnvy.xcodeproj -scheme nvEnvyiOS -destination 'generic/platform=iOS' -allowProvisioningUpdates build`.
2. If it fails with a provisioning error mentioning the container or the App ID `com.nvenvy.app.ios`, **stop stage D**, leave the entitlement commit in place, and put the exact error at the top of the PR description as a blocker for the owner (most likely the container isn't yet enabled on that App ID's iCloud capability). Stages A–C must still be complete and shippable.
3. If it succeeds, confirm `FileManager.default.url(forUbiquityContainerIdentifier:)` returns non-nil at runtime (log it once in DEBUG builds, on a simulator signed into iCloud if available). Note the result in the PR description.
4. Bump `CFBundleVersion` is the owner's job at release (iCloud Drive only republishes the container folder after a build-number change) — mention it in the PR description; do not bump it yourself.

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
- **Migration of existing installs:** if `NotesFolderProvider.bookmarkKey` exists and no `storageLocation` saved → set `.folder`. Existing users see zero change — no onboarding, no prompt, same folder. This migration runs before any onboarding decision. Unit-test the migration decision as a pure function `initialLocation(savedLocation:hasLegacyBookmark:) -> StorageLocation?`.

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
- **File Types** row — **read-only** (D10): shows the active extensions as text (e.g. "md, markdown, mmd, txt, text") with a footnote "Matches your Mac" when the list came from KVS, or "Default" otherwise. Not tappable. No editor screen in this pass.
- **Mac hint** row (when KVS `lastPickedNotesFolderPath` exists and differs from current): "Your Mac uses '{name}'. Open it…" → Files picker pre-navigated (reuse `FirstLaunchView.startingDirectory` logic).
- "Reload All Notes" button → `reconcileFilesystem()`.

### 6.6 First launch (rewrite `Onboarding/FirstLaunchView.swift`)
Shown only when §6.3 migration yields no location (true new install). Order of checks:
- **If KVS hint exists** (`lastPickedNotesFolderPath`, i.e. this user has the Mac app) → primary button **"Open your Mac notes folder ('{name}')"** (Files picker, pre-navigated via existing `startingDirectory` logic), secondary **"Start a new folder in iCloud Drive"** with subtitle *"Creates iCloud Drive › nvEnvy. Your Mac notes won't be in it unless you point the Mac app there."*
- **Else if iCloud available** → primary **"Keep notes in iCloud Drive"** with subtitle *"Creates a new nvEnvy folder in iCloud Drive. To use it on your Mac, choose the iCloud Drive › nvEnvy folder as your notes folder in nvEnvy for Mac."* (one tap, no picker). Secondary "Choose a folder…" with subtitle *"Use an existing folder, e.g. your Obsidian vault or Dropbox."* Tertiary text button "Keep on this iPhone only".
- **Else** → "Choose a folder…" / "Keep on this iPhone only" + note "iCloud is off — turn it on in Settings to sync."
- All strings go in `Localizable.xcstrings`. Use "iPhone"/"iPad" per `UIDevice.current.userInterfaceIdiom`.
- Keep `NSUbiquitousKeyValueStore.default.synchronize()` on appear, and also observe `NSUbiquitousKeyValueStore.didChangeExternallyNotification` to update the hint live.

---

## 7. File-type & sync parity with macOS

### 7.1 Core API additions (`NotesViewModel`)
```swift
public func createNote(title: String, body: String) async -> Note.ID?   // uses NoteStore.addImportedNote(title:body:tags: []), appends, performSearch, returns id; does NOT change selection
public func setAllowedExtensions(_ exts: [String])                       // normalizes (lowercase, strip dots, dedupe, non-empty), updates storage, triggers full reload
```
`setAllowedExtensions` needs `FileStorageService.allowedExtensions` to be settable from the VM (it's a `var` on the actor — add `func setAllowedExtensions(_:)` on the actor) then `reconcileFilesystem()`. Unit-test both.

### 7.2 Allowed extensions — identical defaults, follow the Mac (D10)
- Defaults: `["md", "markdown", "mmd", "txt", "text"]` (= `FileStorageService.defaultAllowedExtensions` and Mac `AppState` default). Use the Core constant, don't duplicate the literal.
- **Mac → iOS sync:** the Mac writes its list to KVS key `allowedExtensions` (§8). iOS computes the **effective set** = the KVS value if it is a non-empty `[String]` (normalized: lowercase, strip leading dots, drop empties, dedupe), else the Core defaults. Put this in a small pure function `effectiveAllowedExtensions(kvsValue: Any?) -> (exts: [String], fromMac: Bool)` and unit-test it (missing, wrong type, empty array, mixed case/dots, valid).
- Re-apply on `NSUbiquitousKeyValueStore.didChangeExternallyNotification`: if the effective set changed, call `notesVM.setAllowedExtensions(_:)` (§7.1).
- Pass the effective set into `notesVM.attach(folderURL:allowedExtensions:coordinator:onInitialLoad:)` — currently iOS does **not** pass it (it silently uses Core defaults). Fix this in stage A.
- **No** iOS-side editable list, no `followMacFileTypes` toggle, no `FileTypesView` in this pass. Settings shows a read-only row (§6.5). **(open)** A future pass can add an editor if someone asks.
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
Only these, in `nvEnvy/nvEnvy/AppState.swift` (ships in stage A):
1. Add a private helper `publishAllowedExtensionsToICloud()` that does `NSUbiquitousKeyValueStore.default.set(allowedExtensions, forKey: "allowedExtensions")`. Call it from the existing `allowedExtensions` `didSet` (≈ line 218, after the `UserDefaults` write) and once at the end of `init` (didSet doesn't fire from init — same reason the init already pushes `notes.allowedExtensions` by hand, ≈ line 422).
2. Leave the existing `lastPickedNotesFolderPath` KVS write (≈ line 506) as is.
3. **Write-only.** The Mac never reads this key back; the Mac's own `UserDefaults` value stays the source of truth. So there is no behavior change on the Mac.
4. The `nvEnvy-MAS` target may not have the KVS entitlement; `NSUbiquitousKeyValueStore` is a harmless no-op without it (same as the existing `lastPickedNotesFolderPath` write). Don't add entitlements to the Mac targets.
No other Mac change. `swift test --parallel` and the macOS build (`xcodebuild -project nvEnvy/nvEnvy.xcodeproj -scheme nvEnvy build CODE_SIGNING_ALLOWED=NO`) must stay green. Mac does **not** adopt the ubiquity container in this pass (it can already open that folder via its folder chooser). **(open)** Future: add a "Use iCloud Drive › nvEnvy" button in Mac Preferences.

---

## 9. Preferences added to `IOSPreferences`
| Key (`nvenvy.iOS.` prefix) | Type | Default |
|---|---|---|
| `launchBehavior` | `.lastNote / .blankNote` | **`.lastNote`** (D6) |
| `blankAfterMinutes` | Int | 15 (only used with `.blankNote`) |
| `counterMode` | `.words/.chars/.both/.hidden` | `.words` |
| `previewLines` | Int 0–3 | 2 |
| `showTagsInList` | Bool | false |
| `edgeSwipeOpensDrawer` | Bool | true (set default false only if the §2c spike fallback is triggered) |
| `storageLocation` | `StorageLocation` (Codable JSON) | nil → migration (§6.3) → onboarding |

Not added (removed in review): `drawerPinnedOnIPad` (D8), `allowedExtensions` / `followMacFileTypes` (D10 — iOS always follows the Mac via KVS).

Settings screen restructure (`SettingsView.swift`): sections **Storage** (→ `StorageSettingsView`, incl. read-only File Types row), **Editor** (font, size, appearance, editing toggles — existing; this is where the cut `Aa` popover's controls live), **Notes List** (preview lines, show tags, sort default, confirm deletion), **Launch** (launch behavior, blank-after — the latter disabled unless `.blankNote`), **Gestures** (edge swipe toggle), **About**.

---

## 10. Implementation order — one PR, five stages (D1)
Work on a new branch off `main` named `ios/drawer-redesign`. One PR at the end. **Every numbered step is its own commit**, and every commit must build (macOS + iOS) and pass `swift test --parallel`. Storage is deliberately **last**: stages A–C run on the existing folder-bookmark storage, so if stage D is blocked (§6.2), A–C are still a complete, shippable PR.

**Stage A — file parity (no visible UI change)**
- A1. Core: `Note.cachedPreview` + tests (§3).
- A2. Core: `NotesViewModel.createNote(title:body:)`, `setAllowedExtensions(_:)` + actor setter + tests (§7.1).
- A3. Core: iCloud placeholder detection in `readAllNotes` (iOS-gated) + `pendingDownloadCount` + tests (§7.3 item 4).
- A4. Core: RTF guard widening + iOS-destination test run (§7.4).
- A5. iOS: `effectiveAllowedExtensions` + pass it into `attach` + KVS change observer (§7.2).
- A6. Mac: KVS write (§8).
- A7. Fixture vault + generator script + parity JSON + `SearchEngineTests` parity test (§11.1–11.2).

**Stage B — drawer**
- B0. **Edge-swipe spike** (§2c). Record the pass/fail result for each criterion in the commit message. Apply the fallback if needed.
- B1. `DrawerState`, `RootView`, `DrawerView` shell; old list content moved into `NoteRow` (title, preview, date). Button open/close only. The old `NoteEditorView` is still the editor at this point.
- B2. Gestures: interactive open/close, keyboard dismissal, haptic, RTL.
- B3. Search bar parity (§4) incl. hardware keys and `onNoteCommitted` close.
- B4. Chip row, bookmarks, tag sheet, footer (counts, sync summary, "Downloading n…"), conflicts entry, pull-to-refresh, row swipe/context actions, Import… overflow.

**Stage C — editor screen + scratch note**
- C1. `EditorScreen` (top bar, bottom bar, counter) replacing `NoteEditorView` chrome; `EditorSource` generalization of `NoteUITextEditor`.
- C2. `ScratchNote` + `deriveTitle` + commit triggers (§2d), with unit tests for `deriveTitle`.
- C3. `ScratchDraftStore` recovery draft + launch restore + duplicate guard (§2d.1), with unit tests.
- C4. Provisional title rename (§2d.2).
- C5. `launchBehavior` / `blankAfterMinutes`; Note Info sheet (§2f); Settings restructure for the non-storage sections (§9).

**Stage D — storage**
- D0. Entitlements + `project.yml` only; verify signing/container per §6.2. **If blocked, stop stage D here** and go to stage E.
- D1. `StorageLocation`, `StorageLocationResolver`, migration of existing bookmark (with test) — app behaves identically for existing installs.
- D2. `IOSFolderMonitor` scope parameter (§6.4).
- D3. `StorageSettingsView` incl. switching with Move/Just switch and the read-only File Types row (§6.5).
- D4. First-launch rewrite (§6.6).

**Stage E — finish**
- E1. Delete `UI/RootSplitView.swift`, `UI/NoteListView.swift`, `UI/NoteEditorView.swift`; `xcodegen generate`; no dead code.
- E2. UI test target + required tests (§11.3); CI job (§11.4).
- E3. Localize all new strings; accessibility pass (§12).
- E4. Open the PR (§10.1).

Do not bump `MARKETING_VERSION` or `CFBundleVersion` (the owner does that at release).

### 10.1 PR description must contain
1. Summary of stages A–E and which (if any) were blocked, with exact errors.
2. Edge-swipe spike result (device or simulator-only) and whether the fallback was used.
3. Stage D0 container verification result.
4. The manual QA checklist (§11.5) as unchecked boxes.
5. Reminder to the owner: bump `CFBundleVersion` at release so iCloud Drive publishes the nvEnvy folder.
6. Screenshots: iPhone editor, drawer with search results, Info sheet, Storage settings, first launch (light + dark).

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

Preferences can be forced per test via the `UserDefaults` argument domain, e.g. `app.launchArguments += ["-nvenvy.iOS.launchBehavior", "blankNote"]`.

**Required test cases (D13 — these run in CI and must pass):**
1. **Notes load:** launch with fixture → open drawer → footer reads "{expected} notes"; rows `Beer`, `2026-11-05`, `notes`, `legacy`, `outline`, `readme`, `cp1252`, `utf16`, `crlf`, `obsidian` exist; `image` does not. Also assert the `Beer` row's preview does not start with "Beer".
2. **Open via button focuses search:** tap `editor.openDrawer` → `drawer.search` has keyboard focus. Tap scrim → drawer hidden.
3. **Edge swipe opens without focus:** press at `coordinate(withNormalizedOffset: (0.0, 0.4))`, drag to (0.6, 0.4) → drawer visible, keyboard not shown. (Skip with `XCTSkip` and a reason if the §2c fallback disabled edge swipe.)
4. **Return opens prefix match:** type `chris` → Return → editor shows "Christmas presents 2026" body; drawer closed.
5. **Create row:** type `brand new note` → tap `createRow` → file `brand new note.md` exists in the sandbox vault; editor focused.
6. **Scratch commit + caret continuity:** launch with `launchBehavior=blankNote` → type "Groceries\nmilk" → tap `editor.openDrawer` → row `Groceries` exists → close drawer → tap the end of the editor text → type " and eggs" → `editor.text` value ends with "milk and eggs" (caret didn't jump). Also assert no file whose name starts with `Untitled` exists.
7. **Provisional rename:** blank scratch → type "Gro" → open drawer (commits `Gro.md`) → close → tap the end of the editor text (single line, so the caret is at the end of the first line) → type "ceries" → open drawer → tap a row to select another note → vault contains `Groceries.md` and no `Gro.md`.
8. **Background commit:** type in scratch → `XCUIDevice.shared.press(.home)` → wait 2 s → `app.terminate()` → relaunch → note exists with the full text.
9. **Kill recovery (no background):** type "Recovery test" in scratch → wait 1 s (draft debounce) → `app.terminate()` immediately → relaunch → editor shows the scratch with "Recovery test"; the vault has no new file yet *or* exactly one (never two) containing it.

**Moved to manual QA (§11.5)** instead of UI tests: swipe-to-close, search-parity UI walk (the Core parity test already covers ordering), delete/rename/tags via context menu, iPad hardware keys, encoding round-trip, and performance.

Run (iPhone only in CI; run the iPad destination locally once before opening the PR):
```bash
cd nvEnvy && xcodegen generate
xcodebuild test -project nvEnvy.xcodeproj -scheme nvEnvyiOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
# local only:
xcodebuild test -project nvEnvy.xcodeproj -scheme nvEnvyiOS \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  CODE_SIGNING_ALLOWED=NO
```
If a named simulator doesn't exist on the machine, pick the closest available one from `xcrun simctl list devices available` and note it in the PR.

### 11.4 CI
Add a job `ios-build-test` to `.github/workflows/ci.yml` (runner `macos-15`): install XcodeGen → generate → `xcodebuild build` the `nvEnvyiOS` scheme for `generic/platform=iOS Simulator` with `CODE_SIGNING_ALLOWED=NO` → run the required UI tests (§11.3) on an iPhone 16 sim. No performance tests in CI (simulator timing on shared runners is too noisy). Keep the existing jobs untouched. (Entitlements with iCloud containers are ignored when signing is disabled — fine for CI.)

### 11.5 Manual device QA (owner runs; agent writes this checklist into the PR description)
Two devices: Mac (nvEnvy 1.3.x) + iPhone (TestFlight/dev build), same Apple ID.
0. **Existing install upgrade (do first):** install this build over the current App Store/TestFlight build → app opens the same folder with no onboarding, same note count, last note restored.
1. **Fresh install, iCloud default:** on a device whose Apple ID has never run the Mac app (no hint) → onboarding → "Keep notes in iCloud Drive" → create note "Sync test A" → in Files it's under iCloud Drive › nvEnvy; within 60 s it appears on the Mac after pointing the Mac at iCloud Drive › nvEnvy.
2. **Existing Mac vault:** on Mac pick a folder in iCloud Drive with ≥500 notes incl. `.txt` and subfolder notes and a custom extension (add `org` in Mac prefs). iPhone fresh install → "Open your Mac notes folder" is the primary button → open folder → **note count matches Mac exactly**; `.org` notes appear; Settings › Storage › File Types row lists `org` and says "Matches your Mac".
3. **Undownloaded files:** on iPhone, Files › long-press the vault folder › Remove Download; relaunch app → footer shows "Downloading n…", count converges to Mac's count without user action.
4. **Live sync both ways:** edit on Mac → appears on iPhone while app open (< 30 s); edit on iPhone → appears on Mac.
5. **Conflict:** airplane-mode iPhone, edit same note on both, reconnect → conflict banner → resolve → both devices show the chosen text.
6. **Kill safety:** (a) in an existing note, type quickly, immediately swipe the app away → relaunch → last characters present. (b) Same in a blank scratch note → relaunch → scratch shows the text; exactly one note (or zero, still in draft) — never a duplicate, never an `Untitled…` file.
7. **Storage switch:** Settings › Storage → On My iPhone → "Move notes" → count identical, iCloud copy untouched.
8. **iCloud signed out:** Settings app → sign out iCloud → reopen → clear banner, no crash, no data loss.
9. **Gesture feel (on a physical device):** edge swipe works while keyboard is up and while text is selected; selection handles and long-press-select near the left edge still work; doesn't fire when a sheet is up; list scroll never triggers close; swipe-left on the drawer closes it.
10. **Dynamic Type XXXL, VoiceOver, Dark mode, RTL (Arabic) locale, iPad Split View/Stage Manager widths, landscape.**
11. **Search parity spot check:** same 10 queries on Mac and iPhone produce the same top results in the same order.
12. **List actions:** delete, rename and edit tags via swipe and context menu; check the file on the Mac.
13. **iPad hardware keyboard:** ⌘L opens + focuses search; ⌘J/⌘K change note; Esc clears then closes; ⌘N starts a blank note; ⌘⇧C toggles the drawer.
14. **Encoding round-trip:** open the Windows-1252 note from the fixture vault (copy it into the vault), append "x", background the app; on the Mac, `file -I` still reports a non-UTF-8 charset and the text ends with "x".
15. **Performance:** cold launch to first row visible with a 2,000-note vault feels under ~1.5 s on a recent iPhone; drawer open and list scroll are smooth.
16. **Launch behavior:** default reopens the last note; switching Settings › Launch to "Blank note" starts on a blank editor, and returning after > 15 min shows a fresh blank note.

---

## 12. Acceptance criteria (definition of done)
- [ ] App launches into a clean, full-screen editor showing the last note (default) or a blank note (setting); no list visible.
- [ ] Typing in a blank note never loses text (recovery draft) and never creates `Untitled…` files; the first commit's title can self-correct once (provisional rename).
- [ ] Drawer opens via top-left button (search focused) and left-edge swipe (not focused — unless the §2c fallback disabled it, documented in the PR); closes via scrim tap, swipe left, selection, Return. Overlay on iPhone and iPad; no pin mode.
- [ ] Rows show title, ≤2 preview lines (title duplicate removed), date footer matching sort field.
- [ ] Search results/order identical to macOS for the parity fixture; Return/Create/⌘Return/Esc semantics identical.
- [ ] Storage screen offers iCloud Drive › nvEnvy, Files folder, On My iPhone; switching works with Move/Just switch; existing installs unaffected; new users with a Mac hint are steered to their Mac folder; copy states that iCloud Drive › nvEnvy is a new, separate folder. (If stage D was blocked at D0, this item is replaced by the blocker note in the PR.)
- [ ] iOS loads every extension the Mac loads (defaults + Mac custom via KVS), subfolders, all encodings, and undownloaded iCloud files converge automatically.
- [ ] No regression in data-safety behavior (flush on background, WAL, coordinated IO).
- [ ] `swift test --parallel` green; macOS app builds; required iOS UI tests (§11.3) green on iPhone simulator in CI and run once on iPad simulator locally; CI job added.
- [ ] Old `RootSplitView`/`NoteListView`/`NoteEditorView` deleted; no dead code; all new strings in `Localizable.xcstrings`.
- [ ] Accessibility: every control labeled; drawer is an accessibility modal (`.accessibilityAddTraits(.isModal)` when overlay), VoiceOver escape (two-finger Z) closes it.

## 13. Risks & mitigations
| Risk | Mitigation |
|---|---|
| Edge-pan vs `UITextView` pan/selection gestures | Spike first (B0); 20pt zone; `require(toFail:)` on text view pan; fallback = top-two-thirds zone, then disable behind a pref. `[≡]` always works. |
| Ubiquity container signing/provisioning fails | Container exists (D12); verified at D0 before any storage code. Storage is the last stage, so a blocker there doesn't hold back A–C. App still works via Files/On-device if the container URL is nil (banner). |
| Scratch→note switch resets the text view | Set `coordinator.currentNoteID` before re-render; UI test #6. |
| Scratch text lost on hard kill | Recovery draft written every 300 ms and synchronously on background (§2d.1); UI test #9. |
| Junk / half-typed note titles | No idle commit, no `Untitled…` files, one provisional rename (§2d.2); UI tests #6–7. |
| Users expect their existing iCloud notes in "iCloud Drive › nvEnvy" | Mac-hint users are steered to their Mac folder; copy says the nvEnvy folder is new and separate (§6.6). |
| Large vaults + drawer animation jank | Rows read only cached fields; no body access; manual perf check (§11.5 #15). |
| Placeholder handling changes macOS load | iOS-gated flag; macOS tests unchanged. |
| Third-party providers (Dropbox) don't emit metadata updates | Documented; foreground reconcile + pull-to-refresh. |
