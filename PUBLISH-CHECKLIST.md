# Before the first public push

Two decisions only the owner can take. Nothing below is done by the code; each is a question
to answer, then an action (or none) to perform. History is not rewritten by any of this unless
(a) is answered "remove from history".

## (a) Keep the Apple development team id?

`app/ios/Runner.xcodeproj/project.pbxproj` carries `DEVELOPMENT_TEAM = 452M7C65ZY;` three
times (Debug, Release, Profile). It is a signing team identifier, not a secret, and it is in
every commit since WP1. Options:

- **Keep it.** Nothing to do. A visitor who builds the app replaces it with their own team in
  Xcode, as with any iOS sample.
- **Blank it going forward.** One commit; the id stays in history.
- **Remove it from history.** Needs a history rewrite (`git filter-repo` or similar) before
  the first push, which also changes every commit hash cited in the `.claude/wpN/NOTES.md`
  decisions.

Also in history and still in the working tree: the bundle id `app.mcmaffin.yomitanuki`
(PLAN.md D9, the Xcode project). Two device UDIDs (the test phone and a simulator) and the
author's home path appeared in the deleted `HANDOFF*.md` files and remain in earlier commits.

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
