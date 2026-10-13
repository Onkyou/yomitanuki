# WP3 notes: dictionary (JMdict + KANJIDIC2 in SQLite, deinflecting lookup)

Binding decisions D3.1–D3.9, measured numbers, the EDRDG attribution text and what will bite
WP4. Branch `wp3-dictionary`. Code: `app/lib/data/services/dictionary/`, build script
`tool/dict/`, fixtures `app/test/fixtures/dict/`, fake `app/test/fakes/fake_dictionary.dart`.

## Decisions

### D3.1 One builder, tested through the committed mini fixture

`DictBuilder.build(jmdict:, kanjidic:, outPath:, meta:)` lives in the app
(`dict_builder.dart`) and takes decoded jmdict-simplified JSON. `tool/dict/build_dict.dart`
wraps it with download, sha256 verification and unzip for the real asset; the tests call it
on `app/test/fixtures/dict/mini_jmdict.json` + `mini_kanjidic.json` (45 entries, 30 kanji,
extracted from the pinned release in the real schema, ~330 KB committed; 48 entries after the
review additions いらっしゃる, a 25-unit proverb and 人【と】). The same code path writes the
56 MB asset and the test database, so the tests never need the asset or the network. The
builder writes `<out>.part` and renames at the end, and the Makefile has `.DELETE_ON_ERROR:`,
so an interrupted `make dict` never leaves a file `make` would consider built.

### D3.2 Pinned sources, checksums in the script, downloads are data

