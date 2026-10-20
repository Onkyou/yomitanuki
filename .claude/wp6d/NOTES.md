# WP6d — Anki card shape after the sentence layer: review findings and decisions

Resolved: see D6d.1 to D6d.6 under "Built decisions" below.

Marv, 2026-10-15, leaving for the day: "consider how the Anki cards could or should be
adjusted" now that a bubble yields the line, per-word readings and glosses, and a translation.
A design review (Claude, Opus, read-only over `anki_note_builder.dart`, `anki_settings.dart`,
`line_gloss.dart`, the Anki URL adapter, WP5/WP6b/WP6c notes, PLAN §1) produced the
findings below. Marv's card templates were not visible to the review; everything here works
whatever the templates show on the front.

## Findings

1. **The Word rule sends spellings the reader never saw.** `Word = headword` when the matched
   reading equals the entry reading, so すごい becomes 凄い and ちょっと becomes 一寸 (the app has
   no "usually kana" flag). Recommended: Word = `baseForm` always (食べた → 食べる, ビール → ビール,
   ちょっと → ちょっと). Cost: わかる and 分かる become separate notes.
2. **Meaning lists every sense, numbered.** For 出る-class entries that is a 15-line answer
   nobody recalls; the matched sense cannot be known. Recommended: at most 3 senses; when the
   word was inflected (`reasons` non-empty), drop senses whose part of speech cannot take that
   inflection first. The example line and its translation show which sense applies.
3. **The target word is not marked in Example.** Wrap `lookup.start/length` in `<b>`.
4. **Furigana belongs in Example as HTML `<ruby>`, not Anki's `漢字[かんじ]` syntax** (which shows
   raw brackets without the `furigana:` filter and would break the default note type). Ruby
   on every matched word except the target (i+1: the tested word's reading is not given away
   if Example is on the front). Needs the `LineGloss` passed to `build`.
5. **Sentence note shape has three problems:** Reading is the whole line in kana with no word
   boundaries (harder to read than the original); Example repeats Word; `Note = sentence` takes
   over Marv's own notes field. Recommended: a recognition card JP → EN. Front: the plain
   line. Back: the line with `<ruby>` furigana (from the `RubySegment`s), then the translation
   as the answer, then the word glosses small or inside `<details>` as a crib. No EN → JP card.
   Sentence-cloze parked (needs a cloze note type and a chosen target). Sentence notes should
   be used sparingly: a line with three unknowns becomes a leech.
6. **Tags:** none are sent. Send `yomitanuki` on every note and `sentence` on sentence notes,
   so every card an early version made can be found and bulk-fixed. Series is already the
   deck; chapters are unknown to the app.
7. **Duplicates:** AnkiMobile refuses an add when the first field matches an existing note of
   the same note type across all decks. Same-spelling different-reading words (方 かた/ほう)
   collide (park: a force-add with `dupes=1`); a separate sentence note type keeps sentences
   out of the word notes' duplicate check.
8. **Bubble crop on the card:** `addnote` carries no media; `<img>` can only point into
   AnkiMobile's media folder, which the app cannot write; a base64 `data:` URI is untested in
   AnkiMobile and bloats sync. Park; the realistic later route is "copy the crop to the
   clipboard before hand-over, paste it into an Image field in AnkiMobile".
9. **Smallest settings change:** one optional `sentenceNoteType` that falls back to `noteType`.
   No new field slots. Tags fixed in code.

## Ranked

