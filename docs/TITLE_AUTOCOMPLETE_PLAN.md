# Plan: Return activates the best title match (issue #13)

Audience: an implementer with no prior context on this repo.

## The problem

GitHub issue #13: in the "Search or Create" box, typing the start of an existing note's title (e.g. `Sho` for "Shopping List") and pressing Return **creates a new note called "Sho"** instead of opening "Shopping List". Original Notational Velocity / nvALT opens the best prefix match, and shows its content in the editor. The "Autocomplete note titles" preference (Settings > General > Search) has no effect.

## What the code does today (findings)

Repo layout: `NvEnvyCore/` is a Swift package (data and logic, unit-tested with `swift test`). `nvEnvy/nvEnvy/` is the macOS SwiftUI app. `nvEnvy/nvEnvyiOS/` is the iOS app. The Xcode project is generated from `nvEnvy/project.yml` with XcodeGen.

1. **Return handling** is `NotesViewModel.createOrSelectNote()` (`NvEnvyCore/Sources/NvEnvyCore/NotesViewModel.swift:211`). It trims `searchQuery`, then calls `SearchEngine.exactTitleMatch` against `allNotes`. On an exact (case-insensitive) match it selects that note. Otherwise it creates a new note. There is no prefix or fuzzy step. This is the bug.
2. **Callers:** macOS `MainView.swift:34-47` (`SearchField.onReturn`), the "Create ..." buttons and row in `nvEnvy/nvEnvy/NoteListView.swift` (lines ~26 and ~45), and iOS `nvEnvyiOS/UI/NoteListView.swift:68` (`.onSubmit(of: .search)`). All route to `createOrSelectNote()`. A single fix in the view model therefore covers both platforms, but see the caveat on the explicit Create buttons under "Design decisions".
3. **The autocomplete pref is dead.** `AppState.autocompleteEnabled` (`nvEnvy/nvEnvy/AppState.swift:125`, key `"autocomplete"`, default `false`) is persisted and shown in `PreferencesView.swift:37`, but nothing reads it. `SearchEngine.autocompleteTitlePrefix(notes:query:)` (`SearchEngine.swift:98`) exists and is unit-tested, but has no production callers. It was added in commit `064c083` ("Phase 6.2") and never wired up. It also only returns the first prefix match in array order, which is arbitrary.
4. **Search ranking** is `SearchEngine.filter` (`SearchEngine.swift:26`). It tiers results as exact title, then all tokens in title (substring), then body or tag. It does not distinguish a title prefix from any other substring, and it has no fuzzy matching. `docs/nvalt-architecture-audit.md` section 3.5 notes that nvALT itself is substring-only, and its autocomplete is a title-prefix check (audit lines ~295-301). So "fuzzy" in the issue really means prefix completion.
5. **List and selection:** the search runs after a 150 ms debounce (`searchQuery` didSet), results land in `filteredNotes`, and `sortedNotes` preserves the relevance order while a query is active. `selectedNoteID` drives the editor. `onNoteCommitted` moves focus to the editor.

## Goal and scope

Make Return open the best existing match when there is one, and create a note only when nothing plausible matches. Keep the explicit "Create ..." affordance so the user can still deliberately create a note whose title is a prefix of another (e.g. creating "Sho" next to "Shopping List").

In scope: the Return behavior, prefix-aware ranking, NV-style live preview of the top match (macOS), wiring or reworking the autocomplete preference, tests.
Out of scope: true typo-tolerant fuzzy matching (subsequence or edit distance). Decide separately if wanted. A prefix-first ranking gets the issue's muscle-memory workflow.

## Design decisions (recommended, confirm with the owner if unsure)

1. **Return rule.** On Return with a non-empty trimmed query:
   1. Exact title match, then select it (current behavior).
   2. Else the best title-prefix match, then select it.
   3. Else create a new note (current behavior).
   Matching is case-insensitive, and the title match must be against the full `allNotes` (not only `filteredNotes`, which can lag the 150 ms debounce).
