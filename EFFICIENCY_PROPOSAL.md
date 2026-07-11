# nvEnvy Efficiency Improvement Proposal

**Scope:** proposal only — no functional changes. This document ranks efficiency
improvements (performance, memory, codebase weight) biggest-impact first, with
`file:line` anchors, the cost mechanism, a concrete fix, risks, and a
verification path. A later implementation session executes from it.

**Baseline:** anchors were re-verified against the working tree on the
`ios-port/phase-2-3-ios-reader-editor` branch (2026-07-06), which includes the
iOS port. `NvEnvyCore` is now a shared macOS/iOS SwiftPM package;
`NotesViewModel` has already been extracted from `AppState`, and search now runs
off the main actor via a new `SearchActor`. Findings and anchors below reflect
that state, not the pre-iOS-port codebase.

## Already resolved since the original review (not proposed here)

These were flagged in the earlier draft and have since been fixed in the working
tree — listed so nobody re-discovers them:

- **First-line preview extraction** — `NotePreviewRow` no longer splits the whole
  body; it reads `Note.cachedFirstLine` (Note.swift:33, computed by
  `Note.firstLine(of:)`; covered by `NoteCacheTests.swift`).
- **`hasExactTitleMatch` per-render title lowercasing** — the computed property is
  gone; "Create <query>" visibility is precomputed in
  `NotesViewModel.showCreateRow` / `updateShowCreateRow()` (NotesViewModel.swift:233).
- **Search on the main actor** — `SearchEngine.filter` now runs on `SearchActor`
  (SearchEngine.swift:12) via an `async performSearch()` with a stale-query guard
  (NotesViewModel.swift:160). The per-keystroke sort/diff still happens on the main
  actor (see P4), but the filter itself no longer blocks the UI.
- **Per-row date formatter allocation** — `NoteRow` now reuses file-level
  `Date.FormatStyle` constants instead of building one per render
  (NoteListView.swift, `rowModifiedDateStyle`/`rowRelativeDateStyle`).
- **P1: incremental FS reconciliation** — FSEvents paths/flags are threaded
  through `FileSystemMonitor`'s callback; `NoteStore.reconcilePaths` reconciles
  only the changed paths (stat-compare, self-write suppression via
  `FileStorageService.wasSelfWrite`), falling back to a full rescan only on
  `MustScanSubDirs`/overflow flags (`fsEventFlagsRequireFullRescan`).
- **P2: concurrent metadata-first load** — `FileStorageService.readAllNotes`
  parses files concurrently via `TaskGroup` after a serial enumeration pass,
  reading with `.mappedIfSafe`.
- **P3: iCloud metadata churn** — `ICloudStatusMonitor.queryDidUpdate` now
  processes only the `NSMetadataQueryUpdateChangedItemsKey`/`AddedItemsKey`
  delta (full pass reserved for `DidFinishGathering`), checks
  `NSFileVersion` conflicts only when `NSMetadataUbiquitousItemHasUnresolvedConflictsKey`
  is set, and applies one coalesced `[filename: SyncStatus]` batch per tick via
  `NotesViewModel.updateSyncStatuses` (backed by a `notesByFilename` index,
  writes skipped when the status is unchanged).
- **P4 (partial): search off the main actor** — `SearchEngine.filter` now runs
  on `SearchActor` via an async `performSearch()` with a stale-query guard. The
  comparator-side tier computation and redundant re-sort/reassignment (the rest
  of P4) are not yet done.

---

## Executive summary

