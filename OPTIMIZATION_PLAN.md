# nvEnvy Optimization Plan

## Architecture Summary

nvEnvy is a macOS note-taking app (~7,700 LOC Swift) built with a two-layer architecture: **NvEnvyCore** (a platform-agnostic Swift package providing data models, file I/O, search, markdown rendering, and crash recovery) and **nvEnvy** (a SwiftUI+AppKit UI layer). State is managed via a single 1,010-line `@Observable` `AppState` class on `@MainActor`. Notes are stored as markdown files with YAML frontmatter, backed by an actor-based `NoteStore` with a write-ahead log for crash safety. Search is in-memory with incremental filtering and lowercased string caching.

## Tech Stack & Dependency Impact

| Dependency | Version | Purpose | Bundle Impact |
|---|---|---|---|
| **Yams** | 5.4.0 | YAML frontmatter parsing | ~200 KB |
| **swift-markdown** | 0.7.3 | Markdown AST + HTML rendering | ~350 KB (+ swift-cmark ~150 KB) |
| **KeyboardShortcuts** | 2.4.0 | Global keyboard shortcut management | ~50 KB |
| **Sparkle** | 2.9.0 | Auto-update framework | ~2.5 MB |
| Apple frameworks | system | Foundation, AppKit, SwiftUI, etc. | 0 (dynamic) |

Sparkle dominates the dependency footprint but is essential for auto-update. The others are lightweight and appropriate.

## Priority Matrix

| # | Optimization | Impact | Effort | Category |
|---|---|---|---|---|
| 1 | Cache regex in WikilinkParser | High | Low | Performance |
| 2 | Add filename index to NoteStore | High | Low | Performance |
| 3 | Deduplicate `escapeHTML()` in MarkdownRenderer | Med | Low | Code bloat |
| 4 | Cache regex in `listContinuation()` (EditorView) | Med | Low | Performance |
| 5 | Pre-compile regexes in ImportExportService | High | Med | Performance |
| 6 | `allKnownTags` recomputes on every access | Med | Low | Performance |
| 7 | `WordCountOverlay` recomputes on every body change | Med | Low | Performance |
| 8 | `SyncStatusToolbarIndicator` scans allNotes on every render | Med | Low | Performance |
| 9 | `syncHealthSummary` does 3 separate filter passes | Low | Low | Performance |
| 10 | Redundant double-update in `updateNoteBody` | Med | Low | Architecture |
| 11 | `BookmarkStore` is `@unchecked Sendable` without synchronization | Med | Low | Correctness |
| 12 | `NoteListView.sortedNotes` re-sorts on every render | Med | Med | Performance |
| 13 | Reduce `htmlToMarkdown()` regex passes | Med | Med | Performance |
| 14 | Split AppState god object | High | High | Architecture |
| 15 | WAL file grows unbounded | Med | Med | Architecture |
| 16 | `note(for:)` in AppState is O(n) linear scan | Med | Low | Performance |
| 17 | DateFormatter allocation in FrontmatterParser.parseDate | Low | Low | Performance |

## Detailed Plan (Top 10)

### 1. Cache compiled regex in WikilinkParser

**Problem**: `WikilinkParser.swift:7,19` — `NSRegularExpression(pattern:)` is compiled fresh on every call to `findWikilinks()` and `findWikilinkNSRanges()`. These are called on every keystroke (via `highlightWikilinks` in `EditorView.swift:380`) and during search.

**Evidence**: Regex compilation involves pattern parsing and NFA construction. For a note with wikilinks being edited, this runs every 300ms (debounce interval). Compiling once eliminates redundant work entirely.

**Solution**:
```swift
public enum WikilinkParser {
    public static let pattern = "\\[\\[([^\\]]+)\\]\\]"
    private static let regex = try! NSRegularExpression(pattern: pattern)

    public static func findWikilinks(in text: String) -> [(range: Range<String.Index>, title: String)] {
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)
        // ... rest unchanged
    }
}
```

**Risk**: None. `NSRegularExpression` is thread-safe for matching. The pattern is a compile-time constant.

**Estimated scope**: 1 file (`WikilinkParser.swift`), ~-4/+2 LOC.

---

### 2. Add filename-to-UUID index in NoteStore

**Problem**: `NoteStore.swift:120` — `updateSyncStatus(filename:status:)` does `notes.values.first(where: { $0.filename == filename })`, an O(n) linear scan. Same pattern at line 182 in `reconcileWithFilesystem()`. Called from `ICloudStatusMonitor` on every metadata query update, potentially for every note.

