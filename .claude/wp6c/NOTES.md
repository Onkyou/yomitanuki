# WP6c — sentence translation in the sheet: options, then the decisions

Resolved: see D6c.1 to D6c.6 under "Decisions" below; the options are kept as the record of why.

Marv, 2026-10-15, after using WP6b on the phone: word glosses alone are hard on the UX; a
full-sentence translation is wanted, high quality, offline preferred. This reopens D6b.1
("no translation on the device"), which Marv may reverse.

## Options (Claude's assessment)

1. **Apple Translation framework, on device (recommended).** iOS 18+ `TranslationSession`
   (`translate(batch:)`); all processing on the device once the language pack is installed;
   the pack is downloaded by the system on first use (`prepareTranslation()`, needs network
   once); `LanguageAvailability` reports supported/installed per pair. Same engine as the
   Translate app, which has Japanese. Quality: consumer MT, sentence by sentence, no manga
   context, but far above any model the app could bundle. Cost: a small iOS plugin
   (`app/packages/translation_ios`) wrapping a hidden SwiftUI host with `.translationTask`
   (the session is handed out by SwiftUI), a method channel, a `SentenceTranslator` port with
   a fake. Does not run in the simulator; device-only verification. iPhone 14 is fine (not
   Apple Intelligence hardware, but this framework does not need it).
2. **Opt-in online translation (Claude or DeepL)** for best quality and page-level context
   (all bubbles of a page translated together, speaker continuity). Breaks D10 "no network
   while reading" unless framed as an opt-in extra: the reader works offline, the translation
   line appears when online and enabled. Could sit on top of option 1 as "better translation
   when online". Cost per page is small; privacy: bubble text leaves the phone.
3. **Bundled open model.** NLLB-200 600M (CoreML ports are ~3 GB), Marian opus-mt ja-en
   (~80 MB int8, weak on colloquial Japanese), or a 1–2B LLM via llama.cpp (~1 GB, slow on an
   A15, mediocre JA→EN). None reaches option 1's quality at a size the app can ship.
   Not recommended.
4. **Apple Foundation Models (iOS 26 on-device LLM).** Not available on iPhone 14 (needs
   Apple Intelligence hardware) and Apple says it is not tuned for translation. Ruled out.

## Proposed shape if option 1 is chosen

- Domain port `SentenceTranslator { Future<String?> translate(String line); }` plus an
  availability query; fake in tests; the ORT-style lazy adapter pattern.
- The translation lands in `OcrText` next to `gloss` (D4.16 identity rule), shown as one
  line between the thumbnail and the word columns; "…" while pending; silently absent when
  the pack is not installed, with a one-time "Download Japanese→English for offline
  translation?" prompt (the system's own sheet).
- Sentence notes get Example (English) = the translation (D5.5 finally fills that field).
- Stays optional: a Settings switch, default on when the pack is installed.

## Decisions

- **D6c.1 (Marv, 2026-10-15) Sentence translation comes from Apple's Translation framework, on
  the device.** Reverses D6b.1's "no translation" for this one source. No bundled MT model
  (option 3), no Apple Foundation Models (option 4). Online translation (option 2) is not part
  of this package; the port leaves room for it.
