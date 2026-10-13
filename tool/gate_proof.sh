#!/usr/bin/env bash
# Gate mutation proof (PLAN.md section 4.2): a gate nobody has seen fail is a
# gate nobody has. This script copies a deliberately unformatted file, a
# deliberately lint-violating file and a deliberately failing test into the
# app, asserts that the matching gate target goes RED on each AND that it went
# red because of that fixture, removes them again and proves the restore with
# an unchanged `git status`.
#
# It is itself part of `make gate` (and of ci.yml), so it calls the individual
# targets `make gate-format` / `make gate-analyze` / `make gate-test` rather than
# `make gate`, which would recurse into this script.
#
# Fixtures live in tool/fixtures/ as *.dart.txt: the gate formats and analyzes
# the WHOLE tree with no exclusions, so a .dart fixture would turn the gate red
# permanently instead of only while this script runs.
set -eo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
fixtures="$root/tool/fixtures"

# The copies go under app/ with names no real file will ever use.
unformatted_copy="app/lib/zz_gate_proof_unformatted.dart"
lint_copy="app/lib/zz_gate_proof_lint_violation.dart"
test_copy="app/test/zz_gate_proof_failing_test.dart"

# Precondition 1, BEFORE any trap is installed: the copy targets are free. The
# restore below deletes what this script created and nothing else, but refusing
# up front keeps a real file at one of these paths from ever being touched.
for f in "$unformatted_copy" "$lint_copy" "$test_copy"; do
  if [ -e "$f" ]; then
    echo "❌ gate proof: $f already exists, refusing to overwrite it."
    exit 1
  fi
done

# The fourth proof (WP2b) edits a COMMITTED golden in place and restores it
# with `git checkout --`, so it must be unmodified before the proof starts.
golden="app/test/goldens/ocr/v_single.json"
if [ -n "$(git status --porcelain -- "$golden")" ]; then
  echo "❌ gate proof: $golden has local modifications, refusing to overwrite them."
  exit 1
fi

out="$(mktemp)"
created=()
golden_mutated=""
# Restore no matter how this script exits, so a failing proof never leaves a
# red fixture in the tree. Only paths this script created are removed, and
# the golden only when this script changed it.
cleanup() {
  rm -f "$out"
  if [ "${#created[@]}" -gt 0 ]; then rm -f "${created[@]}"; fi
  if [ -n "$golden_mutated" ]; then git checkout -- "$golden"; fi
}
trap cleanup EXIT
# An interrupt must never become a verdict: without this, a Ctrl-C during a
# mutated run leaves `make` non-zero and reads as "went red".
trap 'echo "❌ gate proof: interrupted"; exit 130' INT TERM

place() { # <fixture file> <copy path>
  cp "$fixtures/$1" "$2"
  created+=("$2")
}

# The restore is proven against the status BEFORE the proof, not against an
# empty status: in CI the tree is clean and the two are the same thing, while
# locally this lets `make gate` run over uncommitted work instead of refusing.
status_before="$(git status --porcelain)"

# Precondition 2: the gate is GREEN on the untouched tree. Without this, a red
# result below could be the tree's own fault rather than the fixture's.
echo "==> proof: gate-format, gate-analyze and gate-test are green on the untouched tree"
make gate-format
make gate-analyze
make gate-test

expect_red() { # <what> <make target> <evidence string>...
  local what="$1" target="$2" rc
  shift 2
  set +e
  make "$target" >"$out" 2>&1
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "❌ $what: 'make $target' stayed GREEN. The gate does not catch this."
    cat "$out"
    exit 1
  fi
  if [ "$rc" -ge 128 ]; then
    echo "❌ $what: 'make $target' was killed by a signal (exit $rc), that is not a verdict."
    cat "$out"
    exit 1
  fi
  # Red is not enough: a pub-cache lock, an OOM or an SDK hiccup is also red.
  # The output must name the fixture, so the red is the fixture's doing.
  local ev
  for ev in "$@"; do
    if ! grep -qF "$ev" "$out"; then
      echo "❌ $what: 'make $target' went red, but not because of the fixture (no '$ev' in its output):"
      cat "$out"
      exit 1
    fi
  done
  echo "✅ $what: 'make $target' went red because of the fixture:"
  grep -F -m 3 "$1" "$out" | sed 's/^/     | /'
}

echo "==> proof: an unformatted file turns gate-format red"
place unformatted.dart.txt "$unformatted_copy"
expect_red "unformatted file" gate-format "zz_gate_proof_unformatted.dart"
rm "$unformatted_copy"

echo "==> proof: a lint-violating (but formatted) file turns gate-analyze red, and only that"
place lint_violation.dart.txt "$lint_copy"
# The fixture is formatted, so gate-format must stay green on it: that is what
# separates "the analyzer caught the lint" from "something, anything, failed".
make gate-format
expect_red "lint violation (INFO level: the lowest severity fails the gate)" gate-analyze \
  "zz_gate_proof_lint_violation.dart" "prefer_single_quotes"
rm "$lint_copy"

echo "==> proof: a failing test turns gate-test red, and only that"
place failing_test.dart.txt "$test_copy"
# Formatted and lint-clean, so the first two targets stay green on it.
make gate-format
make gate-analyze
expect_red "failing test" gate-test "zz_gate_proof_failing_test.dart" "Some tests failed"
rm "$test_copy"

# The accuracy check (PLAN section 4.1: the WP0b goldens through the real ORT
# adapters) joins the gate with its own proof: the recorded text of one
# committed golden is changed in place, gate-test must go red NAMING that
# golden, and `git checkout --` restores it byte for byte.
echo "==> proof: a corrupted golden turns gate-test red, naming the golden"
golden_mutated=1
sed -i '' 's/^\( *"text": ".*\)"\(,*\)$/\1 corrupted"\2/' "$golden"
if git diff --quiet -- "$golden"; then
  echo "❌ gate proof: the sed left $golden unchanged, the proof cannot run."
  exit 1
fi
expect_red "corrupted golden" gate-test "v_single" "Some tests failed"
git checkout -- "$golden"
golden_mutated=""

echo "==> proof: the tree is restored"
status_after="$(git status --porcelain)"
if [ "$status_after" != "$status_before" ]; then
  echo "❌ gate proof: 'git status' changed during the proof, the tree is NOT restored."
  echo "--- before:"; echo "$status_before"
  echo "--- after:"; echo "$status_after"
  exit 1
fi
if [ -z "$status_after" ]; then
  echo "✅ gate proof: all four mutations went red, tree restored (git status clean)"
else
  echo "✅ gate proof: all four mutations went red, tree restored (git status unchanged; it was not clean to begin with)"
fi