**Evidence**: With 1,000 notes and frequent iCloud status updates, this is O(n) per file status change. The reconciliation path does it inside a loop over all filesystem notes, making it O(n^2).

**Solution**:
```swift
public actor NoteStore {
    private var notes: [UUID: Note] = [:]
    private var filenameIndex: [String: UUID] = [:]  // secondary index

    // Maintain on insert/delete/rename:
    private func indexNote(_ note: Note) {
        filenameIndex[note.filename] = note.id
    }

    public func updateSyncStatus(filename: String, status: SyncStatus) {
        guard let id = filenameIndex[filename],
              let note = notes[id] else { return }
        note.syncStatus = status
    }
}
```

**Risk**: Low. Must keep index in sync on create/delete/rename — all paths are already centralized in `NoteStore`.

**Estimated scope**: 1 file (`NoteStore.swift`), ~+15 LOC.

---

### 3. Deduplicate `escapeHTML()` in MarkdownRenderer

**Problem**: `MarkdownRenderer.swift:37-43` and `MarkdownRenderer.swift:223-229` — identical `escapeHTML()` implementations exist as a static method on `MarkdownRenderer` and as a private method on `HTMLVisitor`.

**Evidence**: Pure code duplication — maintenance burden, not a performance issue.

**Solution**: Remove the private copy from `HTMLVisitor` and call the static version:
```swift
private struct HTMLVisitor: MarkupVisitor {
    // Remove private escapeHTML, use:
    // MarkdownRenderer.escapeHTML(string)  (make the static one internal)
}
```

**Risk**: None.

**Estimated scope**: 1 file (`MarkdownRenderer.swift`), ~-7/+1 LOC.

---

### 4. Cache regex in `listContinuation()` (EditorView)

**Problem**: `EditorView.swift:313,321` — Two `NSRegularExpression` instances are compiled on every Return keypress in `listContinuation(for:)`. Patterns are constant strings.

**Evidence**: Called every time the user presses Enter. While not hot-path, it's an easy fix.

**Solution**:
```swift
private static let unorderedListRegex = try! NSRegularExpression(pattern: "^(\\s*)([-*])\\s")
private static let orderedListRegex = try! NSRegularExpression(pattern: "^(\\s*)(\\d+)\\.\\s")
```

**Risk**: None.

**Estimated scope**: 1 file (`EditorView.swift`), ~-4/+4 LOC.

---

### 5. Pre-compile regexes in ImportExportService

**Problem**: `ImportExportService.swift:244-331` — `stripHTML()` and `htmlToMarkdown()` use `replacingOccurrences(of:with:options:.regularExpression)` with 20+ regex patterns compiled per call. `htmlToMarkdown` alone has ~15 regex replacements. Additionally, `extractArticleContent()` at line 339 compiles 6 removal patterns per call.

**Evidence**: Each `.regularExpression` option internally compiles an `NSRegularExpression`. For URL imports with readability + markdown conversion, this is ~35 regex compilations per import. For batch imports, this multiplies.

**Solution**: Pre-compile all patterns as static `NSRegularExpression` properties and use `stringByReplacingMatches`. Group the overlapping patterns between `stripHTML` and `htmlToMarkdown` (script/style removal is duplicated between them at lines 246-247 and 271-272).

```swift
public actor ImportExportService {
    private static let scriptRegex = try! NSRegularExpression(pattern: "<script[^>]*>[\\s\\S]*?</script>")
    private static let styleRegex = try! NSRegularExpression(pattern: "<style[^>]*>[\\s\\S]*?</style>")
    // ... etc for all patterns

    public static func stripHTML(_ html: String) -> String {
        var text = html as NSString
        text = Self.scriptRegex.stringByReplacingMatches(in: text as String, range: ..., withTemplate: "") as NSString
        // ...
    }
}
```

**Risk**: Low. Behavior is identical; only compilation timing changes.

**Estimated scope**: 1 file (`ImportExportService.swift`), ~+30/-5 LOC.

---

### 6. `allKnownTags` recomputes on every access

**Problem**: `AppState.swift:298-301` — `allKnownTags` is a computed property that does `allNotes.flatMap(\.tags)` then `Set` then `sorted()` on every access. It's called from `TagEditorPanel.updateSuggestions()` on every keystroke in the tag field, and from `TagSidebarView.tagCounts` on every render.

**Evidence**: For 500 notes with avg 3 tags each, that's 1,500 flatMap elements, Set insertion, and sort — on every keystroke.

