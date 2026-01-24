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

main() {
    echo "🔥 Starting Hwaro build..."

    echo "Building in $BUILD_DIR directory"
    cd "$BUILD_DIR"

    # Disable safe directory check to avoid dubious ownership error
    git config --global --add safe.directory "*"
    git config --global init.defaultBranch "gh_action"

    # Show hwaro version
    version=$(hwaro --version)
    echo "Using $version"

    # Build the site
    echo "Building with flags: ${BUILD_FLAGS:-(none)}"
    if [[ -n "$BUILD_FLAGS" ]]; then
        hwaro build $BUILD_FLAGS
    else
        hwaro build
    fi

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

    git commit -m "Deploy ${TARGET_REPOSITORY} to ${TARGET_REPOSITORY}:${remote_branch}"
    git push --force "${remote_repo}" gh_action:"${remote_branch}"

    echo "🚀 Deploy complete!"
}

main "$@"
