+++
title = "Installation"
description = "Install Hwaro from source or pre-built binary"
weight = 1
toc = true
+++

Hwaro is written in Crystal. You can install it from source or use a pre-built binary.

## Homebrew

```bash
brew tap hwaro/hwaro
brew install hwaro
```

## Snapcraft

```bash
sudo snap install hwaro
```

## Pre-built Binary

Pre-built binaries for macOS and Linux are available on the [GitHub Releases](https://github.com/hahwul/hwaro/releases) page.

1. Download the archive for your platform from the [latest release](https://github.com/hahwul/hwaro/releases/latest).
2. Extract the archive and move the binary to a directory in your PATH.

```bash
# Example for Linux (amd64)
tar -xzf hwaro-linux-amd64.tar.gz
sudo mv hwaro /usr/local/bin/
```

## From Source

### Prerequisites

- [Crystal](https://crystal-lang.org/install/) 1.19+
- Git

### Build

```bash
git clone https://github.com/hahwul/hwaro
cd hwaro
shards install
shards build --release
```

The binary is created at `./bin/hwaro`.

### Add to PATH (Optional)

```bash
# Copy to a directory in your PATH
sudo cp ./bin/hwaro /usr/local/bin/

# Or add the bin directory to PATH
export PATH="$PATH:$(pwd)/bin"
```

## Verify Installation

```bash
hwaro --version
```

## Next Steps

- [Create your first site →](/start/first-site/)
