#!/bin/bash
set -e
set -o pipefail

# Detect if running in GitHub Actions environment
# If not in GitHub Actions, pass through to hwaro CLI
if [[ -z "$GITHUB_ACTIONS" ]]; then
    exec hwaro "$@"
fi

# ========================================
# GitHub Actions Mode
# ========================================

# Default values
PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"
BUILD_DIR="${BUILD_DIR:-.}"
OUT_DIR="${OUT_DIR:-public}"
BUILD_ONLY="${BUILD_ONLY:-false}"
GITHUB_HOSTNAME="${GITHUB_HOSTNAME:-github.com}"

if [[ -n "$REPOSITORY" ]]; then
    TARGET_REPOSITORY=$REPOSITORY
else
    if [[ -z "$GITHUB_REPOSITORY" ]]; then
        echo "Set the GITHUB_REPOSITORY env variable."
        exit 1
    fi
    TARGET_REPOSITORY=${GITHUB_REPOSITORY}
fi

# Support both INPUT_TOKEN (from action inputs) and GITHUB_TOKEN
if [[ -n "$INPUT_TOKEN" ]]; then
    GITHUB_TOKEN=$INPUT_TOKEN
fi

if [[ -z "$GITHUB_TOKEN" ]] && [[ "$BUILD_ONLY" == "false" ]]; then
    echo "Error: GITHUB_TOKEN is required for deployment."
    echo "Please set the token input or GITHUB_TOKEN environment variable."
    exit 1
fi

restore_og_cache() {
    local remote_url="https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@${GITHUB_HOSTNAME}/${TARGET_REPOSITORY}.git"
    local og_dir="${OUT_DIR}/og-images"

    # Check if gh-pages branch exists on remote
    if ! git ls-remote --exit-code --heads "${remote_url}" "${PAGES_BRANCH}" &>/dev/null; then
        echo "No ${PAGES_BRANCH} branch found, skipping OG image cache restore"
        return 0
    fi

    echo "Restoring OG image cache from ${PAGES_BRANCH}..."

    local tmp_dir
    tmp_dir=$(mktemp -d)

    git clone --depth 1 --branch "${PAGES_BRANCH}" --filter=blob:none --sparse \
        "${remote_url}" "$tmp_dir" 2>/dev/null || {
        echo "Failed to clone ${PAGES_BRANCH}, skipping cache"
        rm -rf "$tmp_dir"
        return 0
    }

    (cd "$tmp_dir" && git sparse-checkout set og-images 2>/dev/null) || {
        rm -rf "$tmp_dir"
        return 0
    }

    if [ -d "$tmp_dir/og-images" ]; then
        mkdir -p "$og_dir"
        cp -a "$tmp_dir/og-images/." "$og_dir/"
        local count
        count=$(find "$og_dir" -type f \( -name '*.png' -o -name '*.svg' \) | wc -l)
        echo "Restored ${count} cached OG images"
    fi

    rm -rf "$tmp_dir"
}

main() {
    echo "🔥 Starting Hwaro build..."

    echo "Building in $BUILD_DIR directory"
    cd "$BUILD_DIR"

    # Disable safe directory check to avoid dubious ownership error
    git config --global --add safe.directory "*"
    git config --global init.defaultBranch "gh_action"

    # Clear credential helpers that may have been set by actions/checkout (v6+)
    # This prevents exit code 128 when $RUNNER_TEMP is not mounted in the container
    # Safe because we authenticate via token in the remote URL
    git config --global --unset-all credential.helper 2>/dev/null || true
    git config --global --unset-all http.extraheader 2>/dev/null || true

    # Restore OG image cache before building (requires token for remote access)
    if [[ "$BUILD_ONLY" != "true" ]] && [[ -n "$GITHUB_TOKEN" ]]; then
        restore_og_cache
    fi

    # Show hwaro version
    version=$(hwaro --version)
    echo "Using $version"

    # Enable cache mode to preserve restored OG images
    if [[ -n "$BUILD_FLAGS" ]]; then
        BUILD_FLAGS="--cache $BUILD_FLAGS"
    else
        BUILD_FLAGS="--cache"
    fi

    # Build the site
    echo "Building with flags: ${BUILD_FLAGS:-(none)}"
    hwaro build $BUILD_FLAGS

    if [[ "$BUILD_ONLY" == "true" ]]; then
        echo "✅ Build complete. Deployment skipped by request."
        exit 0
    fi

    # Deploy to GitHub Pages
    echo "Pushing artifacts to ${TARGET_REPOSITORY}:${PAGES_BRANCH}"

    remote_repo="https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@${GITHUB_HOSTNAME}/${TARGET_REPOSITORY}.git"
    remote_branch=$PAGES_BRANCH

    cd "${OUT_DIR}"

    # Create .nojekyll to bypass Jekyll processing
    touch .nojekyll

    git init
    git config user.name "GitHub Actions"
    git config user.email "github-actions-bot@users.noreply.${GITHUB_HOSTNAME}"
    git add .

    git commit -q -m "Deploy ${TARGET_REPOSITORY} to ${TARGET_REPOSITORY}:${remote_branch}"
    git push --force "${remote_repo}" gh_action:"${remote_branch}"

    echo "🚀 Deploy complete!"
}

main "$@"
