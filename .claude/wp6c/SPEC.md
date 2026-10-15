# Spec: WP6c — sentence translation in the sheet via Apple's Translation framework

Branch `wp6c-apple-translation` off `main`. Decisions D6c.1–D6c.5 in `.claude/wp6c/NOTES.md`.
Read before coding: `AGENTS.md`, skills `flutter-apply-architecture-best-practices`,
`testability-seams`, `test-driven-development`, `flutter-add-widget-test`,
`error-handling-conventions`, `api-and-interface-design`; `.claude/wp6b/NOTES.md` (how the
gloss lands, D4.16) and `.claude/wp5/NOTES.md` D5.5–D5.8 (note fields).

## Objective

When the OCR sheet opens, an English translation of the whole line appears under the crop
thumbnail and above the word columns, produced on the device by Apple's Translation framework.
The sentence note and the word note carry it as "Example (English)". Nothing else waits for it.

Out of scope: online translation, Android, per-page context, any UI for downloading language
packs (the app points to Settings), iOS below 26 (reports "needs iOS 26").

## Facts about the framework (verified 2026-10-15 from Apple's documentation data)

- `import Translation`; `TranslationSession` iOS 18.0+. `init(installedSource:target:)` and
  `init(installedSource:target:preferredStrategy:)` are **iOS 26.0+**; they need the languages
  installed and cannot request downloads. `translate(batch:)` (iOS 18.0+) takes
  `[TranslationSession.Request(sourceText:clientIdentifier:)]` and returns an `AsyncSequence`
  of `Response` (`targetText`, `clientIdentifier`). `TranslationSession.Strategy.highFidelity`
  / `.lowLatency` are iOS 26.4+. `isReady` iOS 26.0+.
- `LanguageAvailability()` iOS 18.0+: `await status(from: Locale.Language(identifier: "ja"),
  to: Locale.Language(identifier: "en"))` → `.installed`, `.supported`, `.unsupported`.
- The framework does not translate in the Simulator; status there is expected to be
  `.unsupported`. Device-only verification by the orchestrator.

## Structure

```
app/packages/translation_ios/                       NEW Flutter plugin (Swift, method channel)
  pubspec.yaml                                      flutter.plugin.platforms.ios.pluginClass: TranslationIosPlugin
  ios/translation_ios.podspec                       s.dependency 'Flutter'; s.platform :ios, '15.1'; s.swift_version '5.0'; s.weak_frameworks 'Translation'
  ios/Classes/TranslationIosPlugin.swift            the channel handler
  lib/translation_ios.dart                          Dart side: TranslationIos (status, translate) over MethodChannel('yomitanuki/translation')
  test/translation_ios_test.dart                    channel-level tests with TestDefaultBinaryMessenger
app/pubspec.yaml                                    translation_ios: path: packages/translation_ios
app/lib/domain/models/translation_status.dart       NEW enum
app/lib/domain/ports/sentence_translator.dart       NEW port
app/lib/domain/errors.dart                          TranslationUnavailableError(status)
app/lib/data/services/translation/apple_sentence_translator.dart   NEW adapter over TranslationIos
app/lib/ui/reader/view_model/reader_state.dart      OcrText gains `translation` (String?), copyWith
app/lib/ui/reader/view_model/reader_view_model.dart translation step, crop-identity landing (D6c.3), ExampleEN
app/lib/domain/use_cases/anki_note_builder.dart     `contextTranslation` → Example (English) in build and buildSentence
app/lib/ui/reader/view/ocr_sheet.dart               translation line
app/lib/domain/ports/settings_repository.dart       translateEnabled flag (default true)
app/lib/data/repositories/shared_preferences_settings_repository.dart  key `translate.enabled`
app/lib/ui/settings/view_model/settings_view_model.dart  translateEnabled + status text
app/lib/ui/settings/view/settings_view.dart          "Reading" section
app/lib/main.dart                                    wiring (AppleSentenceTranslator(TranslationIos()))
app/integration_test/*.dart                          pass the fake translator
app/lib/domain/README.md                             port row
app/test/fakes/fake_sentence_translator.dart         NEW
tests beside each
```

## Tasks (in order, red first)

### T1 Plugin `translation_ios`

Dart API:
```dart
enum TranslationIosStatus { installed, supported, unsupported, requiresNewerOs }
class TranslationIos {
  TranslationIos({MethodChannel? channel});           // default MethodChannel('yomitanuki/translation')
  Future<TranslationIosStatus> status();              // 'status' → String
  Future<List<String?>> translate(List<String> lines); // 'translate' {lines: [...]} → List<String?> same length
}
```
Swift (`TranslationIosPlugin.swift`): registers the channel; `status`: if
`#available(iOS 26.0, *)` → `LanguageAvailability().status(from: ja, to: en)` mapped to
`installed|supported|unsupported`, else `requiresNewerOs`. `translate`: iOS 26+ only (else
`FlutterError(code: "requiresNewerOs")`); keeps one session (`init(installedSource:target:
preferredStrategy: .highFidelity)` when `#available(iOS 26.4, *)`, else without strategy);
builds requests with `clientIdentifier = String(index)`, iterates `translate(batch:)`, fills an
array by identifier, returns it (nil where no response came). Any thrown error → the session is
dropped (recreated next call) and `FlutterError(code: "translationFailed", message: …)`;
if the error is the not-installed case, `code: "notInstalled"`. Everything on `@MainActor`
tasks; the result callback on the main thread.
Dart side maps `FlutterError` codes to typed exceptions in the adapter (T2), not here; the
plugin's Dart class is a thin channel wrapper. Tests: mock handler returns each status string;
`translate` passes `lines` through and returns the list; a `PlatformException` propagates.
Also `cd app/packages/translation_ios && flutter analyze --fatal-infos` clean. The Swift
compiles in the gate's simulator build; the builder cannot run it, so write it carefully and
keep it under ~120 lines.

