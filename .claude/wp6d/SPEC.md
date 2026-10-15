# Spec: WP6d — Anki card shape after the sentence layer

Branch `wp6d-anki-cards` off `main`. Findings and the ranked table in `.claude/wp6d/NOTES.md`;
this spec implements the **must** and **should** rows and parks the rest. Reverses parts of
D5.5 and D6b.3 (recorded as D6d.1–D6d.6 in the notes by the builder, each one line: what and why).
Read before coding: `AGENTS.md`, skills `test-driven-development`,
`flutter-apply-architecture-best-practices`, `api-and-interface-design`; `.claude/wp5/NOTES.md`
D5.1–D5.8 (URL scheme, HTML fields, duplicates), `.claude/wp6b/NOTES.md` D6b.3, `.claude/wp6c/NOTES.md` D6c.4.

## Objective

Word notes test the spelling the reader saw, mark the target in the example, carry furigana on
the other words, and list at most three senses with the matching ones first. Sentence notes are a
Japanese → English recognition card: plain line, furigana line, translation, glosses; no field
repeats the line, the Note field stays the reader's. Every note is tagged `yomitanuki`.

Out of scope (parked): crop images, sentence-cloze, chapter tags, force-add on duplicates,
kanji hints next to kana words, template changes in AnkiMobile (advice is in the notes).

## Structure

```
app/lib/domain/models/lookup_result.dart          + matchedSenseIndexes (List<int>; empty = all)
app/lib/data/services/dictionary/sqlite_dictionary.dart   fills it from the POS check
app/test/fakes/fake_dictionary.dart                 sets it (empty) on every result
app/lib/domain/models/line_gloss.dart               + rubyHtml(), + rubyHtmlExcept(start, length)
app/lib/domain/use_cases/anki_note_builder.dart     the new field contents; tags
app/lib/domain/models/anki_settings.dart            + sentenceNoteType (String?, null = same as noteType)
app/lib/domain/ports/settings_repository.dart, shared_preferences adapter, fake   persist it (key `anki.sentenceNoteType`, removed when null/blank)
app/lib/ui/settings/view_model/settings_view_model.dart, settings_view.dart   one more field in the Anki section
app/lib/ui/reader/view_model/reader_view_model.dart addToAnki passes the gloss to build()
tests beside each
```

## Tasks (in order, red first)

### T1 Matched senses

- `LookupResult` gains `required List<int> matchedSenseIndexes`: indexes into `entry.senses` of
  the senses whose part of speech the deinflection accepts; **empty when the surface was an exact
  match** (every sense applies) and never empty otherwise (the entry was kept because at least
  one sense passed). `SqliteDictionary._result` computes it with the `Deinflection.acceptsPos`
  already used for the entry check, per sense. Fake and test constants updated (`const []`).
- Tests: 食べた → indexes of the `v1` senses only; an exact match → empty; an entry with a noun
  sense and a `vs` sense matched as Xした → only the `vs` sense index.

### T2 Ruby HTML from the gloss

- `LineGloss.rubyHtml({int? exceptStart, int? exceptLength})`: the whole line as HTML, every
  `RubySegment` with a ruby rendered as `<ruby>text<rt>ruby</rt></ruby>`, bare segments as
  escaped text; a span overlapping `[exceptStart, exceptStart+exceptLength)` is rendered **without
  ruby and wrapped in `<b>…</b>`**. Text is HTML-escaped before markup (reuse the builder's `html`
  helper or move it to `domain/text/html.dart` and import from both; say which). Pure; tested
  with the fake's spans: 魔王を倒した勇者 → `<ruby>魔王<rt>まおう</rt></ruby>を<ruby>倒<rt>たお</rt></ruby>した<ruby>勇者<rt>ゆうしゃ</rt></ruby>`;
  with the 魔王 span excepted → `<b>魔王</b>を…`; a line with `<` in it is escaped.

### T3 Word note

`AnkiNoteBuilder.build({lookup, contextLine, settings, contextTranslation, LineGloss? gloss})`:

| Field | Content |
|---|---|
| Word | `lookup.baseForm` (D6d.1: the spelling the reader saw, deinflected; never the headword) |
| Reading | `lookup.matchedReading` (unchanged) |
| Meaning | senses ordered: `matchedSenseIndexes` first (in order), then the rest; **at most 3**; numbered when more than one; same escaping (D6d.2) |
| Example | `gloss == null` ? `html(contextLine)` with the target wrapped in `<b>` (by `lookup.start/length`) : `gloss.rubyHtml(exceptStart: lookup.start, exceptLength: lookup.length)` (D6d.3) |
| Example (English) | `html(contextTranslation ?? '')` (unchanged) |
| Note | empty |
| tags | `['yomitanuki']` (D6d.5) |

The target bold without a gloss uses `contextLine` offsets, which are the same string the lookup
ran on; if `lookup.start + length` exceeds the line, fall back to the plain escaped line.
Tests: ちょっと-style kana word stays kana (an entry whose headword is kanji, matchedReading equals
the entry reading, surface kana); 食べた → Word 食べる; Meaning capped at 3 with the matched sense
first; Example bold without gloss; Example ruby-with-bold with gloss; tag present.

### T4 Sentence note

`buildSentence({gloss, settings, contextTranslation})`:

| Field | Content |
|---|---|
| Word | `html(gloss.line)` |
| Reading | `gloss.rubyHtml()` (D6d.4: furigana line, not the kana string) |
| Meaning | `html(contextTranslation ?? '')` then, if any matched span, `<br><details><summary>Words</summary>` + one `surface: gloss` line per matched span joined by `<br>` + `</details>` (translation is the answer, glosses the crib) |
| Example | empty |
| Example (English) | empty (the translation already is the Meaning; do not send it twice) |
| Note | empty (D6d.6: the Note field is the reader's) |
| note type | `settings.sentenceNoteType` when non-blank, else `settings.noteType` |
| tags | `['yomitanuki', 'sentence']` |

`sentenceTag` constant goes away. Tests for each row, including the fallback note type and the
no-translation case (Meaning = the details block alone, or empty when no matched span).

### T5 Settings: sentence note type

- `AnkiSettings.sentenceNoteType` (`String?`), in `copyWith`, equality, `toString`; `problems`
  does not complain about blank (blank means "same as noteType"); defaults null.
- Repository key `anki.sentenceNoteType`, removed when null or blank; fake updated.
- Settings screen, Anki section, after "Note type": field "Sentence note type", hint "Empty: same
  as the note type". View model `setSentenceNoteType`. Reset to defaults clears it.
- Tests as for deck/note type.

### T6 Wiring and docs

- `ReaderViewModel.addToAnki` passes `gloss: ocr.gloss` (null until the gloss lands; the note is
  still buildable).
- `lib/domain/README.md`: one line on `rubyHtml`. `.claude/wp6d/NOTES.md`: D6d.1–D6d.6 and the
  red-first section. `.claude/wp5/NOTES.md` D5.5 and `.claude/wp6b/NOTES.md` D6b.3 get a one-line
  pointer "shape changed by WP6d".

## Boundaries

No new dependencies, no code generation, nothing in `wp0/`. The URL adapter is unchanged (it
already sends `tags`). `make gate` stays green.

## Success criteria

All new tests red first then green; `flutter test` and `flutter analyze --fatal-infos` clean;
the before/after tables in the notes hold for the fake's 食べられなかった and 魔王 fixtures.
