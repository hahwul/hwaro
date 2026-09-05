#!/usr/bin/env bash
#
# Guard for the file-split convention: a "part" file (any .cr under a
# directory that sits next to an owner file of the same name, e.g.
# src/core/build/phases/render/*.cr next to render.cr) may only REOPEN types.
# Everything that runs at load time — `Registry.register(...)`, constant
# aliases at the top level, `require`s of siblings — stays in the owner file,
# where the require order is explicit. That keeps a part order-independent,
# so moving one between files, or adding a new one, can never change load-time
# behaviour.
#
# Concretely: every column-0 line of a part must be blank, a comment, a
# `require` (harmless: definitions are order-independent), or one of
# `module|class|struct|abstract class|private ...|end`. Anything else (a bare
# method call, an assignment, a constant alias) fails the check.
set -euo pipefail

cd "$(dirname "$0")/.."

status=0
while IFS= read -r part_dir; do
  owner="${part_dir%/}.cr"
  [ -f "$owner" ] || continue
  for file in "$part_dir"/*.cr; do
    [ -f "$file" ] || continue
    bad="$(grep -nE '^[^ #]' "$file" | grep -vE '^[0-9]+:(require |module |class |struct |abstract |private |end\b)' || true)"
    if [ -n "$bad" ]; then
      echo "✗ $file has top-level statements (parts may only reopen types; keep load-time effects in $owner):"
      echo "$bad" | sed 's/^/    /'
      status=1
    fi
  done
done < <(find src -type d -mindepth 2 | sort)

if [ "$status" = 0 ]; then
  echo "✓ no top-level effects in split part files"
fi
exit $status
