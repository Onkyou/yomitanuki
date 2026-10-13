#!/usr/bin/env bash
# Gate mutation proof (PLAN.md section 4.2): a gate nobody has seen fail is a
# gate nobody has. This script copies a deliberately unformatted file and a
# deliberately lint-violating file into app/lib/, asserts that the matching
# gate target goes RED on each, removes them again and proves the restore with
# a clean `git status`.
#
# It is itself part of `make gate` (and of ci.yml), so it calls the individual
# targets `make gate-format` / `make gate-analyze` rather than `make gate`,
# which would recurse into this script.
#
# Fixtures live in tool/fixtures/ as *.dart.txt: the gate formats and analyzes
# the WHOLE tree with no exclusions, so a .dart fixture would turn the gate red
# permanently instead of only while this script runs.
set -eo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
fixtures="$root/tool/fixtures"

# The copies go under app/lib/ with a name no real file will ever use.
unformatted_copy="app/lib/zz_gate_proof_unformatted.dart"
lint_copy="app/lib/zz_gate_proof_lint_violation.dart"

# Restore no matter how this script exits, so a failing proof never leaves a
# red fixture in the tree.
cleanup() { rm -f "$unformatted_copy" "$lint_copy"; }
trap cleanup EXIT

out="$(mktemp)"

# Precondition 1: the copy targets are free. The restore below deletes them,
# so a real file at either path would be lost.
for f in "$unformatted_copy" "$lint_copy"; do
  if [ -e "$f" ]; then
    echo "❌ gate proof: $f already exists, refusing to overwrite it."
    exit 1
  fi
done

# The restore is proven against the status BEFORE the proof, not against an
# empty status: in CI the tree is clean and the two are the same thing, while
# locally this lets `make gate` run over uncommitted work instead of refusing.
status_before="$(git status --porcelain)"

# Precondition 2: the gate is GREEN on the untouched tree. Without this, a red
# result below could be the tree's own fault rather than the fixture's.
echo "==> proof: gate-format and gate-analyze are green on the untouched tree"
make gate-format
make gate-analyze

expect_red() { # <what> <make target>
  if make "$2" >"$out" 2>&1; then
    echo "❌ $1: 'make $2' stayed GREEN. The gate does not catch this."
    cat "$out"
    exit 1
  fi
  echo "✅ $1: 'make $2' went red:"
  # The reason, so a reader can tell "the formatter found the file" from
  # "make blew up before it got there".
  tail -n 4 "$out" | sed 's/^/     | /'
}

echo "==> proof: an unformatted file turns gate-format red"
cp "$fixtures/unformatted.dart.txt" "$unformatted_copy"
expect_red "unformatted file" gate-format
rm "$unformatted_copy"

echo "==> proof: a lint-violating (but formatted) file turns gate-analyze red, and only that"
cp "$fixtures/lint_violation.dart.txt" "$lint_copy"
# The fixture is formatted, so gate-format must stay green on it: that is what
# separates "the analyzer caught the lint" from "something, anything, failed".
make gate-format
expect_red "lint violation (INFO level: the lowest severity fails the gate)" gate-analyze
rm "$lint_copy"

echo "==> proof: the tree is restored"
status_after="$(git status --porcelain)"
if [ "$status_after" != "$status_before" ]; then
  echo "❌ gate proof: 'git status' changed during the proof, the tree is NOT restored."
  echo "--- before:"; echo "$status_before"
  echo "--- after:"; echo "$status_after"
  exit 1
fi
if [ -z "$status_after" ]; then
  echo "✅ gate proof: both mutations went red, tree restored (git status clean)"
else
  echo "✅ gate proof: both mutations went red, tree restored (git status unchanged; it was not clean to begin with)"
fi
