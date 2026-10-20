# Before the first public push

One decision left for the owner; the team-id question is settled below. Nothing here is done
by the code: each is a question to answer, then an action (or none) to perform. History is not
rewritten.

## (a) Apple development team id: kept (decided 2026-10-20)

`app/ios/Runner.xcodeproj/project.pbxproj` carries `DEVELOPMENT_TEAM = 452M7C65ZY;` three
times (Debug, Release, Profile). It is a signing team identifier, not a secret, and it has been
in every commit since WP1. Decision: keep it and leave history as it is. A visitor who builds the
app replaces it with their own team in Xcode, as with any iOS sample.

Also in history: the bundle id `app.mcmaffin.yomitanuki` (PLAN.md D9, the Xcode project), two
device UDIDs (the test phone and a simulator) and the author's home path in the deleted
`HANDOFF*.md` files. Accepted; no history rewrite.

## (b) Repository name and description

Confirm before creating the GitHub repository under `onkyou`:

- Name: `yomitanuki` is the app name (D9); the local folder is `manga_ocr`. Pick one; no
  tracked file depends on the folder name.
- Description, one line, e.g. "Point the camera at a manga page, tap a bubble, read it on
  the device, send the word to Anki. Flutter + ONNX Runtime, built spec-first with Claude
  Code as the implementer."
- Topics: `flutter`, `onnx-runtime`, `ocr`, `japanese`, `anki`, `claude-code`, `ios`.
- Licence shown by GitHub: GPL-3.0, from the `LICENSE` file at the root.

## After the decisions

```bash
make gate
```

must be green on the branch, then merge to `main` and push. CI (`.github/workflows/ci.yml`)
has never run against a remote; the first push is its first run (see
`docs/PHONE-TESTING.md`, "What will bite").