Upstream is `scriptin/jmdict-simplified` (the plan's "scrutinizer" is a typo), release
`3.6.2+20261012204142` (JMdict 2026-10-12, KANJIDIC2 database 2026-285):

| file | sha256 |
|---|---|
| `jmdict-eng-3.6.2+20261012204142.json.zip` (11.5 MB, 118 MB unpacked) | `9a04fc1d0facf87645f8ec7cdaa370647d4a8f59131f6e2a614bcd680f855b85` |
| `kanjidic2-en-3.6.2+20261012204142.json.zip` (1.3 MB, 14.8 MB unpacked) | `55e83fe744ca681075ef97772f9cafeab761fabbe3d8d7f1015638136e0ac837` |

The script refuses a mismatch and tells you to delete the file or change the pin on purpose.
Downloads live in the gitignored `tool/dict/downloads/`; nothing executes them, only the
JSON decoder reads them. `make dict` rebuilds when the asset is absent or when the script,
its pubspec, `dict_builder.dart` or `kana.dart` changed; it is not part of `make gate`.

### D3.3 Schema (version 1, recorded in `meta.schema_version`)

- `entries(id INTEGER PK, headword, reading, is_common)`: `id` is the JMdict `ent_seq`.
  Headword = first kanji form that is not a secondary spelling (`sK rK oK iK` and their
  lowercase kana twins) ?? the kana reading ?? the first kanji (last resort, no kana at all);
  so いらっしゃる (only kanji 居らっしゃる, sK) shows as kana (154 entries in the full build,
  33 common). An entry whose first sense is tagged `uk` (usually kana) leads with the
  reading (コーヒー, not 珈琲). Reading = first non-secondary kana form that applies to the
  headword, else the first applicable kana form. `is_common` = any form marked common.
- `senses(entry_id, seq, glosses, pos)` WITHOUT ROWID: glosses joined by
  `DictBuilder.listSeparator` (U+001F, ASCII unit separator), POS tags by a space. Split back
  in `SqliteDictionary._loadEntry`.
- `forms(form, entry_id, kind)` + `INDEX forms_form(form)`: every kanji and kana form
  including search-only ones, stored with katakana normalised to hiragana (`toHiragana`,
  ァ..ヴ only: ヵ ヶ ヷ..ヺ and ー stay, so 一ヶ月 is one key; half-width ｱ..ﾝ with ﾞ/ﾟ is
  folded first) plus the raw spelling when it differs. `kind` is `kanji`/`kana`. 611,405 rows
  for 499,430 upstream forms.
- `kanji(literal PK, meanings, on_readings, kun_readings, strokes, grade, jlpt)` WITHOUT
  ROWID, lists joined by U+001F, English meanings only, first stroke count.
- `meta(key, value)`: `schema_version`, `jmdict_version`, `jmdict_date`, `kanjidic_version`,
  `kanjidic_date`, `licence`, and from the script `jmdict_release`, `jmdict_sha256`,
  `kanjidic_release`, `kanjidic_sha256`. `SqliteDictionary.meta` exposes it for the about
  screen.

The plan offered `; ` or a child table for glosses. 867 JMdict glosses contain `; ` inside
(e.g. "to scoop up (and remove; sand, earth, etc.)"), so the joiner is U+001F instead of a
child table: one column, no extra rows, and a split that cannot mis-fire. The builder throws
`FormatException` if any gloss, meaning or reading ever contains U+001F, so a future upstream
release cannot silently corrupt a column.

### D3.4 Deinflector: own rule table with from/to shapes, reasons in derivation order

`deinflector.dart`, no Yomitan rules. Each `_Rule(suffix, replacement, reasons, from:, to:)`
names the shape the string must have before the rule (`from`) and after it (`to`). Shapes
are the `WordClass` enum: dictionary classes `v1 v5k v5ks v5g v5s v5t v5n v5b v5m v5r v5u
adjI vk vs` (each mapped to its JMdict POS tags, e.g. `v5r` ← `v5r v5r-i`, `vs` ← `vs-i
vs-s vs`) and three intermediate shapes `te`, `stem` (連用形) and `terminal` (a finite form
that can only be the outermost layer: past, polite, imperative, volitional, ば, たら, そう,
さ, く). The bare surface starts as every shape except `stem`, which is why たべ alone never
becomes 食べる: a stem is only reached through ます/ません/ました/ませんでした/ましょう/
たい/そう/すぎる/なさい/ながら, and the stem→dictionary rules carry no reason.

Godan rows are generated from a nine-row table (dictionary ending, a/i/e/o-row kana, 音便
stem, voicing), so 書いて/泳いで/話して/待って/死んで/読んで/買って come from one rule shape.
行く/いく/ゆく is its own class `v5ks`: 行って/行った/行ったら/行ったり are the only rules that
produce it, the regular rows produce `v5k|v5ks` (行きます, 行かない, 行ける are regular).
Covered: ます family, て/で, た/だ, ない/なかった/なくて, the classical negatives ず/ずに/ぬ/ん
(食べず, 知らん, せずに; rewritten to ない so the one negative rule per class carries the
reason), なきゃ (`[negative, ba]`), なくちゃ/なくては (`[negative, te]`), potential (incl.
ら抜き and できる), passive, causative, causative-passive (long and short 書かされる),
volitional, imperative, ば, たら, たり, たい, そう, すぎる, さ, く (adverb), まい (after the
stem and after the dictionary form), ちゃう/じゃう, てしまう, とく/どく/といて/とけ (ておく,
reason `toku`), ている/てる/でいる/でる, i-adjective forms, する and 来る (kanji and kana).
Chains are bounded at `maxDepth = 6`; rules are indexed by the last code unit of their suffix.

Each rule also has a `next` shape handed to the following rule in the chain (default: `to`);
potential, passive, causative and causative-passive set `next = 0`, so nothing chains inside
them and 食べられられる / 食べさせさせる / 食ぶ `[potential, potential]` no longer appear while
食べられています, 食べさせている and 食べさせられたくなかった still resolve.

`Deinflection.reasons` is in **derivation order, innermost first**: 食べられなかった →
`[potential, negative, past]`, 知っています → `[te, progressive, polite]`, 食べません →
`[polite, negative]`. The `LookupResult.reasons` doc said "outermost first"; it now says
derivation order (the one-line doc change in `app/lib/domain/models/lookup_result.dart`
is the only edit under `domain/`). Reasons are short English names for the UI.

Potential rules are listed before passive, and a lookup keeps the first candidate per entry,
so an ambiguous られる shows as potential. 食べられる is also a godan passive shape
(取られる → 取る), so 食べる stays a `v5r` candidate too; the POS filter, not the rule table,
is what rejects it.

### D3.5 Lookup: surfaces from the tap, 24 code units, boundaries and breaks

`SqliteDictionary.lookupAt(text, index)` (C15: no pre-segmentation) tries every surface
from `maxSurfaceUnits = 24` UTF-16 code units down to one (an index outside the text is
clamped to `[0, length]`). Ends are placed on code point boundaries (a surrogate pair is
never split; an index on a low surrogate is clamped to the pair's start) and a surface never
crosses whitespace, 、。！？「」『』…‥・（）～ or ASCII `!?,.`. Each surface is
normalised to hiragana, deinflected, each candidate base is looked up in `forms`, and the
entry is kept when some sense's POS tag belongs to the candidate's classes (the identity
candidate accepts everything). A candidate `Xする` of class `vs` with no entry of its own
also tries `X` and keeps it when `X` carries `vs` (冒険した → 冒険 [past]).

Order: longest surface first; within a surface common entries first, then entries whose
headword **or reading** is the matched base (本【ほん】 before 本 as a spelling of 元【もと】;
こられる ranks 来る above 凝る, いって ranks 行く above 要る/入る), then shorter chains, then by
`ent_seq`. One result per entry per surface. `surface`, `start` and `length`
are in the caller's string; `baseForm` is the surface itself for an exact match and the
deinflected base (hiragana-normalised) otherwise.

### D3.6 Measured: no isolate, no extra index

`tool/dict/measure_lookup.dart`, 220 lookups over 11 OCR-like lines after warm-up, Apple
silicon, JIT:

| build | size | mean | max |
|---|---|---|---|
| mini fixture (45 entries) | 0.3 MB | 0.26 ms | 1.32 ms |
| full asset (218,898 entries, 253,779 senses, 611,405 forms, 10,384 kanji) | 56.4 MB | 0.37–0.44 ms (0.81 ms with a `flutter test` running alongside) | 1.5–2.2 ms on コーヒーを飲みすぎちゃったみたいです@0, 18 results (5.9 ms under load) |

Well under the 20 ms line the plan set for moving to an isolate, so `lookupAt` runs on the
caller's isolate (`lookupAtSync` is the body). Build of the full asset: 3.8–6.7 s wall
(2.1 s to decode both JSONs). The four prepared statements are compiled once in the
constructor.

### D3.7 Opening: `DictionaryAsset` seam, bundle copy behind a version stamp

The sqlite3 package cannot open a Flutter asset directly. `BundledDictionaryAsset`
(`bundled_dictionary_asset.dart`, the only Flutter-importing file in the service) copies
`assets/dict/dictionary.sqlite` into the app support directory and writes a
`dictionary.sqlite.version` stamp from the small `assets/dict/dictionary.version` asset
the build script produces: `jmdict <release> kanjidic <release> schema <n> sha256 <hash of
the built file>`, so a rebuild under the same pins (new builder, new rule table) is still
recopied. Later launches read the stamp only; the stamp is written after the copy is
renamed into place, so a failed copy leaves no stamp. A missing asset raises
`DictionaryAssetError` ("run `make dict` and rebuild"). `SqliteDictionary.openFile(path)` is
synchronous and takes any path, which is how the tests open a temporary build; a missing,
unreadable, non-SQLite or foreign-`schema_version` file raises `DictionaryOpenError` (pure
Dart, next to the class) instead of a raw `SqliteException`. `path_provider` and `rootBundle`
are constructor defaults, both injectable.

### D3.8 sqlite3 3.x via Dart hooks; no `sqlite3_flutter_libs`

`sqlite3_flutter_libs` is end-of-life (`0.6.0+eol`: "Not used anymore, update to version
3.x of package:sqlite3"). `sqlite3 ^3.7.0` bundles SQLite 3.53.4 through Dart build hooks on
every platform (prebuilt binaries from the package's GitHub releases, sha256-checked by the
package); verified under `flutter test` on macOS (`select sqlite_version()` → 3.53.4, not
the system library) and the hook output stays under `.dart_tool/`. Consequence: the first
build on a clean machine (and on a CI runner) downloads the prebuilt library during
`flutter test`/`flutter build`, so a sealed network fails the gate; pin or vendor later if
CI is ever offline.

### D3.9 Licences

JMdict and KANJIDIC2: EDRDG licence, CC BY-SA 4.0, attribution screen required. The text
stored in `meta.licence` and in `DictBuilder.licence`, ready for the about screen:

> This app uses the JMdict and KANJIDIC2 dictionary files. These files are the property
> of the Electronic Dictionary Research and Development Group (EDRDG), and are used in
> conformance with the Group's licence (Creative Commons Attribution-ShareAlike 4.0,
> CC BY-SA 4.0): https://www.edrdg.org/edrdg/licence.html

jmdict-simplified's own code is CC BY-SA 4.0 as well (its JSON is a derivative of the
EDRDG files; same attribution covers it). The deinflection rules are this repo's own (no
Yomitan GPL code). SQLite is public domain.