- **D6c.2 (Claude, verified against Apple's doc data on 2026-10-15) Direct sessions, iOS 26
  floor for the feature.** `TranslationSession(installedSource:target:)` exists from iOS 26.0
  (`init.json`: iOS 26.0), so the plugin needs no hidden SwiftUI host. Such a session cannot
  request language downloads (`canRequestDownloads`, iOS 26.0, is false for it); when
  `LanguageAvailability.status(from: ja, to: en)` is `.supported` but not `.installed`, the
  app tells the reader to download Japanese and English under Settings › Apps › Translate
  (Downloaded Languages). `TranslationSession.Strategy.highFidelity` (iOS 26.4) is requested
  when available; Marv's phone is on 26.6. Below iOS 26 the feature reports "needs iOS 26"
  and the sheet shows no translation line; the rest of the app is unchanged (deployment
  target stays 15.1, `Translation` is weak-linked).
- **D6c.3 One translation per read, landed by crop identity.** Gloss and translation both
  replace the `OcrText` instance, so `identical(_ocrState, read)` would drop whichever lands
  second. Both now land if the current state is an `OcrText` whose `crop` is the read's
  (one packed crop per read, never shared), via `copyWith`.
- **D6c.4 The translation fills "Example (English)" in both note kinds** (D5.5 left it empty):
  the sentence note and the word note whose context line it is.
- **D6c.5 On by default, one switch.** Settings › Reading › "Translate sentences"; the
  subtitle shows the status (installed / download needed with the Settings path / not
  supported / needs iOS 26). Translation never blocks the text or the gloss: it runs
  alongside them and the line appears when it lands.

- **D6c.6 (coordinator, 2026-10-15) The English target is the first installed of `en-GB`,
  `en-US`, `en`.** Apple's Translation framework treats English variants as distinct languages
  (the Translate app lists "English (UK)" and "English (US)"), so a pack for one is not
  `.installed` for another and a bare `en` check may report `.supported`. `status` answers
  `installed` when any of the three is installed, else `supported` when any is, else
  `unsupported`; `translate` builds its session (cached with its chosen target, both dropped on
  error) for the first installed one in that fixed order. Source stays `ja`. Implemented in
  `TranslationIosPlugin.swift` (`Translator.targets`).

## Android, for later (Marv asked)

Same shape, different adapter. Google ML Kit on-device translation does ja↔en offline with
~30 MB language packs downloaded by the app (quality: Google's offline models, "casual and
simple translations" per its docs, below Apple's highFidelity). Android 12+ also has a system
Views translation API, but it is aimed at translating UI, not arbitrary text. Either is one
more `SentenceTranslator` adapter behind the same port; nothing above the port changes.

## Red-first evidence

Compile-red = the test file did not compile because the API it names did not exist yet;
assertion-red = a stub or a temporary mutation was in place and the named assertion failed.

T1 (`packages/translation_ios/test/translation_ios_test.dart`): compile-red (`TranslationIosStatus`
undefined), then 10 of 10 green with the wrapper. No assertion-red was seen separately. The Swift
file is not covered by any test here; it was type-checked with
`swiftc -typecheck -swift-version 5 -target arm64-apple-ios15.1-simulator` against the Xcode 27
simulator SDK and the engine's Flutter.xcframework (clean, no warnings), and the gate's simulator
build compiles it too.

Settings repository (`shared_preferences_settings_repository_test.dart`, done ahead of T5 because
T3 needs the port method): written after the port, not seen red by compile; mutation check
`?? true` to `?? false` in `loadTranslateEnabled` failed both tests (`Expected: true / Actual:
<false>`), restored.

T2 (`apple_sentence_translator_test.dart`): compile-red (adapter, status enum and errors missing);
not seen assertion-red. The blank-line tests pass against any adapter that checks before calling
the channel and were written with it.

T3
- `anki_note_builder_test.dart` 'Example (English) (D6c.4)' (4 tests): written before the
  `contextTranslation` parameter; not run red (the named parameter did not exist, so they could
  not have compiled).
- `reader_view_model_test.dart` 'translation after OCR (D6c)' (16 tests): written before the
  implementation, never run against a stub. Mutation checks instead, on the landing rule:
  restoring the WP6b rule `identical(_ocrState, read)` in `_isCurrent` fails 'a gloss landing after
  the translation keeps the translation', 'a translation landing after the gloss keeps the gloss'
  and 'the text shows first and the translation follows' (plus the WP6b 'the text shows first and
  the gloss follows'), i.e. both landing orders. Replacing the crop check by `OcrText() => true`
  fails 'a translation for an earlier read does not land on a newer one' and the WP6b equivalent.
- Existing tests that the translation changed and that were updated: the two note-field tests
  ('add to Anki builds the note ...', 'add sentence ... builds a sentence note ...') now expect
  `ExampleEN` to be the harness's translation instead of `''`.

T4 (`ocr_sheet_test.dart`, `reader_view_test.dart`): written with the widget. Mutation checks:
removing the translation line from the sheet fails 'a translation shows between the crop and the
text', 'a translation shows even if the sheet was not told it is active', 'while it is pending the
sheet says so' and the reader_view 'the sheet shows the translation ...'; making the pending line
unconditional fails 'nothing shows when translation is not active' and the reader_view 'without
the packs ...'. Both restored.

T5 (`settings_view_model_test.dart`, `settings_view_test.dart`): written after the view model and
the view, not run red by compile or stub; they follow the crops-switch tests one to one. Not
mutation-checked.

### Review round (two reviews, 2026-10-15)

- Single-flight `Translator.translate` (Swift): not testable from Dart; type-checked with the
  same `swiftc -typecheck` command as T1 (clean). Verified on device only.
- 'a pack removed since the status was cached stops further attempts': assertion-red with the
  `_translationStatus = e.status` line removed (second tap called the translator again),
  restored.
- `translationActive` resets, each failing with its reset removed and restored:
  - `onTapBlock` reset removed: 'tapping another bubble with the switch off clears the active
    flag' and 'a blank read after a pending one is not active, and the late translation of the
    first does not land' fail. (Written without a dismiss between the taps: `dismissOcr` has its
    own reset and would mask the `onTapBlock` one.)
  - `dismissOcr` reset removed: 'dismissing the sheet clears the active flag' fails.
- T5 mutation checks: `_translateEnabled` default flipped to false fails 'translate sentences
  (D6c.5) a failing switch load keeps the Anki settings that did load' and, after adding a
  before-load assertion, 'load exposes the stored switch, on by default, in one notification'
  (the initial field value is otherwise overwritten by `load`). Swapping the Reading and Anki
  sections fails 'the Reading section (D6c.5) the section comes before Anki'.
- `load()` now starts `status()` before the repository loads (item 5), with its failure handled on
  the future itself; the settings tests for a failing status query still pass, so that behaviour is
  pinned. The ordering itself is not tested.
- 'an empty answer is a failed translation' (adapter): passes by design, written to pin the
  existing `out.isEmpty` branch; not seen red.
- `readingSectionKey` assertions replace the always-true `find.text('Reading').first`; the
  section-swap mutation above fails through it.
- `AppleSentenceTranslator.production()` replaces the plugin import in `main.dart`; covered by
  the compile and by `main_test.dart`'s unchanged fakes (production wiring is not constructed in
  tests).
