# Default
default:
    @echo "Listing available tasks..."
    @just --list

dev:
    bin/hwaro serve -i docs

build:
    shards build

lint:
    crystal tool format
