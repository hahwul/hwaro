+++
title = "Installation"
toc = true
+++

## Prerequisites

- [Crystal](https://crystal-lang.org/install/) 1.19+
- Git

## Homebrew

```bash
brew tap hahwul/hwaro
brew install hwaro
```

## Docker

You can use the official Docker image from GitHub Container Registry:

```bash
# Run hwaro commands
docker run --rm -v $(pwd):/app ghcr.io/hahwul/hwaro --help

# Build a site
docker run --rm -v $(pwd):/app ghcr.io/hahwul/hwaro build

# Serve a site
docker run --rm -p 3000:3000 -v $(pwd):/app ghcr.io/hahwul/hwaro serve
```

## Build from Source

```bash
git clone https://github.com/hahwul/hwaro
cd hwaro
shards install
shards build --release
```

The binary is created at `bin/hwaro`.

### Add to PATH

```bash
# Option 1: Copy to system path
sudo cp bin/hwaro /usr/local/bin/

# Option 2: Add to user path
export PATH="$PATH:$(pwd)/bin"
```

## Verify Installation

```bash
hwaro --version
```

## Update

### Via Homebrew

```bash
brew update
brew upgrade hwaro
```

### Via Source

```bash
cd hwaro
git pull origin main
shards install
shards build --release
```
