#!/usr/bin/env bash
#
# Byte-identity gate for behavior-preserving refactors.
#
# Runs the SAME inputs through two hwaro binaries and `diff -r`s everything
# they produce: scaffold init trees, built sites (plain / --minify / --cache),
# the docs site, a generated benchmark corpus, every importer, convert/export,
# and the text surfaces (`--help`, `--json` reports, doctor, validate, new).
# Optional tiers exercise `serve` incremental rebuilds and `deploy`.
#
# Usage:
#   scripts/verify_byte_identity.sh BASE_BIN CAND_BIN [options]
#
#   --serve        also run the serve tier (incremental rebuild snapshots)
#   --deploy       also run the deploy tier (file:// target)
#   --quick        scaffolds: default config only (skips --minimal/--full/multilingual)
#   --count N      benchmark corpus size (default 300)
#   --keep         keep the work directory on success (always kept on failure)
#   --work DIR     use DIR as the work directory instead of mktemp
#
# Typical:
#   just baseline                      # builds ../hwaro-baseline/bin/hwaro from main
#   shards build
#   scripts/verify_byte_identity.sh ../hwaro-baseline/bin/hwaro bin/hwaro
#
# A self-diff (`BASE BASE`) proves the corpus itself is deterministic; anything
# that differs there is volatile output and belongs in `normalize_tree`, not in
# a refactor's diff.
set -euo pipefail

BASE_BIN=""
CAND_BIN=""
RUN_SERVE=0
RUN_DEPLOY=0
QUICK=0
COUNT=300
KEEP=0
WORK=""

while [ $# -gt 0 ]; do
  case "$1" in
    --serve) RUN_SERVE=1 ;;
    --deploy) RUN_DEPLOY=1 ;;
    --quick) QUICK=1 ;;
    --count) COUNT="$2"; shift ;;
    --keep) KEEP=1 ;;
    --work) WORK="$2"; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *)
      if [ -z "$BASE_BIN" ]; then BASE_BIN="$1"
      elif [ -z "$CAND_BIN" ]; then CAND_BIN="$1"
      else echo "unexpected argument: $1" >&2; exit 2; fi ;;
  esac
  shift
done

if [ -z "$BASE_BIN" ] || [ -z "$CAND_BIN" ]; then
  echo "usage: $0 BASE_BIN CAND_BIN [--serve] [--deploy] [--quick] [--count N] [--keep]" >&2
  exit 2
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BASE_BIN="$(cd "$(dirname "$BASE_BIN")" && pwd)/$(basename "$BASE_BIN")"
CAND_BIN="$(cd "$(dirname "$CAND_BIN")" && pwd)/$(basename "$CAND_BIN")"
[ -x "$BASE_BIN" ] || { echo "not executable: $BASE_BIN" >&2; exit 2; }
[ -x "$CAND_BIN" ] || { echo "not executable: $CAND_BIN" >&2; exit 2; }

if [ -z "$WORK" ]; then
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/hwaro-identity.XXXXXX")"
else
  mkdir -p "$WORK"
  WORK="$(cd "$WORK" && pwd)"
fi

export NO_COLOR=1
export HWARO_NO_UPDATE_CHECK=1

FAILURES=0
PASSED=0
TOTAL=0

log()  { printf '%s\n' "$*"; }
step() { printf '\n▸ %s\n' "$*"; }

# Volatile bytes that legitimately differ between two runs of the SAME binary.
# Keep this list tiny and explicit: every entry is a place where hwaro embeds
# wall-clock time or process state into its output.
normalize_tree() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  # Feed build timestamps: RSS <lastBuildDate>, Atom feed-level <updated> on
  # the line right after <feed ...> / <title> header, JSON Feed has none.
  find "$dir" -type f \( -name '*.xml' -o -name '*.atom' -o -name '*.rss' \) -print0 2>/dev/null |
    xargs -0 perl -pi -e 's{<lastBuildDate>[^<]*</lastBuildDate>}{<lastBuildDate>T</lastBuildDate>}g' 2>/dev/null || true
  # Build bookkeeping written into the input tree (.hwaro/owned_outputs, the
  # build cache) records absolute paths, which differ only by our .base/.cand
  # copy suffix.
  find "$dir" \( -path '*/.hwaro/*' -o -name '.hwaro_cache.json' \) -type f -print0 2>/dev/null |
    xargs -0 perl -pi -e 's/\.(base|cand)(?=\/|\b)/.X/g' 2>/dev/null || true
}

