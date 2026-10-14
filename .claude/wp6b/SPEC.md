# Spec: WP6b — the sentence layer: readings, gloss line, underlines, sentence notes

Branch `wp6b-sentence-layer` off `main` after WP6a is merged (WP6a changed `ocr_sheet.dart`,
`reader_state.dart` and the view model; build on the merged result). Decisions D6b.1–D6b.5
in `.claude/wp6b/NOTES.md`; WP3 D3.4–D3.6 and WP5 D5.5–D5.8 are the ground this stands on.
Read before coding: `AGENTS.md`, skills `flutter-apply-architecture-best-practices`,
`test-driven-development`, `testability-seams`, `flutter-add-widget-test`,
`dart-use-pattern-matching`, `error-handling-conventions`.

## Objective

When the OCR sheet opens with a line, the reader sees, without tapping anything:
the line with the reading of every kanji run written small above it (furigana), the words the
dictionary recognises underlined in two alternating colours, and under each recognised word
its first gloss. One button adds the whole line to Anki as a sentence note. Tapping a
character still opens the per-word card exactly as today (C15 unchanged).

Out of scope: translation (D6b.1), per-kanji furigana data (D6b.2), a second Anki note type
(D6b.3), copula deinflection (D3.10), vertical layout.

## Commands

From `app/`: `dart format .`, `flutter analyze --fatal-infos`, `flutter test`. T1 changes the
dictionary schema, so the orchestrator runs `make dict` (rebuilds `app/assets/dict/`, ~1 min
from the cached downloads) and `make gate`. The builder does not run those two.

## Structure (files to touch)

```
app/lib/data/services/dictionary/dict_builder.dart     forms.reading column, schemaVersion 2
app/lib/data/services/dictionary/sqlite_dictionary.dart matchedReading in results
app/lib/domain/models/lookup_result.dart               + matchedReading
app/lib/domain/models/line_gloss.dart                  NEW: LineGloss, GlossSpan, RubySegment
app/lib/domain/use_cases/line_glosser.dart             NEW: segmentation over Dictionary.lookupAt
app/lib/domain/use_cases/furigana.dart                 NEW: pure alignment of surface vs reading
app/lib/domain/use_cases/anki_note_builder.dart        + buildSentence
app/lib/ui/reader/view_model/reader_view_model.dart    gloss after OCR, addSentenceToAnki
app/lib/ui/reader/view_model/reader_state.dart         OcrText gains `gloss` (nullable)
app/lib/ui/reader/view/ocr_sheet.dart                  the new line rendering + button
app/lib/ui/reader/view/lookup_results_view.dart        card shows matchedReading for the tapped word
app/test/fakes/fake_dictionary.dart                    matchedReading on every result
tests beside each; the mini fixture tests in app/test/data/services/dictionary/
```

## Tasks (in order, each red first)

### T1 Matched reading in the dictionary (fixes the ビール/麦酒 gap, D6b.2)

- `forms` gets `reading TEXT NOT NULL`. For a kana form the value is the form's own text as
  written (ビール, not びーる). For a kanji form it is the primary kana that applies to that
  kanji (`_primary(kana, appliesTo: formText) ?? _first(kana, appliesTo: formText) ?? reading ?? ''`,
  using the existing helpers). Both keys of a form (hiragana-normalised and original) carry
  the same reading. `schemaVersion = 2`; update the class doc comment.
- `SqliteDictionary`: `_formsByKey` becomes `SELECT entry_id, reading FROM forms WHERE form = ?`;
  one result per entry per surface keeps the first reading seen. `LookupResult` gains
  `required String matchedReading` (the reading of the matched *form*; for an inflected
  surface it is the base form's reading, e.g. 食べた → たべる). Every construction site, the
  fake and the test constants (`taberareNakattaResult`) are updated; the fake sets
  `matchedReading` to the entry reading when the form is the headword, else to the form.
- Tests: `dict_builder_test` asserts the column and a kana-form row's reading equals the form
  text; `sqlite_dictionary_test` against the mini fixture: a kana-headword lookup returns its
  own katakana reading, a kanji lookup returns the applying kana. If the mini fixture has no
  entry with a kanji form and a katakana-only reading, add one (JMdict-shaped JSON, with
  `appliesToKanji`) to `test/fixtures/dict/mini_jmdict.json` and the matching expectation in
  `mini_dictionary.dart`.

### T2 Furigana alignment (pure function)

`furigana(String surface, String form, String reading) → List<RubySegment>` where
`RubySegment(text, ruby?)`. Algorithm: build a regex from `form`: each maximal run of kanji
(`[㐀-䶿一-鿿々〆]`) becomes a lazy group `(.+?)`, every kana character becomes its
hiragana-normalised literal; anchor `^…$`; match against `toHiragana(reading)` (import the
existing `kana.dart` helper; move it to `domain/` or re-export if the layering rule demands,
and say so in the report). On a match, each kanji run in `surface` that is also in `form` at
the same prefix position gets the captured group as ruby; kana runs have no ruby. For an
inflected surface (`surface != form`), align on the longest common prefix of surface and form
and leave the surface's tail (the inflection) without ruby. On no match (or the surface shares
no prefix with the form) return one segment, the whole surface with the whole reading as ruby
when the surface contains kanji, else with no ruby. Tests: 食べる/たべる → [食:た][べる];
食べた vs form 食べる → [食:た][べた]; 魔王/まおう → [魔王:まおう]; お茶/おちゃ → [お][茶:ちゃ];
ビール (kana) → no ruby; 大人/おとな (irregular, one run) → [大人:おとな]; a non-matching pair
→ whole-surface ruby.

