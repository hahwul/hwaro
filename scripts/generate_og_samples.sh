#!/usr/bin/env bash
#
# Generate fresh PNG samples for OG image styles.
#
# Usage:
#   ./scripts/generate_og_samples.sh
#
# Output:
#   docs/static/images/og-style-examples/style-*.png
#
set -euo pipefail

if [ ! -f "bin/hwaro" ]; then
    echo "Building hwaro binary..."
    just build
fi

HWARO_BIN="$(pwd)/bin/hwaro"
PROJECT_ROOT="$(pwd)"
OUT_DIR="$PROJECT_ROOT/docs/static/images/og-style-examples"

echo ""
echo "Generating OG image style samples..."
echo "──────────────────────────────────────────────"

STYLES=("default" "editorial" "framed" "artistic" "hero" "surreal" "monument" "split" "band" "brutalist" "terminal" "bauhaus" "halftone" "minimal" "gradient" "waves" "dots" "grid" "diagonal")

mkdir -p "$OUT_DIR"

for style in "${STYLES[@]}"; do
    echo -n "  ${style} ... "

    TMP=$(mktemp -d -t hwaro-og-sample-XXXXXX)
    pushd "$TMP" >/dev/null

    "$HWARO_BIN" init . --scaffold bare --skip-agents-md --skip-sample-content -q 2>/dev/null || true

    # Curated per-style palette + copy so every preview shows the style at
    # its best. No AI-purple defaults; hues stay in each style's family.
    TEXT="#f4ede4"
    SECONDARY=""
    case "${style}" in
        default)
            BG="#171310"; ACCENT="#ec7a66"
            TITLE="Make It Yours"
            DESC="Every page ships with a handsome preview. Zero config."
            ;;
        minimal)
            BG="#101013"; ACCENT="#ec7a66"; TEXT="#f2f0ec"
            TITLE="Less, but better"
            DESC="One accent. Nothing else."
            ;;
        dots)
            BG="#0f1417"; ACCENT="#4cc9f0"; TEXT="#edf3f6"
            TITLE="Signal in the Noise"
            DESC="A halftone fade that points at the headline."
            ;;
        grid)
            BG="#101014"; ACCENT="#ffb703"; TEXT="#f3f1ec"
            TITLE="Built on a Grid"
            DESC="Blueprint lines you can actually see."
            ;;
        diagonal)
            BG="#15100e"; ACCENT="#ff7a45"
            TITLE="Cut to the Chase"
            DESC="A corner of momentum."
            ;;
        gradient)
            BG="#141216"; ACCENT="#e85d75"; TEXT="#f5eff1"
            TITLE="Warm Front"
            DESC="A duotone wash with real depth."
            ;;
        waves)
            BG="#0d1420"; ACCENT="#38bdf8"; TEXT="#ebf2f8"
            TITLE="Below the Fold"
            DESC="Layered tides, calm typography."
            ;;
        editorial)
            BG="#14141b"; ACCENT="#ff4d6d"; TEXT="#f2f1f4"
            TITLE="Field Notes"
            DESC="Thoughtful writing deserves thoughtful presentation."
            ;;
        framed)
            BG="#14141b"; ACCENT="#e2c044"; TEXT="#f2f1f4"
            TITLE="Boundary"
            DESC="A quiet frame and four corners."
            ;;
        monument)
            BG="#0f0f11"; ACCENT="#e0e0e0"; TEXT="#f1f1f2"
            TITLE="SILENCE"
            DESC="A statement in negative space."
            ;;
        artistic)
            BG="#1c1210"; ACCENT="#ff6b5e"; SECONDARY="#2ec4b6"
            TITLE="Winter '26"
            DESC="High-production design for ambitious brands."
            ;;
        hero)
            BG="#0a0a0e"; ACCENT="#ff2d55"; TEXT="#f4f2f3"
            TITLE="THE DROP"
            DESC="Bold design for those who move first."
            ;;
        surreal)
            BG="#0e1216"; ACCENT="#ff8c66"; SECONDARY="#5eead4"; TEXT="#eff3f4"
            TITLE="Echo Chamber"
            DESC="Where form dissolves and meaning multiplies."
            ;;
        split)
            BG="#10131c"; ACCENT="#ff3b6b"; TEXT="#f3f1f2"
            TITLE="A Field Guide to Bold Layouts"
            DESC="A diagonal color block anchors the whole composition."
            ;;
        band)
            BG="#0e1116"; ACCENT="#ffd23f"; TEXT="#f2f2ee"
            TITLE="Cover Story"
            DESC="A magazine-style color band behind a knocked-out title."
            ;;
        brutalist)
            BG="#f6f1e7"; ACCENT="#161616"; TEXT="#161616"; SECONDARY="#ff5b2e"
            TITLE="Raw & Loud"
            DESC="Thick frames, hard shadows, and oversized type."
            ;;
        terminal)
            BG="#0d1117"; ACCENT="#2ee66b"; TEXT="#e9eef4"
            TITLE="hwaro serve --fast-start"
            DESC="Your dev server, rendered like it deserves."
            ;;
        bauhaus)
            BG="#f4f1ea"; ACCENT="#e8453c"; TEXT="#18181b"; SECONDARY="#2563eb"
            TITLE="Form Follows Function"
            DESC="Geometry, color, and type in balance."
            ;;
        halftone)
            BG="#0e0e11"; ACCENT="#ff2e88"; TEXT="#f3f0f2"
            TITLE="Print Isn't Dead"
            DESC="Halftone texture straight from the press."
            ;;
        *)
            BG="#171310"; ACCENT="#ec7a66"
            TITLE="OG Sample"
            DESC="Preview image for style: ${style}"
            ;;
    esac

    # Override config with our desired OG settings for preview. Font size
    # is left at the default — every style self-sizes its typography.
    {
        echo 'title = "Hwaro"'
        echo 'base_url = "https://hwaro.dev"'
        echo 'description = "A fast and lightweight static site generator written in Crystal."'
        echo ''
        echo '[og.auto_image]'
        echo 'enabled = true'
        echo "style = \"${style}\""
        echo "background = \"${BG}\""
        echo "accent_color = \"${ACCENT}\""
        echo "text_color = \"${TEXT}\""
        if [ -n "${SECONDARY:-}" ]; then
            echo "secondary_color = \"${SECONDARY}\""
        fi
        echo 'show_title = true'
        echo 'format = "png"'
        echo 'output_dir = "og-images"'
    } > config.toml

    cat > content/index.md <<EOPAGE
+++
title = "${TITLE}"
description = "${DESC}"
+++

This is a sample page used to demonstrate the "${style}" OG image style.
EOPAGE

    BUILD_LOG=$("$HWARO_BIN" build -q 2>&1)
    BUILD_STATUS=$?

    # Find the generated OG image (PNG)
    GENERATED=$(find public -name "*.png" -path "*og*" 2>/dev/null | head -1 || true)

    if [ -n "$GENERATED" ] && [ -f "$GENERATED" ]; then
        cp "$GENERATED" "$OUT_DIR/style-${style}.png"
        echo "✓"
    else
        echo "✗ (no image generated)"
        if [ $BUILD_STATUS -ne 0 ]; then
            echo "    Build failed. Last lines:"
            echo "$BUILD_LOG" | tail -5 | sed 's/^/    /'
        else
            echo "    Build succeeded but no OG PNG found in public/og-images/"
            echo "    Contents of public/:"
            find public -type f 2>/dev/null | head -20 | sed 's/^/    /'
        fi
    fi

    popd >/dev/null
    rm -rf "$TMP"
done

echo ""
echo "Samples saved to $OUT_DIR/"
echo "You can now review and commit the updated PNG previews."