# Normalise timings / pids / the work-dir path in captured text output.
normalize_text() {
  NORM_WORK="$WORK" NORM_BASE="$BASE_BIN" NORM_CAND="$CAND_BIN" perl -pe '
    s/\b\d+(\.\d+)?\s?(ms|s|sec|seconds)\b/T/g;
    s/"(duration|elapsed|time|took|build_time|duration_ms|elapsed_ms|pid)"\s*:\s*[0-9.]+/"$1": T/g;
    s/pid=\d+/pid=P/g;
    s/\Q$ENV{NORM_WORK}\E/WORK/g;
    s/\Q$ENV{NORM_BASE}\E/BIN/g;
    s/\Q$ENV{NORM_CAND}\E/BIN/g;
  '
}

# compare NAME LEFT RIGHT — diff -r two trees (or files) after normalising.
compare() {
  local name="$1" left="$2" right="$3"
  TOTAL=$((TOTAL + 1))
  normalize_tree "$left"
  normalize_tree "$right"
  if diff -r "$left" "$right" > "$WORK/diff.$TOTAL.txt" 2>&1; then
    PASSED=$((PASSED + 1))
    log "  ✓ $name"
    rm -f "$WORK/diff.$TOTAL.txt"
  else
    FAILURES=$((FAILURES + 1))
    log "  ✗ $name  (see $WORK/diff.$TOTAL.txt)"
    head -n 20 "$WORK/diff.$TOTAL.txt" | sed 's/^/      /'
  fi
}

# run_both LABEL DIR_BASE DIR_CAND -- ARGS...
# Runs each binary from its own copy of a directory, capturing normalised
# stdout+stderr+exit code into LABEL.out beside it. Exit status is never fatal:
# the two runs are compared, whatever they did.
run_both() {
  local label="$1" dir_base="$2" dir_cand="$3"; shift 3
  [ "$1" = "--" ] && shift
  ( cd "$dir_base" && { "$BASE_BIN" "$@" 2>&1; echo "exit=$?"; } | normalize_text > "$dir_base.$label.out" ) || true
  ( cd "$dir_cand" && { "$CAND_BIN" "$@" 2>&1; echo "exit=$?"; } | normalize_text > "$dir_cand.$label.out" ) || true
}

# Same as run_both but both binaries run in the SAME directory (read-only commands).
run_both_here() {
  local label="$1" dir="$2"; shift 2
  [ "$1" = "--" ] && shift
  ( cd "$dir" && { "$BASE_BIN" "$@" 2>&1; echo "exit=$?"; } | normalize_text > "$WORK/text/$label.base" ) || true
  ( cd "$dir" && { "$CAND_BIN" "$@" 2>&1; echo "exit=$?"; } | normalize_text > "$WORK/text/$label.cand" ) || true
  compare "$label" "$WORK/text/$label.base" "$WORK/text/$label.cand"
}

copy_tree() { rm -rf "$2"; cp -R "$1" "$2"; }

# build_compare NAME SRC_DIR -- BUILD_ARGS...
# Copies SRC_DIR per binary, builds with the given args into out/, then diffs
# both the output and the (possibly cache-mutated) input tree.
build_compare() {
  local name="$1" src="$2"; shift 2
  [ "$1" = "--" ] && shift
  local b="$WORK/build/$name.base" c="$WORK/build/$name.cand"
  copy_tree "$src" "$b"
  copy_tree "$src" "$c"
  run_both build "$b" "$c" -- build -q -o out "$@"
  compare "build:$name" "$b" "$c"
  compare "build:$name (stdout)" "$b.build.out" "$c.build.out"
}

mkdir -p "$WORK/init" "$WORK/build" "$WORK/text" "$WORK/import"

log "work dir: $WORK"
log "base:     $BASE_BIN"
log "cand:     $CAND_BIN"

# ---------------------------------------------------------------- scaffolds
step "scaffold init + build"
SCAFFOLDS="simple bare blog docs book"
if [ "$QUICK" = 1 ]; then
  CONFIG_MODES="default"
  LANG_MODES="mono"
else
  CONFIG_MODES="default minimal full"
  LANG_MODES="mono multi"
