# WP6b — the sentence layer in the sheet: decisions (spec in `SPEC.md`, built 2026-10-14)

Marv, 2026-10-14, during the first iPhone run, after WP6a was specced. Three requests; the
assessment below is Claude's, the decisions D6b.1–D6b.5 are settled. Specified in `SPEC.md`
after WP6a landed; the package was built on 2026-10-14.

## Requests

1. Furigana and an English rendering of the whole bubble in the sheet, so a quick reminder
   needs no tap.
2. Add the whole sentence to Anki, not only a word.
3. Make visible what is tappable for a lookup: underline the words, alternating colours for
   neighbours, if the tap-to-look-up concept stays.

## Assessment

- **Translation.** D7 and D10 lock "no server, no network while reading", and nothing on the
  phone translates sentences: JMdict is a word dictionary. Two honest options. (a) A
  **gloss line**: segment the OCR line left to right with the existing `Dictionary.lookupAt`
  (longest match, deinflection), show each matched word's reading above it and its first
  gloss below it. Not a translation, but for a reader who knows the grammar it is the
  reminder asked for, costs ~0.4 ms per word, and the segments are exactly what request 3
  needs to underline. (b) An **on-device MT model** (Marian/NLLB-class, 100–300 MB ONNX,
  seconds per sentence on the phone, trained on nothing like manga speech). A new work
  package of WP2's size with a doubtful payoff; not recommended for v1. Recommendation: (a),
  and revisit (b) only if the gloss line is not enough in practice.
- **Furigana.** Per-word readings from the matched entry are available now; true per-kanji
  furigana (which kana belong to which kanji) needs an alignment step (JMdict has no furigana
  data; the usual source is JmdictFurigana, CC-BY-SA, ~10 MB). Start with a reading over the
  whole word; the handoff's known gap applies (the reading shown is the entry's, not the
  matched form's: ビール shows 麦酒's). Fix that gap in the same package.
- **Sentence to Anki.** The exporter and note builder exist (WP5). A sentence note fits the
  current note type without new fields: Word = the line, Reading = the reading line,
  Meaning = the gloss line, Example = the line. Whether that is a second note type or the same
  one with a sentence in the Word field is Marv's call; the settings screen already lets the
  note type vary.
- **Underlines.** Segmentation from (a) gives the spans. Underline matched spans, two
  alternating colours, particles and unmatched runs plain. Tap behaviour unchanged (C15: the
  lookup still starts at the tapped character, so a wrong segmentation costs nothing).
  Segmentation runs once per OCR result, off the UI path, and lands only if the state is still
  current (D4.16).

## Decisions

- **D6b.1 (Marv, 2026-10-14) No translation on the device.** The sheet gets a gloss line built
  from `Dictionary.lookupAt`, not a translation. Option (b) above is closed for v1.
- **D6b.2 (Marv) Furigana as per-word readings** from the matched entry, fixing the
  matched-form reading gap in the same package. Per-kanji alignment (JmdictFurigana) is not
  in scope.
- **D6b.3 (Marv) "Add sentence to Anki" is a button in the sheet, visible before any word is
  tapped.** *(Note shape changed by WP6d, see `.claude/wp6d/NOTES.md` D6d.4-D6d.6.)* Note shape (Claude's default, reversible): same deck and note type as word notes;
  Word = the OCR line, Reading = the reading line, Meaning = the gloss line, Example = the
  line, Example (English) empty, Note = "sentence". A second note type is not introduced
  unless the first real cards show it is needed.
- **D6b.4 (Marv) Underline the tappable spans**, alternating two colours for neighbours;
  particles and unmatched runs plain; tap behaviour unchanged.
- **D6b.5 (Claude) The gloss line sits above the per-word tap, it does not replace it.** Marv
  asked for the sentence action "before a user clicks a detailed element"; the per-word card
  stays the detailed element.

The spec is `.claude/wp6b/SPEC.md`; WP6a was merged first because both change `ocr_sheet.dart`
and the view model, and the package was built on top of it on 2026-10-14.

## Known imperfections

- A reading that does not fit an inflected surface (the pattern built from the base form does
  not match, or the surface shares no whole kanji run with it) falls back to the base form's
  whole reading as ruby over the whole surface. 来る is special-cased (く/き/こ); other
  irregular stem changes are not.
- A word column is as wide as its gloss (up to 160 px), so a short word can sit over a wide
  gloss and a line wraps earlier than the text alone would.
- `FittedBox(scaleDown)` keeps a word wider than the sheet on one row, and can shrink a very
  long word's tap targets below the 32x44 minimum.
- Not done, left for Marv after seeing it on the phone: centring or capping the column width,
  a floor for the scale-down.

## Red-first evidence

Compile-red = the test file did not compile because the API it names did not exist yet;
assertion-red = a stub of the new shape was in place and the named assertion failed.

T1 (`dict_builder_test.dart`, `sqlite_dictionary_test.dart`)
- 'the schema is version 2 ...': assertion-red `Expected: <2> / Actual: <1>`.
- 'a kana form carries its own text as written, under both keys' and 'a kanji form carries the
  primary kana that applies to it': assertion-red, `SqliteException(1): no such column: reading`.
- 'matched reading (D6b.2) a kana headword form reads as itself ...': compile-red
  (`matchedReading`), then assertion-red against an adapter stub passing `entry.reading`:
  `Expected: 'ビール' / Actual: 'ばくしゅ'`.
- 'a kanji form reads as the kana that applies to it' and 'an inflected surface carries the base
  form's reading': not seen red. The entry reading the stub returned happens to equal the expected
  value for 麦酒, 人 (ひと, と) and 食べる; the builder tests above are what pin those rows.

T2 (`furigana_test.dart`): 14 of 14 assertion-red against a stub returning `[]`. Two were
corrected while going green: 食べた (the prefix cut a kana run of the form whole instead of
stopping at the shared prefix) was an implementation bug, fixed; the line `furigana('来られ',
'来る', 'くる').length == 1` was a wrong expectation in the test (来 is a shared prefix, so it
does align) and was deleted. 'an astral-plane kanji' was added after the implementation and not
seen red.

T3 (`line_glosser_test.dart`): 11 of 12 assertion-red against a stub returning no spans; 'an
empty line has no spans' passes against the stub by design. The 'reading line' test went red
for a real reason once the glosser worked: `たべる` where `たべた` was wanted, which moved
`readingLine` from the matched reading to the assembled ruby (see deviations in the report).

T4 (`anki_note_builder_test.dart`, `reader_view_model_test.dart`)
- `buildSentence` group (4): red against a stub that threw `UnimplementedError`.
- 'gloss after OCR': with `OcrText.gloss` present but never set, 'the gloss lands on the sheet
  that asked for it', 'the text shows first and the gloss follows', 'a gloss for a dismissed
  sheet is dropped', 'a gloss for an earlier read does not land on a newer one' and 'tapping a
  character after the gloss keeps the gloss' were red (the first four on `Bad state`/length
  from `pending`, the last on `Expected: not null / Actual: null`). 'a glosser error leaves the
  line readable' and 'a blank read is not glossed' pass against the stub by design.
