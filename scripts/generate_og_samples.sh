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

STYLES=("default" "editorial" "framed" "artistic" "hero" "surreal" "monument" "split" "band" "brutalist" "minimal" "gradient" "waves")
MODERN_STYLES=("editorial" "framed" "artistic" "hero" "surreal" "monument" "split" "band" "brutalist")

mkdir -p "$OUT_DIR"

for style in "${STYLES[@]}"; do
    echo -n "  ${style} ... "

    TMP=$(mktemp -d -t hwaro-og-sample-XXXXXX)
    pushd "$TMP" >/dev/null

    # For modern/ambitious styles, use a richer base so previews look more realistic
    if [[ " ${MODERN_STYLES[*]} " =~ " ${style} " ]]; then
        "$HWARO_BIN" init . --scaffold docs --skip-agents-md --skip-sample-content -q 2>/dev/null || true
    else
        "$HWARO_BIN" init . --scaffold bare --skip-agents-md --skip-sample-content -q 2>/dev/null || true
    fi

    # Prepare assets for rich samples
    mkdir -p static/images

    # Per-style background and settings to make the samples visually distinct and modern
    TEXT="#ffffff"
    SECONDARY=""
    SHOW_TITLE="false"
    case "${style}" in
        artistic)
            # Use the custom image the user provided from ~/Downloads
            BG="#2a2a35"
            ACCENT="#c4b5fd"
            TEXT_PANEL="0.05"   # Very low so the custom background shows clearly
            FONT_SIZE="62"
            OVERLAY="0.00"      # No overlay

            # Use the user's custom artistic background image (highest priority)
            CUSTOM_BG="$HOME/Downloads/afb89274-cfaa-43a0-b555-d9ab9f93f77e.jpg"
            if [ -f "$CUSTOM_BG" ]; then
                cp "$CUSTOM_BG" static/images/artistic-bg.jpg
                BG_IMAGE="static/images/artistic-bg.jpg"
                echo " (using custom artistic background)"
            else
                echo " (warning: custom image not found, using fallback)"
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
        split)
            BG="#10131c"
            ACCENT="#ff3b6b"
            TEXT_PANEL="0.0"
            FONT_SIZE="58"
            SHOW_TITLE="true"   # site name fills the color block
            ;;
        band)
            BG="#0e1116"
            ACCENT="#ffd23f"
            TEXT_PANEL="0.0"
            FONT_SIZE="60"
            SHOW_TITLE="true"
            ;;
        brutalist)
            BG="#f6f1e7"
            ACCENT="#161616"
            TEXT="#161616"
            SECONDARY="#ff5b2e"
            TEXT_PANEL="0.0"
            FONT_SIZE="78"
            SHOW_TITLE="true"
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
        echo "text_color = \"${TEXT}\""
        if [ -n "${SECONDARY:-}" ]; then
            echo "secondary_color = \"${SECONDARY}\""
        fi
        echo "font_size = ${FONT_SIZE}"
        echo "show_title = ${SHOW_TITLE}"
        echo 'format = "png"'
        echo 'output_dir = "og-images"'

        if [ -n "${BG_IMAGE:-}" ]; then
            echo "background_image = \"${BG_IMAGE}\""
            echo "overlay_opacity = ${OVERLAY:-0.55}"
        fi
    } > config.toml

    # Create richer sample content for modern styles
    if [[ " ${MODERN_STYLES[*]} " =~ " ${style} " ]]; then
        case "${style}" in
            artistic)
                TITLE="Winter '26"
                DESC="High-production design for ambitious brands. Rich backgrounds meet confident typography."
                ;;
            hero)
                TITLE="THE DROP"
                DESC="Limited drop. Bold design for those who move first."
                ;;
            surreal)
                TITLE="Echo Chamber"
                DESC="Where form dissolves and meaning multiplies."
                ;;
            monument)
                TITLE="SILENCE"
                DESC="A statement in negative space."
                ;;
            framed)
                TITLE="Boundary"
                DESC="Clear separation. Modern presence on complex backgrounds."
                ;;
            editorial)
                TITLE="Field Notes"
                DESC="Thoughtful writing deserves thoughtful presentation."
                ;;
            split)
                TITLE="A Field Guide to Bold Layouts"
                DESC="A diagonal color block anchors the whole composition."
                ;;
            band)
                TITLE="Cover Story"
                DESC="A magazine-style color band behind a knocked-out title."
                ;;
            brutalist)
                TITLE="Raw & Loud"
                DESC="Thick frames, hard shadows, and oversized type."
                ;;
        esac
    else
        TITLE="OG Sample"
        DESC="Preview image for style: ${style}"
    fi

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