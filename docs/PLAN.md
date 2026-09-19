# Notes — build plan

Android-only notes app in Flutter. Google Keep's proven mechanics, its own identity.
Local-first storage, import/export from day one, sync-ready schema for later.

---

## 1. Product definition

- **Primary user:** one person on one Android phone, capturing things fast and finding them later.
- **Main task:** get a thought out of the head in under 3 seconds; re-find it in under 10.
- **The one action that matters:** capture. It stays reachable from every screen.
- **Non-goals for v1:** accounts, collaborators, real-time sync, web app, iOS, rich text (bold/italic/links), drawing, audio notes, location reminders, landscape and tablet layouts, and connections to Google services such as Drive, Gmail, or Calendar.
- **Deliberately deferred but designed for:** cloud sync, home-screen widget, share-to-app intent, Keep Takeout import.

---

## 2. Stack

| Layer | Choice | Why |
|---|---|---|
| Framework | Flutter stable (3.x), Dart 3.x | Android-only, single codebase, good animation control |
| State | Riverpod (`riverpod`, `riverpod_generator`, `riverpod_annotation`) | Compile-safe DI, stream providers map cleanly onto Drift watch queries |
| Database | Drift + `drift_flutter` (sqlite3 3.x bundles native SQLite; `sqlite3_flutter_libs` is EOL) | Real SQL, FTS5 for search, typed migrations, reactive `watch()` streams, easy to sync later |
| Models | `freezed` + `json_serializable` | Immutable entities, generated JSON for export |
| Routing | `go_router` | Deep links for reminder taps and share intents |
| Masonry | `flutter_staggered_grid_view` | `MasonryGridView` for the grid; drag-reorder is custom (see Risks) |
| Notifications | `flutter_local_notifications` + `timezone` | Exact alarms, actions, boot reschedule |
| Images | `image_picker` (Android Photo Picker), `flutter_image_compress`, `path_provider` | No storage permission needed on 13+ |
| Files | Android's document pickers through a channel in `MainActivity`, `share_plus`, `archive` | Export bundle out via SAF, import back in; files are streamed, never passed as bytes |
| IDs | `uuid` v7 | Time-sortable, collision-free, sync-friendly |
| Lint | `very_good_analysis` | Stricter than default, catches slop early |

Android config: `minSdk 24`, `targetSdk 36`, `compileSdk 36`, Kotlin, core library desugaring on
(required by `flutter_local_notifications`).

**Rejected:** Isar (maintenance risk), Hive (no query/FTS story), Bloc (more ceremony than this app needs),
stock Material 3 theming (see the design contract — we theme it ourselves).

---

## 3. Architecture

```
lib/
  main.dart
  app.dart                     # MaterialApp.router, theme wiring
  core/
    theme/                     # tokens.dart, typography.dart, app_theme.dart, pigments.dart
    router/                    # routes, deep links
    util/                      # date grouping, debounce, sort keys, result types
  data/
    db/                        # database.dart, tables/, daos/, migrations/
    repository/                # NoteRepository, LabelRepository, AttachmentRepository, ReminderRepository
    mapper/                    # row <-> domain
  domain/
    model/                     # Note, ChecklistItem, Label, Attachment, Reminder (freezed)
    service/                   # ReminderScheduler, BackupService, ImageService, SearchService
  features/
    notes/       # grid, card, selection mode, filter chips, drawer
    editor/      # note editor, checklist editor, color sheet, label sheet, reminder sheet
    search/
    labels/
    archive/
    trash/
    settings/
  widgets/                     # shared primitives (pigment spine, meta text, empty state, skeleton)
```

Rules:
- Widgets never touch Drift. Repositories return domain models only.
- One Riverpod notifier per screen; the grid subscribes to a `Stream<List<Note>>`.
- Every mutation goes through a repository so undo, sync flags, and the FTS index stay consistent.

---

## 4. Data model

Sync-ready from the start: every table carries `updated_at` (UTC millis), a `deleted` tombstone, and
`dirty` (0/1). No hard deletes except trash purge and explicit destructive settings actions.

```sql
notes(
  id TEXT PK,                 -- uuid v7
  type TEXT,                  -- 'text' | 'checklist'
  title TEXT,
  body TEXT,                  -- text notes only
  pigment TEXT,               -- 'graphite' | 'vermilion' | ...
  pinned INT,
  archived INT,
  sort_key TEXT,              -- fractional index string, for manual drag order
  reminder_at INT NULL,       -- UTC millis
  reminder_rule TEXT NULL,    -- null | 'daily' | 'weekly' | 'monthly' | 'yearly'
  reminder_done INT,
  created_at INT, updated_at INT, deleted INT, dirty INT
)

checklist_items(
  id TEXT PK, note_id TEXT FK, text TEXT, checked INT,
  indent INT,                 -- 0 or 1
  sort_key TEXT, updated_at INT, deleted INT, dirty INT
)

labels(id TEXT PK, name TEXT, sort_key TEXT, updated_at INT, deleted INT, dirty INT)
  -- UNIQUE INDEX ON labels(name COLLATE NOCASE) WHERE deleted = 0: a deleted label's name is free again

note_labels(note_id TEXT, label_id TEXT, PRIMARY KEY(note_id, label_id), updated_at INT, deleted INT)

attachments(
  id TEXT PK, note_id TEXT FK, rel_path TEXT, thumb_path TEXT,
  width INT, height INT, bytes INT, mime TEXT,
  sort_key TEXT, created_at INT, deleted INT, dirty INT
)

trash(note_id TEXT PK, deleted_at INT)   -- purge removes notes older than 7 days

recent_searches(folded TEXT PK, query TEXT, used_at INT)   -- this device only; the last three are kept

preferences(key TEXT PK, value TEXT)   -- settings and first-run flags; this device only, never exported

notes_fts USING fts5(title, body, items, labels, tokenize='unicode61 remove_diacritics 2', prefix='1 2 3')
  -- one row per note under the note's rowid, rebuilt by triggers on notes, checklist_items, note_labels,
  -- and labels, in the same statement as the write
```

Indexes: `notes(archived, deleted, pinned, sort_key)`, `notes(reminder_at)`, `note_labels(label_id)`,
`checklist_items(note_id, sort_key)`.

**Ordering:** `sort_key` is a fractional index (a lexicographic string between its neighbours) so a
drag-reorder is one row write and never renumbers the table. Default order for new notes is newest first.

---

## 5. Design contract

Direction: **ink on paper, pigment on the edge.** Notes look like written material, not like chrome.
Color codes a note without flooding it. Chrome is nearly invisible; type and pigment carry the hierarchy.

### Tokens

Light — ground `#F4F5F3`, card `#FFFFFF`, ink `#16181A`, ink-muted `#5C6360`, hairline `#E0E2DE`
Dark — ground `#0F1113`, card `#191C1E`, ink `#E9EDEA`, ink-muted `#9AA3A0`, hairline `#262A2C`
Accent (actions, focus, selection) — verdigris `#28706D` light / `#5FB3AE` dark. The light accent is a step
deeper than the verdigris spine so accent text keeps 4.5:1 on every tint and on the selected-row wash
(milestone 7).
Danger — `#B3402C`

Pigments (8; `graphite` means none). Each defines a spine color plus a card tint per theme:

| Name | Spine | Tint light | Tint dark |
|---|---|---|---|
| graphite | — | card | card |
| vermilion | `#C9452E` | `#FBEDE9` | `#241614` |
| amber | `#B77A16` | `#FBF3E2` | `#221B10` |
| moss | `#4F7A3A` | `#EFF5EA` | `#151E14` |
| verdigris | `#2E7B78` | `#E9F4F3` | `#101F1E` |
| indigo | `#3D53A8` | `#ECEFFA` | `#141827` |
| plum | `#7A3E86` | `#F5EDF7` | `#1F1424` |
| clay | `#8A5A44` | `#F6EEE9` | `#201714` |

### Type

- **Literata** (variable) — note titles and note body. A reading face; makes notes feel written.
- **Schibsted Grotesk** — all UI: buttons, chips, drawer, app bar, sheets. (Replaced General Sans so every face is OFL and ships inside the APK.)
- **Martian Mono** — meta only: timestamps, group headers, counts, reminder times. 11px, +4% tracking, uppercase for headers.

Scale: display 28/32 · note title 17/22 · note body 15/22 · UI 14/20 · meta 11/14.
Fonts ship in `assets/fonts`, subset to Latin — no network font loading.

### Shape and depth

Cards: 14px radius, **1px hairline border and no drop shadow** in light mode; dark mode separates by
surface color alone. Sheets 24px top radius. Chips fully rounded. Spacing scale 4/8/12/16/24/32.

### Signature elements

1. **Pigment spine** — a 3px bar on the card's left edge; the card stays paper-neutral with only a faint
   tint. Color scans at a glance without turning the grid into a candy shop.
2. **Time gutter** — unpinned notes group by capture day under mono uppercase headers
   (`TODAY`, `YESTERDAY`, `07 SEP`) with a hairline running down the left margin. Recency is real
   information in a capture app, so it gets real structure instead of decoration.
3. **Grow-from-tap** — a card container-transforms into the editor, and the compose bar expands into a
   new note from the point of touch. One orchestrated motion, reused everywhere.

### Motion

Container transform 220ms `easeOutCubic` (card ↔ editor). Pushed pages (settings, labels, a note opened from a
notification) use Android's transition with predictive back, held to 250ms. Checkbox strike-through 140ms. Pin
and unpin reflow with a spring. Undo bars slide rather than fade. All of it collapses to an 80ms cross-fade
when `MediaQuery.disableAnimations` is set. The skeleton's slow pulse is an indicator, not a transition, and
holds still when animations are off.

### Required states on every list surface

loading (skeleton cards, not a spinner) · empty first run · empty search · empty label · empty archive ·
empty trash · error (DB read failure, with retry) · permission denied (notifications, exact alarms) ·
selection mode. Offline is not a state — everything is local.

Copy rules: active voice, sentence case, and an action keeps its name through the flow
("Delete" produces "Note deleted · Undo"). Empty screens invite one action and never apologize.

---

## 6. Feature specs

### 6.1 Core notes
- Masonry grid of 2 columns, portrait only; list-mode toggle for a single dense column.
- Pinned notes sit on top under their own `PINNED` header; the rest group by day.
- Compose bar fixed at the bottom: text note, checklist, image, camera.
- The editor autosaves on every change, debounced 400ms, and again on blur or back. No save button.
- Per-note actions: pigment, labels, reminder, archive, delete, copy, share as text.
- Long-press starts selection mode: bulk pigment, label, archive, delete, pin.
- Undo for every destructive action through a 5-second snackbar.
- Trash holds notes 7 days; purge runs at app start; "Empty trash" is manual.
- Drag-to-reorder writes a new `sort_key`; manual order then overrides date order until reset.

**Done when:** create → kill the app → reopen keeps every note, and delete → undo restores the
note with its labels, items, and attachments.

### 6.2 Checklists
- Item row: checkbox, text field, drag handle, remove button.
- Enter creates the next item; backspace at position 0 merges into the previous one.
- One level of indent (swipe or drag right); child items travel with their parent.
- Checked items animate into a collapsible `n checked items` section at the bottom (behavior settable).
- Convert text note ↔ checklist: lines become items and back.
- Uncheck all, and delete checked, from the overflow menu.

**Done when:** a 200-item list scrolls at 60fps and keyboard editing never loses the focus position.

### 6.3 Labels, search, filters
- Labels are created inline from the editor sheet; renamed, deleted, and reordered on a labels screen.
- Drawer: Notes, Reminders, each label, Archive, Trash, Settings.
- Search runs FTS5 across title, body, checklist item text, and label names, with prefix matching and
  debounce; results highlight the matched terms.
- Filter row above results: by type (checklist, image, reminder), by pigment, by label.
- The empty-search state offers the last three searches.

**Done when:** search across 5,000 notes returns in under 50ms on a mid-range device.

### 6.4 Reminders
- One reminder per note: date and time, or quick picks (later today, tomorrow morning, next week).
- Optional repeat: daily, weekly, monthly, yearly.
- The notification carries **Done** and **Snooze 10m** actions, and tapping it deep-links into the note.
- Every reminder is rescheduled on `BOOT_COMPLETED` and after an app upgrade.
- Reminders view in the drawer: overdue, today, upcoming.
- Permissions: request `POST_NOTIFICATIONS` when the first reminder is set (Android 13+). For
  `SCHEDULE_EXACT_ALARM` (Android 12+), deep-link to system settings; if refused, fall back to
  `inexactAllowWhileIdle` and say plainly that reminders may run late. Do not ship `USE_EXACT_ALARM` —
  Play policy reserves it for alarm and clock apps.

**Done when:** a reminder set two minutes out fires after a reboot with the app never reopened.

### 6.5 Images
- Attach from the Android Photo Picker or the camera; several per note.
- Compress to a 2048px long edge and generate a 400px thumbnail; both live under app documents and the
  DB stores relative paths only.
- The card shows up to 3 thumbnails in a mosaic with a `+n` overflow; the editor shows the full strip.
- Tap opens a pinch-zoom viewer with swipe between attachments and delete from inside it.
- An orphan sweep at start removes files with no attachment row.

**Done when:** 50 images across notes add under 300ms to cold start and no files leak after a note is deleted.

---

## 7. Import and export

Bundle format: a zip named `notes-export-YYYYMMDD-HHmm.zip`.

```
manifest.json     { schemaVersion, appVersion, exportedAt, counts }
notes.json        [ full note objects incl. items, labels, reminder, attachment refs ]
labels.json
media/<attachmentId>.<ext>
media/thumbs/<attachmentId>.jpg   (added in milestone 6: an import need not remake thumbnails)
```

- Export writes to a temp file, then hands it to the system share/save sheet (SAF).
- Import modes: **Merge** (matching ids keep the newer `updated_at`, new ids are appended) or
  **Replace** (wipe local, restore the bundle) behind a typed confirmation.
- Import runs in one transaction after a dry-run summary: `+42 notes, 8 updated, 3 labels, 12 images`.
- A bundle with a newer `schemaVersion` than the app understands is refused with a clear message.
- Stretch (phase 7): a Google Keep Takeout importer for `Takeout/Keep/*.json`.

---

## 8. Android platform work

- Manifest: `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`, the boot
  receiver, the notification-action receiver, and `android:enableOnBackInvokedCallback="true"`.
- Portrait only: `android:screenOrientation="portrait"` on the activity, plus
  `SystemChrome.setPreferredOrientations` so the lock holds from the first frame.
