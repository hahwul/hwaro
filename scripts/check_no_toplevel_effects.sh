#!/usr/bin/env bash
#
# Guard for the file-split convention (ARCHITECTURE.md, "The file-split
# convention"): a part file only REOPENS a type and fills it with
# definitions. Everything that runs at load time — `Registry.register(...)`,
# a class-variable initialiser, a bare method call — and every `require`
# stays in the OWNER file, where the require order is explicit. That keeps
# a part order-independent: moving one between files, or adding a new one,
# can never change load-time behaviour.
#
# What counts as a part is listed explicitly in PART_GLOBS below (add a line
# when you split a new owner). For each part the script walks the file with
# an indentation-tracked stack of open types and checks every line that sits
# DIRECTLY inside a type (or at the top level):
#
#   allowed   module/class/struct/enum/annotation openers and their `end`,
#             def / macro / record / constant assignment / alias / property-
#             style declarations / include / extend / annotations / comments
#   rejected  require, a bare call or expression, an ivar or class-var
#             assignment — i.e. anything that executes when the file loads
#
# Lines nested deeper than the innermost open type (method bodies, multi-line
# constant initialisers) are not inspected.
set -euo pipefail

cd "$(dirname "$0")/.."

PART_GLOBS=(
  "src/core/build/phases/render/*.cr"
  "src/core/build/builder/*.cr"
  "src/models/config/*.cr"
  "src/services/doctor/*.cr"
  "src/services/deployer/*.cr"
  "src/services/server/handlers.cr"
  "src/services/server/dev_http_server.cr"
  "src/services/server/change_set.cr"
  "src/services/server/watch.cr"
  "src/services/server/rebuild.cr"
  "src/content/processors/markdown/*.cr"
  "src/content/processors/markdown_extensions/*.cr"
  "src/cli/commands/tool/deadlink_command/*.cr"
)

status=0
checked=0
for glob in "${PART_GLOBS[@]}"; do
  matched=0
  for file in $glob; do
    [ -f "$file" ] || continue
    matched=1
    checked=$((checked + 1))
    bad="$(awk '
      function indent(s,   m) { m = match(s, /[^ ]/); return m ? m - 1 : 0 }
      function body_indent() { return depth ? stack[depth] + 2 : 0 }
      BEGIN { depth = 0 }
      {
        line = $0
        if (line ~ /^[ ]*$/ || line ~ /^[ ]*#/) next
        ind = indent(line)
        t = line; sub(/^[ ]*/, "", t)
        # A `record X, ...` that spans lines may or may not end in a `do` block:
        # its tentative scope is closed by the next line at or above its indent
        # unless that line is the closing end of a do block.
        if (depth && kind[depth] == "record" && ind <= stack[depth]) {
          if (ind == stack[depth] && t ~ /^end([ ]|$)/) { depth--; next }
          depth--
        }
        # Lines at the indent of the innermost open scope close or continue it.
        if (depth && ind == stack[depth]) {
          if (t ~ /^end([ ]|$)/) { depth--; next }
          if (kind[depth] == "def" && t ~ /^(rescue|ensure|else|when|elsif|\)|\]|\})/) next
          print NR ": " t; next
        }
        if (depth && kind[depth] != "type" && ind > stack[depth]) next
        if (ind > body_indent()) next
        if (ind < body_indent()) { print NR ": " t; next }
        # Directly inside the innermost open type (or at the top level).
        if (t ~ /^(private |protected |abstract )?(module|class|struct|enum|annotation) /) { depth++; stack[depth] = ind; kind[depth] = "type"; next }
        if (t ~ /^(private |protected |abstract )?(def |macro )/) {
          if (t !~ /(;|[ ])end$/) { depth++; stack[depth] = ind; kind[depth] = "def" }
          next
        }
        if (t ~ /^(private |protected )?[A-Z][A-Za-z0-9_:]* *=/) {
          if (t ~ /= *begin$/) { depth++; stack[depth] = ind; kind[depth] = "def" }
          next
        }
        if (t ~ /^(private |protected )?record /) { depth++; stack[depth] = ind; kind[depth] = (t ~ / do$/) ? "def" : "record"; next }
        if (t ~ /^(private |protected |abstract )?(record |alias |include |extend |getter |setter |property |class_getter |class_setter |class_property |delegate |forward_missing_to |@\[)/) next
        if (t ~ /^(\)|\]|\})/) next
        print NR ": " t
      }' "$file")"
    if [ -n "$bad" ]; then
      echo "✗ $file has load-time statements or requires (parts only reopen types; keep those in the owner):"
      echo "$bad" | sed 's/^/    /'
      status=1
    fi
  done
  if [ "$matched" = 0 ]; then
    echo "✗ no part matches $glob (update PART_GLOBS)"
    status=1
  fi
done

if [ "$status" = 0 ]; then
  echo "✓ $checked part files contain only type reopenings and definitions"
fi
exit $status