fi
for s in $SCAFFOLDS; do
  for cm in $CONFIG_MODES; do
    for lm in $LANG_MODES; do
      key="$s-$cm-$lm"
      args="--scaffold $s --agents local --force"
      case "$cm" in
        minimal) args="$args --minimal-config" ;;
        full) args="$args --full-config" ;;
      esac
      [ "$lm" = multi ] && args="$args --include-multilingual en,ko"
      mkdir -p "$WORK/init/$key.base" "$WORK/init/$key.cand"
      # shellcheck disable=SC2086
      ( cd "$WORK/init" && { "$BASE_BIN" init -q $args "$key.base" 2>&1; echo "exit=$?"; } | normalize_text > "$key.base.init.out" ) || true
      # shellcheck disable=SC2086
      ( cd "$WORK/init" && { "$CAND_BIN" init -q $args "$key.cand" 2>&1; echo "exit=$?"; } | normalize_text > "$key.cand.init.out" ) || true
      compare "init:$key" "$WORK/init/$key.base" "$WORK/init/$key.cand"
      compare "init:$key (stdout)" "$WORK/init/$key.base.init.out" "$WORK/init/$key.cand.init.out"
      # Build from the BASE init tree so build diffs are not polluted by init diffs.
      build_compare "$key" "$WORK/init/$key.base" --
      build_compare "$key-minify" "$WORK/init/$key.base" -- --minify
    done
  done
done

# --------------------------------------------------------------------- docs
step "docs site"
build_compare "docs" "$REPO/docs" --
build_compare "docs-minify" "$REPO/docs" -- --minify

# ------------------------------------------------------------ bench corpus
step "benchmark corpus (count=$COUNT)"
if ( cd "$REPO" && crystal run scripts/benchmark_run.cr -- --generate-only --force --count "$COUNT" --dir "$WORK/bench" > "$WORK/bench.gen.log" 2>&1 ); then
  build_compare "bench" "$WORK/bench" --
  build_compare "bench-minify" "$WORK/bench" -- --minify
  # Warm cache: build twice with --cache from the same copy; the second run
  # exercises the incremental/fingerprint paths.
  b="$WORK/build/bench-cache.base"; c="$WORK/build/bench-cache.cand"
  copy_tree "$WORK/bench" "$b"; copy_tree "$WORK/bench" "$c"
  run_both build1 "$b" "$c" -- build -q -o out --cache
  compare "build:bench-cache cold" "$b" "$c"
  run_both build2 "$b" "$c" -- build -q -o out --cache
  compare "build:bench-cache warm" "$b" "$c"
  compare "build:bench-cache (stdout)" "$b.build2.out" "$c.build2.out"
else
  log "  ! benchmark corpus generation failed (see $WORK/bench.gen.log) — tier skipped"
  FAILURES=$((FAILURES + 1))
fi

# ---------------------------------------------------------------- importers
step "importers"
IMP="$WORK/import/src"
mkdir -p "$IMP"

mkdir -p "$IMP/wordpress"
cat > "$IMP/wordpress/export.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:wp="http://wordpress.org/export/1.2/" xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel>
<title>WP Site</title>
<item>
<title>Hello &amp; Welcome</title>
<link>https://example.com/2024/01/02/hello/</link>
<dc:creator><![CDATA[admin]]></dc:creator>
<wp:post_name><![CDATA[hello]]></wp:post_name>
<wp:post_date><![CDATA[2024-01-02 10:00:00]]></wp:post_date>
<wp:post_type><![CDATA[post]]></wp:post_type>
<wp:status><![CDATA[publish]]></wp:status>
<category domain="category" nicename="news"><![CDATA[News]]></category>
<category domain="post_tag" nicename="intro"><![CDATA[Intro]]></category>
<content:encoded><![CDATA[<p>First <strong>post</strong> with a <a href="https://example.com/x">link</a>.</p>
<ul><li>one</li><li>two</li></ul>
<pre><code class="language-crystal">puts "hi"</code></pre>]]></content:encoded>
</item>
<item>
<title>About</title>
<wp:post_name><![CDATA[about]]></wp:post_name>
<wp:post_date><![CDATA[2024-01-03 10:00:00]]></wp:post_date>
<wp:post_type><![CDATA[page]]></wp:post_type>
<wp:status><![CDATA[publish]]></wp:status>
<content:encoded><![CDATA[<h2>About us</h2><p>Text.</p>]]></content:encoded>
</item>
</channel>
</rss>
EOF

