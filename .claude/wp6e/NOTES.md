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

## Built (builder, 2026-10-15): interpretations and deviations

- **`extraSenses` for an exact match counts the rest of the entry.** The spec's formula (considered
  senses minus shown) is 0 for every exact match, because an exact match considers sense 1 only,
  so "+N" would never show for a plain 魔王. D6e.1/D6e.2 want "+N says there are more", so for an
  exact match (`matchedSenseIndexes` empty, every sense applies) `extraSenses` = entry senses − shown;
  for a deinflected match it is matched senses − shown (senses the inflection cannot be do not count).
- A sense with no part-of-speech tags is not a function word; neither is a span with no senses.
- **`T6` was built before `T3`**: the sheet's new parameters (`showHint`, `translationNote`,
  `onDismissTranslationNote`) come from the view model.
- **The swipe-to-close strip is the handle row only**, not the header: the header scrolls with the
  list (a 30-character line must not squeeze the word list), and a drag detector over list content
  would fight the list's own scroll.
- **The vertical-crop gutter is 36..80 px wide**, from the crop's aspect at 100 px tall (spec: min 36,
  no max). The text height it would depend on is known only after layout, and the text's width depends
  on the gutter, so the width is fixed at build time; the picture is letterboxed inside. Its height is
  the text's, capped at 140 (a `Stack` with the text as sizing child and the gutter `Positioned` over
  its left edge; the first version used `IntrinsicHeight`, which took the crop's own pixel height and
  pinned every real crop to 140 pt).
- **`ocr.translation` is on the `Text`**, not the `Row`, because every test and flow reads `.data` from
  that key. The pending skeleton sits in a 20 px slot (the bar itself is 16) so a landing translation
  does not move the rows under it.
- **The bottom bar uses `Expanded`+`Align`**, not `Spacer`: a `Flexible` next to a `Spacer` is held to
  half the free width and the "Add <word>" button overflowed.
- A word row hides the reading when it equals the surface (ビール ビール).
- "Add <word>" names `baseForm`, the note's Word (D6d.1) and what the hand-over message names.
- The zoom dialog is a `Dialog` with 12 px insets (barrier tap closes, X closes), not an edge-to-edge
  route: a barrier is what "tap outside" needs.
- Card senses are numbered by display position (matched first), not by dictionary position.
- Cards and rows after the first carry the index in `lookup.moreSenses.$i` / `lookup.kanji.toggle.$i`;
  the first card has the bare keys. `lookup.card.$i` is new (the `Card`).
- The "tap hint" moved out of `LookupResultsView` into the sheet (`showHint`); `LookupIdle` renders nothing.
- A word-too-wide-for-the-line still scales down (`FittedBox`) as a safety net in `RubyLine`.
- `translationNote` also covers a `TranslationUnavailableError` (packs gone since the status was
  cached) by the same two status sentences; `requiresNewerOs` raises no note.
- Integration tests: `anki.add.0` became `anki.addWord`; the lookup wait is the bottom-bar button, because
  the reading text alone also matches the ruby over the line before the lookup lands.

## Red-first evidence

Compile-red = the test did not compile because the API it names did not exist; assertion-red = it
compiled and failed on the assertion against the old code or a temporary mutation.

- T1 `line_glosser_test.dart` (new groups 'the short gloss', 'function words'): compile-red
  (`glossShort`, `extraSenses`, `isFunctionWord` undefined). Not seen assertion-red afterwards.
- T2 `ruby_line_test.dart`: compile-red (`ruby_line.dart` missing). 'a word wider than the line scales
  down' is red by construction without the `FittedBox` (overflow exception), not run that way.
- T6 `reader_view_model_test.dart` 'session flags': compile-red (`showTapHint`, `translationNote`,
  `dismissTranslationNote`). 'a second cause does not replace the first note' passes by design (it pins
  the once-per-lifetime flag).
- T3 `ocr_sheet_test.dart`, `word_list_test.dart`: compile-red (new `OcrSheet` parameters, `WordList`).
  Mutation checks afterwards, each restored: `_closeDistance = 8000` fails 'a slow drag of more than
  80 px closes it too'; `_closeVelocity = 70000` initially failed nothing (the 200 px fling also
  passed the distance rule), so the fling test became a 50 px flick and now fails; removing the
  function-word filter fails 'a function word keeps its underline but has no row'; `maxGutterHeight =
  1400` fails 'a tall block of text lets the gutter grow to 140'; `if (true)` for the hint fails 'the
  hint shows only while it is wanted'; showing the reading unconditionally fails 'a kana word does not
  repeat itself'.
  Not mutation-checked: the 36 px gutter minimum, the 72 px banner cap, the skeleton's 60 % width
  (asserted, written with the widget), the note's Settings button.
- T4 `lookup_results_view_test.dart`: 14 of 19 assertion-red against the old card (the other five pin
  behaviour the old card also had or rely on new keys). Removing the post-frame reveal fails 'the
  first card's top is scrolled into view'. 'a card already in view does not move the list' passes
  with and without the reveal being `keepVisibleAtEnd` and was not mutation-checked.
- T5 `settings_view_test.dart`: four assertion-red (labels, off subtitle, swap on toggle, unknown
  status); 'switched on, the subtitle is the status alone' passes by design.
- Existing tests changed on purpose: `reader_view_test.dart` (card has no `anki.add.0`, the bottom bar's
  `anki.addWord` is the button; the kanji row is folded until toggled; `ocr.gloss.0` is `ocr.word.0`),
  `ocr_sheet_test.dart` (96 px crop box, "Translating…" text, `ocr.gloss.*`, 160 px gloss, the 375 px
  wrap line which is now 18 characters because eight to twelve fit one row).
- Integration tests were edited and not run, except `screenshots_test.dart` (see the report).

### Review round 1 (two reviews, 2026-10-15)

- The translation note renders under the header (outside the gutter `Stack`), full width, two lines.
  It persists across bubbles until the reader dismisses it with the X, a swipe, or its Settings
  button (the sheet's `_close` and the button call `dismissTranslationNote`); closing the reader any
  other way (back to the camera) leaves it set for the next sheet. It is raised once per view model
  lifetime, so after a dismissal it never returns.
- `conj` left the function-word set; `ocr.close` is 44 x 44 (`tapTargetSize.shrinkWrap`), the handle
  row 44 high; `lookup.moreSenses` and `lookup.kanji.toggle` rows are at least 44 high; the crop has
  `Semantics(button, 'Bubble photo, enlarge')`; ruby columns align `start`; `_maxWordColumnWidth`
  names the 220.
- Red-first: 'a short block of text keeps the gutter as tall as the text' was assertion-red on the
  `IntrinsicHeight` code (thumbnail 140 against a text column of about 100) and green after the
  `Stack`. Also assertion-red before their fixes: the note-width test, 'the note is a muted line of
  at most two' (maxLines 1), 'the close button is a 44 pt target' (40), the semantics test, the 44 pt
  rows test, 'a reading wider than its kanji does not centre the cells', and 'a conjunction is not'.
  Compile-red: none of these.
- Mutation checks, each restored: gloss limit 32 to 3200 fails 'a join over 32 characters drops whole
  glosses from the end' and 'a single gloss longer than 32 characters stays whole'; `applicable =
  considered.length` fails 'an exact match shows sense 1 only'; deleting `onDismissTranslationNote()` in
  the note's Settings button fails 'the note's Settings button opens Settings and dismisses it';
  `keepVisibleAtEnd` to `explicit` fails 'a card already in view does not move the list' (and 'the
  first card's top is scrolled into view'). The 'already in view' fixture now asserts it starts at
  700 px, so the card really lands in view.