**Must (before Marv's next study session)**

| Note | Field | Before | After |
|---|---|---|---|
| word | Word | 一寸 (for ちょっと) | ちょっと (`baseForm`) |
| word | Example | この魔法、ちょっと難しいね | この魔法、**ちょっと**難しいね (`<b>` around the target) |
| word | Tags | — | `yomitanuki` |
| sentence | Note | `sentence` | empty |
| sentence | Tags | — | `yomitanuki sentence` |

**Should**

| Note | Field | Before | After |
|---|---|---|---|
| word | Meaning | every sense, numbered | ≤ 3 senses, POS-filtered when inflected |
| word | Example | target in bold | plus `<ruby>` on every other matched word |
| sentence | Reading | このまほう、ちょっとむずかしいね | the line with `<ruby>` furigana |
| sentence | Example | the line again | empty (omitted from the URL) |
| sentence | note type | `noteType` | `sentenceNoteType`, falling back to `noteType` |

Template advice for Marv (not app work): furigana Reading only on the back of the sentence
card; glosses in a `<details>` block; tap-to-reveal furigana via CSS-hidden `rt` and a
JavaScript toggle (iOS `:hover` is unreliable); label the translation as machine translation.

**Park:** the crop image (clipboard route), sentence-cloze, chapter tags, force-add on
duplicate, "ちょっと (一寸)" kanji hint next to a kana Word.

## Decisions (as proposed; resolved, see D6d.1 to D6d.6 below)

Pending Marv at the time of writing. The must and should items reverse parts of D5.5 (Word = headword, all senses)
and D6b.3 (`Note = sentence`, Example = line); if accepted they are recorded here as D6d.x.
Claude's recommendation: take the must list and the should list as one package, since they
touch the same two files and the same tests, and leave the parked items parked.

## Built decisions (WP6d, builder)

Implemented as the spec's must and should rows; each reverses part of D5.5 or D6b.3.

- **D6d.1 `Word` is `lookup.baseForm`, always.** The reader tests the spelling they saw,
  deinflected (食べた -> 食べる, ちょっと stays ちょっと, ビール stays ビール); the headword rule filed
  すごい under 凄い. Cost: わかる and 分かる are separate notes. `LookupResult.matchedSenseIndexes`
  (empty = exact match, every sense applies) is computed at lookup time from the same POS check
  that kept the entry; the schema is unchanged.
- **D6d.2 `Meaning` lists at most 3 senses, matched ones first**, then the others in dictionary
  order; numbered when more than one; out-of-range indexes are ignored.
- **D6d.3 `Example` marks the target.** Without the line's gloss: the line escaped with
  `lookup.start/length` in `<b>` (plain line when the match does not lie inside it). With it:
  `LineGloss.rubyHtml(exceptStart:, exceptLength:)`, every other word in `<ruby>`, the target bold
  and bare so a front-side field does not give away its reading. `ReaderViewModel.addToAnki` passes
  `ocr.gloss`, null until it lands (the note is still buildable). The `escapeHtml` helper moved to
  `domain/text/html.dart` and is imported by the builder and `LineGloss`.
- **D6d.4 Sentence note = JP -> EN recognition card.** `Word` = the plain line, `Reading` = the
  line with `<ruby>` furigana (`rubyHtml()`, not the kana string), `Meaning` = the translation
  (the answer) then `<br><details><summary>Words</summary>` + one `surface: gloss` per matched span
  + `</details>` (the crib; the details block alone without a translation; the translation alone
  without a matched span), `Example` and `Example (English)` empty (the translation already is the
  Meaning), no field repeats the line.
- **D6d.5 Tags:** `yomitanuki` on every note, plus `sentence` on sentence notes. The old
  `AnkiNoteBuilder.sentenceTag` constant (the Note field value) is gone.
- **D6d.6 `Note` is empty on both kinds**: the field belongs to the reader. Sentence notes use
  `AnkiSettings.sentenceNoteType` when non-blank, else `noteType` (settings key
  `anki.sentenceNoteType`, removed when null or blank, field in the Anki section of the settings
  screen). A separate type also keeps sentences out of the word notes' duplicate check (finding 7).

### Before / after, the fixtures the tests pin

Word note, `taberareNakattaResult` (食べられなかった, line 食べられなかった, translation
"I could not eat it."):

| Field | Before | After |
|---|---|---|
| Word | 食べる | 食べる |
| Reading | たべる | たべる |
| Meaning | `1. to eat<br>2. to live on (e.g. a salary)` | same (2 senses) |
| Example | 食べられなかった | `<b>食べられなかった</b>` |
| ExampleEN | I could not eat it. | same |
| Note / tags | empty / none | empty / `yomitanuki` |

Sentence note, same line:

| Field | Before | After |
|---|---|---|
| Word | 食べられなかった | 食べられなかった |
| Reading | たべられなかった | `<ruby>食<rt>た</rt></ruby>べられなかった` |
| Meaning | 食べられなかった: to eat | `I could not eat it.<br><details><summary>Words</summary>食べられなかった: to eat</details>` |
| Example | 食べられなかった | empty |
| ExampleEN | I could not eat it. | empty |
| Note / tags | sentence / none | empty / `yomitanuki sentence` |

ビール (entry 麦酒), line ビールを飲む: Word ビール and Reading ビール as before, Example
`ビールを飲む` -> `<b>ビール</b>を飲む`.

魔王を倒した勇者, word note on 魔王 (gloss present): Word 魔王, Reading まおう, Meaning
`devil king; demon lord`, Example `<b>魔王</b>を<ruby>倒<rt>たお</rt></ruby>した<ruby>勇者<rt>ゆうしゃ</rt></ruby>`
(before: 魔王を倒した勇者). Sentence note: Word 魔王を倒した勇者, Reading all four words in `<ruby>`
where kanji, Meaning translation then the three-word crib, Example / ExampleEN / Note empty.

## Red-first evidence

- T1 (matched senses): the new sqlite tests failed to compile (`matchedSenseIndexes` undefined)
  before the field existed; green after `_result` filled it. Compile-red, not assertion-red.
- T2 (`rubyHtml`, `escapeHtml`): the new test files failed to compile (missing method and
  import); green after. Compile-red.
- T3 (word note): with only the `gloss:` parameter stubbed, 11 of the new or changed tests failed
  on their assertions (Meaning cap and order, bold Example, ruby Example, tags, the kana word);
  green after the implementation. Three older tests (field text is HTML, two-line context, first
  test) were changed on purpose because Example now carries `<b>`. Not seen red: "a target that
  does not fit the line leaves the line plain" (the old code already printed the plain line; it
  is a guard for the new code, not a driver).