mkdir -p "$IMP/jekyll/_posts/tech" "$IMP/jekyll/_drafts"
cat > "$IMP/jekyll/_config.yml" <<'EOF'
title: Jekyll Site
permalink: /:categories/:year/:month/:day/:title/
EOF
cat > "$IMP/jekyll/_posts/2024-01-02-hello.md" <<'EOF'
---
title: "Hello: World"
date: 2024-01-02 10:00:00 +0900
categories: [news, intro]
tags:
  - a
  - b
excerpt: Short summary
---
Body with {% highlight ruby %}puts 1{% endhighlight %} and {{ site.url }}/x.
EOF
cat > "$IMP/jekyll/_posts/tech/2024-02-03-second.markdown" <<'EOF'
---
layout: post
title: Second
published: true
---
Second body.
EOF
cat > "$IMP/jekyll/_drafts/draft.md" <<'EOF'
---
title: Draft
---
Draft body.
EOF
cat > "$IMP/jekyll/about.md" <<'EOF'
---
title: About
permalink: /about/
---
About body.
EOF

mkdir -p "$IMP/hugo/content/posts/bundle" "$IMP/hugo/static/img"
cat > "$IMP/hugo/config.toml" <<'EOF'
baseURL = "https://example.com/"
title = "Hugo Site"
EOF
cat > "$IMP/hugo/content/_index.md" <<'EOF'
+++
title = "Home"
+++
Welcome.
EOF
cat > "$IMP/hugo/content/posts/first.md" <<'EOF'
+++
title = "First"
date = 2024-01-02T10:00:00+09:00
tags = ["a", "b"]
draft = false
[params]
extra = "x"
+++
Body {{< youtube abc >}} and {{% note %}}n{{% /note %}}.
EOF
cat > "$IMP/hugo/content/posts/bundle/index.md" <<'EOF'
---
title: Bundle
date: 2024-03-04
---
![pic](pic.png)
EOF
printf 'PNG' > "$IMP/hugo/content/posts/bundle/pic.png"

mkdir -p "$IMP/notion/Export/Parent 0123456789abcdef0123456789abcdef"
cat > "$IMP/notion/Export/Parent 0123456789abcdef0123456789abcdef.md" <<'EOF'
# Parent

Created: January 2, 2024 10:00 AM
Tags: a, b

Intro text with a [child](Parent%200123456789abcdef0123456789abcdef/Child%20fedcba9876543210fedcba9876543210.md).
EOF
cat > "$IMP/notion/Export/Parent 0123456789abcdef0123456789abcdef/Child fedcba9876543210fedcba9876543210.md" <<'EOF'
# Child

Child body.
EOF

mkdir -p "$IMP/obsidian/notes" "$IMP/obsidian/attachments"
cat > "$IMP/obsidian/Home.md" <<'EOF'
---
title: Home
aliases: [Start]
tags: [a, b]
---
Link to [[Second Note]] and [[notes/Third|third]] and ![[pic.png]]. #inline-tag
EOF
cat > "$IMP/obsidian/Second Note.md" <<'EOF'
Second body with [[Home]] backlink.
EOF
cat > "$IMP/obsidian/notes/Third.md" <<'EOF'
Third body.
EOF
printf 'PNG' > "$IMP/obsidian/attachments/pic.png"

mkdir -p "$IMP/hexo/source/_posts" "$IMP/hexo/source/_drafts"
cat > "$IMP/hexo/_config.yml" <<'EOF'
title: Hexo Site
EOF
cat > "$IMP/hexo/source/_posts/2024-01-02-hello.md" <<'EOF'
---
title: Hello
date: 2024-01-02 10:00:00
tags: [a, b]
categories:
  - news
---
Intro
<!-- more -->
Body {% asset_img pic.png %} and {% codeblock lang:ruby %}puts 1{% endcodeblock %}.
EOF
cat > "$IMP/hexo/source/_drafts/draft.md" <<'EOF'
---
title: Draft
---
Draft body.
EOF

mkdir -p "$IMP/astro/src/content/blog/bundle" "$IMP/astro/public/images"
cat > "$IMP/astro/src/content/config.ts" <<'EOF'
export const collections = {};
EOF
cat > "$IMP/astro/src/content/blog/first.md" <<'EOF'
---
title: First
pubDate: 2024-01-02
tags: ["a", "b"]
draft: false
---
Body ![img](/images/pic.png).
EOF
cat > "$IMP/astro/src/content/blog/second.mdx" <<'EOF'
---
title: Second
pubDate: 2024-02-03
---
import X from "./X.astro";

