# yomitanuki (app)

The Flutter iOS app. Project-level plan and decisions: [`../PLAN.md`](../PLAN.md),
per-work-package decision logs under `../.claude/wpN/NOTES.md`, working rules in
[`../AGENTS.md`](../AGENTS.md).

## Toolchain

Flutter is pinned once, in `pubspec.yaml` (`environment.flutter`). `make check-flutter`
and CI both assert the installed Flutter against that line and refuse to run otherwise.
Flutter is resolved from PATH, falling back to `~/Developer/flutter`; override with
`make FLUTTER=/path/to/flutter/bin/flutter gate`.

## Commands (from the repo root)

```bash
make gate          # the merge gate == .github/workflows/ci.yml: format, analyze, test, proof, build-ios
make gate-format   # dart format --set-exit-if-changed over the whole repo
make gate-analyze  # flutter analyze --fatal-infos (strict-casts/inference/raw-types + extra lints)
make gate-test     # flutter test
make gate-proof    # tool/gate_proof.sh: each gate target is shown to go red on its fixture
make gate-build-ios # flutter build ios (simulator debug + unsigned device release), nm checks the ORT symbol
make help
```

## Layout

```
lib/main.dart                     YomitanukiApp
lib/ui/<feature>/view/            widgets
lib/ui/<feature>/view_model/      state, when a feature has any
lib/domain/models/                plain models
lib/domain/ports/                 the ports: detector, OCR, camera, photo picker, dictionary, translator, Anki, settings, capture log
lib/domain/use_cases/             note building, furigana, line glossing
lib/domain/text/                  kana, lookup breaks, HTML escaping
lib/data/{services,repositories}/ adapters: camera, ONNX inference, dictionary, translation, Anki, settings
test/                             mirrors lib/
```

Inference and the camera are ports; ONNX Runtime adapters implement them, fakes implement
them in every other test. Inference never runs on the UI isolate.