- Predictive back (Android 14+); back from the editor commits the note.
- Edge-to-edge with correct insets on the compose bar and the keyboard.
- Notification channel `reminders` at HIGH importance, created on first run.
- `android:allowBackup="false"` — the export bundle is the backup story, and auto-backup would resurrect
  stale databases.
- Adaptive icon plus a monochrome layer for themed icons. The launch screen is written by hand rather than
  with `flutter_native_splash`: the ground colour for each theme, and on Android 12+ the icon on it, with the
  app's own theme choice handed to Android through `UiModeManager.setApplicationNightMode`.
- `dataExtractionRules` keep the database, files, and preferences out of cloud backup and device transfer.
- Home screen widgets (milestone 8), drawn with `RemoteViews` from a JSON snapshot the app writes, so they
  show notes with the app closed. Each notes widget shows one feed, chosen as it is placed: every note, the
  pinned ones, or one label's. Their colours are copies of the theme tokens in `res/values*/colors.xml`,
  kept equal by a test; their faces are the system's serif, mono, and sans, since a launcher does not load
  an app's font resources.
- Release: R8 keep rules for the notifications plugin's Gson storage, `res/raw/keep.xml` for the notification
  icon, app bundle output, signing from `key.properties`.

---

## 9. Milestones

| # | Milestone | Contents | Checkpoint |
|---|---|---|---|
| 0 | Scaffold | Project, lints, folders, theme tokens, fonts, Drift schema v1, seed data, one card rendering | App runs, seeded grid reads correctly in light and dark |
| 1 | Core notes | Grid, editor, autosave, pin, pigments, archive, trash, undo, selection, reorder | Full create/edit/delete loop survives restart |
| 2 | Checklists | Item model, editor interactions, indent, checked section, conversions | 200-item list smooth, keyboard flow correct |
| 3 | Labels + search | Label CRUD, drawer, FTS5, filter chips, highlighting | Search under 50ms at 5k notes |
| 4 | Reminders | Scheduler, permissions, notification actions, boot reschedule, reminders view | Fires after a reboot |
| 5 | Images | Picker, compression, thumbnails, mosaic, viewer, orphan sweep | No file leaks, cold start unaffected |
| 6 | Import/export + settings | Bundle writer and reader, merge vs replace, settings (theme, purge window, checked-item behavior) | Export → wipe → import round-trips identical content |
| 7 | Polish + finish gate | All states, accessibility, motion, performance, release build | The gate in §10 is fully green |
| 8 | Home screen widgets | A notes widget (pinned, then latest) and a new note widget (the compose bar), placing them from settings | Both widgets draw with the app closed, and every tap lands in the right place |

Later: sync backend, share-to-app intent, Keep Takeout import, tablet layout.

---

## 10. Quality gates

**Finish gate — all of it passes before v1 is called done:**
- Every list surface renders its loading, empty, and error states with real copy.
- No hardcoded color or font size outside `core/theme`.
- Text contrast at least 4.5:1 in both themes, including on every pigment tint.
- Touch targets at least 48dp; TalkBack reads each card as one node with a useful label.
- 200% text scale clips and overlaps nowhere.
- `disableAnimations` is honored; no animation runs longer than 300ms.
- Nothing distorted, clipped, or inert; long titles and 5,000-character bodies render correctly.
- Process death preserves editor content.

**Tests:** unit for repositories, sort keys, recurrence math, and import merge rules; widget tests for
editor autosave and checklist keyboard behavior; golden tests for the note card across pigments and
themes; one integration test for create → remind → fire.

**Performance:** `const` widgets throughout, a `RepaintBoundary` per card, a paged grid query (100 rows
plus a scroll window), and thumbnails that never decode at full resolution.

---

## 11. Risks and open decisions

| Risk | Handling |
|---|---|
| Drag-reorder inside a masonry grid has no ready package | Custom drag layer: capture item rects, drive an overlay with `Draggable`, and compute a fractional `sort_key` on drop. Budget a day; the fallback is reorder in list mode only |
| Exact alarms may be denied, and Play may reject `USE_EXACT_ALARM` | Ship the `SCHEDULE_EXACT_ALARM` request with an inexact fallback and an honest in-app explanation |
| OEM battery managers (Xiaomi, Samsung) drop alarms | Detect known OEMs and show a one-time hint linking to autostart settings |
| The FTS index drifting from the DAO writes | All writes go through DAO methods that update FTS in the same transaction, plus a rebuild-index action in settings |
| Bundled fonts inflate the APK | Subset Literata, Schibsted Grotesk, and Martian Mono to Latin and punctuation; check the size at milestone 0 |

**Decided during milestone 0:**
- Order is capture order, newest first, stored as `sort_key`; a drag overrides it. Editing a note does not move it.
- Sections group by capture day (`created_at`), so a note stays under the day it was written. The gutter applies in grid and list layouts.
- Checked checklist items collapse by default (milestone 2).

---

## 12. Progress

### Milestone 0 — done (2026-09-14)

Checkpoint met: the app runs on an Android 17 emulator, and the seeded grid reads correctly in light and
dark. Analyzer clean; unit, repository, and widget tests pass.

Found and fixed while verifying:
- Sort keys rounded their midpoint down, which could produce a key ending in `a` with nothing able to sort
  below it. Now rounds up, covered by randomised insert tests.
- The generated database part could not see the column enums, because a part only sees its library's
  imports. The analyzer missed it because generated files were excluded; they are now analysed for errors,
  with lints silenced through `build.yaml`.
- Reminder chip, card footer, and compose bar overflowed on a 360dp phone at 200% text. Chips ellipsize,
  the footer wraps, the bar grows, and in-card meta uses Martian Mono's condensed width axis.
- Android can hand Flutter a zero-width surface on the first frame, and the masonry grid asserted on a
  negative column width. That frame is now skipped.
- The time gutter line collapsed to zero height under `Align`; it now stretches.
- Note streams were `async*` generators that only noticed a cancel at the next database write, leaving a
  listener behind every closed screen. They are now controller-based, cancel immediately, and drop stale
  reloads.

### Milestone 1 — done (2026-09-15)

Checkpoint met: create, edit, and delete survive a restart. Covered by 89 tests, and the flows below were
also driven on the Android 17 emulator unless noted under "Carried forward".

- Full-page editor growing out of its card: autosave, pin, archive, colour sheet, share, make a copy,
  delete. A new note is only created once it holds something; opening and closing a note without editing
  it leaves its edited time and sync flag alone; tapping the blank page starts typing.
- Drawer with Notes, Archive, and Trash. Trashed notes open read-only with Restore and Delete forever;
  Empty trash asks first.
- Selection mode with bulk pin, colour, archive, and delete. Every action has undo, which restores each
  note's own previous state rather than one shared value.
- Drag-to-reorder within a section, with "Move earlier" and "Move later" for screen readers. The grid
  scrolls while a dragged note is held at its top or bottom edge.
- Share sends plain text to the system share sheet: the title and body, or checklist items as ☐/☑, as
  they read on the page.
- An edit survives the process being killed in the background.

Decisions and findings:
- Share and Make a copy stay in the menu but are disabled while the page is blank, so no menu item looks
  usable and does nothing.
- The app is portrait-only (decided 2026-09-15): the activity is locked upright, and there is no landscape
  or tablet layout.
