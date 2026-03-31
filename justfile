# Default: just --list
default:
    @echo "Listing available tasks..."
    @just --list

# Serve documents page with builded binary
dev:
    @[ -f bin/hwaro ] || just build
    bin/hwaro serve -i docs

# Build binary
build:
    shards install
    shards build

# Run all tests
test:
    crystal spec

# Fix lint
fix:
    crystal tool format

# Clean build artifacts
clean:
    rm -f src/ext/stb_impl.o
    rm -rf bin/
    rm -rf lib/

# Check version consistency
alias vc := version-check
version-check:
    crystal run scripts/version_check.cr

# Update version
alias vu := version-update
version-update:
    crystal run scripts/version_update.cr