| # | Finding | Impact | Effort | Primary files | Status |
|---|---------|--------|--------|---------------|--------|
| P1 | Incremental FS reconciliation — stop full-vault re-read per FSEvent | Very high | High | FileSystemMonitor, AppState, NotesViewModel, NoteStore, FileStorageService | Done |
| P2 | Concurrent metadata-first load + lazy `cachedLowercaseBody` | High | Medium | FileStorageService, Note | Load parallelized; lazy `cachedLowercaseBody` not done |
| P3 | iCloud metadata churn — O(N²) per update | High (iCloud vaults) | Medium | ICloudStatusMonitor, AppState, NotesViewModel | Done |
| P4 | Search: comparator-side tier compute + redundant re-sorts | Medium | Medium | SearchEngine, NotesViewModel | Off-main-actor done; tier/re-sort work remains |
| P5 | Editor attribute passes on search keystrokes | Medium | Low | EditorView | Not started |
| P6 | Write path double-writes + per-call formatter/handle churn | Medium | Low | FileStorageService, FrontmatterParser, CrashRecoveryService, NoteStore | Double-write fixed; formatter/handle/WAL-task churn remain |
| P7 | Preview window redundant reload + CSS re-read | Medium (preview open) | Low | PreviewWindow | Not started |
| P8 | Remaining per-render/per-keystroke micro-costs | Low–Medium | Low | EditorView, NotesViewModel | Not started |
| P9 | Deduplicate repeated logic (lighter codebase) | Low | Low | multiple | Not started |

---

## Tier 1 — structural hot paths

### P1. Incremental filesystem reconciliation — stop full-vault re-read on every FSEvent (biggest win)

**Problem.** `FileSystemMonitor` requests per-file events
(`kFSEventStreamCreateFlagFileEvents`, FileSystemMonitor.swift:30) but the C
callback **discards the event paths** — `fsEventCallback` (FileSystemMonitor.swift:58)
ignores `eventPaths`/`eventFlags` and just calls `wrapper.callback()`
(FileSystemMonitor.swift:68). That ping flows through
`AppState.setupMonitors` (AppState.swift:524) →
`NotesViewModel.reconcileFilesystem` (NotesViewModel.swift:409) →
`NoteStore.reconcileWithFilesystem` (NoteStore.swift:185) →
`FileStorageService.readAllNotes` (FileStorageService.swift:71), which reads,
encoding-detects, and YAML-parses **every** file in the vault and allocates a
fresh `Note` per file. `reconcileFilesystem` then reassigns `allNotes` wholesale
and calls `performSearch()`, cascading into tag-cache invalidation,
`notesByID` rebuild, search, sort, and a full SwiftUI list diff.

**Why it matters.** The app's own debounced autosaves (2 s flush cadence in
`NoteStore.scheduleFlush`, NoteStore.swift:149; 1 s FSEvents latency,
FileSystemMonitor.swift:29) generate FSEvents, so merely typing triggers periodic
full-vault rescans. Cost is O(vault size) in file reads + YAML parses per save;
on a 5,000-note vault that is thousands of file reads while editing.

**Recommendation.**
1. Thread the FSEvents path list through `CallbackWrapper` so the callback
   receives `[String]` (decode `eventPaths` as CFArray under
   `kFSEventStreamCreateFlagUseCFTypes`) plus the per-event flags.
2. Reconcile only those paths: `stat` each and compare
   `(contentModificationDate, fileSize)` against `note.fileModifiedDate` /
   `note.fileSize` (both already stored — Note.swift:20-21, populated in
   readAllNotes at FileStorageService.swift:120-133); read + parse only real
   changes; handle deletes/creates from the path set.
3. Suppress self-writes: record the post-write stat in
   `FileStorageService.writeNote` (FileStorageService.swift:141) and skip events
   whose `(mtime, size)` match the last write for that path.
4. Keep the full `readAllNotes` scan only as the fallback for
   `kFSEventStreamEventFlagMustScanSubDirs` / overflow flags and for the manual
   reconcile entry points.
5. Never reassign `allNotes` (and thus never fire its `didSet`) when the delta is
   empty.

**Risk/constraints.** Path decoding must be correct for renames and for the
`MustScanSubDirs` fallback. Deletes must still drop `filenameIndex`
(NoteStore.swift:24) entries. Keep the `.obsidian`/dot-dir skip rules
(FileStorageService.swift:80,86).

**Verification.** New benchmark: external single-file change reconciles with a
handful of reads, not N (see Measurement). Assert typing in-app causes zero
`readAllNotes` calls (self-write suppression).

### P2. Concurrent, metadata-first load + lazy lowercase-body cache