2. **Best prefix match.** Among notes whose lowercase title has the query as a prefix, choose deterministically: shortest title first (closest to exact), then most recently modified, then alphabetical. This replaces the arbitrary "first in array" of `autocompleteTitlePrefix`. Make it a static function, e.g. `SearchEngine.bestTitlePrefixMatch(notes:query:)`, and either update or delete `autocompleteTitlePrefix` (and its three tests) accordingly. Do not leave two near-duplicate functions.
3. **The preference.** The existing default (`false`) is what makes the issue reproducible out of the box, and the reporter turned it on and saw no change (because it is unwired). Recommended: **make prefix-on-Return the default, always-on behavior** and repurpose the toggle to control the NV-style *inline selection* of the completion text (decision 6 below), or remove the toggle. Do not leave a dead toggle. If you keep the pref, change its default to `true` via `ud.object(forKey:) as? Bool ?? true` in `AppState.init` (line ~387). Existing users with a stored `false` keep it, which is acceptable. Mention this in the PR. If the owner prefers a minimal change, the alternative is to keep the toggle off by default and gate only the prefix step on it, but that leaves the default experience broken as reported, so it is not recommended.
4. **Explicit create must not be hijacked.** The in-list "Create "..."" row and the empty-state "Create" button should always create (skipping the prefix step), because the user clicked them on purpose. Add a parameter, e.g. `createOrSelectNote(allowPrefixMatch: Bool = true)`, or a separate `createNote(titled:)`. Pass `false` from those two buttons (macOS `NoteListView.swift` ~26 and ~45, iOS `NoteListView.swift` ~33). Keep a keyboard route to force-create: with prefix matching, a user who really wants a note named "Sho" has the Create row. Optionally also bind Cmd+Return in `SearchField` to force-create. If you add it, put it in `MainView`'s `onReturn` path and document it in the README.
5. **`showCreateRow`** (`updateShowCreateRow`, line ~280) stays "no exact title match", so the Create row still appears while typing a prefix. Leave it.
6. **Select the top match as you type (NV-style live preview). In scope.** As the user types, if the best result is a title-prefix (or exact) match, select it so the editor shows its content. The issue asks for this explicitly: "populating the content area so I can see what it says ... without leaving the note title filter". Spec:
   - **Where:** in `performSearch()` (`NotesViewModel.swift:186`), after `filteredNotes` is assigned and only on the non-stale path (after the `guard query == searchQuery`). Reuse the already-computed `sortedNotes`/`filteredNotes`. Do not run another scan.
   - **What qualifies:** the top note of the result list must have a lowercase title that has the trimmed lowercase query as a prefix (this includes an exact match). If the top result is only a substring or body match, do not auto-select. Clear the auto-selection instead (see "No match" below).
   - **Track ownership of the selection.** Add `private var autoSelectedNoteID: Note.ID?`. Auto-select is allowed only when `selectedNoteID == nil` or `selectedNoteID == autoSelectedNoteID`, i.e. the current selection is one the search put there. Whenever auto-select sets the selection, set `autoSelectedNoteID` to the same ID. If the user changes the selection themselves (clicks a row, or arrows down via `selectNextNote`/`selectPreviousNote`), `selectedNoteID != autoSelectedNoteID` and auto-select stops overriding it until the query is cleared or the user presses Return. Reset `autoSelectedNoteID = nil` in `clearSearch()`, when the query becomes empty, and in `createOrSelectNote()` once it commits. This is the simplest reliable way to detect "the user took over" without view-layer focus tracking.
   - **No match:** if the previous selection was an auto-selection (`selectedNoteID == autoSelectedNoteID`) and the new top result does not qualify, set `selectedNoteID = nil` and `autoSelectedNoteID = nil`. The editor should not keep showing a note unrelated to what is being typed. A selection the user made by hand is left alone.
   - **Gates:** skip when the trimmed query is empty (do not select the first note of the whole vault on clear) and when `tagFilter != nil` (the user is browsing a tag, not typing a title). Gate the feature on `autocompleteEnabled`. `NotesViewModel` lives in `NvEnvyCore` and cannot see `AppState`, so add a plain property `public var autoSelectTitleMatch: Bool = false` on the view model, and have `AppState` set it from `autocompleteEnabled` (initial value in `init`, and in the `didSet` at `AppState.swift:125`). iOS leaves it `false`: the iOS list/detail layout navigates on selection, so auto-selecting would push the editor over the list mid-typing. Do not enable it on iOS without a design pass.
   - **Never steal focus.** Only the `onNoteCommitted` hook moves focus to the editor, and auto-select must not call it. The cursor stays in the search field.
   - **Does not touch history or disk.** Auto-select must not push onto `snapbackStack`. Do not mutate the note or its modified date. Selecting a note only displays it.
   - **Return after an auto-select** goes through the normal `createOrSelectNote()` path (decision 1), which commits the selection, moves focus into the editor, and clears `autoSelectedNoteID`.
   - **Known interaction to verify:** `SearchField`'s Down-arrow handler (`SearchField.swift:23-35`, via `MainView.swift:51`) calls `selectNextNote()` and then forces table row 0 selected. With a row 0 auto-selected, `selectNextNote()` advances to row 1 and the NSTableView call then resets to row 0, so the net effect should be row 0 selected. Confirm manually that Down arrow still lands on the first row and that further arrowing works. If it jumps wrongly, make the Down handler start from the current selection instead.
