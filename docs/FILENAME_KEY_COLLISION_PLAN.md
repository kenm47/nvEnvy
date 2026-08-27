# Plan: fix the duplicate-`filename` launch crash and make the note key unique

**Status:** not started
**Target:** nvEnvy 1.2.1
**Origin:** user-submitted crash log against 1.2.0 (2), App Store build, `slice_uuid bcf138b1-d781-3f81-a01e-2fcc12032638`

---

## 0. Context for whoever implements this

You do not need the crash log. Here is everything it told us.

The app traps on launch with `EXC_BREAKPOINT` (Swift runtime `_assertionFailure`). Symbolicated crashing thread, top frames:

```
0  libswiftCore  _assertionFailure(_:_:file:line:flags:)
1  nvEnvy        specialized _NativeDictionary.merge<A>(_:isUnique:uniquingKeysWith:)
2  nvEnvy        NotesViewModel.rebuildNotesByID()      NotesViewModel.swift:227
3  nvEnvy        NotesViewModel._allNotes.setter
4  nvEnvy        partial apply for closure #1 in NotesViewModel.allNotes.setter
7  libswiftObservation  ObservationRegistrar.withMutation(of:keyPath:_:)
8  nvEnvy        closure #1 in NotesViewModel.attach(folderURL:allowedExtensions:coordinator:onInitialLoad:)
12 libswift_Concurrency completeTaskWithClosure
```

Frames 1 + 2 identify it precisely: `Dictionary(uniqueKeysWithValues:)` trapping with
*"Fatal error: Duplicate values for key"*. Line **227** is the **filename** map, not the id map:

```swift
// NvEnvyCore/Sources/NvEnvyCore/NotesViewModel.swift:226-227
notesByID       = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.id, $0) })   // 226 — safe, keyed by UUID
notesByFilename = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.filename, $0) })  // 227 — TRAPS
```

Frame 8 places it in `attach`'s task, i.e. the very first `self.allNotes = await store.allNotes()`
after the vault scan. The user crashed 2.9 s after launch, deterministically, every launch.

### Root cause

`Note.filename` is the vault-relative path **with the extension stripped**
(`FileStorageService.relativeFilename(for:basePrefix:)`, line ~79), but `readAllNotes` accepts
five extensions (`FileStorageService.defaultAllowedExtensions = ["md", "markdown", "mmd", "txt", "text"]`).

So any two files differing only by extension collapse to the same key:

| on disk | `Note.filename` today |
| --- | --- |
| `Ideas.md` | `Ideas` |
| `Ideas.txt` | `Ideas` ← collision → trap |
| `Daily/log.md` | `Daily/log` |
| `Daily/log.markdown` | `Daily/log` ← collision → trap |

A second, rarer route to the same trap: `NoteStore.loadAll`'s WAL-recovery branch constructs
`Note(id:title:body:tags:modifiedDate:)` with **no** `filename`, so `Note.init` falls back to
`Note.sanitizedFilename(from: title)` with no uniqueness check — that can collide with a note
already loaded from disk.

### Two independent defects, both in scope

1. **The trap.** `rebuildNotesByID()` uses a trapping initializer on data derived from a
   user-controlled directory. It must never crash over vault contents.
2. **The key is not unique.** The extension-less relative path is not a unique identity for a
   file. The same defect makes `FileStorageService.fileURL(for:)` hardcode `+ ".md"`, so **a
   `.txt` note that gets saved is rewritten as a new `.md` file and the original `.txt` is
   orphaned** — a silent data bug that exists today, independent of the crash.

Fix 1 stops the crash. Fix 2 is the actual bug. Do both; do them in this order.

### What is NOT affected

- `Note.filename` is never persisted. It is derived from disk on every load; `NoteStore.filenameIndex`
  is in-memory only. **There is no on-disk format change and no migration to write.**
- `notesByID` (line 226) is genuinely collision-free: it is built from `NoteStore.notes`, a
  `[UUID: Note]`, so ids are unique by construction. Leave its semantics alone (but see Part 1).

---

## Part 1 — Stop the trap (small, self-contained, ship-blocking)

**File:** `NvEnvyCore/Sources/NvEnvyCore/NotesViewModel.swift`, `rebuildNotesByID()` (~line 225).

Replace both trapping initializers with the uniquing form. Keep first-wins so behaviour is
deterministic regardless of `Array(notes.values)` ordering.