- T5 (sentence note type): model, repository, view-model and view tests failed to compile before
  the field existed; green after. Compile-red.
- T4 (sentence note): five assertion failures (field map, translation answer, no-matched-span
  case, note type fallback, empty Note) before `buildSentence` changed; green after.
- T6 (wiring): "once the gloss is there the other words carry ruby" failed on its assertion
  (`本と<b>魔王</b>` instead of ruby) before `addToAnki` passed the gloss. Not seen red:
  "before the gloss lands only the target is marked" (the pre-change code already produced the
  gloss-less result by passing nothing; it pins the null path), and the three
  `reader_view_test.dart` expectations I updated for the new shapes failed after the builder
  change and were corrected, not written first.
- The whole-note map tests ("field maps (WP6d)") were written after the code as characterisation
  of the before/after tables; they were not seen red.
- Integration tests (`reader_flow_test.dart`, `real_pipeline_test.dart`) assert `Word` 食べる and
  魔王; both are still true under `Word = baseForm`, so they are unchanged. Not run by the builder.

## Review (one combined review, 2026-10-15) and what changed

Correctness, security and conformance in one pass (a medium package: domain and settings, no
UI flow change). Verdict approve; fixed before commit: the "Handed over" message named the
entry headword while the note's Word is now the base form (ビール announced as 麦酒), now
`result.baseForm` with a test; `rubyHtml` treated a zero-length target inside a span as an
overlap (bold, ruby stripped), now guarded like `_markTarget`, with an assertion; the
`matchedSenseIndexes` doc said "exact match → empty" but an exact 勉強する lists the `vs`
senses through the Xする path (desired), reworded. Noted, not changed: `''` and `null`
for `sentenceNoteType` both mean "same as noteType" but compare unequal; the builder trims at
use. Not verified on a device: whether AnkiMobile's `addnote` keeps `<details>`; one real card
will tell (handoff).
