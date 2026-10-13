# WP1 — scaffold and gate: decision log

Branch `wp1-scaffold`, written 2026-10-13. Everything PLAN.md dictates (D1–D10, §3 WP1, §4) is not
repeated here; these are the choices PLAN.md left open. Binding until explicitly reversed.

## Decisions

- **D1.1 Flutter 3.47.2 stable is the pinned toolchain** (Dart 3.13.2), the SDK at
  `~/Developer/flutter`. Pinned in `Makefile` (`FLUTTER_VERSION`) and `.github/workflows/ci.yml`
  (`env.FLUTTER_VERSION`); `make check-flutter` and the CI step "flutter version pin" assert it by
  reading `flutter --version --machine` and refuse to run on any other version. Change both or
  neither.
- **D1.2 Lint set: `flutter_lints` plus the rules listed in `app/analysis_options.yaml`**, with
  `strict-casts`, `strict-inference`, `strict-raw-types`. The extras are the ones a strict type
  setting does not cover: `unawaited_futures`, `discarded_futures`, `avoid_dynamic_calls`,
  `prefer_final_locals`, `prefer_single_quotes`, `directives_ordering`, `sort_pub_dependencies`,
  `cancel_subscriptions`, `close_sinks`, `only_throw_errors`, and a few more. Not a third-party
  bundle (`very_good_analysis` etc.): a dependency for a list of rule names is one more thing to
  version. `unnecessary_await_in_return` was in the first draft and is deprecated in Dart 3.13; the
  gate itself flagged it (`deprecated_lint`), and it was dropped.
- **D1.3 `flutter analyze --fatal-infos` is passed explicitly although it is the default.**
  Measured: `flutter analyze` without the flag already exits 1 on an INFO-level finding (unlike
  `dart analyze`). The flag stays in the command so the gate does not depend on that default. The
  lint fixture (D1.6) is INFO level, so the proof shows the lowest severity fails the gate.
- **D1.4 Gate layout: four targets, cheapest first, one CI job.** `make gate` =
  `gate-format` → `gate-analyze` → `gate-test` → `gate-proof`, each with `check-flutter` as a
  prerequisite. `ci.yml` has one job (`gate`) with the same five steps in the same order; the two
  files are meant to be diffed. `dart format` runs from the repo root over the whole tree (so a
  Dart script under `tool/` later is gated without editing the Makefile); `flutter analyze` and
  `flutter test` run inside `app/`, where the pubspec is.
- **D1.5 The proof calls sub-targets, not `make gate`.** `tool/gate_proof.sh` is itself part of
  `make gate`, so it runs `make gate-format` / `make gate-analyze` on the mutated tree. The
  Makefile targets are the single definition of those commands; the script does not retype them.
- **D1.6 Fixtures are stored as `*.dart.txt`, copied in as `.dart` only while the proof runs.**
  The gate formats and analyzes the whole tree with no exclusions and no baseline (PLAN §4.1); a
  `.dart` fixture in the tree would be red permanently. The copies land in `app/lib/` under names
  starting `zz_gate_proof_`, and the script refuses to run if either path already exists.
- **D1.7 Restore is proven by `git status --porcelain` before == after, not by an empty status.**
  A `trap ... EXIT` deletes the copies on every exit path. Comparing against the pre-proof status
  (rather than demanding a clean tree) lets `make gate` run over uncommitted work locally; in CI
  the tree is clean, so the two checks are the same thing. The proof also runs `gate-format` on
  the lint fixture and requires it to stay green, so "the analyzer caught the lint" is
  distinguishable from "something failed".
- **D1.8 CI runner `macos-15`, `subosito/flutter-action@v2` with `cache: true`.** macOS because the
  app is iOS-only (D4) and the next work packages add Xcode-dependent steps; the four commands in
  the gate today would run on Linux. No `flutter build ios` in the gate yet: PLAN §4.1 lists four
  commands, and there is no native code or bundled weight (D6) for a build to catch. Add it when
  WP2 adds the ORT dependency.
- **D1.9 Makefile resolves `flutter` from PATH, falling back to `~/Developer/flutter/bin/flutter`;
  `dart` is always the one beside the resolved `flutter`.** Non-interactive shells on this Mac do
  not have Flutter on PATH, so the fallback makes `make gate` work from any shell. Taking `dart`
  from the same bin directory (not a second `dart` on PATH) means the formatter and the analyzer
  cannot come from different SDKs. Override: `make FLUTTER=/path/to/flutter gate`.
- **D1.10 Layering: only what the placeholder needs.** `lib/main.dart` (`YomitanukiApp`) and
  `lib/ui/home/view/home_view.dart` (`HomeView`). No view model: the screen has no state and
  nothing to fetch, and a `ChangeNotifier` with nothing to notify is a speculative file. No
  `lib/domain/models`, `lib/data/services`, `lib/data/repositories` directories either (git does
  not track empty directories and `.gitkeep` files are the same speculation). WP2's ports
  (`TextDetector`, `OcrEngine`) are the first things that belong there; put them at
  `lib/domain/` (interfaces + models) with ORT adapters under `lib/data/services/`.
- **D1.11 Testability seams: nothing to seam in WP1.** The app touches no time, randomness,
  filesystem, network, camera or model. The first of those arrives in WP2 and must be a port with
  a fake from its first commit (PLAN §4.2, `testability-seams` skill).
- **D1.12 `skills-lock.json`: upstream entries verbatim, local ones by sha256.** The eight skills
  that wegziel installed from GitHub (`dart-lang/skills`, `flutter/agent-plugins`) keep wegziel's
  lock entries unchanged, including wegziel's `computedHash` (produced by the skills CLI over the
  skill directory, not reproducible with `shasum`). The nine wegziel-authored skills are recorded
  with `sourceType: local`, `source: wegziel` and the sha256 of the copied `SKILL.md`. Nothing
  checks the lock mechanically yet; it documents provenance.
- **D1.13 Scaffold trimmed, not rewritten.** `cupertino_icons` removed (unused), pubspec tutorial
  comments removed, description set. `app/README.md` (Flutter's generic one), `app/ios/` and
  `app/.gitignore` are as `flutter create` wrote them. The raw scaffold is its own commit so the
  trim is reviewable as a diff.
- **D1.14 Commit granularity: one concern per commit, tests before the code they guard.** The
  home-screen tests were committed with the screen (both red-then-green in the same slice); the
  gate proof was committed one commit before the Makefile, red at that commit, green at the next.

## What will bite the next work package

- **PLAN §4.1's "WP0 accuracy check against the synthetic fixture set" is not in the gate.** There
  is no synthetic fixture set yet (P4; WP0 measured on private photos). WP2 has to build the
  synthetic renderer, and then the check joins `make gate` and `ci.yml` together, with its own
  mutation proof.
- **CocoaPods prints a UTF-8 warning** (`pod --version` on this Mac): harmless until the first
  plugin with a podspec (ORT in WP2). Set `LANG=en_US.UTF-8` in the shell that runs `pod install`.
- **CI has never run.** There is no remote; `ci.yml` is written to be diffed against the Makefile
  and has not executed on a runner. First push: check that `subosito/flutter-action@v2` resolves
  3.47.2 and that `make` on `macos-15` is GNU Make (the proof calls it).
- **The proof's `git status` comparison counts untracked files**, so anything that writes an
  untracked, non-ignored file under the repo during `flutter analyze`/`flutter test` would fail
  it. Today nothing does; a new plugin that generates files outside `app/.gitignore` would.
