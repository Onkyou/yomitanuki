# Spec: WP6e — the sheet as a sentence

Branch `wp6e-sheet-as-sentence` off `main` **after WP6d is merged** (D6e.2 uses
`LookupResult.matchedSenseIndexes` from WP6d T1). Decisions D6e.1–D6e.7 in
`.claude/wp6e/NOTES.md`. Read before coding: `AGENTS.md`, skills
`flutter-apply-architecture-best-practices`, `flutter-add-widget-test`, `test-driven-development`,
`frontend-ui-engineering`; `.claude/wp6b/NOTES.md`, `.claude/wp6c/NOTES.md` D6c.3–D6c.5;
`app/lib/ui/reader/view/ocr_sheet.dart`, `lookup_results_view.dart`, `reader_view.dart`,
`app/lib/domain/models/line_gloss.dart`, `app/lib/domain/use_cases/line_glosser.dart`, and the
screenshots in `app/build/screenshots/` (regenerate with the command at the top of
`integration_test/screenshots_test.dart` if missing).

## Objective

When the sheet opens, the reader sees the Japanese line as one ruby sentence, the translation
under it, then a compact list of the recognised words, with the actions under the thumb. The
dictionary card is a quick reminder first. Behaviour under the hood (taps, lookups, landing
rules, Anki) is unchanged.

Out of scope: everything under "Parked" in the notes; any change to the view model's data flow
beyond the two flags in T6.

## Structure

```
app/lib/domain/models/line_gloss.dart            GlossSpan: + glossShort, + extraSenses, + isFunctionWord
app/lib/domain/use_cases/line_glosser.dart       the gloss rule (D6e.2), function-word rule
app/lib/ui/reader/view/ocr_sheet.dart            layout: handle, thumbnail by aspect, line, translation, word list, bottom bar
app/lib/ui/reader/view/ruby_line.dart            NEW: the tappable ruby sentence (extracted from ocr_sheet.dart)
app/lib/ui/reader/view/word_list.dart            NEW: the rows under the line
app/lib/ui/reader/view/crop_zoom.dart            NEW: full-screen InteractiveViewer dialog
app/lib/ui/reader/view/lookup_results_view.dart  card density, kanji row, shorter-match rows
app/lib/ui/reader/view/reader_view.dart          wiring of the new callbacks, swipe-to-close
app/lib/ui/reader/view_model/reader_view_model.dart  hintSeen flag, translationNoteSeen flag
app/lib/ui/settings/view/settings_view.dart      labels, off-state subtitle
tests beside each; `test/ui/reader/view/ocr_sheet_test.dart` largely rewritten
```

## Tasks (in order, red first)

### T1 Gloss rule and function words (domain)

- `GlossSpan` gains `String? glossShort` (D6e.2 text), `int extraSenses` (senses not shown, 0 for
  plain spans) and `bool isFunctionWord` (true when every considered sense's `partsOfSpeech`
  is within {`prt`, `aux`, `aux-v`, `aux-adj`, `cop`, `cop-da`, `conj`}). `gloss` (the long form)
  stays for the Anki builder and the `glossLine`.
- `LineGlosser._span`: considered senses = `matchedSenseIndexes` non-empty ? those (in order) :
  `[0]`; `glossShort` = first gloss of each of the first two considered senses joined with
  `' · '`; if longer than 32 characters, drop whole glosses from the end until it fits (never cut
  inside a gloss; a single gloss longer than 32 stays whole); `extraSenses` = considered senses
  count − shown count.
- Tests with the fake dictionary: 魔王 (two senses) → `Satan · king of the demons…` style join and
  `extraSenses` per the fake's data; a `prt` entry → `isFunctionWord`; an exact match uses sense 1
  only; 食べた with `matchedSenseIndexes [1]` uses that sense first.

### T2 The ruby line (`ruby_line.dart`)

- Extract `_TappableLine` into `RubyLine(spans, highlight, onTapCharacter, selectedOrdinal…)`.
  One `Wrap` of word groups; inside a group a `Row` of per-code-point cells: width = glyph width
  (no `minWidth`, no horizontal padding), `minHeight: 52`, ruby over the segment in
  `labelMedium`; the span's underline (2 px, alternating colours) spans the whole word; a 4 px
  `SizedBox` between groups; `runSpacing: 8`. Keys `ocr.char.$start`, `ocr.ruby.$offset`,
  `ocr.span.$start` unchanged. The highlight range renders as one continuous pill across the
  word (one decoration on the group when the whole span is highlighted, else per cell as today).
- Tests: eight characters fit one row at 375 px; `tester.getSize` of a cell is ≤ its glyph width
  + 2; tapping each character calls back with its UTF-16 start; wrapping on a 30-character line
  produces no exception.

### T3 Sheet layout (`ocr_sheet.dart`, `word_list.dart`, `crop_zoom.dart`)

Order top to bottom inside the sheet:
1. Grab handle (4 × 32, `onSurfaceVariant` at 40 %, 8 pt margins), key `ocr.handle`.
2. Header block: for a vertical crop (h > w) a `Row` [thumbnail gutter | `Column`(line,
   translation)], thumbnail height = the column's height capped at 140 (use `IntrinsicHeight`),
   width by aspect, min 36; for a horizontal crop: thumbnail full width, height = width × h/w
   capped at 72, then line, then translation. Thumbnail key `ocr.crop` (kept), wrapped in an
   `InkWell` that opens `CropZoom` (full-screen dialog, `InteractiveViewer` around a
   `BgraImageView`, close on tap outside or an X; key `ocr.crop.zoom`).