- Leaving actions from the editor (archive, delete, restore) are applied by whoever opened it, after the
  close transition, so a card never disappears from the grid while its editor is still shrinking into it.
- Notes reorder only within their own section. Sections group by capture day, so a note dropped under
  another day would jump back under its own day on the next rebuild. Each drop writes one sort key.
- Android 16 and later hand back to the system unless the app claims it, and an open drawer does not
  claim it: one back press with the drawer open left the app. `ShelfScaffold` refuses the pop while the
  drawer is open, which does claim back, and closes the drawer. Covered by a test that watches the exact
  platform message.
- Cards hide their inner semantics so TalkBack reads one node, so the card itself now carries tap,
  long-press, and move actions; without them a screen reader could not open or select a note.

Carried forward:
- The compose bar's image and camera shortcuts arrive with milestone 5, alongside the feature they open.

### Milestone 2 — done (2026-09-15)

Checklists, covered by 135 tests in total and driven on the Android 17 emulator where noted.

- A "New list" button on the compose bar opens a list with its first line ready to type into. On the
  device: a fast burst of typing lands in that one item, Enter adds the next line with the cursor on it,
  the status reads NEW LIST, and backing out of an untouched list leaves nothing behind.
- Enter splits a line at the cursor; pasted lines become one item each; backspace in an empty item
  removes it and returns to the end of the item above.
- Ticking an item folds it under an "n checked items" count, collapsed by default (checked on the
  device). A parent carries its children when checked or unchecked; a child changes alone.
- Indent and outdent, and remove, on the focused row. Reorder by drag handle, where a parent moves with its
  children, and by the screen-reader actions "Move up" and "Move down".
- More menu: Show checkboxes turns a text note into a list line by line, Hide checkboxes turns it back
  with children indented, plus Uncheck all and Delete checked items.
- Empty items are cleared when the editor closes. Share and Make a copy use the list's current items.

Decisions and findings:
- A new list is created, with its first item, the moment the editor opens. The first version started the
  list on the first keystroke instead, and on the device a quick burst of typing raced that creation:
  "Oat milk" became three items, "Oat ", "l", and "k". A text note still waits for its first character.
- Indenting is a button on the focused row rather than the planned swipe or drag right: it is
  discoverable, works with a screen reader, and does not compete with scrolling or text selection.
- Closing a list tidies its empty items, which touches the database after the page is gone. Widget tests
  therefore unmount the editor before closing their in-memory database.

Carried forward:
- Drag-to-reorder of list items is covered by a widget test that drags a real handle through Flutter's
  gesture handling. On the emulator, injected touches landed on the text field instead of the handle,
  so it still wants a check by hand on a phone.
- Backspace at the start of a non-empty item joins it to the one above with a hardware keyboard and in
  tests. Soft keyboards send no key event when there is nothing before the cursor in a non-empty field, so
  on a phone that join may not happen; an empty item always works.
- "A 200-item list scrolls at 60fps" is checked as opening and scrolling to the last of 200 items without
  errors, with rows built lazily. The frame rate has not been measured on a device.

### Milestone 3 — done (2026-09-15)

Labels, search, and filters, covered by 208 tests in total. The emulator run was installed over a database
the milestone 2 build had written, so it also tried the upgrade on real data.

- **Upgrade.** Schema version 2 upgrades a version 1 database in place. On the emulator the grid kept all
  10 notes, and search found the lists typed there during milestone 2.
- **Labels.** A note's labels page opens from the More menu or from its label chips. Its one field both
  filters the list and makes a new label. Several selected notes can be labelled at once, and a dash marks
  a label only some of them wear.
- The drawer lists labels. A label's page shows its notes, and a note written there wears the label from
  the start. The labels page renames in place and refuses a name another label has in any case. It
  reorders by drag or with Move up and Move down, and deletes with undo.
- On the emulator:
  - the three labels from version 1 were in the drawer;
  - Reading's page held its 2 notes, and a note written there got the label;
  - Travel, made on the labels page, went onto Bike through the picker;
  - the editor and the search result card both showed it.
- **Search.** Search opens from the grid header. Words match titles, bodies, list items, and label names
  from their first letters, ignoring case and accents. The trash is left out, and archived notes come last
  under ARCHIVE.
- Matched words are highlighted. A match deep in a long body opens the card at that line, and matched
  list items and labels move to the front of the card.
- Type, Colour, and Label filters offer only what some note has, and work alone or with words. The last
  three searches are offered again.
- On the emulator: "sourdough" found 3 notes, the search came back under Recent, and the Lists filter alone
  found 4 notes.

Decisions and findings:
- **Search index.** A regular FTS5 table kept up to date by triggers, not the contentless table written
  by the repository that §4 first planned.
  - Triggers cover every path that writes a note, including import and sync, which are not written yet.
  - A regular table can drop a note's row by rowid.
  - The copied text is small.
- **Label names.** Names are unique among live labels, ignoring case, through a partial unique index.
  - Version 1's column constraint counted case and deleted labels, so the upgrade rebuilds the labels
    table.
  - SQLite's NOCASE folds only ASCII, so "Școală" and "școală" count as different names.
- **Undo after reuse.** Undoing a label delete after the name was used again puts the notes under the new
  label rather than making a second one.
- **Deleting a label.** No confirmation dialog, only undo, the same as deleting a note.
- **Selection bar.** It shows the count as a bare number. With six 48dp buttons, a 360dp phone has no
  room for "2 SELECTED".
- **Recent searches.** A search is remembered only when it is acted on, by opening a result or pressing
  the search key, so half-typed words are never stored.
- **Result limit.** One search loads at most 150 notes. The count covers every match, and a line says when
  more exist.
- **Label pages.** They show notes on the grid only. Archived notes with the label turn up in search with
  the Label filter.

Measured on this desktop, with 5,000 notes of which a fifth are lists of 8 items. Each time is the median
of 5 runs of a whole search, including loading up to 150 notes:

| Search | Median |
|---|---|
| "b" | 26ms |
| "bre" | 22ms |
| "bresto" | 18ms |
| "ka lo" | 21ms |
| "gra" with a colour | 16ms |
| Lists filter alone | 31ms |

Carried forward:
- **Search time on a phone.** "Done when" asks for under 50ms on a mid-range phone, which has not been
  measured. The slowest case above is loading 150 whole notes for a broad filter, not the index lookup.
- **Image filter.** It appears once notes can hold images, in milestone 5.
- **Drawer.** Reminders and Settings join it in their own milestones.
- **Reordering labels by drag.** It has no test of its own. It uses the same drag list as the checklist,
  whose drag is tested, and the screen-reader moves are tested.
- **Travel's label page on the device.** The device script did not reach it: returning to the search page
  brought the keyboard back, and the keyboard took the back press. Label pages were checked on the device
  through Reading.

### Before milestone 4 — the grid stopped short of its end (2026-09-15)

On the phone the grid could not be scrolled to its oldest notes: it stopped with the last days hidden behind
the compose bar.

- **Cause.** `SliverMasonryGrid` from flutter_staggered_grid_view 0.7.0, the newest release. Once a grid
  section was scrolled 250px past the top of the screen, the sliver pulled the scroll position back, so any
  page that stacks several masonry sections stopped 250px into the first one. Search results stack two, and
  had the same fault. A single `MasonryGridView`, as the archive and trash use, is not affected.
