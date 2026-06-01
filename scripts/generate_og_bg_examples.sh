#!/usr/bin/env bash
#
# Generate PNG samples that demonstrate the OG `background_image` option.
#
# The same photo, style, and (near-black) background color are used for every
# sample — only `overlay_opacity` changes — so the previews show how the overlay
# dims the photo to keep the title readable.
#
# Usage:
#   ./scripts/generate_og_bg_examples.sh
#
# Output:
#   docs/static/images/og-style-examples/bg-image-{low,mid,high}.png
#
set -euo pipefail

if [ ! -f "bin/hwaro" ]; then
    echo "Building hwaro binary..."
    just build
fi

HWARO_BIN="$(pwd)/bin/hwaro"
PROJECT_ROOT="$(pwd)"
OUT_DIR="$PROJECT_ROOT/docs/static/images/og-style-examples"
# stb_image (used for PNG output) can't decode WebP, so derive a PNG from the
# committed, on-brand background photo.
BG_WEBP="$PROJECT_ROOT/docs/static/images/hwaro-minecraft.webp"
BG_PNG="$(mktemp -t hwaro-og-bg-src-XXXXXX).png"

if [ ! -f "$BG_WEBP" ]; then
    echo "✗ Background photo not found: $BG_WEBP" >&2
    exit 1
fi

# Convert WebP -> PNG with whatever is available on the system.
if command -v sips >/dev/null 2>&1; then
    sips -s format png "$BG_WEBP" --out "$BG_PNG" >/dev/null 2>&1
elif command -v magick >/dev/null 2>&1; then
    magick "$BG_WEBP" "$BG_PNG"
elif command -v convert >/dev/null 2>&1; then
    convert "$BG_WEBP" "$BG_PNG"
elif command -v dwebp >/dev/null 2>&1; then
    dwebp "$BG_WEBP" -o "$BG_PNG" >/dev/null 2>&1
else
    echo "✗ Need one of: sips, magick, convert, or dwebp to convert WebP -> PNG." >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

echo ""
echo "Generating OG background_image samples..."
echo "──────────────────────────────────────────────"

# name  overlay_opacity  caption
SAMPLES=(
    "low|0.30"
    "mid|0.55"
    "high|0.80"
)

for entry in "${SAMPLES[@]}"; do
    NAME="${entry%%|*}"
    OVERLAY="${entry##*|}"
    echo -n "  overlay_opacity=${OVERLAY} ... "

    TMP=$(mktemp -d -t hwaro-og-bg-XXXXXX)
    pushd "$TMP" >/dev/null

    "$HWARO_BIN" init . --scaffold bare --skip-agents-md --skip-sample-content -q 2>/dev/null || true
    mkdir -p static
    cp "$BG_PNG" static/og-bg.png

    cat > config.toml <<EOF
title = "Hwaro"
base_url = "https://hwaro.dev"
description = "A fast and lightweight static site generator written in Crystal."

[og.auto_image]
enabled = true
style = "editorial"
background = "#0c0a08"
accent_color = "#ffb347"
text_color = "#ffffff"
font_size = 60
show_title = true
format = "png"
output_dir = "og-images"
background_image = "static/og-bg.png"
overlay_opacity = ${OVERLAY}
EOF

    cat > content/index.md <<'EOPAGE'
+++
title = "Lighting the Furnace"
description = "A custom photo sits behind the text, dimmed by a color overlay so the title stays readable."
+++

Sample page demonstrating a real background image.
EOPAGE

    "$HWARO_BIN" build -q >/dev/null 2>&1 || true
    GENERATED=$(find public/og-images -name "*.png" 2>/dev/null | head -1 || true)

    if [ -n "$GENERATED" ] && [ -f "$GENERATED" ]; then
        cp "$GENERATED" "$OUT_DIR/bg-image-${NAME}.png"
        echo "✓ -> bg-image-${NAME}.png"
    else
        echo "✗ (no image generated)"
    fi

    popd >/dev/null
    rm -rf "$TMP"
done

rm -f "$BG_PNG"

echo ""
echo "Samples saved to $OUT_DIR/"
echo "You can now review and commit the updated PNG previews."