```swift
private func rebuildNotesByID() {
    // Both maps use `uniquingKeysWith` rather than `uniqueKeysWithValues`: the
    // keys come from a user-controlled directory, and a vault containing e.g.
    // `Ideas.md` alongside `Ideas.txt` used to trap the whole app on launch.
    // First-wins keeps the result stable; Part 2 makes real collisions
    // impossible in the first place.
    notesByID = Dictionary(allNotes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    notesByFilename = Dictionary(allNotes.map { ($0.filename, $0) }, uniquingKeysWith: { first, _ in first })
}
```

> Do **not** "fix" this by sorting, deduping `allNotes`, or filtering — `allNotes` is the list the
> user sees, and dropping a note from it silently hides a real file. The index is allowed to be
> lossy; the list is not.

### Regression test (Part 1)

Add to `NvEnvyCore/Tests/NvEnvyCoreTests/NotesViewModelTests.swift`:

```swift
@MainActor
func testDuplicateFilenamesDoNotTrap() {
    let vm = NotesViewModel()
    let a = Note(title: "Ideas", filename: "Ideas")
    let b = Note(title: "Ideas", filename: "Ideas")   // same key, different id
    vm.allNotes = [a, b]                              // must not crash
    XCTAssertEqual(vm.allNotes.count, 2)
    XCTAssertNotNil(vm.note(for: a.id))
    XCTAssertNotNil(vm.note(for: b.id))
}
```

(Match whatever `NotesViewModel` construction the neighbouring tests in that file already use —
`vm.allNotes` is `public`, and its `didSet` is what calls `rebuildNotesByID()`.)

---

## Part 2 — Make `Note.filename` the full relative path, extension included

### The decision

`Note.filename` changes meaning from *"vault-relative path, extension stripped"* to
**"vault-relative path exactly as it appears on disk, extension included"**.

| on disk | before | after |
| --- | --- | --- |
| `Ideas.md` | `Ideas` | `Ideas.md` |
| `Ideas.txt` | `Ideas` | `Ideas.txt` |
| `Daily/log.markdown` | `Daily/log` | `Daily/log.markdown` |

Consequences that fall out for free:
- The key is now unique per file, so Part 1's `uniquingKeysWith` never actually collides.
- `fileURL(for:)` stops hardcoding `.md`, so a `.txt` note saves back to its own `.txt` file.
- Renaming a note in a subfolder stops silently moving it to the vault root (see 2.4).

Rejected alternatives, so you don't relitigate them:
- *Add a separate `fileExtension` field and key on `filename + "." + ext`* — every call site
  would have to remember to recombine; the same bug returns the first time one forgets.
- *Dedupe by appending a counter to colliding names* — makes the key non-deterministic across
  launches (ordering depends on `Dictionary.values`), which breaks sync-status matching.

`Note.title` is unchanged: still `url.deletingPathExtension().lastPathComponent`. Nothing user-visible
displays `filename`, so there is no UI copy to update — verify with
`grep -rn "\.filename" nvEnvy` that every hit is a path/keying use, not a label.

---

### 2.1 `Note.swift`

**File:** `NvEnvyCore/Sources/NvEnvyCore/Note.swift`

`Note.init` (~line 58) falls back to a bare sanitized title when no filename is passed. New notes
always live at the vault root and are always Markdown, so give the fallback an extension:

```swift
// before
self.filename = filename.isEmpty ? Note.sanitizedFilename(from: title) : filename
// after
self.filename = filename.isEmpty ? Note.sanitizedFilename(from: title) + ".md" : filename
```

Leave `sanitizedFilename(from:)` itself alone — it stays a *base name* helper (it strips `/`, which
is exactly right for turning a title into one path component; relative paths from disk contain `/`
and are passed in explicitly, bypassing it).

Add two helpers on `Note` (or as free functions in `Note.swift`) so the recombination logic lives in
exactly one place:

```swift
extension Note {
    /// Directory portion of `filename`, "" for a note at the vault root.
    /// "Daily/log.md" -> "Daily/", "log.md" -> "".
    public var filenameDirectory: String {
        guard let slash = filename.lastIndex(of: "/") else { return "" }
        return String(filename[...slash])
    }

    /// Extension of `filename` including the dot, ".md" if there is none.
    /// "Daily/log.markdown" -> ".markdown".
    public var filenameExtension: String {
        let base = filename.split(separator: "/").last.map(String.init) ?? filename
        guard let dot = base.lastIndex(of: "."), dot != base.startIndex else { return ".md" }
        return String(base[dot...])
    }
}
```

### 2.2 `FileStorageService.swift`