3. Translation (D6e.3): `Row`[`Icon(Icons.translate, size: 16, color: onSurfaceVariant)`, 8 px,
   `Expanded(Text(translation, bodyMedium, onSurfaceVariant))`], key `ocr.translation`; while
   pending (`translationActive && translation == null`): a `Container` 16 pt high, 60 % wide,
   `surfaceContainerHighest`, radius 8, key `ocr.translation.pending` (no text). When
   `translationNote != null` (T6) a one-line `Text` in `bodySmall` muted, key
   `ocr.translation.note`, with a trailing "Settings" `TextButton` that pushes the `settings`
   route.
4. `WordList`: one `ListTile`-height (44) row per span with `matched && !isFunctionWord`:
   `Text.rich` with surface (`titleMedium`), 8 px, reading (`bodySmall` muted), 12 px,
   `Expanded(Text(glossShort, bodyMedium, maxLines 1, ellipsis))`, trailing `+N` (`labelSmall`
   muted) when `extraSenses > 0`. Key `ocr.word.$start`. `onTap` → `onTapCharacter(span.start)`.
   The row of the currently looked-up span (highlight range start) gets `primaryContainer`
   background.
5. The lookup results (`LookupResultsView`), unchanged position.
6. The tap hint `Text('Tap a character to look it up.')` only when `showHint` (T6).
7. Sticky bottom bar outside the `ListView`, inside `SafeArea(bottom: true)`: `Row`[
   `FilledButton.tonalIcon` "Add sentence" (key `anki.addSentence`, enabled as today),
   `Spacer`, `FilledButton.icon` "Add <headword>" (key `anki.addWord`) visible only when
   `lookupState is LookupResults && results.isNotEmpty`, calls `onAddToAnki(results.first)`].
   The close `IconButton` (key `ocr.close`) stays top-right of the header row with the handle.
- Swipe-to-close: a `GestureDetector` on the sheet's `Material` with `onVerticalDragEnd`: primary
  velocity > 700 or the drag's total dy > 80 → `onClose()`. Does not intercept the `ListView`'s
  own scroll (wrap only the handle+header area, not the list).
- Tests: order of keys top to bottom (`tester.getTopLeft` comparisons: handle < line < translation
  < first word row); vertical crop → `ocr.crop` height ≤ 140 and sits left of the line; horizontal
  crop → full width, height ≤ 72; tapping `ocr.crop` opens `ocr.crop.zoom`; the pending skeleton
  has no text; a `prt` span has no `ocr.word.*` row; tapping a word row calls `onTapCharacter`
  with the span start; the bottom bar is inside the sheet's bounds at 600 px height and
  `anki.addWord` appears only with results; a fling down on the handle calls `onClose`; the
  existing Anki tests move to `anki.addWord` where they used `anki.add.0` on the first card.

### T4 Card density (`lookup_results_view.dart`)

- First result card: headword + reading (as today, with the matched-reading line), then at most
  3 senses with `matchedSenseIndexes` first, each `bodyMedium` with the POS tags as one small
  muted tag (`labelSmall`, `surfaceContainerHighest` chip) trailing, "+N more senses" row when
  cut (tap expands to all; key `lookup.moreSenses`); no "Add to Anki" button on the first card
  (the bottom bar has it); kanji cards behind a `ListTile` "Kanji ›" (key `lookup.kanji.toggle`)
  that expands them.
- Second and later results: one-line rows `headword 【reading】 first gloss` (key
  `lookup.row.$index`) that expand to the full card on tap; their "Add to Anki" stays in the
  expanded card (key `anki.add.$index` unchanged).
- When results land, scroll the first card's top into view (`Scrollable.ensureVisible` in a
  post-frame callback), key unchanged.
- Tests: three senses shown of five with "+2 more senses"; matched sense first; kanji hidden
  until toggled; second result collapsed then expanded; first card has no `anki.add.0`.

### T5 Settings polish

- Labels: "Example (Japanese)" and "Example (English)" for the two example slots (the map
  `_fieldLabels`); the translate switch subtitle when off: "Shows an English translation of each
  bubble, translated on this phone." followed by the status text when relevant.
- Tests updated.

### T6 Two session flags in the view model

- `bool get showTapHint`: true until the first `onTapCharacter` of the view model's lifetime.
- `String? get translationNote`: set once per view model lifetime when a read had the switch on
  and the cached status was `downloadNeeded` ("Japanese or English is not downloaded yet.") or
  `unsupported` ("This phone cannot translate Japanese."), or when a translation failed
  (`TranslationFailedError`: "Translation failed for this bubble."); cleared when the reader
  acknowledges it via `dismissTranslationNote()` (the sheet calls it when the note's Settings
  button is tapped or the sheet closes). Never a notice/banner.
- Tests: hint disappears after a lookup; note set once for `downloadNeeded`, not again on the
  next bubble; failed translation sets the failure note; dismissed note stays away.

## Boundaries

No new dependencies. View model data flow (landing rules, D4.16/D6c.3) unchanged except the two
flags. Keys listed above are the contract the integration and widget tests rely on; keep every
existing key that is not explicitly renamed here. `make gate` green. Regenerate the
screenshots at the end (`flutter drive … --dart-define=SCREENSHOTS=true`) if a simulator is
booted, and name the files in the report; if none is booted, say so.

## Success criteria

All new tests red first then green; `flutter test` and `flutter analyze --fatal-infos` clean;
at 375 × 812 (`tester.view.physicalSize`) the fake line 魔王を倒した勇者 renders on one row with
the translation and four or fewer word rows visible without scrolling.
