# nvEnvy

A fast, keyboard-driven note-taking app for macOS. A modern rebuild of nvALT built with Swift and SwiftUI, targeting macOS 14+.

## Screenshots

<!-- TODO: Add screenshots -->

## Features

- **Instant search** — Type to search, Return to create. Incremental filtering with phrase search support.
- **Plain-text Markdown** — Notes stored as plain `.md` files with YAML frontmatter for tags and dates.
- **Keyboard-first** — Full keyboard navigation: ⌘L to search, ⌘J/K to navigate, Escape to go back.
- **iCloud sync** — Drop your notes folder in iCloud Drive for seamless sync with conflict resolution.
- **Wikilinks** — `[[link to note]]` with autocomplete and click-to-navigate.
- **Tags** — Frontmatter tags, batch tagging, tag sidebar with counts, Finder tag mirroring.
- **Markdown preview** — Live HTML preview with custom CSS, source view, and Print/Save HTML.
- **Import/Export** — Import from Markdown, RTF, RTFD, HTML, PDF, Word, web archives. Export to plain text, HTML, RTF, Word.
- **nvALT migration** — One-click import from nvALT with OpenMeta tag migration.
- **Bookmarks** — Save and recall search queries with keyboard shortcuts (⌘1-9).
- **URL schemes** — `nvenvy://find/title` and `nvenvy://make?title=...&body=...` for automation.
- **AppleScript & Shortcuts** — Full scripting support via `.sdef` and App Intents.
- **Services menu** — Create notes from selected text in any app.
- **Auto-update** — Sparkle integration for seamless updates.
- **Localized** — English, German, French, Italian, Portuguese (BR), Chinese (Simplified).

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘L | Focus search field |
| Return | Create or select note |
| Escape | Return to search |
| ⌘J / ⌘K | Next / Previous note |
| ⌘D | Deselect (or snapback) |
| ⌘⇧T | Edit tags |
| ⌘⇧C | Toggle note list |
| ⌘⌥L | Toggle layout (side-by-side / stacked) |
| ⌘B / ⌘I / ⌘Y | Bold / Italic / Strikethrough |
| ⌘T | Plain text style (strip formatting) |
| ⌘] / ⌘[ | Indent / Outdent |
| ⌘⇧L | Insert link from clipboard |
| ⌘⌥V | Paste as Markdown link |
| ⌘⌥C | Copy note link |
| ⌘⌃P | Toggle preview window |
| ⌘⌥U | Toggle preview source |
| ⌘⇧K | Toggle word count |
| ⌘E | Export note |
| ⌘P | Print |
| ⌘S | Save bookmark |
| ⌘0 | Show bookmarks |
| ⌘1-9 | Restore bookmark |
| ⌘R | Rename note |
| ⌘⇧R | Reveal in Finder |
| ⌘⌫ | Delete note |

## Build Instructions

### Prerequisites

- Xcode 15+ with Swift 5.9
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- macOS 14.0+

### Build the Core Framework

```bash
cd NvEnvyCore
swift build
swift test
```

### Build the App

```bash
cd nvEnvy
xcodegen generate
xcodebuild -project nvEnvy.xcodeproj -scheme nvEnvy build
```

### Run Tests

```bash
cd NvEnvyCore
swift test   # 168 unit tests
```

## Project Structure

```
nvEnvy/
  nvEnvy/         — macOS app target (SwiftUI + AppKit)
  project.yml     — XcodeGen project spec
NvEnvyCore/       — Swift Package (platform-agnostic data layer)
  Sources/
  Tests/
```

## Distribution

See [RELEASING.md](RELEASING.md) for archive, code signing, notarization, and DMG creation instructions.

## License

<!-- TODO: Add license -->
