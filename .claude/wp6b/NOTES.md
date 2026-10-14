# WP6b — the sentence layer in the sheet: draft, not yet specified

Marv, 2026-10-14, during the first iPhone run, after WP6a was specced. Three requests; the
assessment below is Claude's, the decisions are still open. Specified after WP6a lands.

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
  tapped.** Note shape (Claude's default, reversible): same deck and note type as word notes;
  Word = the OCR line, Reading = the reading line, Meaning = the gloss line, Example = the
  line, Example (English) empty, Note = "sentence". A second note type is not introduced
  unless the first real cards show it is needed.
- **D6b.4 (Marv) Underline the tappable spans**, alternating two colours for neighbours;
  particles and unmatched runs plain; tap behaviour unchanged.
- **D6b.5 (Claude) The gloss line sits above the per-word tap, it does not replace it.** Marv
  asked for the sentence action "before a user clicks a detailed element"; the per-word card
  stays the detailed element.

Spec to follow once WP6a is merged, since both change `ocr_sheet.dart` and the view model.