### D3.10 Deferred: na-adjective and noun copula forms

静かだった, 静かじゃない, 静かです, 静かな, 学生だった are not deinflected in v1: the copula
attaches to any noun/na-adjective, so a rule `だった → ''` would turn every `Xだった` into a
lookup of `X`, which the shorter-surface scan already yields (tapping 静 in 静かだった finds
静か as the 2-unit surface). A `copula` reason over `adj-na`/`n` can be added to the rule table
once WP4 shows whether the missing highlight on the だった part matters in practice.

## Red-first evidence

- Deinflector: tests committed on a stub returning nothing, `3 passed, 22 failed`
  (`2cb1ed9`), then green with 25 (`20f66a9`).
- Builder: stub creating an empty database, `0 passed, 7 failed` (`022a7be`), green with 7
  (`d1c4261`).
- SqliteDictionary: stub returning nothing, `2 passed, 19 failed` (`4fc00cf`), green with
  21 (`acb5188`).
- Asset seam and fake: written against the implementation in the same step (4 + 2 tests).
- Review round (`cac9dfd`…): the new rule tests, headword test (いらっしゃる), open-error
  tests, cap/clamp/ordering tests, hash-stamp and no-stamp-on-failure tests, kana tests and
  the canned fake result were added with their fixes (83 tests green).