<X />
Body.
EOF
cat > "$IMP/astro/src/content/blog/bundle/index.md" <<'EOF'
---
title: Bundle
pubDate: 2024-03-04
---
![pic](./pic.png)
EOF
printf 'PNG' > "$IMP/astro/src/content/blog/bundle/pic.png"
printf 'PNG' > "$IMP/astro/public/images/pic.png"

mkdir -p "$IMP/eleventy/posts" "$IMP/eleventy/_includes"
cat > "$IMP/eleventy/.eleventy.js" <<'EOF'
module.exports = function(cfg) {};
EOF
cat > "$IMP/eleventy/index.md" <<'EOF'
---
title: Home
layout: base.njk
---
Home body.
EOF
cat > "$IMP/eleventy/posts/posts.json" <<'EOF'
{ "tags": ["posts"], "layout": "post.njk" }
EOF
cat > "$IMP/eleventy/posts/first.md" <<'EOF'
---
title: First
date: 2024-01-02
tags: [a]
---
Body {{ page.url }} and {% include "x.njk" %}.
EOF
cat > "$IMP/eleventy/posts/index.md" <<'EOF'
---
title: Posts index
---
Listing.
EOF
cat > "$IMP/eleventy/about.md" <<'EOF'
---
title: About
permalink: /about/
---
About body.
EOF

for fmt in wordpress jekyll hugo notion obsidian hexo astro eleventy; do
  src="$IMP/$fmt"
  [ "$fmt" = wordpress ] && src="$IMP/wordpress/export.xml"
  b="$WORK/import/$fmt.base"; c="$WORK/import/$fmt.cand"
  mkdir -p "$b" "$c"
  ( cd "$b" && { "$BASE_BIN" tool import "$fmt" "$src" -o content --drafts -v 2>&1; echo "exit=$?"; } | normalize_text > "$b.out" ) || true
  ( cd "$c" && { "$CAND_BIN" tool import "$fmt" "$src" -o content --drafts -v 2>&1; echo "exit=$?"; } | normalize_text > "$c.out" ) || true
  compare "import:$fmt" "$b" "$c"
  compare "import:$fmt (stdout)" "$b.out" "$c.out"
done

# ------------------------------------------------------- convert / export
step "convert + export (blog scaffold content)"
BLOG="$WORK/init/blog-default-mono.base"
if [ ! -d "$BLOG" ]; then BLOG="$WORK/init/blog-default-mono.base"; fi
for target in to-yaml to-json to-toml; do
  b="$WORK/build/convert-$target.base"; c="$WORK/build/convert-$target.cand"
  copy_tree "$BLOG" "$b"; copy_tree "$BLOG" "$c"
  run_both convert "$b" "$c" -- tool convert "$target"
  compare "convert:$target" "$b" "$c"
  compare "convert:$target (stdout)" "$b.convert.out" "$c.convert.out"
done
for target in hugo jekyll; do
  b="$WORK/build/export-$target.base"; c="$WORK/build/export-$target.cand"
  copy_tree "$BLOG" "$b"; copy_tree "$BLOG" "$c"
  run_both export "$b" "$c" -- tool export "$target" -o export --drafts -v
  compare "export:$target" "$b" "$c"
  compare "export:$target (stdout)" "$b.export.out" "$c.export.out"
done

# ------------------------------------------------------------ text surfaces
step "text surfaces (--help, --json reports, doctor, validate, new)"
run_both_here "help:root" "$WORK" -- --help
run_both_here "help:version" "$WORK" -- version
for cmd in init build serve new deploy doctor tool completion; do
  run_both_here "help:$cmd" "$WORK" -- "$cmd" --help
done
for sub in convert list check-links doctor platform ci import export stats validate unused-assets agents-md; do
  run_both_here "help:tool-$sub" "$WORK" -- tool "$sub" --help
done
for shell in bash zsh fish; do
  run_both_here "completion:$shell" "$WORK" -- completion "$shell"
done
run_both_here "init:list-scaffolds" "$WORK" -- init --list-scaffolds
run_both_here "init:list-scaffolds-json" "$WORK" -- init --list-scaffolds --json

