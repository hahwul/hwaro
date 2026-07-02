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
#   docs/static/images/scaffolds/scaffold-<name>.png            (1280x800)
#   /tmp/hwaro-scaffold-previews-dark/scaffold-<name>-dark.png  (--dark only)
#
# Sites are served (not opened via file://) because asset URLs are absolute
# against base_url. Requires headless Chrome/Chromium.
set -euo pipefail

if [ ! -f "bin/hwaro" ]; then
    echo "Building hwaro binary..."
    just build
fi

HWARO_BIN="$(pwd)/bin/hwaro"
PROJECT_ROOT="$(pwd)"
OUT_DIR="$PROJECT_ROOT/docs/static/images/scaffolds"
DARK_OUT_DIR="/tmp/hwaro-scaffold-previews-dark"
PORT="${HWARO_PREVIEW_PORT:-3799}"
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

SERVER_PID=""
stop_server() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" >/dev/null 2>&1 || true
        wait "$SERVER_PID" 2>/dev/null || true
        SERVER_PID=""
    fi
}
trap stop_server EXIT

# serve_and_shoot <site-dir> <output-png>
serve_and_shoot() {
    "$HWARO_BIN" serve -p "$PORT" --base-url "http://127.0.0.1:$PORT" -q >/dev/null 2>&1 &
    SERVER_PID=$!
    for _ in $(seq 1 100); do
        curl -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1 && break
        sleep 0.1
    done
    "$CHROME" --headless --disable-gpu --hide-scrollbars \
        --window-size=1280,800 \
        --screenshot="$2" \
        "http://127.0.0.1:$PORT/" >/dev/null 2>&1
    stop_server
}

# Pin the resolved scheme. The scaffolds are auto light+dark
# (color-scheme: light dark), so an unpinned capture would follow the
# machine's OS scheme; the committed previews must be deterministic.
# Appending `dark` is byte-identical to what the *-dark presets ship.
force_scheme() {
    if [ -f "static/css/style.css" ]; then
        printf '\n:root { color-scheme: %s; }\n' "$1" >>static/css/style.css
    elif [ -f "templates/header.html" ]; then
        # simple inlines its CSS — inject the override into the shared head.
        SCHEME="$1" perl -0pi -e 's#</head>#<style>:root { color-scheme: $ENV{SCHEME}; }</style>\n</head>#' templates/header.html
    fi
}

echo ""
echo "Generating scaffold previews (1280x800)..."
echo "──────────────────────────────────────────────"

for scaffold in "${SCAFFOLDS[@]}"; do
    echo -n "  ${scaffold} ... "

    TMP=$(mktemp -d -t hwaro-scaffold-preview-XXXXXX)
    pushd "$TMP" >/dev/null

    "$HWARO_BIN" init . --scaffold "$scaffold" --skip-agents-md -q

    # Light scaffolds are pinned light for the committed shot (a *-dark
    # sheet already ends in a forced-dark rule, so it needs no pin).
    if [[ " ${LIGHT_SCAFFOLDS[*]} " == *" ${scaffold} "* ]]; then
        force_scheme light
    fi
    serve_and_shoot "$TMP" "$OUT_DIR/scaffold-${scaffold}.png"

    if $CAPTURE_DARK && [[ " ${LIGHT_SCAFFOLDS[*]} " == *" ${scaffold} "* ]]; then
        # Appended after the light pin — the later rule wins.
        force_scheme dark
        serve_and_shoot "$TMP" "$DARK_OUT_DIR/scaffold-${scaffold}-dark.png"
    fi

    popd >/dev/null
    rm -rf "$TMP"
    echo "done"
done

echo "──────────────────────────────────────────────"
echo "Previews written to $OUT_DIR"
$CAPTURE_DARK && echo "Dark self-review shots in $DARK_OUT_DIR"
exit 0
