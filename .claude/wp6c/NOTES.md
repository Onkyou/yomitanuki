# WP6c — sentence translation in the sheet: options, not yet decided

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

## Android, for later (Marv asked)

Same shape, different adapter. Google ML Kit on-device translation does ja↔en offline with
~30 MB language packs downloaded by the app (quality: Google's offline models, "casual and
simple translations" per its docs, below Apple's highFidelity). Android 12+ also has a system
Views translation API, but it is aimed at translating UI, not arbitrary text. Either is one
more `SentenceTranslator` adapter behind the same port; nothing above the port changes.