**Solution**: Cache the tag set and invalidate when tags change:
```swift
private var _cachedKnownTags: [String]?

public var allKnownTags: [String] {
    if let cached = _cachedKnownTags { return cached }
    let tags = Array(Set(allNotes.flatMap(\.tags))).sorted()
    _cachedKnownTags = tags
    return tags
}

// In updateNoteTags, deleteNote, and note-loading paths:
_cachedKnownTags = nil
```

**Risk**: Low. Must invalidate in all tag-mutating paths (there are 3: `updateNoteTags`, `deleteNote`, and initial `loadAll`).

**Estimated scope**: 1 file (`AppState.swift`), ~+10 LOC.

---

### 7. `WordCountOverlay` recomputes on every body mutation

**Problem**: `EditorView.swift:35-41` — `wordCount`, `charCount`, and `lineCount` are computed properties that recalculate on every SwiftUI view evaluation. Because the overlay reads `note.body`, any body change triggers recomputation.

**Evidence**: `text.split(whereSeparator:)` for word count is O(n) on body length. `text.components(separatedBy: "\n")` allocates an array of all lines. For a 50KB note, these run on every keystroke.

**Solution**: Make `WordCountOverlay` use a debounced binding or compute lazily:
```swift
struct WordCountOverlay: View {
    let text: String
    @State private var stats: (words: Int, chars: Int, lines: Int) = (0, 0, 0)
    @State private var updateTask: Task<Void, Never>?

    var body: some View {
        Text("\(stats.words) words | \(stats.chars) chars | \(stats.lines) lines")
            // ...
            .onChange(of: text) { _, newValue in
                updateTask?.cancel()
                updateTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    let w = newValue.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                    let c = newValue.count
                    let l = newValue.isEmpty ? 0 : newValue.components(separatedBy: "\n").count
                    stats = (w, c, l)
                }
            }
    }
}
```

**Risk**: Low. Word count display will lag by 300ms, which is fine for a status indicator.

**Estimated scope**: 1 file (`EditorView.swift`), ~+12/-4 LOC.

---

### 8. `SyncStatusToolbarIndicator` scans `allNotes` redundantly

**Problem**: `MainView.swift:207-218` — Both `icon` and `color` computed properties independently scan `appState.allNotes` with `.contains { }`. The `icon` property scans twice (once for conflicts, once for syncing). In total, up to 3 full passes over all notes on every render.

**Evidence**: This view is in `MainView.body`, which re-evaluates whenever any `AppState` property changes. With `@Observable`, any mutation triggers re-evaluation.

**Solution**: Combine into a single computed enum:
```swift
private var syncState: SyncState {
    var hasConflict = false
    var hasSyncing = false
    for note in appState.allNotes {
        switch note.syncStatus {
        case .conflict: hasConflict = true
        case .uploading, .downloading: hasSyncing = true
        default: break
        }
        if hasConflict { break }  // worst state found, stop early
    }
    if hasConflict { return .conflict }
    if hasSyncing { return .syncing }
    return .synced
}
```

**Risk**: None.

**Estimated scope**: 1 file (`MainView.swift`), ~+10/-15 LOC.

---

### 9. Redundant double-update in `updateNoteBody`

**Problem**: `AppState.swift:567-575` — `updateNoteBody` mutates the `Note` object directly (setting `body`, `modifiedDate`, calling `invalidateSearchCache()`) and then calls `noteStore?.updateBody()` which does the exact same mutations again (`NoteStore.swift:83-88`).

**Evidence**: Every keystroke causes: 2x `invalidateSearchCache()` (which does 3 `.lowercased()` calls each = 6 total), 2x `Date()` construction, 2x property sets. The `Note` object is a reference type shared between `AppState.allNotes` and `NoteStore.notes`, so the first mutation is already visible to the store.

**Solution**: Remove the redundant mutations from `AppState.updateNoteBody`, keeping only the `noteStore` call. Or, if the intent is to update before the async store call lands, keep the AppState mutations but have `NoteStore.updateBody` skip them:
```swift
// In NoteStore:
public func updateBody(noteID: UUID, body: String) {
    // Note is already mutated by AppState; just mark dirty
    markDirty(noteID)
}
```

**Risk**: Medium. Requires understanding that the `Note` reference is shared. If NoteStore is ever used independently, it would need the mutations. Add a comment.

**Estimated scope**: 2 files (`AppState.swift`, `NoteStore.swift`), ~-8 LOC.

---

### 10. `note(for:)` in AppState is O(n) linear scan

**Problem**: `AppState.swift:563-565` — `note(for id: UUID) -> Note?` uses `allNotes.first { $0.id == id }`, a linear scan through the array. Called from `updateNoteBody` (every keystroke), `EditorView.body`, `NoteListView` row construction, and many other hot paths.