# Read-only reports on each scaffold (same directory for both binaries).
for s in $SCAFFOLDS; do
  d="$WORK/init/$s-default-mono.base"
  [ -d "$d" ] || continue
  run_both_here "doctor:$s" "$d" -- tool doctor
  run_both_here "doctor-json:$s" "$d" -- tool doctor --json
  run_both_here "list:$s" "$d" -- tool list all --sort path
  run_both_here "list-json:$s" "$d" -- tool list all --json
  run_both_here "stats:$s" "$d" -- tool stats
  run_both_here "stats-json:$s" "$d" -- tool stats --json
  run_both_here "validate:$s" "$d" -- tool validate
  run_both_here "validate-json:$s" "$d" -- tool validate --json
  run_both_here "unused-assets:$s" "$d" -- tool unused-assets
  run_both_here "check-links:$s" "$d" -- tool check-links --internal-only
  run_both_here "deploy-list:$s" "$d" -- deploy --list-targets
done

# Mutating commands on per-binary copies.
for s in blog docs; do
  d="$WORK/init/$s-default-mono.base"
  [ -d "$d" ] || continue
  b="$WORK/build/new-$s.base"; c="$WORK/build/new-$s.cand"
  copy_tree "$d" "$b"; copy_tree "$d" "$c"
  run_both new "$b" "$c" -- new posts/identity-check.md --title "Identity Check" --tags a,b
  compare "new:$s" "$b" "$c"
  compare "new:$s (stdout)" "$b.new.out" "$c.new.out"
  b="$WORK/build/doctor-fix-$s.base"; c="$WORK/build/doctor-fix-$s.cand"
  copy_tree "$d" "$b"; copy_tree "$d" "$c"
  run_both fixdry "$b" "$c" -- tool doctor --full --dry-run
  run_both fix "$b" "$c" -- tool doctor --full
  compare "doctor-fix:$s" "$b" "$c"
  compare "doctor-fix:$s (stdout)" "$b.fix.out" "$c.fix.out"
  compare "doctor-fix:$s (dry-run stdout)" "$b.fixdry.out" "$c.fixdry.out"
  b="$WORK/build/platform-$s.base"; c="$WORK/build/platform-$s.cand"
  copy_tree "$d" "$b"; copy_tree "$d" "$c"
  run_both platform "$b" "$c" -- tool platform github-pages
  run_both ci "$b" "$c" -- tool ci github-actions
  run_both agents "$b" "$c" -- tool agents-md --write --force
  compare "generators:$s" "$b" "$c"
done

