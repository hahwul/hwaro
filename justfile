alias b := build
alias d := dev
alias vc := version-check
alias vu := version-update

# List available tasks.
default:
    @just --list

# Build hwaro binary.
#
# Parallelism comes from Crystal's execution contexts (see src/main.cr),
# not the deprecated `-Dpreview_mt` flag: its legacy MT scheduler spins
# forever at exit under CPU oversubscription and the process never quits.
[group('build')]
build:
    shards install
    shards build

# Update shards.nix. Run this whenever shard.lock changes — the Nix build
# resolves dependencies offline from shards.nix, and CI gates on the two
# agreeing. `nix develop` pins crystal2nix via flake.lock so the output matches
# what CI regenerates.
[group('build')]
nix-update:
    nix develop --command crystal2nix

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

# ameba 1.7 ships no executable, and a cached bin/ameba is much faster than
# recompiling lib/ameba/src/cli.cr on every run.
#
# Build the ameba linter binary.
[group('development')]
ameba:
    @[ -x bin/ameba ] || { [ -d lib/ameba ] || shards install; mkdir -p bin; crystal build lib/ameba/src/cli.cr -o bin/ameba --release; }

# Auto-format code and fix lint issues.
[group('development')]
fix: ameba
    crystal tool format
    bin/ameba --fix

# Check code format and lint without changes.
[group('development')]
check: ameba
    crystal tool format --check
    bin/ameba

# Always ONE `crystal spec` process per cache dir: two concurrent runs sharing
# ~/.cache/crystal clobber each other's spec binary (see AGENTS.md).
#
# Run all tests.
[group('development')]
test:
    crystal spec

#     just test-file spec/unit/models/config_spec.cr
#     just test-file spec/unit/models/config_spec.cr:42
#
# Run one spec file (or file:line) in its own compiler cache, safe alongside `just test`.
[group('development')]
test-file TARGET:
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn-stale-binary
    export CRYSTAL_CACHE_DIR="${CRYSTAL_CACHE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/hwaro-spec.XXXXXX")}"
    crystal spec "{{ TARGET }}"

#     just test-dir spec/unit/assets/sass
#
# Run every spec under a directory (same isolation as test-file).
[group('development')]
test-dir DIR:
    #!/usr/bin/env bash
    set -euo pipefail
    just _warn-stale-binary
    export CRYSTAL_CACHE_DIR="${CRYSTAL_CACHE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/hwaro-spec.XXXXXX")}"
    crystal spec "{{ DIR }}"

# Functional specs spawn bin/hwaro: a stale binary makes them test old code.
[private]
_warn-stale-binary:
    #!/usr/bin/env bash
    if [ ! -x bin/hwaro ]; then
        echo "note: bin/hwaro is not built — functional specs that spawn it will be skipped (run: shards build)" >&2
    elif [ -n "$(find src -newer bin/hwaro -name '*.cr' -print -quit)" ]; then
        echo "warning: bin/hwaro is older than src/ — functional specs will run the OLD binary (run: shards build)" >&2
    fi

#     just baseline            # → ../hwaro-baseline/bin/hwaro
#     just baseline v0.20.1    # any ref
#
# Build a baseline hwaro binary from a ref (default main) in ../hwaro-baseline for byte-identity checks.
[group('development')]
baseline REF="main":
    #!/usr/bin/env bash
    set -euo pipefail
    dir="$(dirname "$PWD")/hwaro-baseline"
    if [ -d "$dir" ]; then
        git -C "$dir" checkout --detach "{{ REF }}"
    else
        git worktree add --detach "$dir" "{{ REF }}"
    fi
    [ -e "$dir/lib" ] || ln -s "$PWD/lib" "$dir/lib"
    (cd "$dir" && shards build)
    echo "baseline: $dir/bin/hwaro"

#     just verify
#     just verify --serve --deploy
#
# Byte-identity gate: diff -r everything the baseline and current binaries produce (args → script).
[group('development')]
verify *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    base="${HWARO_BASELINE_BIN:-$(dirname "$PWD")/hwaro-baseline/bin/hwaro}"
    [ -x "$base" ] || { echo "no baseline binary at $base — run: just baseline" >&2; exit 1; }
    shards build
    scripts/check_no_toplevel_effects.sh
    scripts/verify_byte_identity.sh "$base" bin/hwaro {{ ARGS }}

# Check version consistency across all files.
[group('development')]
version-check:
    crystal run scripts/version_check.cr

# Update version across all files.
[group('development')]
version-update:
    crystal run scripts/version_update.cr

# Merge changelog.d/*.md fragments into CHANGELOG.md's Unreleased section
# (pass --check to validate without merging).
[group('development')]
changelog *ARGS:
    crystal run scripts/changelog_assemble.cr -- {{ ARGS }}

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
        "chei-l/chei-l.github.io ."
    )

    # Ensure we have a built binary
    if [ ! -f "bin/hwaro" ]; then
        echo "Building hwaro binary..."
        just build
    fi

    # Absolute path to the binary, resolved once from the project root.
    # Using an absolute path keeps the build step independent of how deep
    # a friend's doc-path is — including "." when the repo root *is* the site.
    HWARO_BIN="$PWD/bin/hwaro"

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

        if (cd "$site_path" && "$HWARO_BIN" build -q); then
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

# Regenerate the scaffold preview screenshots for the docs.
#
# Builds each built-in scaffold into a temp dir and captures a 1280x800
# headless-Chrome screenshot of its homepage.
#
#     just scaffold-previews
#
# The generated images will be placed in:
#     docs/static/images/scaffolds/scaffold-*.png
#
# Pass DARK=1 to also capture forced-dark self-review shots of the light
# scaffolds into /tmp/hwaro-scaffold-previews-dark (not committed).
[group('documents')]
scaffold-previews:
    @[ -f bin/hwaro ] || just build
    ./scripts/generate_scaffold_previews.sh {{ if env("DARK", "") == "1" { "--dark" } else { "" } }}

# Regenerate the `background_image` preview samples for the docs.
#
# These demonstrate how `overlay_opacity` dims a real background photo,
# using the same photo/style across three overlay values.
#
#     just og-bg-samples
#
# The generated images will be placed in:
#     docs/static/images/og-style-examples/bg-image-{low,mid,high}.png
[group('documents')]
og-bg-samples:
    @[ -f bin/hwaro ] || just build
    ./scripts/generate_og_bg_examples.sh