- **Fix.** The grid, search, and the reminders page lay each section out with `MasonryColumns`, a box that
  places each card under the shortest column, as one item of a lazy list. Sections far off screen are still
  not built; the cards within one section are built together.
- Covered by tests that drag the grid to its end and back on a 1080×2400 phone at 420dpi: a single pinned
  note, days of one note between fuller ones, every day holding one note, long sections, and the archive. All
  of them failed at 290px before the fix. On the emulator the grid now reaches its oldest day.

### Milestone 4 — done (2026-09-15)

Reminders, covered by 258 tests in total and checked on the Android 17 emulator.

- **Setting one.** The alarm button on a note, or its reminder chip, opens a sheet with three quick picks and
  a date and time picker.
  - Later today is 18:00, or 20:00 once 18:00 is under an hour away, and is not offered after 19:00.
  - Tomorrow morning is 08:00. Next week is the coming Monday at 08:00.
  - A picked time that has already passed is refused.
  - Repeat once, daily, weekly, monthly, or yearly. A new repeat on an existing reminder saves at once.
  - Remove has undo.
- **On the note.** A chip shows when the reminder rings next. It turns red once a one-off reminder is
  overdue, is struck through once done, and carries a loop when it repeats. TalkBack reads it as part of the
  card.
- **Reminders page.** In the drawer under Notes: overdue first, then the rest of today, then upcoming. It
  says plainly when notifications are off, or when Android is ringing reminders late for want of exact
  alarms, and offers the one step that fixes each.
- **Permissions.** Setting the first reminder asks to post notifications; once that has been refused for good,
  the app's notification settings open instead. "Allow exact alarms" opens Android's page for the app;
  without the permission reminders are scheduled inexact. `USE_EXACT_ALARM` is not requested.
