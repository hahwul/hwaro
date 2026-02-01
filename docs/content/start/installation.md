+++
title = "Installation"
weight = 1
toc = true
+++

Hwaro is written in Crystal. You can install it from source or use a pre-built binary.

## Homebrew

```bash
brew tap hwaro/hwaro
brew install hwaro
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