**File:** `NvEnvyCore/Sources/NvEnvyCore/FileStorageService.swift`

**(a) `relativeFilename(for:basePrefix:)` (~line 79)** — stop stripping the extension. Delete the
final two lines and return the relative path directly:

```swift
// remove:
let ext = url.pathExtension
return String(relativePath.dropLast(ext.count + 1)) // remove .ext
// replace with:
return relativePath
```

Update the doc comment above it — it currently says *"Relative 'filename' (no extension)"*.

**(b) Make it `public static`.** It is `private static` today; the sync monitors in Part 2.6 need it.
Keep it `static` (it is pure path arithmetic and runs from parallel load tasks off the actor).

**(c) `fileURL(for:)` (~line 275)** — drop the hardcoded extension:

```swift
public func fileURL(for note: Note) -> URL {
    notesDirectory.appendingPathComponent(note.filename)
}
```

**(d) `renameNote(_:oldFilename:)` (~line 262)** — `oldFilename` is now a complete relative path:

```swift
let oldURL = notesDirectory.appendingPathComponent(oldFilename)
```

Also create the destination directory before moving, since `newURL` may now be in a subfolder:

```swift
try FileManager.default.createDirectory(
    at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
```

**(e) `ensureUniqueFilename(_:)` (~line 279)** — currently takes a bare base name and hardcodes
`.md`. Change it to take and return a full relative filename:

```swift
/// Returns `candidate` (a vault-relative filename *with* extension), or the
/// first " 2", " 3", … variant that does not already exist on disk.
public func ensureUniqueFilename(_ candidate: String) -> String {
    guard fileManager.fileExists(atPath: notesDirectory.appendingPathComponent(candidate).path) else {
        return candidate
    }
    let url = URL(fileURLWithPath: candidate)
    let ext = url.pathExtension                       // "md", no dot
    let stem = url.deletingPathExtension().path       // "Daily/log"
    var counter = 2
    while true {
        let next = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
        if !fileManager.fileExists(atPath: notesDirectory.appendingPathComponent(next).path) {
            return next
        }
        counter += 1
    }
}
```

**(f) `atomicWrite` (~line 289)** — writes `.tmp` next to the destination and `replaceItemAt`s.
That already works for subfolders, but the parent directory must exist. Add the same
`createDirectory(withIntermediateDirectories: true)` guard at the top of `writeNote` before
`coordinate(writingItemAt:)`.

**(g) `parseNoteFile` (~line 147)** needs no change — `let title = url.deletingPathExtension().lastPathComponent`
is still correct, and `filename` now comes back from `relativeFilename` with its extension.

**(h) `filename(forPath:)` (~line 100)** needs no change — it delegates to `relativeFilename`.

### 2.3 `NoteStore.swift` — creation paths

**File:** `NvEnvyCore/Sources/NvEnvyCore/NoteStore.swift`

`createNote` (~line 76) and `addImportedNote` (~line 86) both do
`sanitizedFilename(from:)` → `ensureUniqueFilename(_:)`. Feed the latter a full filename:

```swift
let sanitized = Note.sanitizedFilename(from: title) + ".md"
let uniqueName = await storage.ensureUniqueFilename(sanitized)
let note = Note(title: title, filename: uniqueName)
```

Apply the identical two-line change in both functions.

### 2.4 `NoteStore.updateTitle` — preserve directory and extension

`updateTitle` (~line 108) currently does:

```swift
note.filename = Note.sanitizedFilename(from: title)
```

which under the old scheme silently moved a subfolder note to the vault root, and under the new
scheme would strip its extension entirely. Replace with:

```swift
public func updateTitle(noteID: UUID, title: String) async throws {
    guard let note = notes[noteID] else { return }
    let oldFilename = note.filename
    unindexNote(note)
    note.title = title
    // Keep the note where it lives and in the format it is already in: only the
    // base name follows the title. Renaming "Daily/log.txt" to "Journal" yields
    // "Daily/Journal.txt", not "Journal.md" at the vault root.
    let candidate = note.filenameDirectory + Note.sanitizedFilename(from: title) + note.filenameExtension
    note.filename = candidate == oldFilename
        ? oldFilename
        : await storage.ensureUniqueFilename(candidate)
    note.modifiedDate = Date()
    note.invalidateSearchCache()
    indexNote(note)
    try await storage.renameNote(note, oldFilename: oldFilename)
    markDirty(noteID)
}
```

Note the `candidate == oldFilename` guard: without it, a title-case-only rename would see its own
file on disk and bump to " 2".