- **The notification.** Its title and text come from the note (a list's open items), with Done and
  Snooze 10 min.
  - Done finishes a one-off reminder; on a repeat it waits for the next ring.
  - Snooze moves a one-off reminder ten minutes on, and rings a repeat once more on the side.
- On the emulator:
  - the seeded passport reminder showed under OVERDUE, red on its card and in the editor;
  - "Allow exact alarms" opened Android's Alarms & reminders page, and the notification prompt appeared when
    the first reminder was set;
  - a reminder set through the pickers was registered with Android as an exact alarm, to the second;
  - Snooze and Done worked with the app closed: the notification cleared, the alarm moved ten minutes on or
    went away, and the app did not come up;
  - installing a new build over a waiting reminder started the plugin's receiver, the alarm stayed in place,
    and the reminder rang on time at 21:10 without the app being opened;
  - tapping that notification started the app and opened the note, its chip red as overdue;
  - afterwards the passport reminder finished with Done showed struck through on its card, and the reminders
    page held only the overdue note, with no notice once both permissions were allowed.
- **Checkpoint.** Snooze moved a reminder to 20:59 with the app closed, and the emulator was rebooted. The app
  was never opened. The plugin's boot receiver put the alarm back 40 seconds after boot, and the reminder
  rang at 20:59.

Decisions and findings:
- **Notifications follow the notes.** Nothing that changes a note calls the scheduler. `ReminderSync` watches
  the stored reminders and schedules, replaces, or cancels until Android's alarms match. Undo, the trash and
  restore, and the imports still to come all ring correctly without reaching for the scheduler.
- **Notification ids** are the note's row id, since Android wants an int. A snooze of a repeat rings under a
  second id of its own, so it does not replace the repeat.
- **Repeats** use Android's own repeating notifications, so they keep ringing with the app closed.
  - Android places a repeat by stepping from today to the next matching date. A monthly reminder on the 31st
    therefore skips shorter months, and a yearly one on 29 February waits for a leap year.
  - The app works out the next ring the same way, so the time it shows is the time the phone rings.
  - A first ring more than one repeat away would come early that way. It is scheduled on its own instead,
    and the repeat is set up the next time the app runs or the notification is used; swiping it away counts.
- **Done and Snooze** run on a background isolate the plugin starts, whether or not the app is open. The
  database connection is shared across isolates, so the app's lists update when they write.
- **Stale buttons.** The notification carries the time its reminder was set for. Done or Snooze on a
  notification whose reminder has since been moved or removed does nothing.
- **A one-off reminder that has rung** keeps its notification on screen through later edits to the note. A
  repeat turned into a one-off whose time has passed is cancelled, so it does not go on ringing. Found in
  review, with the stale buttons above and the next two items.
- **Repeat chips.** Tapping the repeat already chosen saves nothing. Switching a finished reminder to a repeat
  brings it back; switching to Once leaves it finished.
- **The sheet and settings.** The sheet reads permissions again when the app returns to the front, so it stops
  saying reminders may ring late once exact alarms are allowed. Found on the emulator.
- **Opening from a notification.** A tapped notification opens its note as a plain page over whatever is
  showing. There is no `/note/:id` route: a card grows into its editor, which a route cannot express.
- **Emulator clock.** A quick-boot snapshot left the emulator's clock seven hours behind until the first
  reboot. The first reminder therefore came due during that reboot, and it rang as soon as the boot receiver
  ran.

Carried forward:
- **A repeat far off, left alone.** When a repeat's first ring was scheduled on its own, and that
  notification is never swiped or used and the app is not opened, the second ring does not come.
- **OEM battery managers.** The one-time hint linking to autostart settings on Xiaomi and Samsung (§11) is
  not written.
- **The app icon** beside a notification is Flutter's launcher icon until milestone 7's adaptive icon.
- **Repeats on a device.** Daily, weekly, monthly, and yearly arithmetic is tested against the plugin's own
  rules, but no repeat was left to ring a second time on the emulator.

### Milestone 5 — done (2026-09-15)

Images, covered by 276 tests in total and checked on the Android 17 emulator.

- **Adding.** Add image in the editor offers Choose photos, which opens the Android photo picker (up to 20 at
  once), and Take a photo, which opens the camera app. The compose bar has its own photo and camera buttons,
  which start a note holding the photos; closing the picker or the camera opens nothing. Neither needs a
  storage or camera permission.
- **Storing.** Each photo is compressed to a JPEG no longer than 2048px on its long edge, turned upright, with
  a 400px thumbnail, under `media/` in the app's documents folder. The database keeps relative paths. A photo
  that cannot be read is skipped with a message, and the rest still go in.
- **On the note.** Images sit at the top of the page in rows of up to three, each near its own shape, with a
  line counting photos still being compressed. A card shows one image at its own shape, two side by side, or
  three as one large and two small with a count of the rest. Cards use thumbnails; the editor decodes each
  image at the size its tile draws it.
- **Viewer.** Full screen on a dark ground in both themes: swipe between images, pinch or double-tap to zoom,
  and delete with undo. It closes when the last image goes.
- **Copies and the trash.** Make a copy gives the copy files of its own. A note in the trash keeps its images,
  so restoring it brings them back.
- **No leaks.** Deleting a note forever, emptying the trash, and the trash purge take the note's attachment
  rows with it. A janitor watching the attachments table deletes their files a second later, and at start-up
  it also clears the files of removed images and anything nothing refers to.
- On the emulator:
  - three photos from the picker were stored as 2048×1536 images and 400×300 thumbnails, 93–95 KB and
    13 KB each;
  - the viewer swiped and zoomed, a deleted photo came back with Undo, and the card showed the three;
  - a photo from the camera app started a new note that kept it without any text, with Share off and Make a
    copy on;
  - a note in the trash kept its files, and five seconds after Delete forever its image and thumbnail were
    gone while the other note's files stayed;
  - search's Images filter found the six notes holding photos and no others.
- **Checkpoint.** Cold start on a release build, measured with `am start -W`, the median of seven runs after
  a warm-up: 1,653ms with 3 images, 1,640ms with 50 images across five notes. The difference is within the
  noise between runs, well under the 300ms allowed.

Decisions and findings:
- **Compression.** flutter_image_compress scales by the smaller of its two ratios and never enlarges, so
  asking for a long edge means passing the short edge the result should have as both limits. That holds
  whichever way EXIF turns the photo. Sizes are read from the file header rather than by decoding the image.
- **Files and undo.** A removed image keeps its row as a tombstone and its files on disk, so Undo works; only
  the start-up sweep, when no undo can be waiting, deletes those files. A new note whose images were all
  removed is not discarded as blank when the page closes, since that would take the undo with it.
- **The janitor.** Drift reports the rows a note's cascade removes as writes to the attachments table, so one
  watcher covers every way a note is deleted for good, including imports still to come. A sweep leaves alone
  the files of photos still being written.
- **Batches** of photos run one after another, so a second batch started while the first is compressing goes
  after it rather than among it.
- **Process death.** Photos picked just before Android closed the app come back at the next start as a new
  note.
- **Found on the emulator.** The viewer's status bar icons stayed dark on its dark ground; they now turn light
  there, along with the gesture handle. A note started from photos focused its text and raised the keyboard
  over the photo; it now opens on the photos with the keyboard down. Both fixes were checked again on a
  rebuilt release build.
- **Found in review.**
  - A HEIC photo's temporary full-size copy sat in the media folder, where a sweep could delete it mid-way;
    it now goes to the cache.
  - Undo could lose the only image of a new note.
  - Two batches added together could interleave.
  - Make a copy was off for a note holding only images.
  - Very wide photos were decoded too narrow for their tile and looked soft.

Carried forward:
- **Other formats.** HEIC and other formats Flutter cannot size go through a fallback that decodes them to a
  full-size JPEG first. The emulator's photos are all JPEGs, so that path is covered by the code only.
- **Sharing** still sends text only; images are not shared.

### Milestone 6 — done (2026-09-16)

Import, export, and settings, covered by 332 tests in total and checked on the Android 17 emulator.

- **Settings.** Last in the drawer, under Trash, and pushed over the page that opened it. Every choice applies
  the moment it is made.
  - **Theme:** system default, light, or dark, chosen from three small pages drawn in each theme's own colours.
    The launch screen stays up until the choice is read, capped at a second, so a dark choice never shows a
    light first frame.
  - **Checked list items:** fold away at the bottom (the default, as before), show at the bottom, or leave in
    place. In place, the editor and the card keep list order and a new item goes last. Backspace in an empty
    item directly under a checked one removes it, rather than joining into a finished item.
  - **Trash:** 1, 7, or 30 days, read by the purge at start-up. The trash's header line and its empty state
    name the chosen stay.
  - **Rebuild search index**, the remedy §11 planned for an index out of step with the notes.
- **Export.** One zip, `notes-export-YYYYMMDD-HHmm.zip`: the manifest, every note including the archive and
  the trash, the labels, and each image with its thumbnail. The JSON is deflated; photos are stored as they
  are. The sheet writes the file as it opens, shows the counts and the size, then offers Save to a file
  (Android's save picker) and Share.
- **Import.** Android's open picker, then a sheet that reads the file and shows what each way would do before
  anything is written.
  - **Merge:** a note on both keeps its later edit, and its place here. New notes go above the notes here in
    the file's order. Labels match by name ignoring case, new ones go after the labels here, and a label
    deleted here after the export stays deleted.
  - **Replace:** behind typing "replace". Every note and label here is deleted, and the file comes back
    exactly, sort keys included.
  - Images are unpacked first; then every write runs in one transaction, worked out again from the notes as
    they are at that moment. A failed import writes nothing and removes the files it unpacked. Images of notes
    that stayed as they were are swept like any unused file.
  - Refused, each with its own message: a file that is not an export, one from a newer bundle format, and a
    damaged one. Images a file lists but does not hold are left out and counted.
- **Starter notes** are written once, on an install's first run. Before, a phone whose notes were all deleted
  for good, or replaced by an empty export, got them back at the next start.
- On the emulator, installed over the milestone 3 era database, which upgraded with its 11 notes and 4 labels:
  - dark applied at once, status bar icons included; after a force-stop, 30 screenshots through the cold start
    went from the launch screen straight to a dark first frame;
  - with Leave in place, the Groceries card and editor kept list order and ticking Oat milk left it first;
    Show at the bottom listed the checked items under an open count;
  - a note of three photos from the photo picker was added, one note archived and one trashed, and the export,
    12 notes, 4 labels, 3 images, 407 KB, was saved to Downloads through the save picker;
  - Share offered the zip under its export name.
- **Checkpoint.** After that export, `pm clear` wiped the app, which started again with the 8 starter notes.
  Merge would have added 12 notes, 1 label (Home, Admin, and Reading matched by name), and 3 images; Replace
  showed −8 notes here and +12 notes, +4 labels, +3 images, and its button stayed off until "replace" was
  typed. After the import, a second export matched the first entry for entry: `notes.json`, `labels.json`,
  and all six image and thumbnail files byte-identical, and the manifest differing only in `exportedAt`.
  Importing the file again offered nothing new, and a 13 MB file that is not a zip was refused as not an
  export.

Decisions and findings:
- **Where settings live.** A `preferences` table, schema version 3, kept on the device like recent searches
  and left out of exports. No new plugin, and the theme reaches the app as a stream. Upgrading from version 2
  marks the starter notes as written, since every earlier install wrote them on its first run. The upgrade
  tests start from a snapshot of version 2's schema.
- **Pickers.** A small channel in `MainActivity` opens Android's save and open pickers, instead of
  `file_picker` as §2 first planned. `file_picker` 12 hands a save over as one byte array through the channel;
  the channel copies the file as a stream on a background thread, both ways.
- **The bundle's version** is its own, 1, apart from the database schema, which can change without changing
  what an export holds.
- **Thumbnails travel in the bundle**, under `media/thumbs/`, so an import does not compress anything again.
  A thumbnail missing from a file is replaced by a copy of its image.
- **Ids from a file become file names**, so they must look like ids the app makes; a sort key must be letters
  that do not end in `a`. A file that breaks either is damaged. Colours, types, and repeats this version does
  not know fall back to their defaults.
- **Speed.** 5,000 notes, a fifth of them lists of 8 items and half with a label, on this desktop: export
  0.6–1.0s, reading 0.2–0.4s, and replace 0.5–0.9s, depending on how busy the machine was. The first version
  wrote note by note with the search triggers indexing each row, and replace took 4.2s. Writes now go in one
  batch, and a replace, or a merge of more than 200 notes, drops the triggers inside its transaction and
  indexes everything once.
- **Found in review.**
  - Two exports could overlap, when a sheet closed mid-export was opened again, and the second cleared or
    wrote over the file the first was writing. Exports now run one after the other.
  - A picker that failed to open left the channel busy until the app restarted.
  - A label the file renamed to a name another label has here joins that label, as a new label with that name
    would. Kept, and covered by a test.
- **Found on the emulator.** The empty trash said "seven days" whatever was chosen. The export ledger printed
  each count twice, and its "398 KB" wrapped at 200% text; the size moved to the heading line. The export time
  carried microseconds; times are written to the millisecond.

Carried forward:
- **Cold start with the theme hold** has not been measured on a release build. The emulator holds a debug
  install, and a release build cannot be installed over it without uninstalling.
- **The launch screen** is still Flutter's white one, so with dark chosen a white screen shows before the dark
  first frame. The splash is milestone 7's.
- **Auto-backup.** The installed app reports `ALLOW_BACKUP`: the manifest does not yet set
  `android:allowBackup="false"` as §8 plans.
- **Import progress** shows a running line, not how far along it is. Large imports have been timed on the
  desktop only.
- **Process death with a picker open** loses that call; the export or import has to be started again.

### Milestone 7 — done (2026-09-17)

Polish and the finish gate, with milestone 6's open items closed. Covered by 470 tests, the finish gate
among them, and checked on the Android 17 emulator on a release build.

- **The finish gate as a test.** `finish_gate_test.dart` opens 17 surfaces (the grid, drawer, selection mode, a
  text note, a list, the colour and reminder sheets, the label picker, a label page, archive, trash, a note in
  the trash, reminders, search, labels, settings, the export sheet) on a 360dp phone in both themes, and checks
  Android's 48dp and labelled tap target guidelines, text contrast, and 200% text with any overflow failing the
  test. Seeded with an archived note, a trashed one, and a note with a long title and a 5,000-character body,
  which also opens whole in the editor. 104 checks, all passing.
  - Beside it, `theme_contract_test.dart`: every text colour against every surface it is drawn on, including
    all tints and the selected-row wash, at 4.5:1; every motion token and the page transition at 300ms or less;
    and a scan of `lib/` for colours and font sizes outside `lib/core/theme/`, which found five font sizes, now
    type tokens (`noteItem`, `displaySmall`, `metaOverlay`, `uiLargeStrong`).
- **Fixed by the gate.**
  - Contrast: the light accent read 4.3:1 on pigment tints, 4.0:1 on the selection wash, and the snack bar's
    Undo 3.6:1. The accent is now `#28706D`, and Undo on the dark bar takes the dark theme's accent.
  - Touch targets: checklist item fields were 26dp tall and the editor title 28dp, with their padding outside
    the field; the padding moved inside. Search, new label, and label rename fields were 46dp; the label chips
    under a note 22dp. A full-page tap area in the editor showed up as an unnamed button and is now hidden
    from TalkBack, which reaches the body field itself. Checklist checkboxes carry the item's text.
  - 200% text: the drawer's Labels heading, the trash header with Empty trash, and every shelf header now wrap
    their action below the title; reminders' notices scroll with the page instead of pushing it off screen;
    the add-item and checked-items rows grow with their text.
- **Loading and error states** on every list surface: search shows skeleton cards while it reads; the labels
  page and the label picker have a skeleton and an error with retry.
- **Motion.** Pushed pages use Android's transition with predictive back at 250ms (Flutter's default is
  450ms), a fast fade with animations off, and the theme change stops cross-fading then too.
- **Paging.** The grid, label pages, archive, and trash read 100 notes and 100 more as the end nears
  (`NotePage`, `LoadMore`). Headers count the whole shelf. A drag to the end of what is loaded sorts before the
  first note not yet loaded.
- **Milestone 6's open items.**
  - Launch screen: the ground colour in each theme instead of Flutter's white, with the icon on Android 12+,
    and the app's own theme choice handed to Android, so a dark choice on a light phone starts dark. On the
    emulator, 13 frames of launch screen on `#0F1113` went straight to the dark first frame.
  - `allowBackup="false"` and `dataExtractionRules`; `dumpsys` no longer reports `ALLOW_BACKUP`.
  - Import and export show images done of all of them on a determinate bar, then a running line while the
    notes are written in one transaction.
  - Cold start with the theme hold, release build, 14 runs after warm-up: median 1,880ms (1,628–5,362). A
    build without the hold: median 1,724ms over 7 runs (1,638–1,947). The hold costs about 150ms on this
    emulator, most of it the settings read the first frame would otherwise do right after.
- **Icon.** An adaptive icon, a note on verdigris with a vermilion spine, plus a monochrome layer for themed
  icons and regenerated legacy PNGs.
- **Reminders on phones that stop apps.** Xiaomi, Samsung, Huawei, Honor, OPPO, realme, OnePlus, vivo, and
  iQOO get a one-time hint, once Android itself allows reminders, that opens the maker's background or
  autostart page, falling back to the app's details. Dismissed or used, it stays away.
- **Process death.** The editor saves as soon as the app turns inactive rather than waiting out the 400ms
  debounce. On the emulator, text typed, then Home, then a force-stop 50ms later was there on the next start;
  before the change, 150ms lost it.
- **Tests.** Goldens for the note card in all eight pigments and both themes (`--tags golden`, recorded on
  Windows, skipped in CI). `integration_test/reminder_rings_test.dart`, create → remind → ring, passed on the
  emulator in 38s. The rest of §10's test list was already covered.
- **Release build on the emulator.** Installed signed with the release key (the debug install was gone, see
  below), then the milestone 6 export imported with Replace; `flutter build appbundle --release` builds too. A reminder set in the app rang at 15:09:00 with
  the process killed, and Done from the shade marked it done from the background isolate, so R8 keeps what the
  notifications plugin and Drift need.

Decisions and findings:
- **go_router 18 gave pushed pages no transition.** It decides a `builder:` route's page by looking for
  `material_ui`'s `MaterialApp`, a different class from Flutter's, so settings and labels opened as
  `NoTransitionPage`s with no predictive back. Found when a held back swipe on the emulator moved nothing.
  They are built as `MaterialPage`s now, covered by a test that drives the back gesture channel. On the
  emulator, the same held swipe now draws settings smaller with the grid behind it.
- **Undo bars never left.** Flutter 3.47 makes a snack bar with an action persist by default, so every Undo sat
  over the bottom of the pages opened after it, covering Restore and Delete forever on a trashed note. It now
  leaves after five seconds, and stays only while TalkBack is on.
- **The integration test wipes the device.** `flutter test -d` uninstalls the app when it finishes. Its first
  run took the emulator's notes, restored from the milestone 6 export in Downloads. The test now also shows
  the app only its own notification ids, since the first reminder pass cancels anything its database does not
  know, and leaves the phone's theme alone.
- **Skeleton pulse** (1,100ms) is an indicator, not a transition, and stands still when animations are off.
- **Formatting.** Much of the tree predates the formatter's style. Changes are formatted where they were
  made, not whole files.
- **APK size.** The release APK is 64MB: three ABIs with native libraries stored uncompressed, as the Android
  Gradle plugin now defaults. Not changed here.
- Stale Gradle merge state from before the launch screen change broke the first release build; clearing
  `build/app/intermediates` for release fixed it.

Carried forward:
- **The maker hint** cannot show on the Google emulator; its channel paths are untested on real Xiaomi or
  Samsung phones.
- **Themed icon** not yet seen with themed icons switched on.
- **Process death with a picker open** loses that call, as in milestone 6.
- Timings are from one emulator on this desktop.

### Milestone 8 — done (2026-09-17)

Home screen widgets, asked for after v1. Covered by 489 tests in total and checked on the Android 17
emulator on a release build.

- **Notes widget** (3 by 3, resizable down to 2 by 2): a "Notes" heading with the count and a + for a new
  note, over the notes as cards in grid order, pinned first, up to 20. Each card is the grid's card in
  miniature: the pigment tint with its spine curving round the corners, the title, up to five lines of body or
  five checklist items (open ones first, checked ones muted and struck through, `+N more` after), and a meta
  line with labels and the image count. TalkBack reads each card as one button, with the same words as the
  card in the grid.
- **New note widget** (4 by 1): the compose bar. Take a note, New list, Add photos, and Take a photo, each
  opening the app straight into that. At three cells the words go, and at two only a note and a list stay, so
  every button keeps 48dp.
- **Settings → Home screen** places either widget through the launcher's own confirmation, shown only where
  the launcher supports it.
- **How it fits together.** `HomeWidgetSync` watches the grid's first page and hands Android a JSON snapshot
  whenever what the widget shows changes, from any path that writes a note; a change it does not show, such as
  a reminder, sends nothing. Kotlin writes the snapshot to `noBackupFilesDir` and redraws, and the widgets read
  it with the app closed. A tap starts MainActivity with an action; the app opens the note, or a new note,
  list, or photo note, over whatever is showing. A deleted note says so.
- On the emulator: both widgets placed from settings; a card tapped with the app in the background, and with
  its process ended, opened that note; +, New list, Add photos (the photo picker, closed back to the grid with
  no note), and Take a photo (the camera) all landed; a title edited in the app showed on the widget on
  return; dark mode redrew both in the dark tokens; at 200% text the heading grew and the cards scrolled; the
  new note widget resized to three and two cells switched layouts; the picker's preview showed sample notes.

Decisions and findings:
- **No custom fonts on the home screen.** Launchers draw widgets without loading an app's font resources:
  Literata bundled as a font resource, by family XML or the file itself, still drew as Roboto. The widgets use
  the system's serif for note text, its mono for meta, and its sans for the bar, which keeps the reading and
  meta voices. The bundled copies were dropped again, 1.3 MB.
- **The widgets follow the phone's theme**, not the one chosen in the app: the launcher resolves their
  colours against its own night mode.
- **Reminders are left off the widget.** Done and Snooze change a reminder from the notification without the
  app running, and the widget would show it stale.
- **Colours are copies.** `res/values*/colors.xml` now hold every token the widgets need;
  `android_resources_test.dart` fails if one drifts from `app_colors.dart`. The Material icons are traced from
  Flutter's own icon font into vector drawables, so they match the compose bar exactly.
- **Card descriptions** moved out of `NoteCard` into `describeNote`, shared with the widget snapshot.
- Opening a note from outside the grid, a widget or a notification, waits for the first frame when the app
  is still starting and its navigator not yet built, rather than giving up.
- `am force-stop` puts an app in Android's stopped state, and the launcher greys its widgets until it runs
  again. Ordinary process death does not; checked with `am crash`.

Carried forward:
- Android 7 to 11 take the pre-12 paths (the list service is the same; the new note widget picks its layout
  from the width the launcher reports), untested here: the emulator runs Android 17.
- Only the Pixel launcher was tried. Other launchers size cells differently, and some cannot place a widget
  from the app, in which case settings leaves the section out.
- The new note widget on the emulator's home screen was left three cells wide; the launcher would not take
  the resize back to four.

### After milestone 8 — a widget for the pinned notes, or one label (2026-09-19)

Asked for after milestone 8: a notes widget that shows only the pinned notes, or only one label's. Covered by
the suite (517 tests) and checked on the Android 17 emulator on a release build.

- **Each notes widget shows one feed**: every note (as before), the pinned notes, or one label's notes, in
  grid order. The heading is the feed's name with its count; the + starts a note that lands on the widget, pinned
  from the pinned widget and wearing the label from a label's; the heading of a label's widget opens that
  label's page, closing a note left open over it; an empty feed invites the note it would show.
- **Choosing.** Placing the widget from the launcher's list opens a sheet over the home screen: All notes,
  Pinned notes, then the labels, each with its count and its first notes in the reading face. Backing out takes
  the widget off again. The widget's own Settings (long press) opens the same sheet with the current choice
  marked. Settings → Add the notes widget asks the same in the app first, since a launcher placing a widget
  for an app skips the setup.
- **A label deleted** under a widget leaves it saying so, and a tap opens the sheet. A label renamed renames
  the widget. Widgets placed before this keep showing every note.
- **How it fits together.** The snapshot (version 2) holds every feed, each naming its notes by id over one
  set of notes, so a note on three feeds crosses once. `loadWidgetShelves` reads the grid, the pinned notes,
  and every label's first 20 (the pinned notes are the grid's first rows) and hydrates their union in one
  pass. Kotlin redraws the widgets on its io thread, off the thread Flutter shares. Android keeps each widget's choice in its
  own preferences, since the widget draws with the app closed. The setup sheet is a native activity: it draws
  with the app's own faces, read from Flutter's copies in the APK, and the tokens in `res/values*`.
