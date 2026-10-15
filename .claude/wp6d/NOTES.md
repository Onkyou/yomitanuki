# WP6d — Anki card shape after the sentence layer: review findings, decisions pending

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

## Decisions

Pending Marv. The must and should items reverse parts of D5.5 (Word = headword, all senses)
and D6b.3 (`Note = sentence`, Example = line); if accepted they are recorded here as D6d.x.
Claude's recommendation: take the must list and the should list as one package, since they
touch the same two files and the same tests, and leave the parked items parked.
