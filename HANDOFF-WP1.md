# Handoff after WP1 (2026-10-13)

**Where the code is:** `~/Documents/marv/manga_ocr`, branch `wp1-scaffold` merged into `main`.
Flutter app under `app/`, gate in `Makefile` + `.github/workflows/ci.yml`, proof in `tool/`.

**What landed:** `flutter create` (iOS only, `app.mcmaffin.yomitanuki`), placeholder home screen with
two widget tests, strict analysis (`strict-*` + ~20 extra lints, `--fatal-infos`), `make gate` ==
`ci.yml` (format, analyze, test, proof), a mutation proof that shows each gate target going red on
its own fixture and requires the fixture's name in the output, the 17 binding skills under
`.agents/skills/` pinned in `skills-lock.json`, decisions D1.1–D1.14 in `.claude/wp1/NOTES.md`.
Both reviews (architecture conformance, code review) ran; every must-fix and should-fix landed in
`eb27c38`; what was deliberately not changed is recorded in D1.13.

**What is left:** WP0b, then WP2 onwards.

**What will bite (details in `.claude/wp1/NOTES.md` "What will bite"):**
- Generated code vs the strict analyzer modes and whole-tree `dart format`; decide exclusions before
  the first `*.g.dart` / `*.mocks.dart`.
- CI has never executed (no remote). First push: `subosito/flutter-action@v2` must honour
  `flutter-version-file: app/pubspec.yaml`, and `make` on `macos-15` must be GNU Make.
- The proof compares `git status` including untracked files; a plugin that writes non-ignored files
  during analyze/test fails it.
- `LANG=en_US.UTF-8` before the first `pod install` (ORT in WP2).
- No `flutter build ios` in the gate yet; add it with the first native dependency.

**Corrections to PLAN.md:**
- §3 WP1 bullet 3 (layering): only directories with files exist; the PLAN spelling
  `ui/<feature>/{view,view_model}` is binding, not the skill's `ui/features/.../views` (D1.10).
- §4.1 bullet 4: the "accuracy check against the synthetic fixture set" is not in the gate; the set
  does not exist yet. WP0b creates the synthetic goldens; WP2 adds the check with its own proof.
- §4.1 bullet 3 is now met literally: the Flutter version lives in one place (`app/pubspec.yaml`).

**Open judgement calls:** none from WP1. (WP0's D0.11/D0.12 were answered by Marv the same evening.)
