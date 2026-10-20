# WP5 — Anki export and settings: decision log

Branch `wp5-anki`, written 2026-10-13. PLAN.md §1 "Anki target", §3 WP5 and WP0 C14 are not
repeated; these are the choices they left open. Binding until explicitly reversed.

Source for the URL scheme: https://docs.ankiweb.net/ankimobile/url-schemes (read 2026-10-13).
What was relied on, quoted: the documented example
`anki://x-callback-url/addnote?profile=User%201&type=Basic&deck=Default&fldFront=front%20text&fldBack=back%20text`;
"Fields are entered by prefixing their name with 'fld'"; `tags=<tags separated by space>`;
`dupes=1`: "allow a note to be added even if the same content is on an existing note";
`x-success=<url scheme>`: "use to automatically return to another app after the note is added";
"Special characters in the URL must be escaped" and "if you have spaces in a field, they must be
represented with %20"; nested decks "Separate nested decks with `::`"; "The field text is
interpreted as HTML". The page does not say what happens without `dupes` (C14 records the
observed behaviour: the add is refused), does not document `x-error`/`x-cancel`, and says
nothing about `LSApplicationQueriesSchemes` (that is Apple's `canOpenURL` rule).

## Decisions

- **D5.1 URL format and encoding.** `AnkiUrlBuilder.addNote` (`lib/data/services/anki/anki_url.dart`,
  pure Dart) emits `anki://x-callback-url/addnote?type=…&deck=…&fld<Name>=<value>…[&tags=…]
  [&dupes=1]&x-success=<return url>`, parameters in that order, fields in the `AnkiNote.fields`
  map order, empty field values omitted, `tags` omitted when empty. Every value is
  percent-encoded over its UTF-8 bytes leaving only RFC 3986 *unreserved* characters bare
  (`A-Z a-z 0-9 - . _ ~`), so `::` → `%3A%3A`, space → `%20`, `(`/`)` → `%28`/`%29`, `→` →
  `%E2%86%92`, and Japanese is encoded byte by byte. This is stricter than `Uri.encodeComponent`
  (which keeps `!*'()`): the docs ask for every special character to be escaped, and it is what
  the Shortcuts "URL encode" action they recommend produces. `profile` is not sent: the user
  has one profile, and a wrong name makes the add fail. The tests pin the exact strings for an
  ASCII and a Japanese note and round-trip every value through `Uri.queryParameters`.
- **D5.2 Duplicates are AnkiMobile's decision: `dupes` is NOT sent by default.** Without it
  AnkiMobile refuses a note whose first field (Word) already exists (C14), which is the right
  default for a vocabulary deck: tapping the same word on a later page must not create a second
  card. `AnkiUrlBuilder(allowDuplicates: true)` / `UrlLauncherAnkiExporter(allowDuplicates:
  true)` sends `dupes=1`; it is a constructor option, not a user setting, until someone wants
  it (WP6 can surface it). The refusal is shown by AnkiMobile itself; the app only learns that
  it handed the note over (`AnkiExportOutcome.handedOver`).
- **D5.3 Return trip: `x-success=yomitanuki://anki-return`.** `ios/Runner/Info.plist` registers
  `CFBundleURLTypes` with scheme `yomitanuki` (name `app.mcmaffin.yomitanuki`, D9) so AnkiMobile
  can open it after the add, and `LSApplicationQueriesSchemes: [anki]` so `canOpenURL`
  (url_launcher's `canLaunchUrl`) answers truthfully (C14). The app does not parse the incoming
  URL in v1: being foregrounded is the whole message, and WP4's reader resumes its capture
  session on resume regardless of why it was backgrounded (PLAN §3 WP4). `x-error`/`x-cancel`
  are undocumented for `addnote` and not sent. The default lives on
  `UrlLauncherAnkiExporter.defaultReturnUrl`; the builder takes any `Uri`.
- **D5.4 Exporter outcomes.** `UrlLauncherAnkiExporter` (`lib/data/services/anki/`) takes
  `canLaunch` and `launch` as two injected `Future<bool> Function(Uri)` closures, defaulting to
  url_launcher's `canLaunchUrl` and `launchUrl(mode: externalApplication)`, so no test touches
  the plugin. `canLaunch == false` → `ankiNotInstalled`; `launch == false` → also
  `ankiNotInstalled`, because for a custom scheme iOS's `open` fails only when no app handles
  it (the domain enum has no third value and this is not a reason to add one); `true` →
  `handedOver`. A thrown `PlatformException` propagates: it is a programming or plugin error,
  not an outcome.
- **D5.5 The field mapping lives in `AnkiNoteBuilder`** *(shape changed by WP6d, see `.claude/wp6d/NOTES.md` D6d.1-D6d.6)* (`lib/domain/use_cases/anki_note_builder.dart`:
  pure logic over domain models, no I/O, so the reader view model never imports `data/` for
  it), one `build(lookup:, contextLine:, settings:)` call for WP4. Word = `entry.headword`
  (the dictionary form, not the inflected surface), Reading = `entry.reading`, Meaning = each
  sense's glosses joined with `; `; one sense is written as is, several are numbered
  `1. …<br>2. …`, Example = the OCR line, ExampleEN and Note empty (omitted from the URL by
  D5.1). No tags. Field *names* come from `AnkiSettings`, trimmed; the builder never spells
  `Word` itself. **Field text is HTML** (the docs: "The field text is interpreted as HTML"),
  so every value is escaped with `dart:convert`'s `HtmlEscape(HtmlEscapeMode.element)` (`&`
  `<` `>`) *before* any markup is composed, and a newline in the OCR line becomes `<br>`:
  `R&D` is sent as `R&amp;D`, `a<b` as `a&lt;b`. Anki strips HTML before its duplicate check
  (it compares the stripped first field), so an escaped Word still deduplicates against the
  same word added by hand (D5.2). *Revised after review: the first version inserted the values
  raw.*
  **Since WP6c (D6c.4): Example (English) carries the line's on-device translation in both
  the word note and the sentence note; Note is `sentence` on sentence notes (D6b.3).**
- **D5.6 Settings model and storage.** `AnkiSettings` (`lib/domain/models/anki_settings.dart`)
  is a value object: deck, note type, and a `Map<AnkiField, String>` of field names where a
  missing slot resolves to its default (`AnkiSettings.defaults` = PLAN §1: `Japanese::Frieren
  Vol. 1`, `Frieren Vocab (JP→EN)`, `Word, Reading, Meaning, Example, ExampleEN, Note`). The port
  `SettingsRepository` (`lib/domain/ports/settings_repository.dart`, the one domain addition of
  WP5, two methods: `loadAnkiSettings`, `saveAnkiSettings`) is implemented by
  `SharedPreferencesSettingsRepository` on `SharedPreferencesAsync`, one string key per value
  (`anki.deck`, `anki.noteType`, `anki.field.<slot>`); a value equal to its default is *removed*
  rather than written, so "nothing stored" and "the defaults" are one state and a changed
  default reaches a user who never edited that value. The model is a second domain file next
  to the port because the port's signature needs the type and the domain cannot import `data/`.
  `shared_preferences_platform_interface` is a dev dependency only, for
  `InMemorySharedPreferencesAsync` in the adapter test (the plugin's own documented test
  route); the legacy `SharedPreferences` API with `setMockInitialValues` was not used because
  the plugin steers new code to the async API.
- **D5.7 Settings screen: save on change, no save button.** `SettingsViewModel`
  (`lib/ui/settings/view_model/`, a `ChangeNotifier` over the port) applies every edit to its
  state and notifies before the save, then saves the whole object and notifies again only when
  `error` changes (so a plain successful edit is one notification, a failed save two); a failed
  save or load keeps the edit on screen and sets `error` to a **fixed sentence** ("Settings
  could not be saved." / "… loaded."), never the exception's text; the exception is kept in
  `lastFailure` and `debugPrint`ed for the log (error-handling-conventions: the description is
  for the user, the cause for the log). A save that answers after a newer edit replaced the
  state is ignored (`identical(next, _settings)` guard): the newer save reports for itself. The
  view shows `error` in an `errorContainer` banner until the next successful save.
  `SettingsView` (`lib/ui/settings/view/`) holds one `TextEditingController` per value and
  pushes state into them only when it differs (after a load or a reset), so the caret never
  moves under a typing user (pinned by a widget test: after typing, the selection is collapsed
  at the end); every `onChanged` wraps the async call in `unawaited` (D1.2
  `discarded_futures`). "Reset to defaults" is an app-bar action rather than the last list item
  so it is reachable with the keyboard up (and built in a 600 px test viewport). Material 3 by
  Flutter's default; colours come only from `Theme.of(context).colorScheme`, verified by a
  dark-theme render test. Route name `settings`; wiring in `lib/main.dart` is WP4's. The test
  fake yields to the event loop before every answer (`latency`, default zero) so the "before
  the save" and "after the save" states are both observable; a zero latency is still elapsed
  by one `pump()`, so the widget test for the failed-save banner sets a 50 ms latency and
  pumps past it.
- **D5.8 Validation: one rule, two consumers.** `AnkiSettings.problems` lists, as user
  sentences, an empty (after trimming) deck, note type or field name and a field name used by
  two slots (a duplicate name would silently drop a field: the map literal keeps the last key
  and the headword is lost). `SettingsViewModel._update` shows an invalid edit, reports the
  first problem via `error`, and does **not** persist it, so what is stored always builds a
  note; the next valid edit saves and clears the error. `AnkiNoteBuilder.build` throws
  `ArgumentError` (message = the problems) on the same rule, so WP4 can never send a truncated
  note even from settings written by a future path. Surrounding whitespace is tolerated while
  typing and trimmed when the note is built.

## What will bite the next work package

- **`main.dart` wiring (WP4 owns it):** `SharedPreferencesSettingsRepository(SharedPreferencesAsync())`,
  `UrlLauncherAnkiExporter()`, `const AnkiNoteBuilder()` (import
  `domain/use_cases/anki_note_builder.dart`), and `routes: {'settings': (_) =>
  SettingsView(viewModel: SettingsViewModel(repository: settingsRepository))}`. The reader
  must `loadAnkiSettings()` before building a note (settings can change while it is open) and
  catch `ArgumentError` from `build` (D5.8; it cannot happen with settings saved by the
  settings screen, but the reader should send the user to `settings` rather than crash).
  Add a `darkTheme` next to `theme` in `MaterialApp` or the dark palette never shows.
- **The return URL is not handled.** If WP4/WP6 ever wants to know *that* the add succeeded (vs.
  the user switching back by hand), add a deep-link listener for `yomitanuki://anki-return`;
  until then the scheme registration only makes AnkiMobile's `x-success` open the app.
- **CocoaPods runs for the first time** with these two plugins (`url_launcher_ios`,
  `shared_preferences_foundation`); `pod install` has not been executed in this WP (no
  `flutter build ios` in the gate, D1.8). Set `LANG=en_US.UTF-8` (WP1 notes).
- **`canLaunchUrl` on the simulator** answers false without AnkiMobile installed; the exporter
  then reports `ankiNotInstalled`, which is correct, but means the full round trip can only be
  tried on the phone.