### T3 Line glosser (domain use case)

`LineGlosser(Dictionary)` with `Future<LineGloss> gloss(String line)`. Walk the line by code
point: at offset `i`, if the character is whitespace or one of D3.5's break characters, emit
nothing and advance; else `lookupAt(line, i)`; if non-empty take the first result (D3.5's
order already puts the longest, best-ranked match first) and emit
`GlossSpan(start, length, surface, reading: matchedReading, gloss: first sense's glosses
joined ', ', ruby: furigana(surface, baseForm, matchedReading), baseForm)` and advance by
`length`; if empty, emit a plain `GlossSpan` for that one code point (gloss null, ruby =
[surface, no ruby]) and advance. Adjacent plain spans are merged. `LineGloss(line, spans)`
with `String get readingLine` (every span's reading if matched, else its surface; readings
hiragana-normalised with `toHiragana`) and `String get glossLine` (`surface: gloss` for each
matched span joined by `\n`). Pure over the port; the fake dictionary drives the tests:
'魔王を倒した' with the fake's default entries → spans [魔王 matched][を plain][倒した plain]
(the fake has no 倒す); a line of only punctuation → no matched spans; a lookup error from
the dictionary propagates (the view model handles it).

### T4 View model: gloss after OCR, sentence to Anki

- `OcrText` gains `LineGloss? gloss` (constructor `(block, crop, text, {this.gloss})`).
  After the OCR result lands in `onTapBlock` (and only if still current, D4.16), the view
  model runs `LineGlosser(_dictionary).gloss(text)` and, if the state is still that same
  `OcrText` instance, replaces it with a copy carrying the gloss and notifies. A glosser
  error is logged (`_log`) and leaves `gloss` null: the line is still readable and tappable.
- `addSentenceToAnki()`: requires `OcrText` with a non-null gloss; builds the note with
  `AnkiNoteBuilder.buildSentence(gloss: gloss, settings:)` and hands it to `_anki.add`,
  mapping outcomes like `addToAnki` does; `AnkiHandedOver(line)` on success. Settings
  problems → the same `AnkiFailed` sentence as today.
- `AnkiNoteBuilder.buildSentence`: Word = `html(line)`, Reading = `html(readingLine)`,
  Meaning = each `surface: gloss` line escaped and joined with `<br>`, Example = `html(line)`,
  Example (English) empty, Note = `sentence` (D6b.3). Same `problems` guard.
- Tests: gloss lands on the current state and not on a dismissed one (hold the fake with
  `manual`, dismiss, release); glosser error → `gloss` null and no notice; `addSentenceToAnki`
  produces the field map above with the fake exporter; it is a no-op (no export) when there
  is no gloss yet.

### T5 Sheet rendering and the button

- Replace `_TappableLine`'s flat Wrap of character cells with a Wrap of **span columns**, one
  per `GlossSpan` (when `gloss` is null, one plain span per code point as today, so the sheet
  is unchanged until the gloss arrives). A span column is a `Column` (min size): a ruby row
  (small text, `labelSmall`, one `Text` per `RubySegment` positioned over its segment: render
  the segment row as a `Row` of per-segment `Column`s [ruby or empty, characters]), then the
  character cells (the existing `InkWell` per code point, keys `ocr.char.$start`, highlight
  logic unchanged), then for a matched span a bottom border 2 px in colour A or B alternating
  by matched-span ordinal (`colorScheme.primary` / `colorScheme.tertiary`), then the gloss
  `Text` (`bodySmall`, max 2 lines, ellipsis, max width 160) for matched spans. Plain spans:
  no ruby, no border, no gloss.
- Button: in the top row next to the close icon, `FilledButton.tonalIcon` with
  `Icons.playlist_add`, label 'Add sentence', key `anki.addSentence`, enabled only when
  `ocrState is OcrText && gloss != null`; `onAddSentence` callback wired in `reader_view.dart`
  to `vm.addSentenceToAnki()`.
- `LookupResultsView._ResultCard`: when `result.matchedReading` differs from
  `entry.reading`, show the matched reading as the word's reading and the entry's headword
  【reading】 as a second, smaller line (ビール, then 麦酒【ばくしゅ】).
- Widget tests: with a gloss, `find.byKey(Key('ocr.gloss.$start'))` for the matched span's
  gloss text and `ocr.ruby.$start` for a ruby; the button is disabled without a gloss and
  calls the callback with one; the character keys still exist and tap through.

## Boundaries

No new dependencies. No code generation. Nothing in `wp0/`. `tool/dict/build_dict.dart` is
unchanged unless the schema bump needs a flag (it should not: the stamp already carries
`schemaVersion`). Dictionary rebuild and `make gate` are the orchestrator's.

## Success criteria

- All new tests red first, then green; `flutter test` and `flutter analyze --fatal-infos` clean.
- After `make dict`: a real lookup of ビール returns `matchedReading` ビール.
- On the phone: open a bubble, see readings over kanji, underlines, glosses; tap 'Add sentence',
  AnkiMobile shows Word = the line, Reading = kana, Meaning = word glosses.

## Open questions

None blocking. If `kana.dart`'s location (data layer) violates the dependency rule for a
domain use case, move `toHiragana` to `lib/domain/text/kana.dart` and leave a re-export in
place; report it.