Two test expectations were corrected while going green, both recorded here: polite forms
are in derivation order (ません → `[polite, negative]`), and 食べられなかった → 食べる must not
be asserted to exclude `v5r` (it is a valid godan passive shape; `v5k`/`adj-i` are excluded).

## What will bite WP4

- **First launch copies 56 MB** from the bundle to app support: `rootBundle.load` holds the
  whole file in memory once (~60 MB peak) and the write takes on the order of a second on a
  phone. Do it behind a splash/progress state, off the first frame, and never on the UI
  thread's critical path; `DictionaryAssetError` (asset missing) and `DictionaryOpenError`
  (copy corrupt or built with another schema) are the "run `make dict`"/"reinstall" cases and
  should be a visible screen, not a crash. The IPA grows by ~56 MB (SQLite compresses poorly).
- **`make dict` before any device build**: the asset is gitignored. A build without it
  bundles an empty `assets/dict/` (`.gitkeep` only) and the app will raise
  `DictionaryAssetError` on first lookup.
- **`lookupAt` is synchronous under an async signature** (D3.6). Sub-millisecond, so fine
  on the UI isolate; if WP4 batches lookups for a whole bubble, it is still ~0.5 ms × taps,
  not per character.
- **Reasons are in derivation order** (D3.4); render them as `食べる ← potential ← negative
  ← past`, not the other way round.
- **`DictionaryEntry.headword` is the entry's primary form, not the matched one**: tapping
  びーる gives entry 麦酒【ばくしゅ】 with `surface` びーる. Show `surface`/`baseForm` as the
  tapped word and the headword/reading as the entry; a per-form "matched reading" column
  is the next schema step if the UI needs ビール's own reading.
- **FakeDictionary** (`test/fakes/fake_dictionary.dart`) does exact headword/reading
  prefix matches with three entries, one canned inflected surface (食べた → 食べる `[past]`)
  for chain rendering, and records `lookups`; it does no deinflection.
- **Copula forms are not deinflected** (D3.10): 静かだった highlights 静か only.
- **Analysis of `tool/dict`** is by hand (`cd tool/dict && dart analyze --fatal-infos .`);
  the gate formats it (whole-tree `dart format`) but `flutter analyze` only covers `app/`.