- On the emulator: placed from the launcher's list (backing out removed it; choosing Reading showed its two
  notes), from settings with a label (the launcher's dialog, then Admin with its count), and changed from the
  widget's settings between all, pinned, and four labels; + on the pinned widget made a pinned note and on a
  label's a note wearing it, each showing on its widget on return; the heading of a label's widget opened its
  page, also with a note open; a card opened its note; a label made, chosen (its empty state), then deleted
  showed the deleted state, and its tap opened the sheet; the sheet in the light and dark themes and at 200%
  text. The accessibility tree gives each choice as one radio button with its name, count, and first notes;
  TalkBack itself was not run over the sheet.

Decisions and findings:
- **The widget heading never changed after it was first drawn, on Android 17.** A list filled by a
  `RemoteViewsService` makes the whole widget "legacy": the system only tells the launcher to fetch an update
  (`Trying to notify widget update deferred`), and the Pixel launcher drops it (`Widget update called, when
  the widget no longer exists`). The cards refreshed through the service, the heading kept its first name and
  count. This was already so in milestone 8: the count never moved after an edit. From Android 12 the widget
  now hands its cards over as `RemoteCollectionItems` with the rest of it; the service stays for Android 7 to
  11. An app update redraws from scratch, which is why it looked right after each install.
- The widgets' own intents are kept apart by request code, one pair per widget, rather than by intent data:
  FlutterActivity reads intent data as a deep link.
- The setup activity is exported with the `APPWIDGET_CONFIGURE` filter, since some launchers start it
  themselves; it acts only on a notes widget of this app.
- A label deleted meanwhile goes on nothing: `LabelRepository.setOnNotes` checks it is still there. A note
  from a widget whose label is gone is a plain one, and so is a note begun on a label's page as the label is
  deleted, which before kept a hidden link that came back if the delete was undone.
- At 200% text, the finish gate's step for the export sheet had stopped tapping it (the row sat past the
  screen's edge), so that sheet went unchecked at 200%; both settings steps now bring their row fully on
  screen first. The new settings sheet has its gate entry.

Carried forward:
- Android 7 to 11 take the service path for the cards, untested here.
- Only the Pixel launcher was tried, and only its dialog for placing from the app, which skips the setup.
