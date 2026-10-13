#!/bin/sh
# Locate a node runtime for guard-bulk-read.mjs.
#
# A hook does not run in your interactive shell. It gets a bare environment, so
# a node installed by nvm/fnm/asdf — which those tools put on PATH from your
# shell profile — is simply not there. `node ...` then fails with 127, the
# failure is non-blocking, and every read sails through while the guard looks
# installed. That is not hypothetical: it is how this guard spent its first
# afternoon, firing only in the one session that happened to inherit nvm's PATH.
#
# Fail open on purpose: if no runtime can be found, exit 0 and let the read
# proceed. A guard that cannot run must not be a guard that blocks work.

NODE=""
for c in /opt/homebrew/bin/node /usr/local/bin/node /usr/bin/node; do
  [ -x "$c" ] && NODE="$c" && break
done

# Whatever the caller's PATH already offers, if anything.
if [ -z "$NODE" ]; then
  p=$(command -v node 2>/dev/null)
  [ -n "$p" ] && [ -x "$p" ] && NODE="$p"
fi

# Version managers, newest version first.
if [ -z "$NODE" ]; then
  for base in "$HOME/.nvm/versions/node" "$HOME/.local/share/fnm/node-versions" "$HOME/.asdf/installs/nodejs"; do
    [ -d "$base" ] || continue
    for v in $(ls -1 "$base" 2>/dev/null | sort -rV); do
      for cand in "$base/$v/bin/node" "$base/$v/installation/bin/node"; do
        [ -x "$cand" ] && NODE="$cand" && break 3
      done
    done
  done
fi

[ -z "$NODE" ] && exit 0

exec "$NODE" "$(dirname "$0")/guard-bulk-read.mjs"