### T2 Port, status, adapter

```dart
enum TranslationStatus { installed, downloadNeeded, unsupported, requiresNewerOs }
abstract interface class SentenceTranslator {
  Future<TranslationStatus> status();
  /// Throws TranslationUnavailableError when not installed/supported.
  Future<String> translate(String line);
}
```
`AppleSentenceTranslator(TranslationIos)` maps statuses (`supported` → `downloadNeeded`),
calls `translate([line])`, returns the single string, throws `TranslationUnavailableError`
for codes `notInstalled`/`requiresNewerOs`, `TranslationFailedError` (new, in `errors.dart`)
otherwise; an empty or whitespace line returns `''` without a channel call. Tests with a
`TranslationIos` over a mocked channel. `FakeSentenceTranslator` in `test/fakes/`: canned
`translations` map (line → text), `status`, `error`, `manual` completers like the other fakes.
`describeReaderError` is NOT extended: translation failures are never shown as notices.

### T3 View model, state, notes

- `OcrText` gains `String? translation` and `OcrText copyWith({LineGloss? gloss, String?
  translation})`. `_addGloss` and the new `_addTranslation(read)` land their result only when
  `_ocrState is OcrText && identical((_ocrState as OcrText).crop, read.crop)` (D6c.3), onto
  the *current* state via `copyWith`, so whichever lands second keeps the first.
- `onTapBlock`: after the text lands, `Future.wait([_addGloss(next), _addTranslation(next),
  _capture(...)])`. `_addTranslation`: returns at once when the settings flag is off
  (`loadTranslateEnabled()`), when the text is blank, or when a cached status is not
  `installed` (query `status()` once per view model lifetime and cache it; re-query when
  `start()` is called again, since the reader may have installed the pack meanwhile). Failures
  are logged via `_log` and leave `translation` null.
- `addToAnki` and `addSentenceToAnki` pass `contextTranslation: translation` to the builder;
  `AnkiNoteBuilder.build`/`buildSentence` write `html(contextTranslation ?? '')` to Example
  (English).
- Tests: translation lands and keeps an earlier gloss, gloss lands and keeps an earlier
  translation (both orders, with `manual` fakes); a translation for an earlier read does not
  land on a newer read; flag off → no call; status `downloadNeeded` → no call; error → null,
  no notice; both note builders carry the translation; `build` with null translation keeps
  Example (English) empty.

### T4 Sheet

Between the thumbnail and the word columns: when `OcrText.translation` is non-null and not
empty, a `Text` with key `ocr.translation`, `bodyLarge`, selectable not required. While
the translation is still pending (state is `OcrText`, translation null, and the sheet was told
translation is active) show a one-line `Text('Translating…', key: Key('ocr.translation.pending'))`
in `bodySmall` muted colour; the sheet learns "active" through a new `bool translationActive`
parameter the view passes from `vm.translationActive` (true when the flag is on and status is
`installed`). Tests: line shown; pending shown only while active and null; nothing when
inactive.

### T5 Settings

- `SettingsRepository.loadTranslateEnabled()` default true / `saveTranslateEnabled(bool)`,
  key `translate.enabled`, key removed when true (the default), same `_put` pattern.
- `SettingsViewModel`: `translateEnabled`, `setTranslateEnabled`, `translationStatus`
  (from the port, loaded in `load()` in its own try; null on failure) and `String get
  translationStatusText`: installed → 'Japanese → English is installed for offline use.';
  downloadNeeded → 'Download Japanese and English under Settings › Apps › Translate ›
  Downloaded Languages to translate offline.'; unsupported → 'This device cannot translate
  Japanese to English.'; requiresNewerOs → 'Sentence translation needs iOS 26.'; null → ''.
  The view model takes the `SentenceTranslator` as a constructor dependency.
- `SettingsView`: a "Reading" section before "Anki" with `SwitchListTile` key
  `SettingsView.translateKey`, title 'Translate sentences', subtitle = status text.
- Tests as for the crops switch (view model and widget), plus the partial-load guard.

## Boundaries

No new pub dependencies (the plugin is local). No change to deployment target. No code
generation. `Translation` weak-linked; everything behind `#available`. Do not touch `wp0/`.

## Success criteria

- All new tests red first, then green; `flutter test`, `flutter analyze --fatal-infos` clean in
  `app/` and in `app/packages/translation_ios/`.
- `make gate` green (its simulator debug build compiles the Swift).
- On the phone (orchestrator/Marv): with the packs installed, a bubble shows its translation
  within about a second of the text; with the packs missing, Settings shows the download
  hint and the sheet shows no translation line; sentence and word notes carry the English line.

## Open questions

None blocking. If `translate(batch:)` must be consumed on the main actor and the plugin's
result callback ordering is awkward, collect the responses into an array first and reply once.