**Problem.** `readAllNotes` (FileStorageService.swift:71) already enumerates with
resource keys and avoids per-file symlink resolution, but it still runs **serially**
— read → `decodeWithFallback` → `FrontmatterParser.parse`, one file at a time
(FileStorageService.swift:93-96) — inside a single actor call. Separately,
`Note.init` eagerly lowercases title, body, and tags for **every** note
(Note.swift:53-55), so startup lowercases the entire corpus, and
`cachedLowercaseBody` (Note.swift:28) permanently holds a second full copy of
every body (~2× corpus RAM), even for notes never searched.

**Recommendation.**
- Parallelize the parse/allocate step with a `TaskGroup` (parsing is pure): keep
  the directory enumeration serial to collect `[URL]`, then chunk and decode +
  parse + build `Note`s concurrently, merging results.
- Read file contents with `Data(contentsOf:options:.mappedIfSafe)`.
- Make `cachedLowercaseBody` a lazily computed cache: build on first search touch,
  clear in `invalidateSearchCache` (Note.swift:59). `cachedLowercaseTitle` /
  `cachedLowercaseTags` are small — leaving them eager is fine.

**Why it matters.** Multi-x faster cold start on large vaults, corpus-sized RAM
saved until first search, and removal of the full-corpus lowercase from launch.

**Risk/constraints.** Keep `readAllNotes` external behavior identical (same Note
fields, same skip rules). Lazy body cache must stay thread-safe under the actor
model; if `Note` stays `@unchecked Sendable`, guard the lazy fill.

### P3. iCloud metadata churn — effective O(N²) per update

**Problem.** `ICloudStatusMonitor.queryDidUpdate` (ICloudStatusMonitor.swift:42)
iterates **all** query results on every update — `for i in 0..<query.resultCount`
(ICloudStatusMonitor.swift:48) — rather than the delta, computes `syncStatus(for:)`
per file (which calls `NSFileVersion.unresolvedConflictVersionsOfItem`, a syscall,
per file), and spawns one `Task { @MainActor }` **per file**
(ICloudStatusMonitor.swift:57). Each lands in
`AppState.updateSyncStatus` (AppState.swift:573) →
`NotesViewModel.updateSyncStatus` (NotesViewModel.swift:493), which does a
**linear scan** `allNotes.first(where: { $0.filename == filename })`
(NotesViewModel.swift:494) plus another `Task` hop into `NoteStore`. For an
iCloud vault of N notes, each metadata tick costs N tasks × N scans.

**Recommendation.**
- Read `NSMetadataQueryUpdateChangedItemsKey` / `AddedItemsKey` / `RemovedItemsKey`
  from `notification.userInfo`; process only the delta (full pass only on
  `NSMetadataQueryDidFinishGatheringNotification`).
- Coalesce into a single `[filename: SyncStatus]` batch applied in one MainActor
  hop and one `NoteStore` call.
- Add a `filename → Note` index to `NotesViewModel` (mirror
  `NoteStore.filenameIndex`, NoteStore.swift:5) to replace the linear scan.
- Check `NSFileVersion` conflicts only for items whose metadata flags suggest a
  conflict.
- Write `note.syncStatus` only when the value actually changed, to avoid
  Observation invalidation churn in every visible row.

**Risk/constraints.** Delta keys are absent on the initial gather — keep the full
pass for `DidFinishGathering`. Keep `enableUpdates`/`disableUpdates` bracketing
(ICloudStatusMonitor.swift:45-46).

---

## Tier 2 — per-keystroke costs

### P4. Search pipeline: comparator-side tier computation and redundant re-sorts

**Problem 1.** `SearchEngine.filter` computes `relevanceTier` **inside the sort
comparator** (SearchEngine.swift:58-61) — O(N log N) tier evaluations, each
re-running `tokens × title.contains`. Fix: compute the tier once per result and
bucket into 3 stable arrays (O(N), preserves current ordering). This now runs on
`SearchActor` (off the main actor), so it no longer blocks the UI, but it is still
wasted CPU per keystroke.

**Problem 2.** `rebuildSortedNotes` (NotesViewModel.swift:207) re-sorts with
`localizedCaseInsensitiveCompare` for title and tags sorts
(NotesViewModel.swift:218-219, 229-230) on every `filteredNotes` assignment —
i.e., every debounced keystroke, delete, import, and reconcile. Fix: for
title/tags sorts compare the already-cached `cachedLowercaseTitle` (or a
precomputed collation key) instead of a locale-aware compare per comparison; skip
the rebuild when `filteredNotes` is unchanged.