- 'add sentence to Anki': with `addSentenceToAnki` an empty stub, the note, settings-problem,
  not-installed and exporter-error tests were red; 'does nothing without text' passes by design.
- Mutation check on the D4.16 guard: replacing `!identical(_ocrState, read)` with
  `_ocrState is! OcrText` fails only 'a gloss for an earlier read does not land on a newer one'
  (restored).

T5 (`ocr_sheet_test.dart`, `reader_view_test.dart`)
- 'the sentence layer': 7 of the 8 tests then in the group were red against an `OcrSheet` that
  only had the new `onAddSentence` parameter (no button, no span widgets, no keys);
  'tapping a character inside a matched word reports that character' passes by design because
  the cells did not change.
- 'a word wider than the sheet scales down': red, `RenderFlex overflowed by 512 pixels`, then
  green with the `FittedBox`.
- 'the card shows the reading of the form that matched': the first test red
  (`Found 0 widgets with text "ビール"`), the second passes by design (the unchanged card).
- `reader_view_test.dart` 'the sheet glosses the line and Add sentence hands it to Anki' and
  'Add sentence is off while the gloss is not there': written after the widgets, not observed red;
  the sheet-level tests above are the red-first ones.
- Existing tests that the gloss changed and that were updated, not weakened: the `lookups`
  assertions (the glosser's walk adds lookups before the tap), the manual-completer lookup test
  (set `manual` after the sheet opens), the '食べる/た/to eat' finders (the reading and the gloss
  now repeat them), and two tests whose fake returned a fixed `start`/`surface` for every index.

### Review round (two reviews, 2026-10-14)

- Word notes use the matched form (`AnkiNoteBuilder.build`): 'a kana spelling of an entry is the
  word, read as itself (ビール)' assertion-red, `Expected: 'ビール' / Actual: '麦酒'`. 'an inflected
  surface still files under the entry headword' passes by design.
- 来る reading (`furigana_test.dart`): '来た and 来て, 来ます, 来ちゃう read き', '来ない, 来られ, 来い,
  来させ, 来ず read こ' and the compound 持って来た were red (`来:く` instead of `来:き`/`来:こ`);
  '来る keeps く', 'any other tail keeps く' and 'a different kanji before る' pass by design.
- ヵ/ヶ in a kanji run: 'ヶ inside a number-like run belongs to the run: 一ヶ月ぶり' red against a
  `_isKanji` without them (whole-surface ruby `一ヶ月ぶり:いっかげつぶり`), checked by temporarily
  removing them.
- `readingLine` keeps kana as written: 'a katakana word stays katakana in the reading line' red,
  `Expected: 'ビールを' / Actual: 'びーるを'`.
- Glosser rejects a result that is not the text at the offset: 'a result that does not sit at the
  offset it was asked for is no match' red, `Actual: ['*王@0+1', '*王@1+1']`.
- `hasMatches`: 'does nothing when the dictionary recognised nothing in the line' (view model)
  red, `Expected: empty / Actual: [Instance of 'AnkiNote']`; 'the button is off for a line with no
  recognised word' red, `Expected: null / Actual: <Closure: () => void>`.
- Text paints before the walk: 'the walk starts only after a turn of the event loop' red,
  `Expected: empty / Actual: [(食べられなかった, 0)]`; 'the capture does not wait for the gloss'
  red, `Expected: an object with length of <1> / Actual: []`.
- Not red by construction: `ORDER BY rowid` on the forms query (the result for the mini fixture
  is the same, it only makes the order explicit); the 375 px wrap test ('several matched words
  wrap to a second row', a pin that passed on first run); the `anki_note_builder_test`
  fixture-length fix; moving `kana_test.dart` to `test/domain/text/`; the two `case` patterns.
