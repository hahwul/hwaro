alias b := build
alias d := dev
alias vc := version-check
alias vu := version-update

# List available tasks.
default:
    @just --list

# Build hwaro binary.
[group('build')]
build:
    shards install
    shards build

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
