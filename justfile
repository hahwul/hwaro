# Default: just --list
default:
    @echo "Listing available tasks..."
    @just --list

# Serve documents page with builded binary
dev:
    bin/hwaro serve -i docs

# Build binary
build:
    shards build

# Run all tests
test:
    crystal spec

# Fix lint
fix:
    crystal tool format

# Check version consistency
alias vc := version-check
version-check:
    crystal run scripts/version_check.cr

# Update version
alias vu := version-update
version-update:
    crystal run scripts/version_update.cr