**Problem 3.** `performSearch` (NotesViewModel.swift:160) reassigns `filteredNotes`
even when the result set is identical, cascading into `rebuildSortedNotes` + a
SwiftUI diff. Fix: compare by ids/identity before assigning. (`showCreateRow` is
already precomputed once per rebuild — NotesViewModel.swift:233 — so that part is
done.)

**Risk/constraints.** Locale-aware sort semantics change if you drop
`localizedCaseInsensitiveCompare`; if user-visible ordering must match the system
locale exactly, precompute a collation key instead of a plain lowercase compare.

### P5. Editor attribute passes on search-field keystrokes

**Problem.** Every search keystroke mutates `appState.searchQuery`, which re-runs
`EditorView.updateNSView` (EditorView.swift:134) → `highlightSearchTerms`
(EditorView.swift:433). That does a full-document `text.lowercased()`
(EditorView.swift:444) — a **full copy of the open note** — every keystroke, then
scans it. A large open note makes search typing janky.

**Recommendation.** Debounce highlighting to match the 150 ms search debounce;
remember previously highlighted ranges and clear only those (instead of a
document-wide `removeAttribute`); find matches with
`nsText.range(of:options:[.caseInsensitive])` against the original text rather
than lowercasing a copy of the whole document.

**Risk/constraints.** Case-insensitive `range(of:)` must match the current
lowercased-comparison semantics for the highlight color.

### P6. Disk write path: double-write plus per-call formatter/handle churn

- **Double write.** `atomicWrite` writes the temp file with `.atomic`
  (FileStorageService.swift:199) — which itself writes another temp and renames —
  then `replaceItemAt` (FileStorageService.swift:200) renames again. Each save =
  2× data written + 2 renames. Fix: write the temp **without** `.atomic`;
  `replaceItemAt` already provides atomicity.
- **Formatter alloc.** `FrontmatterParser.formatDate` allocates a **new**
  `ISO8601DateFormatter` per call (FrontmatterParser.swift:220) while the
  parse-side formatters are cached statics (FrontmatterParser.swift:137-153). Fix:
  reuse a static shared formatter.
- **File handle churn.** `CrashRecoveryService.appendRecord`
  (CrashRecoveryService.swift:32) opens and closes a `FileHandle`
  (CrashRecoveryService.swift:57) on every append. Fix: cache a
  "directory ensured" flag and keep a lazily opened handle (close on `truncate`,
  CrashRecoveryService.swift:123).
- **Unstructured WAL task.** `NoteStore.markDirty` spawns an unstructured
  `Task { await crashRecovery.appendRecord }` per call (NoteStore.swift:141),
  allowing out-of-order appends plus task overhead. Fix: append within the actor
  call path (already off the main actor) or via one serialized consumer.

**Risk/constraints.** Dropping `.atomic` on the temp is safe only because
`replaceItemAt` is the durability boundary — verify on the target filesystem.
Keeping a WAL handle open means handling truncation and app-relaunch correctly.

---

## Tier 3 — visible-scale render costs

### P7. Preview window redundant work

- `PreviewWebView.updateNSView` calls `webView.loadHTMLString` unconditionally on
  every SwiftUI update (PreviewWindow.swift:162,167) — a full WebKit reload/layout
  even when the HTML is unchanged. Fix: cache the last-loaded string in the
  coordinator and compare before reloading.
- `loadCustomCSS` re-reads `custom.css` from disk on **every render**
  (PreviewWindow.swift:107-109) — i.e., every render tick while typing with the
  preview open. Fix: cache with a mod-date check, or load once per window
  appearance.

### P8. Remaining list/editor micro-costs

- `checkWikilinkAutocomplete` / `insertWikilinkCompletion` backward scans allocate
  substrings per keystroke (EditorView.swift:497,531,559); compare
  `character(at:)` values instead of allocating a lowercased substring.
- `flushBeforeQuit` re-lowercases the **entire corpus** —
  `for note in allNotes { note.invalidateSearchCache() }` (NotesViewModel.swift:420)
  — when at most one note had a pending body update. Track the pending note ID and
  invalidate only it.

