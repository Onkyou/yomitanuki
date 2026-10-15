# WP6e — the sheet as a sentence: UI/UX review findings and decisions

Marv, 2026-10-15, leaving for the day: "run critical UI/UX review agents to check if we could
make the design better for the translation and views". A design review (Claude, Opus, over the
simulator screenshots in `app/build/screenshots/` from `integration_test/screenshots_test.dart`
and the sheet, card, reader and settings widgets) produced the findings below. Decisions are
Claude's, taken so the prototype Marv tests next is the improved one; each is reversible.

## What the screenshots showed

About 100 pt of the 60 % sheet went to the top row and the thumbnail before any Japanese; an
8-character line took two rows laid out like a table (one column per word, as wide as its
gloss); 魔王 rendered as 魔 王 (32 px minimum cell width); the translation looked exactly like
the source text and sat above it; the thumbnail of a vertical bubble was a 96 px sliver; the
card's "Add to Anki" was below the fold; 魔王's gloss was "Satan, the Devil, the Prince of
Darkness" (JMdict's first sense) and the verb's gloss was truncated mid-word.

## Decisions

- **D6e.1 The line is one ruby sentence; glosses move to a word list under it.** Cells are as
  wide as their glyph (no minimum width, no inner padding), taller instead (≥ 52 pt), a 4 px gap
  between words so the alternating underlines stay apart; the line wraps as text does. Every
  character stays a tap target (C15 unchanged). Under the line and the translation, one 44 pt row
  per recognised word: surface, reading, gloss on one line with an end ellipsis and "+N" when
  more senses exist; tapping a row is tapping the word's first character. Particles and
  auxiliaries (JMdict `prt`, `aux`, `aux-v`, `aux-adj`, `cop`) keep their underline but get no row.
  Replaces the WP6b column layout and removes its "column width follows the gloss" and
  "FittedBox scale-down" imperfections.
- **D6e.2 Gloss rule.** Senses considered: the matched senses (WP6d `matchedSenseIndexes`) when
  there are any, else sense 1. Text: the first gloss of each of up to two senses joined with
  " · ", cut at a gloss boundary to about 32 characters, "+N" for the senses not shown. No rule
  finds "demon lord" for 魔王 (JMdict orders Satan first); the translation line resolves the
  sense and "+N" says there are more.
- **D6e.3 Japanese first, then the translation, then the words.** The reader checks the line
  against the book in the other hand; English must not pre-empt that. The translation is
  `bodyMedium` in `onSurfaceVariant` with a leading 16 px translate icon as the "machine
  translation" mark; no italics, no text label. While pending, a one-line muted skeleton bar of
  the same height, not "Translating…", so a late landing does not shift the tappable line under
  the finger (the sheet is bottom-anchored).
- **D6e.4 Thumbnail sized by aspect, tap to zoom.** Vertical crops (h > w): a left gutter beside
  the line-and-translation block, height = that block's height capped at 140 pt, width by aspect
  (min 36 pt). Horizontal crops: full width, height by aspect, max 72 pt. Tap opens it full
  screen in an `InteractiveViewer`. Kept rather than dropped: the sheet covers the bubble (the
  review's "sampling pauses" premise is outdated since D6a.1, the conclusion stands).
- **D6e.5 Actions at the thumb; swipe to close.** A grab handle and swipe-down-to-close; a
  sticky bottom bar inside the `SafeArea` under the list: "Add sentence" left, a primary
  "Add <word>" right once a lookup result is showing (the longest result). The per-card button
  goes from the first result card; later cards keep theirs. The X stays top-right.
- **D6e.6 The card is a reminder first.** Headword and reading, then at most 3 senses, matched
  first, `bodyMedium`, POS as a small muted trailing tag; the kanji cards behind a "Kanji ›"
  row; shorter matches (魔 under 魔王) as one-line rows that expand on tap; the card's top is
  scrolled into view when it opens.
- **D6e.7 Small fixes taken.** The "Tap a character to look it up." hint shows only until the
  first lookup of the app session; ruby in `labelMedium` (12–13 pt) for sunlight; when the switch
  is on but the pack is missing or translation failed, the sheet shows one quiet one-line note
  per app session pointing to Settings; Settings labels "Example (Japanese)" / "Example
  (English)"; the translate switch's subtitle says what turning it on does when it is off.

## Parked (recorded, not done)

Transparent app bar or a floating photo button on the reader (56 pt of preview); a pulse on
the box outline instead of the 2 px scanning line; collapsing "Field names" in Settings; helper
text under the field-name inputs; an undo snackbar for "Reset to defaults".

## Kept on purpose (the review's list)

Per-character tap targets and lookups from the tapped character (C15); alternating underline
colours; longest-match highlight; the in-tree sheet bound to `ocrState` (D4.7); translation
that never blocks text or gloss, on by default with one switch (D6c.5); "Add sentence" gated on
the gloss; auto-save in Settings; the "No bubbles found" hint; the selected-box highlight and
the box style; the 60 % cap.