### 2.5 `NoteStore.loadAll` — the WAL-recovery collision

Still in `NoteStore.swift`, the `else` branch of the crash-recovery loop (~line 47) builds a note
with no filename. Give it a unique one explicitly:

```swift
} else {
    // Note not on disk yet — recreate from WAL. The WAL carries no filename,
    // so derive one and make sure it can't collide with a note we just loaded
    // from disk (this was a second route into the launch-time index collision).
    let candidate = await storage.ensureUniqueFilename(
        Note.sanitizedFilename(from: rec.title) + ".md")
    let note = Note(
        id: rec.noteID,
        title: rec.title,
        body: rec.body,
        tags: rec.tags,
        filename: candidate,
        modifiedDate: rec.timestamp
    )
    notes[note.id] = note
    indexNote(note)
    dirtyNoteIDs.insert(note.id)
}
```

`ensureUniqueFilename` only checks the filesystem, so also guard against a name already claimed by
an in-memory note from this same load:

```swift
var candidate = await storage.ensureUniqueFilename(Note.sanitizedFilename(from: rec.title) + ".md")
var n = 2
while filenameIndex[candidate] != nil {
    candidate = "\(Note.sanitizedFilename(from: rec.title)) \(n).md"
    n += 1
}
```

While you are in `indexNote` (~line 19), add a comment noting that `filenameIndex[note.filename] = note.id`
silently overwrites on collision — after Part 2 collisions are impossible, and that is now the
invariant the index relies on.

### 2.6 Sync-status keying — the part that breaks if you skip it

Two monitors build their `[String: SyncStatus]` batch keys as
`url.deletingPathExtension().lastPathComponent`:

- `nvEnvy/nvEnvy/ICloudStatusMonitor.swift:66`
- `nvEnvy/nvEnvyiOS/Storage/IOSFolderMonitor.swift:82`

These keys are looked up in `NotesViewModel.notesByFilename`. Two things are wrong:

1. After Part 2 they would no longer match at all (keys lack the extension) — sync status would
   silently stop working everywhere.
2. They are **already** wrong today for any note in a subfolder: `lastPathComponent` drops the
   directory, so `Daily/log.md` produces the key `log`, which never matches `Daily/log`.

Fix both by keying on the vault-relative path. Both call sites already have the absolute `path` and
access to the vault root (`appState.notesFolderURL` on macOS; `IOSFolderMonitor` holds the folder URL
it queries — check its init and thread it through if it does not store it).

Use the now-public helper from 2.2(b):

```swift
// ICloudStatusMonitor.queryDidUpdate, replacing line 66
guard let root = folderURL else { continue }   // vault root URL
let basePrefix = FileStorageService.basePrefix(for: root)
let key = FileStorageService.relativeFilename(for: url, basePrefix: basePrefix)
batch[key] = syncStatus(for: item, at: url)
```

That needs `basePrefix` exposed too — it is a private computed property today. Add:

```swift
/// Trailing-slash-terminated absolute path of `directory`, for `relativeFilename`.
public static func basePrefix(for directory: URL) -> String {
    let p = directory.resolvingSymlinksInPath().path
    return p.hasSuffix("/") ? p : p + "/"
}
```

and rewrite the existing instance property as `Self.basePrefix(for: notesDirectory)` so there is one
implementation. Hoist the `basePrefix` computation out of the per-item loop in both monitors — it
resolves symlinks and hits the filesystem.

Apply the identical change in `IOSFolderMonitor.swift` (~line 82).

### 2.7 `NotesViewModel.tryRenameNote` — collision check

`tryRenameNote` (~line 359) compares `Note.sanitizedFilename(from: trimmed)` against `other.filename`.
Both sides must be composed the same way as 2.4, or the pre-flight check and the actual rename
disagree:

```swift
guard let target = note(for: noteID) else { return nil }
if target.title == trimmed { return nil }

let newFilename = target.filenameDirectory
    + Note.sanitizedFilename(from: trimmed)
    + target.filenameExtension
let lowerNewFilename = newFilename.lowercased()
let collides = allNotes.contains { other in
    other.id != noteID && other.filename.lowercased() == lowerNewFilename
}
```

(The `.lowercased()` comparison is deliberate — APFS is case-insensitive by default. Keep it.)

### 2.8 App-layer `+ ".md"` call sites

Eight places build a file URL by hand. Every one becomes `appendingPathComponent(note.filename)`
with the `+ ".md"` removed:

| file | line |
| --- | --- |
| `nvEnvy/nvEnvy/AppState.swift` | 592 (`revealInFinder`) |
| `nvEnvy/nvEnvy/AppState.swift` | 598 (`writeFinderTags`) |
| `nvEnvy/nvEnvy/AppState.swift` | 611 (`openInExternalEditor`) |
| `nvEnvy/nvEnvy/ContentView.swift` | 99 (`openSelectedNoteInMarked`) |
| `nvEnvy/nvEnvy/PreviewWindow.swift` | 152 (`openInMarked`) |
| `nvEnvy/nvEnvy/ConflictResolutionView.swift` | 182, 199 |
| `nvEnvy/nvEnvyiOS/UI/ConflictView.swift` | 174, 189 |

Rather than editing eight duplicated expressions, add one helper to `AppState` and route the macOS
sites through it:

```swift
/// Absolute URL of a note's backing file, or nil if no vault is open.
public func fileURL(for note: Note) -> URL? {
    notesFolderURL?.appendingPathComponent(note.filename)
}
```

`ConflictView.swift` (iOS) takes `folderURL` as a parameter rather than reading `AppState`; leave its
structure alone and just drop the `+ ".md"` there.

Also check `nvEnvy/nvEnvy/nvEnvyApp.swift:87-88` — it declares `UTType`s for the folder importer
(`md`, `markdown`, `mmd`) and is missing `txt`/`text` that `defaultAllowedExtensions` accepts. Not
part of this bug; note it and leave it, or fix it in a separate commit.

---

## Part 3 — Tests

All in `NvEnvyCore/Tests/NvEnvyCoreTests/`. Run with `cd NvEnvyCore && swift test`.

### 3.1 Update existing assertions

These encode the old extension-less key and **will fail** — that is expected; update them:

- `FileStorageServiceTests.swift:105` — `"Root Note"` → `"Root Note.md"`
- `FileStorageServiceTests.swift:110` — `"subfolder/Sub Note"` → `"subfolder/Sub Note.md"`
- `FileStorageServiceTests.swift:171` — `"a/b/c/Deep"` → `"a/b/c/Deep.md"`
- `NotesViewModelTests.swift:231` — `tempDir.appendingPathComponent(note.filename + ".md")` → drop `+ ".md"`
- `SyncStatusTests.swift:48-66` — notes are constructed with `filename: "A"` / `"B"` and looked up by
  `"A"`. These still pass (the key is opaque), but change them to `"A.md"` / `"B.md"` so the fixtures
  reflect reality.
- `FinderTagServiceTests.swift:45,57`, `PerformanceTests.swift:42,97`, `EncodingDetectionTests.swift:36` —
  explicit `filename:` values without extensions. Add `.md`. Check whether each test writes to or
  reads from disk via `fileURL(for:)`; if it does, the extension now matters.
- `NoteStoreTests.swift:23` — `XCTAssertFalse(note.filename.isEmpty)`; tighten to
  `XCTAssertTrue(note.filename.hasSuffix(".md"))`.

### 3.2 New tests

**`FileStorageServiceTests.swift`** — the actual crash repro at the storage layer:

```swift
func testSameStemDifferentExtensionsProduceDistinctFilenames() async throws {
    // Regression: `Ideas.md` + `Ideas.txt` both mapped to the key "Ideas",
    // which trapped `Dictionary(uniqueKeysWithValues:)` on launch.
    try "one".write(to: tempDir.appendingPathComponent("Ideas.md"), atomically: true, encoding: .utf8)
    try "two".write(to: tempDir.appendingPathComponent("Ideas.txt"), atomically: true, encoding: .utf8)

    let storage = FileStorageService(notesDirectory: tempDir)
    let notes = try await storage.readAllNotes()

    XCTAssertEqual(notes.count, 2)
    XCTAssertEqual(Set(notes.map(\.filename)), ["Ideas.md", "Ideas.txt"])
    XCTAssertEqual(Set(notes.map(\.title)), ["Ideas"])   // titles still collide, and that's fine
}

func testWriteNotePreservesNonMarkdownExtension() async throws {
    try "body".write(to: tempDir.appendingPathComponent("Plain.txt"), atomically: true, encoding: .utf8)
    let storage = FileStorageService(notesDirectory: tempDir)
    let note = try await storage.readAllNotes().first!
    note.body = "edited"
    try await storage.writeNote(note)

    XCTAssertEqual(
        try String(contentsOf: tempDir.appendingPathComponent("Plain.txt"), encoding: .utf8)
            .contains("edited"), true)
    XCTAssertFalse(FileManager.default.fileExists(
        atPath: tempDir.appendingPathComponent("Plain.md").path),
        "editing a .txt note must not fork it into a new .md file")
}

func testEnsureUniqueFilenameKeepsExtensionAndDirectory() async {
    try? FileManager.default.createDirectory(
        at: tempDir.appendingPathComponent("Daily"), withIntermediateDirectories: true)
    try? "x".write(to: tempDir.appendingPathComponent("Daily/log.md"), atomically: true, encoding: .utf8)
    let storage = FileStorageService(notesDirectory: tempDir)
    let unique = await storage.ensureUniqueFilename("Daily/log.md")
    XCTAssertEqual(unique, "Daily/log 2.md")
}
```

