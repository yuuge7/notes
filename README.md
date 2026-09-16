# Notes

A local-first notes app for Android, built with Flutter. It takes Google Keep's proven mechanics (a masonry
grid of colour-coded notes, checklists, labels, reminders, and photos) and gives them a visual identity of its
own. Everything stays on the device: no account, no sign-in, and no network needed.

## Features

- **Fast capture.** The compose bar on the home screen starts a text note, a checklist, or a note from photos
  or the camera.
- **Masonry grid** grouped by day, with pinned notes on top and drag to reorder within a day.
- **Checklists** with indented items, drag handles, and checked items folded away under a count. Notes
  convert between text and list in either direction.
- **Colours and labels** to sort notes, with a page for each label.
- **Search** across titles, bodies, list items, and label names. Words match from their first letters,
  ignoring case and accents, and results can be filtered by type, colour, and label.
- **Reminders** at a set time or on a daily, weekly, monthly, or yearly repeat, with Done and Snooze on the
  notification itself. Reminders survive reboots and app updates.
- **Images** from the Android photo picker or the camera, compressed on the device, shown as a mosaic on the
  card and full screen with pinch-to-zoom.
- **Archive and trash**, with undo, plus Make a copy and Share. The trash keeps notes for 1, 7, or 30 days.
- **Export and import.** Every note, label, and image goes into one zip, saved wherever you choose or shared
  with another app. Import merges it with the notes on the phone, keeping each note's latest edit, or replaces
  them all.