---

## Tier 4 — lighter codebase (no behavior change)

### P9. Deduplicate repeated logic

- `findTableView` duplicated in `EditorView.Coordinator` (EditorView.swift:707)
  and `SearchField` (SearchField.swift:65) → one shared helper.
- "Open in Marked" duplicated in `ContentView.openSelectedNoteInMarked`
  (ContentView.swift:95) and `PreviewWindow.openInMarked` (PreviewWindow.swift:136).
- Print code duplicated in `AppState.printNote` (AppState.swift:707) and
  `PreviewWindow.printPreview` (PreviewWindow.swift:122).
- HTML entity tables duplicated in `stripHTML` (ImportExportService.swift:291) and
  `htmlToMarkdown` (ImportExportService.swift:354).
- `note.filename + ".md"` URL construction is scattered — `FileStorageService`
  (`fileURL(for:)` at :179, `renameNote` at :168, uniquing at :186) plus
  `AppState.revealInFinder`/`writeFinderTags`/`openInExternalEditor`
  (AppState.swift:582,589,595), `ContentView`, and `PreviewWindow`. Route through
  one helper mirroring `FileStorageService.fileURL(for:)` so the extension policy
  lives in one place (also relevant to the `.txt`/`.markdown` correctness note
  below).
- `MarkdownRenderer.escapeHTML` does 4 chained `replacingOccurrences` full passes
  (MarkdownRenderer.swift:37-42) → single-pass scan. Note a near-duplicate private
  `escapeHTML` also exists (MarkdownRenderer.swift:223).
- **Deferred / flag as optional:** the iOS port already extracted
  `NotesViewModel`, but `AppState` still forwards a large surface to it; collapsing
  that forwarding so views use the view model directly is wide but mechanical, and
  must preserve the shared macOS/iOS boundary. Dropping the Yams dependency
  (frontmatter is a flat 3-key mapping) is only worth it if binary size becomes a
  goal — Yams currently guarantees arbitrary-YAML tolerance for unknown fields.

---

## Measurement & acceptance

Extend `NvEnvyCore/Tests/NvEnvyCoreTests/PerformanceTests.swift` with:

- **P1** reconcile-after-single-file-change benchmark (assert file-read count is
  small and independent of vault size).
- **P2** cold-load wall-time benchmark on a large synthetic vault; Allocations run
  to confirm the corpus-sized RAM reduction until first search.
- **P3** sync-status batch-update benchmark (delta of K in a vault of N should cost
  O(K), not O(N²)).
- **P4** search+sort per-keystroke benchmark on 5k notes.

**Instruments:** Time Profiler + `os_signpost` ranges around reconcile, search,
and flush; File Activity template to confirm the P6 write halving; Allocations for
the P2 memory claim.

**Acceptance criteria (examples):**
- External single-file change reconciles with ≤ a handful of file reads (was: N).
- Typing in the app causes zero full-vault rescans (self-write suppression).
- A search keystroke does no full-document lowercase of the open note.
- An iCloud metadata tick touches only changed items.

---

## Appendix: correctness observations (out of scope, listed for awareness)

- `applicationWillTerminate` blocks the main thread on a `DispatchSemaphore`
  (nvEnvyApp.swift:356-361) waiting for a `@MainActor` task that cannot run while
  the main thread is blocked — the quit flush can silently never execute.
- `scriptingSearch` getter uses `DispatchQueue.main.sync`
  (nvEnvyApp.swift:372) and deadlocks if AppleScript invokes it on the main thread.
- `.md` is hardcoded in `fileURL(for:)` / `renameNote`
  (FileStorageService.swift:168,180,186), so notes loaded from `.txt` / `.markdown`
  are written back / renamed as `.md`.
- `TagPill` colors derive from `String.hashValue`
  (NoteListView.swift:351), which is randomly seeded per process — tag colors
  change every launch.
- `SearchEngine`'s prefix-extension optimization can filter from a stale
  `previousResults` working set (SearchEngine.swift:34-40) when notes changed
  between keystrokes. `SearchActor` (SearchEngine.swift:12) now owns that state on
  one executor, but the staleness across a mutated corpus is unchanged.
