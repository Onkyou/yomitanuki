# domain

Plain models, the ports every adapter implements, and under `use_cases/` the pure
logic that combines models (no I/O, no plugins). Nothing in here imports Flutter
widgets, plugins or ONNX Runtime. Each port has exactly two kinds of implementation:
the real adapter under `lib/data/` (`services/` wraps a plugin or a model,
`repositories/` persists; PLAN §3 WP1), and a fake under `test/fakes/` used by every
test that is not the adapter's own.

| Port | Real adapter | Work package |
|---|---|---|
| `TextDetector` | ONNX Runtime, blocks-only detector graph | WP2 |
| `OcrEngine` | ONNX Runtime, manga-ocr encoder + greedy decoder | WP2 |
| `Dictionary` | SQLite (JMdict + KANJIDIC2) + deinflector | WP3 |
| `FrameSource` | `camera` plugin, BGRA8888 stream | WP4 |
| `PhotoPicker` | `image_picker` + `dart:ui` decode, under `lib/data/services/photo/` | WP4 |
| `AnkiExporter` | `anki://x-callback-url/addnote` via `url_launcher` | WP5 |
| `SettingsRepository` | `shared_preferences`, under `lib/data/repositories/` | WP5 |
| `OcrCaptureLog` | files in the Documents folder (`ocr-captures/`), under `lib/data/services/capture/` | WP6a |
| `SentenceTranslator` | Apple's Translation framework through the local `translation_ios` plugin, under `lib/data/services/translation/`; `TranslationStatus` says whether the packs are installed (iOS 26+ only) | WP6c |

Image data crosses every port as `BgraImage` (8-bit BGRA, the iOS camera's native
layout); the ONNX graphs consume it directly (WP0 D0.9), so no adapter resamples pixels.

## Models, text helpers and use cases added by WP6b (the sentence layer)

| File | What |
|---|---|
| `models/line_gloss.dart` | `LineGloss` (an OCR line cut into spans, with `readingLine` and `glossLine`), `GlossSpan` (a matched word or plain text), `RubySegment` (characters and the reading over them) |
| `use_cases/line_glosser.dart` | `LineGlosser(Dictionary).gloss(line)`: walks the line with `lookupAt`, first result wins, plain text merges |
| `use_cases/furigana.dart` | `furigana(surface, form, reading)`: pure alignment of a reading with the kanji runs of a form |
| `use_cases/anki_note_builder.dart` | `buildSentence` next to `build`: the line as a note, `Note` = `sentence` |
| `text/kana.dart` | `toHiragana`, moved down from `data/services/dictionary/` (which re-exports it) because the use cases need it and the domain does not import the data layer |
| `text/lookup_breaks.dart` | the characters a dictionary surface never crosses, shared by `SqliteDictionary` and `LineGlosser` |
