#!/usr/bin/env bash
#
# Generate fresh PNG previews of every built-in scaffold for the docs
# (docs/content/start/first-site.md embeds them).
#
# Usage:
#   ./scripts/generate_scaffold_previews.sh            # regenerate the 8 committed previews
#   ./scripts/generate_scaffold_previews.sh --dark     # ALSO capture forced-dark shots of the
#                                                      # light scaffolds into a review dir
#                                                      # (not committed — design self-review)
#
# Output:
#   docs/static/images/scaffolds/scaffold-<name>.png          (1280x800)
#   /tmp/hwaro-scaffold-previews-dark/scaffold-<name>-dark.png  (--dark only)
#
# Requires headless Chrome/Chromium on PATH (google-chrome, chromium, or
# the macOS Google Chrome app bundle).
set -euo pipefail

if [ ! -f "bin/hwaro" ]; then
    echo "Building hwaro binary..."
    just build
fi

HWARO_BIN="$(pwd)/bin/hwaro"
PROJECT_ROOT="$(pwd)"
OUT_DIR="$PROJECT_ROOT/docs/static/images/scaffolds"
DARK_OUT_DIR="/tmp/hwaro-scaffold-previews-dark"
CAPTURE_DARK=false
[ "${1:-}" = "--dark" ] && CAPTURE_DARK=true

# Locate a headless-capable Chrome.
find_chrome() {
    for candidate in google-chrome chromium chromium-browser; do
        if command -v "$candidate" >/dev/null 2>&1; then
            echo "$candidate"
            return
        fi
    done
    local mac_chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if [ -x "$mac_chrome" ]; then
        echo "$mac_chrome"
        return
    fi
    echo ""
}

CHROME="$(find_chrome)"
if [ -z "$CHROME" ]; then
    echo "error: no Chrome/Chromium found for headless screenshots" >&2
    exit 1
fi

SCAFFOLDS=(simple bare blog blog-dark docs docs-dark book book-dark)
LIGHT_SCAFFOLDS=(simple blog docs book)

mkdir -p "$OUT_DIR"
$CAPTURE_DARK && mkdir -p "$DARK_OUT_DIR"

shoot() {
    # shoot <built-site-dir> <output-png>
    "$CHROME" --headless --disable-gpu --hide-scrollbars \
        --window-size=1280,800 \
        --screenshot="$2" \
        "file://$1/index.html" >/dev/null 2>&1
}

echo ""
echo "Generating scaffold previews (1280x800)..."
echo "──────────────────────────────────────────────"

for scaffold in "${SCAFFOLDS[@]}"; do
    echo -n "  ${scaffold} ... "

    TMP=$(mktemp -d -t hwaro-scaffold-preview-XXXXXX)
    pushd "$TMP" >/dev/null

    "$HWARO_BIN" init . --scaffold "$scaffold" --skip-agents-md -q
    "$HWARO_BIN" build -q

    shoot "$TMP/public" "$OUT_DIR/scaffold-${scaffold}.png"

    # Forced-dark self-review shot: appending the same rule the *-dark
    # presets ship flips every light-dark() token, byte-identical to the
    # preset mechanism.
    if $CAPTURE_DARK && [[ " ${LIGHT_SCAFFOLDS[*]} " == *" ${scaffold} "* ]]; then
        if [ -f "$TMP/public/css/style.css" ]; then
            printf '\n:root { color-scheme: dark; }\n' >>"$TMP/public/css/style.css"
        else
            # simple inlines its CSS — inject the override into the page head.
            find "$TMP/public" -name "*.html" -exec \
                perl -0pi -e 's#</head>#<style>:root { color-scheme: dark; }</style></head>#' {} +
        fi
        shoot "$TMP/public" "$DARK_OUT_DIR/scaffold-${scaffold}-dark.png"
    fi

    popd >/dev/null
    rm -rf "$TMP"
    echo "done"
done

echo "──────────────────────────────────────────────"
echo "Previews written to $OUT_DIR"
$CAPTURE_DARK && echo "Dark self-review shots in $DARK_OUT_DIR"