# ---------------------------------------------------------------- serve
if [ "$RUN_SERVE" = 1 ]; then
  step "serve (incremental rebuild snapshots)"
  SERVE_SRC="$WORK/init/blog-default-mono.base"
  PORT=$((20000 + RANDOM % 20000))

  serve_sequence() {
    local bin="$1" dir="$2" snaps="$3"
    mkdir -p "$snaps"
    local log="$snaps/serve.log"
    ( cd "$dir" && exec "$bin" serve --port "$PORT" --no-live-reload --no-open > "$log" 2>&1 ) &
    local pid=$!
    local deadline=$((SECONDS + 60))
    until grep -q 'ready url=' "$log" 2>/dev/null; do
      sleep 0.2
      if [ $SECONDS -gt $deadline ] || ! kill -0 $pid 2>/dev/null; then
        echo "serve did not become ready (see $log)" >&2
        kill $pid 2>/dev/null || true
        return 1
      fi
    done
    local out="$dir/.hwaro/serve"
    local first_post
    first_post="$(cd "$dir" && find content -name '*.md' -path '*posts*' ! -name '_index.md' | sort | head -n 1)"
    [ -n "$first_post" ] || first_post="$(cd "$dir" && find content -name '*.md' ! -name '_index.md' | sort | head -n 1)"
    local page_tmpl
    page_tmpl="$(cd "$dir" && ls templates/*.html | head -n 1)"

    wait_for() { # wait_for PATTERN FILE_GLOB_DIR
      local pat="$1" d=$((SECONDS + 30))
      until grep -rq -- "$pat" "$out" 2>/dev/null; do
        sleep 0.2; [ $SECONDS -gt $d ] && { echo "timeout waiting for $pat" >&2; return 1; }
      done
      sleep 0.5
    }
    wait_gone() { # wait_gone FILE
      local f="$1" d=$((SECONDS + 30))
      while [ -e "$f" ]; do
        sleep 0.2; [ $SECONDS -gt $d ] && { echo "timeout waiting for $f to disappear" >&2; return 1; }
      done
      sleep 0.5
    }

    cp -R "$out" "$snaps/0-initial"
    printf '\n\nIDENTITY-MARKER-CONTENT\n' >> "$dir/$first_post"
    wait_for 'IDENTITY-MARKER-CONTENT' && cp -R "$out" "$snaps/1-content"
    printf '\n<!-- IDENTITY-MARKER-TEMPLATE -->\n' >> "$dir/$page_tmpl"
    wait_for 'IDENTITY-MARKER-TEMPLATE' && cp -R "$out" "$snaps/2-template"
    mkdir -p "$dir/static" && printf 'static marker\n' > "$dir/static/identity-marker.txt"
    wait_for 'static marker' && cp -R "$out" "$snaps/3-static"
    local removed_html
    removed_html="$(grep -rl 'IDENTITY-MARKER-CONTENT' "$out" | head -n 1 || true)"
    rm -f "$dir/$first_post"
    if [ -n "$removed_html" ]; then wait_gone "$removed_html"; else sleep 2; fi
    cp -R "$out" "$snaps/4-removed"
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
    normalize_text < "$log" > "$snaps/serve.norm.log"
    rm -f "$log"
  }

  copy_tree "$SERVE_SRC" "$WORK/serve.base"
  copy_tree "$SERVE_SRC" "$WORK/serve.cand"
  if serve_sequence "$BASE_BIN" "$WORK/serve.base" "$WORK/serve-snaps.base" &&
     serve_sequence "$CAND_BIN" "$WORK/serve.cand" "$WORK/serve-snaps.cand"; then
    compare "serve:snapshots" "$WORK/serve-snaps.base" "$WORK/serve-snaps.cand"
  else
    log "  ✗ serve sequence failed"
    FAILURES=$((FAILURES + 1))
  fi
fi

# --------------------------------------------------------------- deploy
if [ "$RUN_DEPLOY" = 1 ]; then
  step "deploy (file:// target)"
  SRC="$WORK/init/blog-default-mono.base"
  for side in base cand; do
    d="$WORK/deploy.$side"
    copy_tree "$SRC" "$d"
    mkdir -p "$WORK/deploy-target.$side"
    cat >> "$d/config.toml" <<EOF

[[deployment.targets]]
name = "local"
url = "file://$WORK/deploy-target.$side"
EOF
  done
  ( cd "$WORK/deploy.base" && "$BASE_BIN" build -q -o public >/dev/null 2>&1 ) || true
  ( cd "$WORK/deploy.cand" && "$CAND_BIN" build -q -o public >/dev/null 2>&1 ) || true
  run_both dry "$WORK/deploy.base" "$WORK/deploy.cand" -- deploy local --dry-run
  run_both dep "$WORK/deploy.base" "$WORK/deploy.cand" -- deploy local
  # Second deploy with a removed file exercises the delete path.
  rm -f "$WORK/deploy.base/public/index.html" "$WORK/deploy.cand/public/index.html"
  run_both dep2 "$WORK/deploy.base" "$WORK/deploy.cand" -- deploy local
  perl -pi -e 's/deploy-target\.(base|cand)/deploy-target.X/g' "$WORK"/deploy.*.out
  compare "deploy:target" "$WORK/deploy-target.base" "$WORK/deploy-target.cand"
  compare "deploy:dry-run stdout" "$WORK/deploy.base.dry.out" "$WORK/deploy.cand.dry.out"
  compare "deploy:stdout" "$WORK/deploy.base.dep.out" "$WORK/deploy.cand.dep.out"
  compare "deploy:second stdout" "$WORK/deploy.base.dep2.out" "$WORK/deploy.cand.dep2.out"
fi

# ---------------------------------------------------------------- summary
printf '\n%s\n' "──────────────────────────────────────────────"
log "byte identity: $PASSED/$TOTAL comparisons identical"
if [ "$FAILURES" -gt 0 ]; then
  log "✗ $FAILURES difference(s) — work dir kept at $WORK"
  exit 1
fi
if [ "$KEEP" = 1 ]; then
  log "✓ identical — work dir kept at $WORK"
else
  rm -rf "$WORK"
  log "✓ identical"
fi