7. **Ranking.** In `SearchEngine.filter`, split tier 1 so title-prefix matches sort ahead of other title-substring matches (a new tier between exact and substring). This makes the top row, the Return target, and the previewed note agree. Within a tier, keep the current input order. Be careful with the incremental-search optimization (`previousQuery` / `previousResults`): extending a query only narrows results, so a prefix tier remains valid, but add a test that backspacing and retyping gives the same ordering as a cold search.

## Implementation steps

1. `SearchEngine.swift`: add `bestTitlePrefixMatch` (rule in decision 2); remove or fold `autocompleteTitlePrefix`; add the prefix tier to `filter` (decision 7).
2. `NotesViewModel.swift`: update `createOrSelectNote` per decisions 1 and 4. When a prefix match is chosen, mirror the exact-match branch: `filteredNotes = [match]`, `selectedNoteID = match.id`, `onNoteCommitted?(match.id)`. Think about whether replacing `filteredNotes` with the single match is right here. The exact-match branch already does this, so stay consistent. Leave `searchQuery` as typed so the user can see what they typed.
3. Callers: pass `allowPrefixMatch: false` from the explicit Create buttons (macOS and iOS).
4. Preference (decision 3): update `AppState.swift` and `PreferencesView.swift`. If the toggle is repurposed, change its label and add a help string, and update `Localizable.xcstrings` (the app uses `String(localized:)` and SwiftUI localized literals).
5. Live preview (decision 6): add `autoSelectedNoteID` and `autoSelectTitleMatch` to `NotesViewModel`, apply the rule in `performSearch()`, reset in `clearSearch()` and `createOrSelectNote()`. Wire `AppState` to set `autoSelectTitleMatch` from `autocompleteEnabled`. Make this its own commit so the Return fix (steps 1-4) stands alone.
6. Docs: a short README line on the Return behavior and how to force-create.

## Tests (NvEnvyCore, run with `cd NvEnvyCore && swift test`)

Add to `SearchEngineTests.swift` and `NotesViewModelTests.swift`. See the existing `createOrSelectNote` tests (lines 16-73 and 219) for how the view model is set up without a store.

- Return with query `Sho` and notes ["Shopping List", "Show Notes"] selects the deterministic best match (shortest title), and creates nothing.
- Exact match still wins over a longer prefix match ("Shop" with notes "Shop" and "Shopping List" selects "Shop").
- No prefix or exact match still creates (needs the store path; follow the existing create tests, or assert the no-match branch does not set `selectedNoteID` synchronously).
- Case-insensitivity: `sho` matches "Shopping List".
- Leading and trailing whitespace in the query is trimmed. Whitespace-only does nothing.
- `allowPrefixMatch: false` creates even when a prefix match exists.
- Ranking: title-prefix notes sort before substring-only title matches, which sort before body-only matches. Backspace/retype ordering equals cold-search ordering (incremental cache).
- Tie-breaks: equal-length titles resolve by most recent `modifiedDate`, then alphabetically.
- Update or remove the three `testAutocompleteTitlePrefix*` tests to match the replaced function.

### Live-preview tests (`NotesViewModelTests.swift`)

The existing search tests drive `performSearch()` by assigning `searchQuery` and then `try await Task.sleep(for: .milliseconds(300))` to outlast the 150 ms debounce (see "Debounced / off-main search", around line 144). Follow that pattern. Use `seedAllNotes(_:)` for setup, set `vm.autoSelectTitleMatch = true`, and mark the tests `async throws`.

