+++
title = "Installation"
description = "Install Hwaro from source or pre-built binary"
weight = 1
toc = true
+++

Hwaro is written in Crystal. You can install it from source or use a pre-built binary.

## Homebrew

```bash
brew tap hahwul/hwaro
brew install hwaro
```

## Snapcraft

```bash
sudo snap install hwaro
```

## APK (Alpine Linux)

Download the `.apk` package from the [latest release](https://github.com/hahwul/hwaro/releases/latest) and install it:

```bash
apk add --allow-untrusted hwaro-*.apk
```

## DEB (Debian/Ubuntu)

Download the `.deb` package from the [latest release](https://github.com/hahwul/hwaro/releases/latest) and install it:

```bash
sudo dpkg -i hwaro_*_amd64.deb
```

## RPM (Fedora/RHEL/CentOS)

Download the `.rpm` package from the [latest release](https://github.com/hahwul/hwaro/releases/latest) and install it:

```bash
sudo rpm -i hwaro-*.x86_64.rpm
```

## AUR (Arch Linux)

```bash
yay -S hwaro
```

## Nix

### Install

```bash
nix profile install github:hahwul/hwaro
```

### Run without installing

```bash
nix run github:hahwul/hwaro -- --version
```

### Development shell

```bash
nix develop github:hahwul/hwaro
```

## Pre-built Binary

Pre-built binaries for macOS and Linux are available on the [GitHub Releases](https://github.com/hahwul/hwaro/releases) page.

1. Download the binary for your platform from the [latest release](https://github.com/hahwul/hwaro/releases/latest).
2. Move the binary to a directory in your PATH.

```bash
# Example for Linux (amd64)
chmod +x hwaro-v*-linux-x86_64
sudo mv hwaro-v*-linux-x86_64 /usr/local/bin/hwaro
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