**`NoteStoreTests.swift`**:

```swift
func testRenamePreservesSubfolderAndExtension() async throws {
    try? FileManager.default.createDirectory(
        at: tempDir.appendingPathComponent("Daily"), withIntermediateDirectories: true)
    try "x".write(to: tempDir.appendingPathComponent("Daily/log.txt"), atomically: true, encoding: .utf8)

    let store = NoteStore(storage: FileStorageService(notesDirectory: tempDir))
    try await store.loadAll()
    let note = await store.allNotes().first!

    try await store.updateTitle(noteID: note.id, title: "Journal")

    XCTAssertEqual(note.filename, "Daily/Journal.txt")
    XCTAssertTrue(FileManager.default.fileExists(
        atPath: tempDir.appendingPathComponent("Daily/Journal.txt").path))
    XCTAssertFalse(FileManager.default.fileExists(
        atPath: tempDir.appendingPathComponent("Journal.md").path))
}
```

**`NotesViewModelTests.swift`** — the Part 1 test from above, plus:

```swift
@MainActor
func testSyncStatusMatchesNoteInSubfolder() {
    let vm = NotesViewModel()
    let note = Note(title: "log", filename: "Daily/log.md")
    vm.allNotes = [note]
    vm.updateSyncStatus(filename: "Daily/log.md", status: .conflict)
    XCTAssertEqual(note.syncStatus, .conflict)
}
```

### 3.3 Manual verification (not covered by unit tests)

The sync-status monitors are AppKit/UIKit-bound and untested. After the change, verify by hand:

1. Point the app at an iCloud Drive folder containing a note in a subfolder.
2. Edit that note on another device; confirm the row shows a sync-status indicator and it clears.
   Before this change it never did for subfolder notes.
3. Open a vault containing both `Ideas.md` and `Ideas.txt` — the app must launch and list both.
4. Edit and save the `.txt` one; confirm no stray `Ideas 2.md` or `Ideas.md` appears.

---

## Part 4 — Order of work, and what a reviewer should check

Suggested commits:

1. **`Fix launch crash on vaults with colliding note filenames`** — Part 1 only, plus its regression
   test. Small, obviously safe, shippable on its own as 1.2.1 if you want the fix out fast.
2. **`Make Note.filename the full relative path including extension`** — Parts 2.1–2.5 and 2.7,
   plus the `NvEnvyCore` test updates. Package-only; nothing outside `NvEnvyCore` compiles against
   it yet, so build the package alone first (`cd NvEnvyCore && swift build && swift test`).
3. **`Key sync status on vault-relative paths`** — Part 2.6. Independently reviewable and it fixes a
   pre-existing subfolder bug.
4. **`Drop hardcoded .md from app-layer file URLs`** — Part 2.8.

Commits 2–4 must land together for the app target to build; do not merge 2 alone to `main`.

Reviewer checklist:

- [ ] `grep -rn '+ "\.md"' nvEnvy NvEnvyCore/Sources` returns nothing.
- [ ] `grep -rn 'uniqueKeysWithValues' NvEnvyCore/Sources` returns nothing.
- [ ] `grep -rn 'deletingPathExtension().lastPathComponent' nvEnvy` returns only `title`-derivation
      sites, never a sync-status or index key.
- [ ] `Note.filename` is assigned in exactly four places: `Note.init`, `parseNoteFile`,
      `NoteStore.updateTitle`, and the WAL-recovery branch — every one of them producing a path
      with an extension.
- [ ] `cd NvEnvyCore && swift test` passes, and both app schemes (`nvEnvy`, `nvEnvy-MAS`) build.
- [ ] Manual checks in 3.3 done on a real iCloud vault.
