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

STYLES=("default" "editorial" "framed" "artistic" "hero" "surreal" "monument" "minimal" "gradient" "waves")

mkdir -p "$OUT_DIR"

for style in "${STYLES[@]}"; do
    echo -n "  ${style} ... "

    TMP=$(mktemp -d -t hwaro-og-sample-XXXXXX)
    pushd "$TMP" >/dev/null

    # Initialize a bare project (gives us minimal working templates)
    "$HWARO_BIN" init . --scaffold bare --skip-agents-md --skip-sample-content -q 2>/dev/null || true

    # Prepare assets for rich samples
    mkdir -p static/images

    # Per-style background and settings to make the samples visually distinct and modern
    case "${style}" in
        artistic)
            # Use the custom image the user provided from ~/Downloads
            BG="#2a2a35"
            ACCENT="#c4b5fd"
            TEXT_PANEL="0.05"   # Very low so the custom background shows clearly
            FONT_SIZE="62"
            OVERLAY="0.00"      # No overlay

            # Try the exact custom JPEG first
            CUSTOM_BG="$HOME/Downloads/afb89274-cfaa-43a0-b555-d9ab9f93f77e.jpg"
            if [ -f "$CUSTOM_BG" ]; then
                cp "$CUSTOM_BG" static/images/artistic-bg.jpg
                BG_IMAGE="static/images/artistic-bg.jpg"
                echo " (using custom image from ~/Downloads as artistic background)"
            else
                echo " (warning: custom image not found at $CUSTOM_BG, falling back)"
                # Fallback to local style preview if custom image missing
                if [ -f "$PROJECT_ROOT/docs/static/images/og-style-examples/style-waves.png" ]; then
                    cp "$PROJECT_ROOT/docs/static/images/og-style-examples/style-waves.png" static/images/artistic-bg.png
                    BG_IMAGE="static/images/artistic-bg.png"
                else
                    BG_IMAGE=""
                fi
            fi
            ;;
        hero)
            BG="#0a0a0e"
            ACCENT="#ff2d55"
            TEXT_PANEL="0.82"
            FONT_SIZE="72"
            OVERLAY="0.00"
            ;;
        surreal)
            BG="#0c0818"
            ACCENT="#c084fc"
            TEXT_PANEL="0.85"
            FONT_SIZE="56"
            OVERLAY="0.15"
            ;;
        monument)
            BG="#0f0f11"
            ACCENT="#e0e0e0"
            TEXT_PANEL="0.72"
            FONT_SIZE="82"
            OVERLAY="0.00"
            ;;
        framed)
            BG="#22222b"
            ACCENT="#fda4af"
            TEXT_PANEL="0.58"
            FONT_SIZE="56"
            ;;
        editorial)
            BG="#1a1a1f"
            ACCENT="#ff4d6d"
            TEXT_PANEL="0.38"
            FONT_SIZE="52"
            ;;
        *)
            BG="#0f0f12"
            ACCENT="#ff4d6d"
            TEXT_PANEL="0.0"
            FONT_SIZE="48"
            ;;
    esac

    # Override config with our desired OG settings for preview
    {
        echo 'title = "Hwaro"'
        echo 'base_url = "https://hwaro.dev"'
        echo 'description = "A fast and lightweight static site generator written in Crystal."'
        echo ''
        echo '[og.auto_image]'
        echo 'enabled = true'
        echo "style = \"${style}\""
        echo "text_panel = ${TEXT_PANEL}"
        echo "background = \"${BG}\""
        echo "accent_color = \"${ACCENT}\""
        echo 'text_color = "#ffffff"'
        echo "font_size = ${FONT_SIZE}"
        echo 'show_title = false'
        echo 'format = "png"'
        echo 'output_dir = "og-images"'

        if [ -n "${BG_IMAGE:-}" ]; then
            echo "background_image = \"${BG_IMAGE}\""
            echo "overlay_opacity = ${OVERLAY:-0.55}"
        fi
    } > config.toml

    # Nice sample page for preview (tailored per style)
    case "${style}" in
        artistic)
            TITLE="Winter '26"
            DESC="High-production design for ambitious brands. Rich backgrounds, confident typography."
            ;;
        hero)
            TITLE="THE DROP"
            DESC=""
            ;;
        surreal)
            TITLE="Echoes"
            DESC="Where reality bends and design becomes myth."
            ;;
        monument)
            TITLE="VOID"
            DESC=""
            ;;
        framed)
            TITLE="The Frame"
            DESC="Clear content separation with modern card treatment on artistic backgrounds."
            ;;
        editorial)
            TITLE="Editorial"
            DESC="Clean, generous, and harmonious. The modern default for thoughtful brands."
            ;;
        *)
            TITLE="OG Sample"
            DESC="Preview image for style: ${style}"
            ;;
    esac

    cat > content/index.md <<EOPAGE
+++
title = "${TITLE}"
description = "${DESC}"
+++

Sample content for OG image style previews.
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