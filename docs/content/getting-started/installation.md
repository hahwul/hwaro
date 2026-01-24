+++
title = "Installation"
+++

## Prerequisites

- [Crystal](https://crystal-lang.org/install/) 1.0+
- Git

## Build from Source

```bash
git clone https://github.com/hahwul/hwaro
cd hwaro
shards install
shards build --release
```

The binary is created at `bin/hwaro`.

## Add to PATH

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

```bash
cd hwaro
git pull origin main
shards install
shards build --release
```