- **Settings** for the theme (light, dark, or the system's), where checked list items go, and how long the
  trash keeps notes.
- **TalkBack labels** and layouts that hold up at 200% text size.

## Download

Signed APKs are published on the [Releases](../../releases) page, and every push to `main` produces a new
one. They install on Android 7.0 (API 24) and later. Your browser or file manager may ask for permission to
install apps.

## Tech stack

| Area | Choice |
|---|---|
| Framework | Flutter 3.47 (stable), Dart 3.13 |
| State | Riverpod 3 with riverpod_generator |
| Storage | Drift on SQLite, with an FTS5 full-text index for search |
| Models | freezed, json_serializable |
| Navigation | go_router |
| Reminders | flutter_local_notifications, timezone |
| Images | image_picker (Android photo picker and camera), flutter_image_compress |
| Backup | archive, Android's document pickers, share_plus |
| Linting | very_good_analysis |

## Getting started

### Prerequisites

| Tool | Version |
|---|---|
| Flutter | 3.47.0 on the stable channel (includes Dart 3.13) |
| Android SDK | Platform 36 and build tools, from Android Studio or the command-line tools |
| JDK | 17 or newer (the JDK bundled with Android Studio works) |
| Device | An emulator or phone on Android 7.0 (API 24) or later |

Run `flutter doctor` and fix anything it reports under Flutter and the Android toolchain before going on.

### Set up

```sh
git clone https://github.com/<your-account>/notes.git
cd notes
flutter pub get
dart run build_runner build
```

The last step is required. Drift tables, freezed models, JSON serialisation, and Riverpod providers are
generated into `*.g.dart` and `*.freezed.dart` files, which are not checked in. Run it again after changing
anything annotated with `@DriftDatabase`, `@DriftAccessor`, `@freezed`, or `@riverpod`, or keep
`dart run build_runner watch` running while you work.

### Run

```sh
flutter devices                 # lists connected phones and emulators
flutter run -d <device-id>
```

A fresh install seeds eight starter notes, so the grid has content to show.

The first reminder you set asks for permission to post notifications. Exact alarms are granted in system
settings, reached from "Allow exact alarms" on the Reminders page. Until then, Android rings reminders close
to their time rather than exactly on it.

### Everyday commands

| Task | Command |
|---|---|
| Regenerate code as files change | `dart run build_runner watch` |
| Static analysis | `flutter analyze` |
| All tests | `flutter test` |
| Timing checks only | `flutter test --tags perf` |
| Local release build | `flutter build apk --release` |

## Project structure

```
lib/
  core/router/         go_router shelves: Notes, Archive, Trash
  core/theme/          colour tokens, typography, spacing, motion (the only place colours and sizes are defined)
  core/ui/             shelf scaffold, masonry columns, undo messages, highlighted search text
  core/util/           sort keys, day grouping, checklist rules, search and share text, reminder times, ids
  data/                Drift database and migrations, full-text index, DAOs, repositories, providers, seed data
  data/media/          image files and compression, photo picker and camera, cleanup of unused files
  data/notifications/  notification scheduler, with Done and Snooze handled on a background isolate
  data/reminders/      keeps scheduled notifications in line with stored reminders
  domain/model/        Note, ChecklistItem, Label, Attachment, Pigment, search queries and filters
  domain/service/      service interfaces
  features/editor/     full-page editor, checklist section, colour sheet
  features/images/     image strip, card mosaic, full-screen viewer
  features/labels/     label picker and labels page
  features/notes/      home grid, label pages, note card, selection, drawer
  features/reminders/  reminder sheet, reminder chip, Reminders page
  features/search/     search page with filters and recent searches
  features/shelf/      Archive and Trash
test/                  unit, repository, and widget tests; fakes in test/support/
assets/fonts/          Literata, Schibsted Grotesk, Martian Mono
.github/workflows/     release pipeline
```

## Testing

Tests run against a real in-memory database wherever data is involved. They cover:

- **Data:** create, archive, trash and restore, trash retention, copies, bulk edits with undo, and schema
  upgrades that keep every note, item, and label.
- **Editor:** saving on close, capture from the compose bar, pinning, archiving, and deleting with undo.
- **Grid:** drag reordering, screen-reader move actions, and scrolling to the last note whatever mix of
  day sections the grid holds.
- **Checklists:** typing, splitting and merging items, indenting, checking parents with their children,
  reordering, and converting to and from text.
- **Labels and search:** renames, deletes with undo, prefix and accent-insensitive matching, filters, recent
  searches, and 5,000 notes searched in under 50ms on a desktop.
- **Reminders:** quick picks, repeat arithmetic matching Android's, scheduled notifications following edits,
  the trash, and permission changes, and the Done and Snooze actions.
- **Images:** storage and thumbnails, undo, no files left behind after deleting forever, copies, the viewer,
  and the card mosaic.
- **Export and import:** an export replaced into an empty phone comes back identical, entry for entry;
  merge rules for later edits, label names, and deleted labels; files that are not exports, are damaged, or
  come from a newer version; and 5,000 notes exported and replaced in about a second on a desktop.
- **Settings:** the theme the app wears, where checked list items go, the trash's stay, and schema upgrades
  that keep notes and leave settings at their defaults.
- **Layout and accessibility:** a 360dp-wide phone at 200% text size in both themes, and what TalkBack reads
  for each card.

## Contributing

Contributions are welcome. To propose a change:

1. Fork the repository and create a branch from `main`.
2. Set up the project as described in [Getting started](#getting-started).
3. Make your change, following the existing structure:
   - colours, type, spacing, and motion come only from the tokens in `lib/core/theme/`, and every screen
     works in both themes;
   - screens reach data through the repositories and providers in `lib/data/`, never the database directly;
   - a change to a Drift table raises the schema version, adds a migration, and extends the upgrade tests in
     `test/data/`.
4. Add or update tests, regenerate code, and make sure `flutter analyze` is clean and `flutter test` passes.
5. Open a pull request against `main` that says what changed and how you tested it, with screenshots for
   visual changes.

The app is deliberately Android-only, phone-only, and portrait-only, and it keeps everything on the device.
Changes that add accounts, cloud services, or other platforms are out of scope.

Contributors do not need the release key. Without it, release builds are signed with the local debug key,
which is fine for testing but cannot update an installed release from GitHub.

## Releases and versioning

[`.github/workflows/release.yml`](.github/workflows/release.yml) runs on every push to `main`:

1. It installs Flutter 3.47.0, generates code, runs the analyzer, and runs every test. Any failure stops the
   release.
2. It picks the next version. The major number comes from `version` in `pubspec.yaml`; the minor number is one
   higher than the highest `vMAJOR.*` tag on GitHub. The first release under major version 1 is `v1.0`, then
   `v1.1`, `v1.2`, and so on.
3. It builds a release APK with that version (`versionName` `1.2`, `versionCode` `10002`), signs it with the
   upload key held in the repository secrets, and refuses to go on if the APK carries the debug key.
4. It publishes a GitHub release titled `Notes v1.2`, tagged `v1.2`, with `Notes-v1.2.apk` attached and
   release notes generated from the commits.

Releases run one at a time, and a tag that already exists fails the run instead of replacing a release. The
version is not committed back to the repository, so you never need to pull after pushing.

- **New major version:** change `version` in `pubspec.yaml` to `2.0.0+1`. The next push is released as `v2.0`.
- **Push without a release:** put `[skip ci]` in the message of the last commit you push.
- **Failed run:** nothing is published, and the next push takes the same number.

## Release signing

Releases are signed with an upload key that is kept out of Git. Two files in the project root, both listed in
`.gitignore`, hold it:

| File | Contents |
|---|---|
| `notes-release.jks` | The keystore: PKCS12, RSA 4096, alias `notes` |
| `key.properties` | The keystore's file name, passwords, and alias, read by `android/app/build.gradle.kts` |

> **Back up both files.** Android installs an update only if it is signed with the same key as the installed
> app. If the keystore or its password is lost, no future release can update existing installs, and users
> would have to uninstall, losing their notes. Keep copies outside the repository, such as in a password
> manager or on an encrypted drive.

### Using the key on another machine

1. Clone the repository and complete [Getting started](#getting-started).
2. Copy `notes-release.jks` and `key.properties` from your backup into the project root, next to
   `pubspec.yaml`.
3. Build with `flutter build apk --release`.
4. Confirm the APK carries the release key:

   ```sh
   <android-sdk>/build-tools/<version>/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
   ```

   The output should show `CN=Notes, O=Notes`. `CN=Android Debug` means `key.properties` was not found.

### Giving the key to GitHub Actions

In the repository on GitHub, open **Settings → Secrets and variables → Actions** and add four repository
secrets:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | The keystore encoded as base64 (commands below) |
| `ANDROID_KEYSTORE_PASSWORD` | `storePassword` from `key.properties` |
| `ANDROID_KEY_ALIAS` | `keyAlias` from `key.properties` |
| `ANDROID_KEY_PASSWORD` | `keyPassword` from `key.properties` |

To encode the keystore, run one of these in the project root, then paste the result as the secret's value:

```powershell
# Windows (PowerShell): copies the result to the clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$PWD\notes-release.jks")) | Set-Clipboard
```

```sh
base64 -i notes-release.jks | pbcopy   # macOS: copies the result to the clipboard
base64 -w 0 notes-release.jks          # Linux: prints the result
```

If publishing fails with a permissions error, open **Settings → Actions → General → Workflow permissions** and
choose **Read and write permissions**.

## Credits

The bundled fonts, [Literata](https://github.com/googlefonts/literata),
[Schibsted Grotesk](https://github.com/schibsted/schibsted-grotesk), and
[Martian Mono](https://github.com/evilmartians/mono), are licensed under the SIL Open Font License.