**Evidence**: With 500 notes, this scans up to 500 elements per keystroke. Combined with the fact that `updateNoteBody` calls it then calls `invalidateSearchCache`, this is a meaningful per-keystroke cost.

**Solution**: Add a dictionary index alongside the array:
```swift
private var notesByID: [UUID: Note] = [:]

public func note(for id: UUID) -> Note? {
    notesByID[id]
}

// Maintain on allNotes mutations (append, remove, load):
// notesByID[note.id] = note  /  notesByID.removeValue(forKey: id)
```

**Risk**: Low. Must keep in sync — all mutations go through a small number of AppState methods.

**Estimated scope**: 1 file (`AppState.swift`), ~+12 LOC.

---

## Quick Wins (<1hr, near-zero risk)

1. **Cache WikilinkParser regex** (item #1 above) — static `let regex`, 2 lines changed.

2. **Cache list-continuation regexes** (item #4) — static `let` on Coordinator, 4 lines.

3. **Deduplicate `escapeHTML()`** (item #3) — delete 7 duplicate lines.

4. **`syncHealthSummary` triple-filter** — `AppState.swift:305-307` filters `allNotes` 3 times for uploading, downloading, conflicts. Combine into single pass:
   ```swift
   public var syncHealthSummary: String {
       var uploading = 0, downloading = 0, conflicts = 0
       for note in allNotes {
           switch note.syncStatus {
           case .uploading: uploading += 1
           case .downloading: downloading += 1
           case .conflict: conflicts += 1
           default: break
           }
       }
       // ...
   }
   ```

5. **`SyncStatusToolbarIndicator` triple-scan** (item #8) — combine into single loop.

6. **Static DateFormatters in FrontmatterParser** — `FrontmatterParser.swift:140-151` creates `ISO8601DateFormatter` and `DateFormatter` on every `parseDate()` call. These are expensive to construct. Make them `static let`:
   ```swift
   private static let isoFormatter: ISO8601DateFormatter = {
       let f = ISO8601DateFormatter()
       f.formatOptions = [.withInternetDateTime]
       return f
   }()
   ```

7. **Remove `handlePlainTextStyle` redundant regex compilations** — `EditorView.swift:622-634` compiles 7 regexes on every "plain text style" invocation. Make static.

## Do-Not-Touch List

1. **AppState god object split** — While AppState is 1,010 lines and manages too many concerns, splitting it into `PreferencesManager`, `NoteManager`, etc. would require threading `@Environment` objects through the entire view hierarchy and updating all 16 UI files. The risk of regressions across the app is high relative to the modest performance gain. The current design works correctly, and SwiftUI's `@Observable` with property-level tracking already prevents most unnecessary re-renders. Revisit only if AppState grows past ~1,500 LOC or a specific re-render issue is traced to it.

2. **SearchEngine struct-to-class conversion** — `SearchEngine` is a mutable struct, but it's only ever used as a `private var` on `AppState` (which is `@MainActor`). It's never passed across isolation boundaries. Converting to a class would add reference semantics complexity for no practical gain.

3. **FileStorageService async conversion** — `readAllNotes()` is synchronous but is only called from `async` contexts (`NoteStore.loadAll()`, `reconcileWithFilesystem()`). Since the actor isolation of `NoteStore` already moves work off the main thread, making `FileStorageService` methods `async` would add complexity without benefit — the file I/O is already not blocking the main thread.

4. **Sparkle framework size** — At ~2.5 MB it's the largest dependency, but auto-update is a critical feature for a distributed Mac app. No lighter alternative exists with equivalent security and reliability.

5. **`nv-src/` legacy Objective-C archive** (~650 files) — This is the original nvALT source preserved for reference. It's not compiled or linked. Removing it would save disk space but has zero impact on build time or bundle size. Leave it for historical reference.

6. **FlowLayout in TagEditorPanel** — Custom `Layout` implementation (`TagEditorPanel.swift:265-303`) could theoretically be replaced, but it's simple, correct, and only used in a sheet that opens rarely. Not worth touching.

7. **CrashRecoveryService WAL unbounded growth** — While the WAL file grows until `truncate()` is called, the flush interval is 2 seconds and truncation happens after every successful flush. In practice, the WAL only contains the most recent dirty notes (a few KB). Adding rotation logic adds complexity for a problem that doesn't manifest in normal use. Only relevant if the app crashes repeatedly without successfully flushing — an edge case not worth optimizing for.