- **Selects a prefix match:** notes ["Shopping List", "Meeting"], query `Sho`, wait. `selectedNoteID == shoppingList.id`, and `onNoteCommitted` was not called (set a closure that flips a flag).
- **Selects an exact match:** query `Meeting`, wait. Selects "Meeting".
- **Prefers the better prefix match:** notes "Shop" and "Shopping List", query `Sho`. Selects "Shop" (shortest title, per decision 2). This pins the auto-select to the same function that Return uses, so preview and Return can never disagree. Also assert that after waiting, `vm.createOrSelectNote()` selects the same ID.
- **Substring or body-only top result does not select:** notes ["Grocery Shopping"] (contains but does not start with `shop`) and a note with `shop` in the body. Query `shop`, wait. `selectedNoteID == nil`.
- **Disabled flag:** `autoSelectTitleMatch = false`, same setup as the first test. `selectedNoteID == nil`.
- **Empty query never selects:** type `Sho`, wait (selected), then `vm.searchQuery = ""`, wait. Selection is cleared (it was an auto-selection), and the first note in the vault is not selected.
- **Keeps narrowing as you type:** notes "Shopping List", "Show Notes". Query `Sho`, wait, then query `Shopp`, wait. Selection ends on "Shopping List". Then query `Show`, wait. Selection moves to "Show Notes".
- **Clears a stale auto-selection:** query `Sho` (selects), then `Shx`, wait. `selectedNoteID == nil`, and `autoSelectedNoteID` is reset.
- **User selection wins:** query `Sho`, wait (auto-selects A). Set `vm.selectedNoteID = B.id` as the user would (or call `vm.selectNextNote()`). Then query `Shop`, wait. `selectedNoteID` is still B. Also verify that a later no-match query does not clear the user's choice.
- **Auto-selection resumes after clear:** continuing from the previous test, `vm.clearSearch()`, wait, then query `Sho`, wait. Auto-select works again.
- **Tag filter gate:** set `vm.tagFilter = "work"` and a matching prefix query. `selectedNoteID` stays nil.
- **Snapback untouched:** after an auto-select, `vm.snapbackStack.isEmpty`.
- **Stale result is dropped:** assign `Sho`, then immediately `Zzz`, wait. No selection from the superseded `Sho` run (this guards the `guard query == searchQuery` path).
- **Return commits an auto-selection:** query `Sho`, wait, call `createOrSelectNote()`. `onNoteCommitted` fires with the same ID, `allNotes.count` is unchanged, and a later non-matching query does not clear this committed selection (`autoSelectedNoteID` was reset).
- **Note content not modified:** record `modifiedDate` before and after the auto-select. They are equal.

### Regression guard

`PerformanceTests.swift` / `testPerformanceAt1KNotes`: auto-select adds only an O(1) check of the top result inside `performSearch()`. Re-run the performance tests and confirm no measurable change.

Manual check on macOS (build the "nvEnvy (Direct Download)" scheme after `cd nvEnvy && xcodegen generate`): create "Shopping List", type `Sho`, press Return, and confirm it opens the existing note with focus in the editor. Then type `Shopx`, press Return, and confirm a new note is created. Check the same on the iOS target if you can build it (iOS should behave as before for live preview: no auto-selection). With the toggle on, also check live preview: type `S`, `Sh`, `Sho`, and watch the editor follow the top prefix match without losing the cursor in the search box. Type `Shx` and confirm the editor clears. Click a different row mid-search, keep typing, and confirm your choice is not overridden. Press Escape and confirm the list and editor reset. With the toggle off, confirm nothing is selected as you type but Return still opens the prefix match. The `.searchable` submit path (`nvEnvyiOS/UI/NoteListView.swift:68`) is the same view-model call.

## Risks and gotchas

- Live preview fights the user: the `autoSelectedNoteID` ownership rule in decision 6 is what prevents the app from overriding a manual selection, so keep its tests. Editor side effects of changing `selectedNoteID` (e.g. `EditorView` search-term highlighting keyed on `searchQuery`, and the macOS list's `onChange(of: selectedNoteID)` scroll in `NoteListView.swift:86`) are expected and desired, but check that the list scrolls to keep the selected row visible while typing.
- Breaking the "I want to create a note whose title is a prefix of an existing one" workflow. Mitigated by the explicit Create row and button, plus optional Cmd+Return. Call this out in the PR description, because it is a deliberate behavior change that matches NV.
- `allNotes` can contain two notes with the same title in different folders or extensions (see `docs/FILENAME_KEY_COLLISION_PLAN.md`). The tie-break in decision 2 must be total, so the choice is deterministic.
- Do not do prefix matching on the main actor over huge vaults in a way that blocks typing. A linear scan of `cachedLowercaseTitle` on Return is cheap (the existing exact-match scan is the same cost), but do not add a per-keystroke scan on the main actor for the live preview. Reuse the results `performSearch` already computed.
- `PerformanceTests.swift` has search benchmarks. Re-run them after changing `filter`.
- CONTRIBUTING.md asks for one logical change per PR, a regression test for bug fixes, and all tests passing. Do it in one PR with two commits: the Return fix (steps 1-4, 6), then the live preview (step 5), so a reviewer can drop the second without losing the bug fix.

## Definition of done

- The issue's repro (type 3 characters, press Return) opens the existing note and shows its content, on macOS and iOS.
- A query with no exact or prefix match still creates a note.
- Explicit Create affordances still always create.
- With the toggle on (macOS), typing a title prefix live-selects the best match and shows its content without moving focus, never overrides a manual selection, and clears when nothing matches or the query is cleared. iOS is unchanged.
- The autocomplete preference is either removed or does what its label says, and the default produces the behavior from the issue.
- `swift test` in `NvEnvyCore` passes, including the new tests.
