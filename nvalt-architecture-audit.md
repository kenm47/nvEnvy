# nvALT Complete Architecture & Feature Audit

> **Codebase**: [ttscoff/nv](https://github.com/ttscoff/nv) (nvALT fork of Notational Velocity)
> **Version**: 2.2.8 (Build 128)
> **Language**: Objective-C (manual retain/release, pre-ARC)
> **Bundle ID**: `net.elasticthreads.nv`

---

## 1. Core Architecture

### 1.1 Architecture Pattern

nvALT uses a **hybrid MVC + Delegate** pattern:

- **Model**: `NoteObject`, `DeletedNoteObject`, `LabelObject`, `NotationPrefs`, `GlobalPrefs`, `FrozenNotation`
- **View**: `NotesTableView`, `LinkingEditor`, `DualField`, `PreviewController`, `EmptyView`
- **Controller**: `AppController`, `NotationController`, `SyncSessionController`, `PrefsWindowController`
- **Delegate communication** between layers (no bindings, no notifications-only)
- **Category extensions** on `NotationController` split its responsibilities: `NotationFileManager`, `NotationDirectoryManager`, `NotationSyncServiceManager`

### 1.2 Key Classes & Responsibilities

| Class | Superclass | Role |
|-------|-----------|------|
| `AppController` | `NSObject` | Top-level app controller. Owns window, search field, editor, table view, preview. Coordinates all UI. |
| `NotationController` | `NSObject` | Central data controller. Owns `allNotes` array, manages filtering, sorting, file sync, WAL journaling, sync sessions. |
| `NoteObject` | `NSObject` | Single note model. Stores title, content (`NSMutableAttributedString`), labels, timestamps, file encoding, sync metadata. Each note has its own `NSUndoManager`. |
| `DeletedNoteObject` | `NSObject` | Lightweight tombstone for sync reconciliation. Stores UUID + sync metadata + LSN. |
| `LabelObject` | `NSObject` | Represents one tag/label. Maintains an `NSMutableSet` of associated `NoteObject`s. |
| `NotationPrefs` | `NSObject` | Per-database preferences: encryption, storage format, sync accounts, file type/extension mappings. |
| `GlobalPrefs` | `NSObject` | Global app preferences (singleton). Fonts, colors, table columns, hotkey, bookmarks. Observer pattern for change notifications. |
| `FrozenNotation` | `NSObject` | `NSCoding`-compliant archive containing all notes + deleted notes + prefs for serialization to disk. |
| `FastListDataSource` | `NSObject` | High-performance C-array-backed `NSTableViewDataSource`. Supports in-place filtering and stable sorting via function pointers. |
| `LabelsListController` | `FastListDataSource` | Manages filtered label list. Tracks `NSCountedSet` of all/filtered labels. Caches label images. |
| `SyncSessionController` | `NSObject` | Manages sync service lifecycles, timers, network reachability, power state callbacks, status menus. |
| `SimplenoteSession` | `NSObject` | Simperium API sync implementation. Handles auth, full/partial index fetch, note CRUD, conflict resolution. |
| `WALStorageController` | `WALController` | Write-ahead log for crash recovery. Compressed + encrypted per-record journaling. |
| `WALRecoveryController` | `WALController` | Reads and replays WAL journal on crash recovery. |
| `DualField` | `NSTextField` | Unified search/create bar. Snapback button, clear button, document icon, followed-link history. |
| `LinkingEditor` | `NSTextView` | Note body editor. Rich text, auto-links, markdown support, auto-pairing, find/replace, text width management. |
| `NotesTableView` | `NSTableView` | Note list display. Column management, sort indicators, grid lines, preview rows, keyboard nav. |
| `NoteAttributeColumn` | `NSTableColumn` | Custom column with C function pointers for sort/reverse-sort and attribute dereferencing. |
| `PreviewController` | `NSWindowController` | Markdown/MultiMarkdown/Textile preview in separate WebView window. Save, print, share, source view. |
| `BookmarksController` | `NSObject` | Saved searches with note references. Menu items Cmd-1 through Cmd-0. |
| `DeletionManager` | `NSObject` | Manages note file deletion confirmation and trash operations. |
| `ExternalEditorListController` | `NSObject` | Singleton managing registered external editors (ODB-compliant and user-added). |
| `ODBEditor` | `NSObject` | ODB Editor Suite protocol implementation for external editing via Apple Events. |
| `AlienNoteImporter` | `NSObject` | Multi-format note importer (files, URLs, pasteboard, directories). |
| `ExporterManager` | `NSObject` | Manages note export to various formats. |
| `TagEditingManager` | `NSObject` | Floating panel for tag/label editing with text completion. |
| `EncodingsManager` | `NSObject` | Character encoding detection and conversion UI. |
| `KeyDerivationManager` | `NSObject` | PBKDF2 iteration configuration UI for encryption. |
| `PrefsWindowController` | `NSObject` | Preferences window with toolbar-switchable panes. |
| `NotationPrefsViewController` | `NSObject` | Database-specific preferences pane (encryption, sync, storage format). |

### 1.3 Data Flow: Note Creation -> Storage -> Display -> Search

```
CREATION:
  1. User types in DualField (search field)
  2. AppController:-fieldAction: called on Return
  3. AppController:-createNoteIfNecessary allocates NoteObject
  4. NoteObject:-initWithNoteBody:title:delegate:format:labels:
  5. NotationController:-addNewNote: inserts into allNotes array
  6. NotationController:-refilterNotes updates FastListDataSource
  7. Delegate callback: -notationListDidChange: reloads table

STORAGE:
  1. NoteObject:-makeNoteDirtyUpdateTime:updateFile: marks note dirty
  2. NotationController:-scheduleWriteForNote: adds to unwrittenNotes set
  3. Timer fires: NotationController:-synchronizeNoteChanges:
  4. For file-based format:
     a. NoteObject:-writeUsingCurrentFileFormat writes to individual file
     b. NotationFileManager:-storeDataAtomicallyInNotesDirectory: (atomic via temp+exchange)
  5. For database format:
     a. FrozenNotation:-frozenDataWithExistingNotes: serializes all notes
     b. Atomic write to "Notes & Settings" file
  6. WALStorageController:-writeEstablishedNote: journals change for crash recovery

DISPLAY:
  1. NotesTableView queries FastListDataSource (C array of NoteObject*)
  2. NoteAttributeColumn::columnAttributeForObject() dereferences display values
  3. Title: tableTitleOfNote() or unifiedCellForNote() for preview mode
  4. Labels: labelColumnCellForNote() renders colored label blocks
  5. Dates: dateModifiedStringOfNote() / dateCreatedStringOfNote()
  6. Selection change -> AppController:-processChangedSelectionForTable:
  7. AppController:-displayContentsForNoteAtIndex: loads content into LinkingEditor
  8. Search terms highlighted via LinkingEditor:-highlightTermsTemporarilyReturningFirstRange:

SEARCH:
  1. Each keystroke fires AppController:-controlTextDidChange:
  2. Calls NotationController:-filterNotesFromString:
  3. Converts to lowercase UTF-8 C string
  4. Calls -filterNotesFromUTF8String:forceUncached:
     Phase 1: Reset if prefix changed (re-fill from allNotes)
     Phase 2: Tokenize search string, filter with noteContainsUTF8String()
     Phase 3: Reset found pointers if needed
     Phase 4: Autocomplete via noteTitleHasPrefixOfUTF8String()
  5. FastListDataSource:-filterArrayUsingFunction: filters C array in-place
  6. Delegate callback reloads table with filtered results
```

### 1.4 Threading Model

- **Main thread**: All UI operations, note model mutations, search/filter operations, user events
- **Background**: `SyncResponseFetcher` HTTP calls, `FSEventStream` directory monitoring callbacks, URL download in `AlienNoteImporter`
- **Timer-based deferred writes**: `changeWritingTimer` on main thread triggers periodic flush
- **Power state callbacks**: `IONotificationPortRef` for sleep/wake handling in `SyncSessionController`
- **No explicit threading primitives** (GCD, NSOperationQueue) — relies on run loop scheduling

### 1.5 Memory Management

- **Manual retain/release** (MRC) throughout — pre-ARC codebase
- `NoteObject` retains its `contentString`, `undoManager`; delegate is non-retaining
- `NotationController` owns `allNotes` (strong), `deletedNotes` (strong), `walWriter` (strong)
- `FastListDataSource` uses raw C array (`id *objects`) — does NOT retain objects
- `DualField.followedLinks` retains `NoteBookmark` stack
- Autorelease pools used in category methods and import operations

---

## 2. Data Model & Storage

### 2.1 Note Storage Formats

Defined in `NotationPrefs.h`:

```objc
enum {
    SingleDatabaseFormat = 0,  // All notes in single encrypted archive
    PlainTextFormat      = 1,  // Individual .txt files
    RTFTextFormat        = 2,  // Individual .rtf files
    HTMLFormat           = 3,  // Individual .html files
    WordDocFormat        = 4,  // .doc (import only)
    WordXMLFormat        = 5   // .docx (import only)
};
```

### 2.2 File-Based Storage (PlainText/RTF/HTML)

- Each note stored as individual file in the notes directory
- Filename derived from title via `NotationFileManager:-uniqueFilenameForTitle:fromNote:`
- File extension configured per format in `NotationPrefs` (e.g., `.txt`, `.md`, `.rtf`)
- Atomic writes: temp file created, data written, `FSExchangeObjects` swaps atomically
- File metadata tracked: `UTCDateTime fileModifiedDate`, `UInt32 nodeID`, `UInt32 logicalSize`
- Directory monitored via `FSEventStream` (10.5+) or `FNSubscription` (10.4)

### 2.3 Database-Backed Storage (SingleDatabaseFormat)

- Single archive file: `"Notes & Settings"` in notes directory
- Serialized via `NSKeyedArchiver` as `FrozenNotation` object containing:
  - `NSMutableArray *allNotes` — all `NoteObject`s (each `NSCoding`-compliant)
  - `NSMutableSet *deletedNoteSet` — `DeletedNoteObject` tombstones
  - `NotationPrefs *prefs` — database preferences
- Encryption: Optional AES encryption with PBKDF2-derived key
- Compression: zlib before encryption
- Verification: After write, file is read back and deserialized to verify integrity

### 2.4 Write-Ahead Log (WAL)

```objc
typedef union {
    struct {
        u_int32_t originalDataLength;
        u_int32_t dataLength;
        u_int32_t checksum;
        char saltBuffer[RECORD_SALT_LEN]; // 32 bytes
    };
    char recordBuffer[(sizeof(u_int32_t) * 3) + RECORD_SALT_LEN];
} WALRecordHeader;
```

- Location: `~/Library/Caches/` (configured by `kUseCachesFolderForInterimNoteChanges` in `nvaDevConfig.h`)
- Per-record encryption: master key + per-record salt
- zlib compression before encryption
- On crash recovery: `WALRecoveryController` replays journal, deduplicates by UUID, reconciles with existing notes

### 2.5 Metadata Storage

Each `NoteObject` stores (as instance variables, not properties):

```objc
@public
    NSMutableArray *prefixParentNotes;
    NSString *filename;
    NSString *titleString, *labelString;
    UInt32 logicalSize;
    UTCDateTime fileModifiedDate, *attrsModifiedDate;
    NSStringEncoding fileEncoding;
    NSInteger currentFormatID;
    CFAbsoluteTime modifiedDate, createdDate;
```

Plus private ivars:
- `CFUUIDBytes uniqueNoteIDBytes` — unique identifier for sync
- `NSMutableDictionary *syncServicesMD` — per-service sync metadata
- `NSRange selectedRange` — last cursor position
- `unsigned int logSequenceNumber` — WAL sequence number
- `UInt32 nodeID` — HFS catalog node ID
- `PerDiskInfo *perDiskInfoGroups` — per-volume tracking data

### 2.6 Note Titles & Filenames

- Title is the primary identifier; filename is derived
- `NoteObject:-setFilenameFromTitle` generates filesystem-safe name
- Forbidden characters replaced; length truncated if needed
- Uniqueness enforced by `NotationFileManager:-uniqueFilenameForTitle:fromNote:`
- Title changes trigger file rename via `NotationFileManager:-noteFileRenamed:fromName:toName:`

### 2.7 Sync Mechanisms

#### Simplenote/Simperium Sync

- **Session**: `SimplenoteSession` implements `<SyncServiceSession>`
- **Auth**: Email/password -> Simperium token via `+simperiumURLWithPath:parameters:`
- **API Key**: `kSimperiumAPIKey` constant
- **Full sync**: Fetches complete note index, compares with local
- **Partial sync**: Uses `indexMark` for pagination, `lastCV` for change version tracking
- **Push**: Timer-based (`pushTimer`), note mutations queued per-note to prevent conflicts
- **Conflict resolution**: `localEntry:compareToRemoteEntry:` — compares modification times
- **Tag sync**: `tagsShouldBeMergedForEntry:` controls tag merging behavior
- **Suppression**: `notesToSuppressPushing` prevents push loops during sync-initiated changes

#### Folder Sync / Directory Monitoring

- `NotationDirectoryManager` category on `NotationController`
- `FSEventStream` monitors notes directory for external changes
- `_readFilesInDirectory` builds catalog of all files
- `synchronizeNotesFromDirectory` compares catalog with in-memory notes
- `makeNotesMatchCatalogEntries:` reconciles: adds new files, updates modified, handles deletions
- Two reconciliation modes: by CNID (catalog node ID) or by content comparison

### 2.8 Encoding Handling

- Default: UTF-8 for new notes
- Legacy support: system default encoding for old databases
- Per-note encoding stored in `fileEncoding` ivar
- `EncodingsManager` provides UI for encoding selection/conversion
- `NoteObject:-upgradeToUTF8IfUsingSystemEncoding` — batch upgrade on database migration
- `NoteObject:-setFileEncodingAndReinterpret:` — re-reads file with new encoding
- `[UNCLEAR]` UTF-8 detection has known false positives (see `NSString_NV.m:703`)

### 2.9 Backup/Versioning

- **WAL journal**: Crash recovery via write-ahead log
- **Atomic writes**: Temp file + FSExchangeObjects prevents corruption
- **Database verification**: Post-write verification reads back and compares
- **No built-in versioning** — relies on macOS Versions (if volume supports) or Dropbox/Time Machine
- **Old database preserved**: On epoch upgrade, old file renamed (e.g., "Notes & Settings (old version from 2.0b)")

---

## 3. Search & Indexing

### 3.1 Unified Search/Title Bar

The `DualField` is the core UX innovation — a single text field that simultaneously:
1. Searches all notes incrementally as you type
2. Creates a new note when you press Return with a non-matching string
3. Shows the title of the currently selected note (with document icon)

**Components:**
- `DualFieldCell`: Custom cell rendering clear button (right) and snapback button (left)
- `DualField`: Manages followed-link history, tooltip tags, cursor management
- Placeholder text: "Search or Create"

### 3.2 Incremental Search Algorithm

Located in `NotationController.m`, method `filterNotesFromUTF8String:forceUncached:`:

**Phase 1 — Prefix Detection** (lines 1315-1329):
```
IF no current filter OR forceUncached OR new string is shorter OR prefix doesn't match:
    Reset: fill data source from allNotes
    Clear last word position
```

**Phase 2 — Token-Based Filtering** (lines 1332-1362):
```
Tokenize search string by delimiters:
    If quotes present: delimiter = '"' (phrase search)
    Otherwise: delimiters = " :\t\r\n"
For each token:
    Set NoteFilterContext { needle = token, useCachedPositions }
    Filter array using noteContainsUTF8String()
```

**Phase 3 — Pointer Reset** (lines 1364-1381):
```
If filtered but not touched (blank search):
    Reset all found pointers via resetFoundPtrsForNote()
```

**Phase 4 — Autocomplete** (lines 1383-1414):
```
If autoCompleteSearches enabled:
    For each filtered note:
        If note title has prefix of search string:
            Set selectedNoteIndex
            Check prefix-parent chain for shorter match
            Break
```

### 3.3 Search Matching Function

```objc
// NoteObject.m:1823
BOOL noteContainsUTF8String(NoteObject *note, NoteFilterContext *context) {
    if (!context->useCachedPositions)
        resetFoundPtrsForNote(note);

    char *needle = context->needle;

    // Darwin's strstr() is "heinously, supernaturally optimized"
    if (note->cTitleFoundPtr)
        note->cTitleFoundPtr = strstr(note->cTitleFoundPtr, needle);
    if (note->cContentsFoundPtr)
        note->cContentsFoundPtr = strstr(note->cContentsFoundPtr, needle);
    if (note->cLabelsFoundPtr)
        note->cLabelsFoundPtr = strstr(note->cLabelsFoundPtr, needle);

    return note->cContentsFoundPtr || note->cTitleFoundPtr || note->cLabelsFoundPtr;
}
```

Key characteristics:
- **Case-insensitive**: Search string lowercased before matching; cached C strings are lowercase
- **Substring match**: Uses `strstr()` — not fuzzy, not regex
- **Incremental**: Cached position pointers allow resuming search from last match position
- **Multi-field**: Matches in title, content, OR labels
- **No scoring/ranking**: Filtered results maintain current sort order

### 3.4 Full-Text Indexing

- **No inverted index** — linear scan through all notes per keystroke
- **C-string cache**: Each `NoteObject` caches `cTitle`, `cContents`, `cLabels` as UTF-8 `char*`
- Cache initialized via `initContentCacheCString`, updated via `updateContentCacheCStringIfNecessary`
- Cache invalidated on content change (`contentCacheNeedsUpdate` flag)
- Performance relies on Darwin's optimized `strstr()` implementation

### 3.5 Regex / Fuzzy Matching

- **No regex support** in search
- **No fuzzy matching** — strict substring only
- Quote-delimited phrase search is the only advanced syntax
- `[INFERRED]` The simplicity is intentional for instantaneous search performance

### 3.6 Search Creates Notes

When user presses Return in the search field:
1. `AppController:-fieldAction:` fires
2. `createNoteIfNecessary` checks if search string matches existing note title
3. If no exact match: creates new `NoteObject` with search string as title
4. New note added to `NotationController`
5. Focus moves to `LinkingEditor` for editing
6. `isCreatingANote` flag prevents re-filtering during creation

---

## 4. UI/UX — Every Element

### 4.1 Window Layout

Single-window design with `RBSplitView` (programmatically created, not IB):

```
+--------------------------------------------------+
| [Snapback] [Search/Create Field...] [Clear]      |  <- DualField (35pt)
+--------------------------------------------------+
| Note List      |  Note Editor (LinkingEditor)     |  <- RBSplitView
| (NotesTableView)|                                 |
|                |                                  |
|                |                                  |
+--------------------------------------------------+
                                    [Word Count]    |  <- WordCountToken (optional)
```

- Split view divider: `LinearDividerShader` (8pt expanded / 5pt collapsed thickness)
- Autosave name: `"centralSplitView"`
- Left pane min: 80pt, max: 600pt
- Can toggle horizontal/vertical layout

### 4.2 DualField — Exact Keystroke Behavior

- **Each character typed**: `controlTextDidChange:` fires → `filterNotesFromString:` → table reloads → first matching note auto-selected (if autocomplete enabled) → editor shows selected note content
- **Return**: Creates new note with field text as title (if no exact match), or selects matching note
- **Escape**: Clears search, shows all notes, returns focus to field
- **Tab**: Moves focus to notes table
- **Down Arrow**: Moves selection to notes table
- **Cmd-L**: Returns focus to search field from anywhere
- **Snapback click**: Pops last followed link from history stack, restores previous search
- **Clear click**: Equivalent to Escape

### 4.3 Note List

**Columns available:**

| Column ID | Display | Sort Function | Reverse Sort |
|-----------|---------|---------------|--------------|
| `NoteTitleColumnString` | Title (+ optional body preview) | `compareTitleString` | `compareTitleStringReverse` |
| `NoteLabelsColumnString` | Tags/Labels (colored blocks) | `compareLabelString` | `compareLabelStringReverse` |
| `NoteDateModifiedColumnString` | Date Modified | `compareDateModified` | `compareDateModifiedReverse` |
| `NoteDateCreatedColumnString` | Date Created | `compareDateCreated` | `compareDateCreatedReverse` |

**Additional internal sort functions**: `compareFilename`, `compareNodeID`, `compareFileSize`

**Display modes:**
- Standard: Separate columns with headers
- Preview: Unified cell showing title + first line of body (togglable via `tableColumnsShowPreview`)
- Horizontal layout: Table above editor instead of left of editor

**Configuration:**
- Right-click header → show/hide columns
- Click header → sort by column (toggle direction)
- Configurable font size (`tableFontSize`, default: small system font)
- Grid lines (preference: `ShowGrid`)
- Alternating row colors (preference: `AlternatingRows`)

### 4.4 Note Editor

`LinkingEditor` (NSTextView subclass) features:
- **Rich text** with attributed string support
- **Bold** (Cmd-B), **Italic** (Cmd-I), **Strikethrough** (Cmd-Y)
- **Default style** (Cmd-T) — strips formatting
- **Auto-linking**: URLs detected and made clickable (via `AutoHyperlinks.framework`)
- **Wiki-style links**: `[[Note Title]]` autocompletes from note titles, clickable
- **Auto-indentation**: New lines match previous indent
- **Auto-pairing**: Brackets, parentheses, quotes (optional preference)
- **Auto list bullets**: Continues bullet lists on Return
- **Auto "done" tag formatting**: Strikethrough for `@done` tagged items
- **Soft tabs**: Spaces instead of tab characters (configurable count)
- **Max text width**: Configurable body width limit with centering
- **Search term highlighting**: Configurable highlight color
- **Find/Replace**: `NSTextFinder` (Lion+) or custom `MultiTextFinder` (pre-Lion)
- **RTL support**: Right-to-left text direction (preference)
- **Markdown formatting shortcuts**: `changeMarkdownAttribute:` for inline syntax
- **Insert link**: Cmd-Shift-L creates `[text](url)` from clipboard URL
- **Paste markdown link**: Cmd-Alt-V creates link from clipboard

### 4.5 Empty View / Status

`EmptyView` displayed when no note is selected, showing status message.

### 4.6 Word Count

`WordCountToken` — optional overlay showing word/character/line counts. Toggled via Shift-Cmd-K.

### 4.7 Toolbar

- Minimal toolbar: DualField can be in toolbar or main view
- `TitlebarButton` in title bar area shows sync status icon with dropdown menu
- No other toolbar buttons in default configuration

### 4.8 Preferences Panes

**General Pane:**
- Autocomplete note titles in search (checkbox)
- App activation global hotkey (via `PTKeyCombo`)
- External text editor selection (popup)
- Show/hide dock icon (checkbox)
- Show status bar item (checkbox)

**Editing Pane:**
- Tab key behavior: indent or next field (radio matrix)
- Soft tabs (checkbox) + spaces per tab
- Check spelling as you type (checkbox)
- Auto-pairing of brackets/quotes (checkbox)
- Auto-indent new lines (checkbox)
- Auto-format list bullets (checkbox)
- Auto-format @done tag with strikethrough (checkbox)
- Auto-suggest inter-note links (checkbox)
- Make URLs clickable (checkbox)
- Highlight search terms (checkbox + color well)
- Paste preserves style (checkbox)
- Right-to-left text (checkbox)

**Fonts & Colors Pane:**
- Note body font (font panel button)
- Table font size (popup)
- Foreground text color (color well)
- Background text color (color well)
- Search highlight color (color well)
- Custom ET scrollbars on Lion+ (checkbox)
- Show grid lines (checkbox)
- Alternating row colors (checkbox)
- Max body width (slider)
- Manage text width in window (checkbox)

**Database Pane** (NotationPrefsViewController):
- Notes folder location (popup + file chooser)
- Storage format (popup: Database/Plain Text/RTF/HTML)
- Encryption on/off (checkbox)
- Change passphrase (button)
- Simplenote sync enable/disable + credentials
- Sync frequency
- Use Markdown import for HTML (checkbox)
- Use Readability for URL import (checkbox)
- Use Finder Tags vs OpenMeta (checkbox)
- Confirm file deletion (checkbox)
- Allowed file types and extensions (table views)

### 4.9 Font Handling

- Body font: User-selectable, default Helvetica 12pt, stored as archived `NSFont`
- Table font: System font at configurable size
- Monospace detection: `_bodyFontIsMonospace` adjusts paragraph style
- Font changes propagate to all notes via `NotationController:-restyleAllNotes`
- Preview CSS uses its own font stack (Helvetica, Arial, sans-serif)

### 4.10 Color Scheme / Themes

Three built-in schemes (Cmd-Alt-1/2/3):
1. **B/W**: Black text on white background
2. **Low Contrast**: Dark gray on light gray
3. **User**: Custom foreground/background from preferences

Colors affect: editor background, editor text, table background, table text, insertion point, selection, links.

`[INFERRED]` No explicit dark mode support beyond user-defined colors; the color scheme system predates macOS dark mode.

### 4.11 Window Behavior

- **Minimum size**: Enforced by split view constraints
- **Full-screen**: Toggle via Ctrl-Cmd-F; uses `NSApplicationPresentationAutoHideMenuBar | NSApplicationPresentationHideDock`
- **Window frame autosave**: Standard `NSWindow` frame autosave
- **Close behavior**: Configurable quit-on-close vs hide-on-close (`quitWhenClosingWindow`)
- **Dock icon**: Can be hidden (`LSUIElement` toggled at runtime)
- **Status bar item**: Optional menu bar icon with note commands
- **Window tabbing disabled**: `setAllowsAutomaticWindowTabbing:NO` on Sierra+

---

## 5. Keyboard Shortcuts — Complete List

### Global

| Shortcut | Action |
|----------|--------|
| User-configured hotkey | Activate nvALT (via PTHotKey) |

### Notes Menu

| Shortcut | Action |
|----------|--------|
| Cmd-L | Focus search field |
| Cmd-R | Rename note |
| Cmd-Shift-R | Reveal in Finder |
| Cmd-Shift-T | Tag note |
| Cmd-E | Export note |
| Cmd-P | Print note |
| Cmd-Delete | Delete note |
| Cmd-J | Select next note |
| Cmd-K | Select previous note |
| Cmd-D | Deselect / Snapback |

### Edit Menu

| Shortcut | Action |
|----------|--------|
| Cmd-Z | Undo |
| Cmd-Shift-Z | Redo |
| Cmd-X | Cut |
| Cmd-C | Copy |
| Cmd-Alt-C | Copy note link (`nvalt://find/...`) |
| Cmd-V | Paste |
| Cmd-Alt-V | Paste as Markdown link |
| Cmd-A | Select All |

### Find

| Shortcut | Action |
|----------|--------|
| Cmd-F | Find |
| Cmd-Alt-F | Find and Replace |
| Cmd-G | Find Next |
| Cmd-Shift-G | Find Previous |
| Cmd-Alt-E | Use Selection for Find |
| Cmd-Alt-J | Jump to Selection |

### Format

| Shortcut | Action |
|----------|--------|
| Cmd-T | Plain Text style (strip formatting) |
| Cmd-B | Bold |
| Cmd-I | Italic |
| Cmd-Y | Strikethrough |
| Cmd-Shift-L | Insert Link |
| Cmd-[ | Shift Left (decrease indent) |
| Cmd-] | Shift Right (increase indent) |

### View

| Shortcut | Action |
|----------|--------|
| Cmd-Alt-L | Toggle horizontal/vertical layout |
| Cmd-Shift-C | Collapse/expand notes list |
| Cmd-Alt-P | Toggle note body previews in list |
| Cmd-Alt-1 | B/W color scheme |
| Cmd-Alt-2 | Low Contrast color scheme |
| Cmd-Alt-3 | User color scheme |
| Cmd-Shift-K | Toggle word count |

### Preview

| Shortcut | Action |
|----------|--------|
| Ctrl-Cmd-P | Toggle markdown preview window |
| Ctrl-Cmd-M | Preview in Marked (external app) |
| Cmd-Alt-U | Toggle source view in preview |
| Cmd-Alt-S | Save preview as HTML |

### Bookmarks

| Shortcut | Action |
|----------|--------|
| Cmd-0 | Show bookmarks window |
| Cmd-1 through Cmd-9 | Restore bookmark 1-9 |
| Cmd-Shift-1 through Cmd-Shift-9 | Restore bookmark 10-18 `[INFERRED]` |
| Cmd-S | Add to saved searches |

### Navigation

| Shortcut | Action |
|----------|--------|
| Tab | Cycle: search field -> table -> editor |
| Escape | Cancel current operation / clear search |
| Return (in field) | Create note / select match |
| Return (in table) | Focus editor |
| Up/Down arrows | Navigate note list |
| Ctrl-Cmd-F | Toggle full screen |

---

## 6. Markdown & Preview

### 6.1 Rendering Engines

Three markup processors available as `NSString` categories:

| Mode | Category | Method | Implementation |
|------|----------|--------|----------------|
| Markdown | `NSString (Markdown)` | `+stringWithProcessedMarkdown:` | Wraps `Markdown.pl` (v1.0.1) `[INFERRED]` |
| MultiMarkdown | `NSString (MultiMarkdown)` | `+stringWithProcessedMultiMarkdown:` | External `multimarkdown` binary |
| Textile | `NSString (Textile)` | `+stringWithProcessedTextile:` | Wraps `Textile.pm` (v2.12) via Perl |

`[INFERRED]` Markdown mode actually redirects to MultiMarkdown (`markupProcessorSelector:` returns `stringWithProcessedMultiMarkdown:` for both Markdown and MultiMarkdown modes).

Additional methods:
- `+documentWithProcessedMultiMarkdown:` — full HTML document with template
- `+xhtmlWithProcessedMultiMarkdown:` — XHTML output
- `+processTaskPaper:` — TaskPaper format support

### 6.2 Preview Window

- **Type**: Separate `NSWindow` managed by `PreviewController` (NSWindowController subclass)
- **Nib**: `MarkupPreview.xib`
- **Renderer**: `WebView` (WebKit)
- **Tabs**: `NSTabView` with rendered preview tab and source view tab (`NSTextView`)
- **Buttons**: Save, Share, Sticky (lock), Print, View Source
- **Web Inspector**: Enabled by default (`WebKitDeveloperExtras` = true)

### 6.3 Custom CSS

Two CSS files bundled:

- **`custom.css`**: Full template CSS with screen/print media queries, scrollbar styling, typography
- **`customclean.css`**: Identical CSS for "clean" template (no jQuery)

User can override by placing custom files in Application Support directory (created by `+createCustomFiles`).

Key CSS features:
- Fixed-position layout for screen (`#wrapper` fixed, `#contentdiv` scrollable)
- Custom WebKit scrollbar styling (6px width, rounded thumb)
- Print media query with relative positioning
- Title bar (`h1.doctitle`) with gray background
- Responsive images (`max-width: 100%`)

### 6.4 HTML Templates

Two templates:

**`template.html`** (with jQuery):
```html
<title>{%title%}</title>
<style>{%style%}</style>
<h1 class="doctitle">{%title%}</h1>
<div id="contentdiv">{%content%}</div>
<script src="{%support%}/jquery.js"></script>
<!-- Back-to-top button, smooth anchor scrolling, widow prevention -->
```

**`templateclean.html`** (without jQuery):
```html
<title>{%title%}</title>
<style>{%style%}</style>
<h1 class="doctitle">{%title%}</h1>
<div id="contentdiv">{%content%}</div>
```

Template variables: `{%title%}`, `{%style%}`, `{%content%}`, `{%support%}`

### 6.5 Preview Updates

- **Notification-driven**: `TextViewHasChangedContents` notification triggers `requestPreviewUpdate:`
- **Debounced**: Uses `performSelector:withObject:afterDelay:` for rate limiting
- **Sticky mode**: `isPreviewSticky` prevents auto-update when switching notes
- **Outdated flag**: `isPreviewOutdated` tracks whether content needs re-render

### 6.6 Share Feature

- Sends note HTML to external service (peg.gd) via HTTP POST
- MIME multipart body with content
- Returns shareable URL displayed in `MAAttachedWindow` popover
- "View in Browser" button opens returned URL

---

## 7. Import/Export

### 7.1 Supported Import Formats

Via `AlienNoteImporter`:
- **Plain text** (`.txt`, `.text`, `.utf8`, `.utxt`)
- **RTF** (`.rtf`, `.rtx`)
- **RTFD** (`.rtfd` bundles)
- **HTML** (`.htm`, `.html`)
- **PDF** (via dynamically-loaded PDFKit)
- **Word** (`.doc`, `.docx`)
- **BLOR** — legacy Notational Velocity encrypted database
- **Web URLs** — fetched and converted (with optional Readability extraction)
- **Directories** — recursively imports all supported files
- **Stickies database** — macOS Stickies format
- **Web archives** (`.webarchive`)

Via pasteboard:
- `NSStringPboardType`, `NSRTFPboardType`, `NSRTFDPboardType`, `NSHTMLPboardType`
- `NSFilenamesPboardType` (file drag-and-drop)
- WebKit and Gecko URL pasteboard types

### 7.2 Export Formats

Via `ExporterManager`:
- Plain text (`.txt`)
- RTF (`.rtf`)
- HTML (`.html`)
- Word (`.doc`)
- Word XML (`.docx`)

Via preview:
- HTML from rendered Markdown/MultiMarkdown/Textile (Save Preview)
- With or without template wrapper

### 7.3 Clipboard Behavior

- **Paste preserves style**: Configurable (default: YES)
- **Rich text paste**: Sanitized via `santizeForeignStylesForImporting` — strips fonts, preserves bold/italic
- **URL paste**: Auto-detects URLs on pasteboard, option to create note from URL
- **Markdown link paste** (Cmd-Alt-V): Creates `[selected text](clipboard URL)` syntax
- **Pasteboard types written on copy**: Standard NSString + custom `NVPTFPboardType`

### 7.4 Printing

- `MultiplePageView` handles multi-page print layout
- Supports printing note body with custom font
- Preview window supports direct print via `printPreview:`
- Standard `NSPrintOperation` with `NSPrintInfo`

### 7.5 Services Menu

Defined in `Info.plist`:

```
Service: "nvALT: New Note from Selection"
  Shortcut: Cmd-Shift-V (global)
  Message: createFromSelection
  Accepts: public.text, com.apple.rtfd, com.apple.webarchive, com.adobe.pdf,
           com.apple.flat-rtfd, public.rtf, public.plain-text
```

### 7.6 Readability Import

- Bundled Python library at `readability/` (BeautifulSoup + readability.py + html2text.py)
- `AlienNoteImporter:-contentUsingReadability:` extracts article content from HTML
- `AlienNoteImporter:-markdownFromSource:` converts HTML to Markdown via html2text.py
- Optional via preference `UseMarkdownImportKey`

---

## 8. External Editor Support

### 8.1 How It Works

1. `ExternalEditorListController` maintains list of available editors
2. User triggers edit via menu or Cmd-E `[INFERRED]`
3. `NoteObject:-editExternallyUsingEditor:` called
4. `ODBEditor:-editNote:inEditor:context:` creates temporary file, opens in editor
5. `TemporaryFileCachePreparer` manages temp directory for editing files
6. Apple Events (ODB Editor Suite) handle callbacks:
   - `kAEModifiedFile` → note content updated from file
   - `kAEClosedFile` → editing session ended

### 8.2 File Watching

- ODB protocol handles modification callbacks via Apple Events
- For non-ODB editors: `[UNCLEAR]` — likely relies on directory monitoring
- `_filePathsBeingEdited` dictionary tracks active editing sessions

### 8.3 Supported/Configured Editors

**ODB-compliant editors** (detected automatically):
- WriteRoom (`com.hogbaysoftware.WriteRoom`)
- MultiMarkdown Composer (`com.multimarkdown.composer.mac`)
- Other ODB editors detected via `+ODBAppIdentifiers`

**User-added editors**: Any app selected via file chooser, stored in `UserEEIdentifiers` default

**Default editor**: Configurable in Preferences (`DefaultEEIdentifier`)

---

## 9. URL Scheme

### 9.1 Registered Schemes

From `Info.plist`:
```xml
<key>CFBundleURLSchemes</key>
<array>
    <string>nvalt</string>
    <string>nv</string>
</array>
```

### 9.2 Complete URL Actions

**`nvalt://find/{search_term}?parameters`**

Searches for notes matching `{search_term}` (URL-decoded).

Optional query parameters for direct note lookup:
- `NV={base64_uuid}` — Look up note by internal UUID (base64-encoded `CFUUIDBytes`)
- `SN={simplenote_key}` — Look up note by Simplenote sync key

Example:
```
nvalt://find/url%20test/?SN=agtzaW1wbGUtbm90ZXINCxIETm90ZRiY-dEFDA&NV=5WJ0eP3YRaCjyQn%2F8p62iQ%3D%3D
```

Behavior:
1. Pushes current note onto snapback stack
2. Performs search with decoded path
3. If UUID/key parameter resolves a note, reveals that specific note
4. Brings window to front

**`nvalt://make?parameters`**

Creates a new note with specified content.

Parameters:
- `title={url_encoded_title}` — Note title
- `txt={url_encoded_text}` — Plain text body
- `html={url_encoded_html}` — HTML body (converted to attributed string)
- `tags={url_encoded_tags}` — Labels/tags string
- `url={url_encoded_url}` — URL to fetch and import (overrides txt/html)

Behavior:
- If `url=` present: fetches URL via `AlienNoteImporter`, optionally with title
- If `title` + (`txt` or `html`): creates note directly
- If only `txt` or `html` (no title): creates via pasteboard mechanism

### 9.3 Inter-Note Links

Generated by `NoteObject:-uniqueNoteLink`:
```objc
[NSURL URLWithString:[@"nvalt://find/" stringByAppendingFormat:@"%@/?%@",
    [titleString stringWithPercentEscapes],
    // base64-encoded UUID as NV= parameter
]]
```

Used in:
- **Copy Note Link** (Cmd-Alt-C): Copies `nvalt://find/...` URL to clipboard
- **Wiki-style links**: `[[Note Title]]` creates `nvalt://find/Note%20Title` link attribute
- **LinkingEditor**: Clicking `nvalt://` links dispatches to `interpretNVURL:`

### 9.4 AppleScript

Defined in `Notation.sdef`:
```xml
<command name="search" code="nvsssrch" description="Perform a search">
    <direct-parameter>
        <type type="text" name="searchTerm"/>
    </direct-parameter>
</command>
```

`SearchCommand` class handles AppleScript search commands.

---

## 10. Tags & Organization

### 10.1 Tag Storage

Tags are stored as:
- **In-memory**: `NSString *labelString` on each `NoteObject` (comma-separated)
- **Parsed**: `NSMutableSet *labelSet` of `LabelObject` instances
- **On disk (file-based formats)**: Extended attributes via xattr
  - **OpenMeta**: `com.apple.metadata:kMDItemOMUserTags` xattr (plist-encoded array)
  - **Finder Tags**: macOS 10.9+ native tag API via `NSURL` resource values
- **On disk (database format)**: Serialized with `NoteObject` via `NSCoding`
- **Sync**: Tags synced as part of Simplenote note metadata

### 10.2 Tag UI

- **Tag column**: `LabelColumnCell` renders colored tag blocks in table
- **Tag editing**: Cmd-Shift-T opens `TagEditingManager` floating panel
- **Multi-tag**: `AppController:-multiTag:` for batch tagging multiple selected notes
- **Autocomplete**: `LabelsListController:-labelTitlesPrefixedByString:indexOfSelectedItem:minusWordSet:` provides tag completion
- **Tag filtering**: Click tag in column to filter notes by that tag
- **Display**: Tags rendered as small colored blocks with label text

### 10.3 OpenMeta / Finder Tags

- **NSFileManager (NV) category** provides tag read/write:
  - `getOpenMetaTagsAtFSPath:` — reads `kMDItemOMUserTags` xattr
  - `setOpenMetaTags:atFSPath:` — writes to xattr
  - `getFinderTagsAtFSPath:` — reads via `NSURL` resource values (10.9+)
  - `setFinderTags:atFSPath:` — writes via `NSURL` resource values
  - `mergedTagsForFileAtPath:` — combines OpenMeta + Finder tags
- **Preference**: `UseFinderTags` (default: NO) — switches between OpenMeta and Finder tags
- **Migration**: `NotationController:-mirrorAllOMToFinderTags` copies OpenMeta tags to Finder tags

### 10.4 Smart Folders / Saved Searches

`BookmarksController` provides saved search functionality:
- **Add**: Cmd-S saves current search + selected note as bookmark
- **Restore**: Cmd-1 through Cmd-9 restore bookmarks
- **Menu**: Bookmarks appear in menu with keyboard shortcuts
- **Persistence**: Saved to user defaults as dictionary representations
- **Note tracking**: Each bookmark stores `CFUUIDBytes` reference to the note, plus search string

---

## 11. Accessibility

### 11.1 VoiceOver Support

- **No custom accessibility code** found in the codebase
- Relies entirely on standard AppKit accessibility:
  - `NSTableView` provides row/column accessibility
  - `NSTextView` provides text accessibility
  - `NSTextField` provides field accessibility
- XIB files reference `NSAccessibility.h` in framework headers but no custom implementations

### 11.2 Accessibility-Specific Code

`[UNCLEAR]` No explicit accessibility roles, descriptions, or custom `NSAccessibility` protocol implementations were found. The app relies on Cocoa's default accessibility support.

---

## 12. Edge Cases & Quirks

### 12.1 Notable TODOs/FIXMEs

| File | Line | Comment |
|------|------|---------|
| `SimplenoteSession.m` | 179 | `TODO: Should we default to NSOrderedDescending (to force server-side sync) when in doubt??` |
| `NSFileManager_NV.m` | 202 | `TODO: use volumeCapabilities in FSExchangeObjectsCompat.c to skip some work` |
| `NSString_NV.m` | 153, 173, 179 | `TODO: possibly obsolete? SN api2 formats dates as doubles from start of unix epoch` |
| `NSString_NV.m` | 703 | `TODO: there are some false positives for UTF-8 detection; e.g., MacOSRoman copyright symbol` |
| `PreviewController.m` | 9 | `TODO for the defines only, can you get around that?` |
| `PreviewController.m` | 270, 276, 571 | `TODO high coupling; too many assumptions on architecture` |
| `GlobalPrefs.m` | 110 | `FIXME` (context unclear) |
| `NotationSyncServiceManager.m` | 222 | `XXX need to verify GMT conversions XXX` |

### 12.2 Deprecated API Usage

- **FSRef APIs** throughout (`FSRefMakePath`, `FSCreateFileUnicode`, `FSExchangeObjects`, `FSResolveAliasWithMountFlags`) — deprecated since macOS 10.8
- **Carbon File Manager** (`FSCatalogInfo`, `HFSUniStr255`, `FSGetCatalogInfo`) — deprecated
- **`FNSubscriptionUPP`** — old directory notification API (pre-FSEventStream)
- **`NSRunAlertPanel`** — deprecated alert API used in several places
- **`beginSheetForDirectory:`** — deprecated open panel method

### 12.3 Workarounds

- **Window tabbing**: Explicitly disabled on Sierra+ (`setAllowsAutomaticWindowTabbing:NO`)
- **Temporary file symlinks**: ODB editor resolves `/tmp/` → `/private/tmp/` manually
- **iBeam cursor hack**: `defaultIBeamCursorIMP` / `whiteIBeamCursorIMP` — method swizzling for dark background cursor
- **NSTextFinder hacks**: Multiple ivars (`selectedRangeDuringFind`, `lastImportedFindString`, `stringDuringFind`, `noteDuringFind`) to work around `NSTextFinder` limitations (comment: "just write your own, damnit!")
- **Database epoch upgrades**: Progressive migration through epoch iterations 1→4, each fixing different issues

### 12.4 Differences from Original Notational Velocity

nvALT adds:
- Markdown/MultiMarkdown/Textile preview (`PreviewController`, `NSString_*` categories)
- External editor support via ODB Editor Suite
- Readability URL import
- Auto-pairing for brackets/quotes
- Markdown formatting shortcuts
- Wiki-style `[[links]]` between notes
- Custom color schemes (B/W, Low Contrast, User)
- Status bar menu item
- Dock icon toggle
- Word count display
- Finder Tags support (alongside OpenMeta)
- Simperium API for Simplenote sync (replacing older API)
- Custom scrollbar appearance (`ETScrollView`, `BTTransparentScroller`)
- Horizontal/vertical layout toggle
- Copy note link feature
- Share to web (peg.gd)
- Preview in Marked (external app)
- Grid lines and alternating rows options
- Max text width control
- Various UI refinements (`ETContentView`, `DFView`, `LinearDividerShader`)
- WAL journal moved to `~/Library/Caches/` (configurable)

---

## 13. Dependencies & Third-Party Code

### 13.1 System Frameworks

| Framework | Purpose |
|-----------|---------|
| Cocoa.framework | Core macOS app framework |
| Carbon.framework | Legacy file system APIs (FSRef, etc.) |
| WebKit.framework | HTML preview rendering (WebView) |
| Security.framework | Keychain access, encryption |
| SecurityInterface.framework | Password entry UI |
| CoreServices.framework | Launch Services, file type detection |
| SystemConfiguration.framework | Network reachability monitoring |
| IOKit.framework | Power state callbacks, disk UUID |
| ApplicationServices.framework | Font/color services |
| Quartz.framework/PDFKit | PDF import (dynamically loaded) |

### 13.2 Bundled Frameworks

| Framework | Purpose | License |
|-----------|---------|---------|
| **Sparkle.framework** | Auto-update mechanism (check for updates, DSA signature verification) | MIT |
| **AutoHyperlinks.framework** | URL detection/highlighting in text views | BSD `[INFERRED]` |

### 13.3 Static Libraries

| Library | Purpose |
|---------|---------|
| `libcrypto.a` | OpenSSL cryptography (AES encryption, PBKDF2) |
| `libssl.a` | OpenSSL TLS (HTTPS for sync) |

### 13.4 Vendored Source Code

| Directory/Files | Purpose | License |
|-----------------|---------|---------|
| `Markdown_1.0.1/Markdown.pl` | Perl Markdown processor | BSD |
| `Textile_2.12/Text/Textile.pm` | Perl Textile processor | GPL `[INFERRED]` |
| `readability/` | Python: BeautifulSoup, readability.py, html2text.py — HTML article extraction | MIT/BSD `[INFERRED]` |
| `hashcash/libsha1.c, sha1.h` | SHA-1 hash implementation | `[UNCLEAR]` |
| `JSON/` | BSJSONEncoder — custom JSON serialization (BSJSONEncoder, NSString+BSJSONAdditions, etc.) | `[UNCLEAR]` |
| `RBSplitView/` | Custom resizable split view (RBSplitView, RBSplitSubview) | BSD/MIT `[INFERRED]` |
| `PTHotKeys/` | Global hotkey support (PTHotKey, PTKeyCombo, PTKeyBroadcaster, PTKeyComboPanel) | BSD `[INFERRED]` |
| `ODBEditor/` | External Editor protocol via Apple Events | BSD `[INFERRED]` |
| `library/openssl/` | OpenSSL header files for compilation | OpenSSL License |

### 13.5 Runtime Dependencies

- `multimarkdown` binary — external command for MultiMarkdown processing
- `perl` — system Perl for Markdown.pl and Textile.pm
- `python` — system Python for readability/html2text

---

## 14. Build & Configuration

### 14.1 Build Settings

| Setting | Value |
|---------|-------|
| Deployment Target | macOS 10.9 (Mavericks) |
| Architecture | x86_64 |
| Bundle Identifier | `net.elasticthreads.nv` |
| App Category | `public.app-category.productivity` |
| Code Signing | Enabled for embedded frameworks |
| Sandbox | **Not sandboxed** (no entitlements file) |
| ATS | `NSAllowsArbitraryLoads: YES` |
| AppleScript | Enabled (`NSAppleScriptEnabled: YES`) |
| Sparkle | DSA key: `dsa_pub.pem`, check interval: 345600s (4 days) |

### 14.2 Preprocessor Macros / Build Flags

```objc
// nvaDevConfig.h
#define kUseCachesFolderForInterimNoteChanges 1

// AppController.h
#define MarkdownPreview 13371
#define MultiMarkdownPreview 13372
#define TextilePreview 13373

// NotationPrefs.h
#define EPOC_ITERATION 4

// WALController.h
#define RECORD_SALT_LEN 32
```

Conditional compilation:
- `MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_6` — protocol conformance declarations
- `MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_7` — Lion features (toolbar toggle, NSTextFinder, scroll elasticity)
- `MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5` — FNSubscription fallback for Tiger
- `IsLionOrLater`, `IsLeopardOrLater`, `IsMavericksOrLater` — runtime version checks

### 14.3 Document Types (Info.plist)

| Type | Extensions | Role |
|------|-----------|------|
| RTFD | `.rtfd` | Viewer |
| HTML | `.htm`, `.html` | Editor |
| PDF | `.pdf` | Viewer |
| RTF | `.rtf`, `.rtx` | Viewer |
| Word | `.doc`, `.docx` | Viewer |
| Plain Text | `.txt`, `.text`, `.utf8`, `.utxt` | Viewer |
| BLOR | `.blor` | Viewer (legacy NV database) |

### 14.4 Localizations

- English (`en.lproj`) — primary
- German (`de.lproj`)
- French (`fr.lproj`)
- Italian (`it.lproj`)
- Portuguese (`pt-PT.lproj`)
- Chinese (`zh.lproj`)

### 14.5 XIB/NIB Files

- `MainMenu.xib` — main window and menus
- `MarkupPreview.xib` — preview window
- `SaveHTMLPreview.nib` — HTML save accessory
- Various dialog nibs: `PassphrasePicker`, `PassphraseChanger`, `BlorPasswordRetriever`, `KeyDerivationManager`, `URLGetter`, `ExporterManager`, `TagEditingManager`, `DeletionManager`, `BookmarksTable`, `NotationPrefsView`
