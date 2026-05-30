alias b := build
alias d := dev
alias vc := version-check
alias vu := version-update

# List available tasks.
default:
    @just --list

# Build hwaro binary.
#
# Always passes `-Dpreview_mt` so dev/CI builds exercise the same
# multi-threaded runtime that release binaries ship with. Without this,
# fiber races stay hidden in dev and only surface for end users.
[group('build')]
build:
    shards install
    shards build -Dpreview_mt

# Update shards.nix.
[group('build')]
nix-update:
    nix-shell -p crystal2nix --run crystal2nix

# Clean build artifacts.
[group('build')]
clean:
    rm -f src/ext/stb_impl.o
    rm -rf bin/
    rm -rf lib/

# Serve docs site with the built binary.
[group('documents')]
dev:
    @[ -f bin/hwaro ] || just build
    bin/hwaro serve -i docs

# Auto-format code and fix lint issues.
[group('development')]
fix:
    crystal tool format
    lib/ameba/bin/ameba.cr --fix

# Check code format and lint without changes.
[group('development')]
check:
    crystal tool format --check
    lib/ameba/bin/ameba.cr

# Run all tests.
[group('development')]
test:
    crystal spec

# Check version consistency across all files.
[group('development')]
version-check:
    crystal run scripts/version_check.cr

# Update version across all files.
[group('development')]
version-update:
    crystal run scripts/version_update.cr

# Test known external hwaro-powered sites ("friends") to prevent regressions.
# This ensures that changes to hwaro don't accidentally break real user sites.
#
# Each friend is defined as "owner/repo" "doc-path"
# Example:
#   "omarluq/termisu" "docs-web"
#   "hahwul/dalfox"   "docs"
[group('development')]
test-friends:
    #!/usr/bin/env bash
    set -euo pipefail

    FRIENDS_DIR=".test_friends"

    # Always clean up the friends directory when the task finishes
    trap 'rm -rf "$FRIENDS_DIR"' EXIT

    # List of known hwaro user repositories and their documentation directories.
    # Format: "owner/repo" "doc-path"
    declare -a friends=(
        "omarluq/termisu docs-web"
        "hahwul/dalfox docs"
        "owasp-noir/noir docs"
    )

    # Ensure we have a built binary
    if [ ! -f "bin/hwaro" ]; then
        echo "Building hwaro binary..."
        just build
    fi

    echo ""
    echo "Testing hwaro friend sites"
    echo "──────────────────────────────────────────────"
    echo ""

    total=${#friends[@]}
    passed=0
    failed=0
    results=()

    for friend in "${friends[@]}"; do
        read -r repo doc_path <<< "$friend"

        echo "▸ $repo → $doc_path"

        repo_name=$(basename "$repo")
        repo_dir="$FRIENDS_DIR/$repo_name"

        # Clone or update repository (shallow clone for speed)
        if [ -d "$repo_dir" ]; then
            git -C "$repo_dir" fetch --depth 1 origin &>/dev/null || true
            if git -C "$repo_dir" show-ref --verify --quiet refs/remotes/origin/main; then
                git -C "$repo_dir" reset --hard origin/main &>/dev/null
            else
                git -C "$repo_dir" reset --hard origin/master &>/dev/null
            fi
        else
            git clone --depth 1 "https://github.com/$repo.git" "$repo_dir" &>/dev/null
        fi

        site_path="$repo_dir/$doc_path"

        if [ ! -d "$site_path" ]; then
            echo "    ✗ Documentation directory not found: $doc_path"
            results+=("✗ $repo ($doc_path) — directory not found")
            ((failed++))
            echo ""
            continue
        fi

        echo "    ... Building..."

        if (cd "$site_path" && ../../../bin/hwaro build -q); then
            echo "    ✓ Build successful"
            results+=("✓ $repo ($doc_path)")
            ((passed++))
        else
            echo "    ✗ Build failed"
            results+=("✗ $repo ($doc_path) — build failed")
            ((failed++))
        fi

        echo ""
    done

    # Pretty summary
    echo "──────────────────────────────────────────────"
    echo "Results ($passed/$total passed)"
    echo ""

    for result in "${results[@]}"; do
        echo "    $result"
    done

    echo ""

    if [ $failed -eq 0 ]; then
        echo "✓ All friend sites build successfully!"
    else
        echo "! $failed friend site(s) failed to build."
        exit 1
    fi


# Generate fresh PNG samples for all OG image styles.
#
# This is extremely useful when modifying the OG renderer
# (src/content/seo/og_png_renderer.cr). Instead of manually
# building the docs site and taking screenshots, just run:
#
#     just og-samples
#
# The generated images will be placed in:
#     docs/static/images/og-style-examples/style-*.png
#
# Generates samples for every style preset, including the bold geometric
# styles (split, band, brutalist).
[group('documents')]
og-samples:
    @[ -f bin/hwaro ] || just build
    ./scripts/generate_og_samples.sh
