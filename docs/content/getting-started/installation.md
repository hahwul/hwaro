+++
title = "Installation"
description = "Learn how to install Hwaro on your system"
+++


Hwaro is a static site generator written in Crystal. This guide covers all the ways you can install Hwaro on your system.

## Prerequisites

Before installing Hwaro, ensure you have the following:

- **Crystal** 1.0 or later ([Installation Guide](https://crystal-lang.org/install/))
- **Git** (for cloning the repository)

## Install from Source

The recommended way to install Hwaro is from source:

```bash
git clone https://github.com/hahwul/hwaro
cd hwaro

shards install

shards build --release
```

After building, the `hwaro` binary will be available in the `bin/` directory.

### Add to PATH

To use Hwaro from anywhere, add it to your system PATH:

```bash
sudo cp bin/hwaro /usr/local/bin/

export PATH="$PATH:/path/to/hwaro/bin"
```

## Development Build

For development or debugging purposes, build without release optimizations:

```bash
shards build
```

This compiles faster but produces a slower binary.

## Verify Installation

Confirm that Hwaro is installed correctly:

```bash
hwaro --version
```

You should see the version number output:

```
hwaro version X.X.X
```

## Updating Hwaro

To update to the latest version:

```bash
cd hwaro
git pull origin main
shards install
shards build --release
```

If you copied the binary to `/usr/local/bin/`, copy it again after rebuilding.

## Troubleshooting

### Crystal not found

Make sure Crystal is installed and in your PATH:

```bash
crystal --version
```

If not found, follow the [Crystal installation guide](https://crystal-lang.org/install/) for your operating system.

### Permission denied

If you get permission errors when copying to `/usr/local/bin/`:

```bash
sudo cp bin/hwaro /usr/local/bin/
```

Or install to a user-local directory:

```bash
mkdir -p ~/.local/bin
cp bin/hwaro ~/.local/bin/
export PATH="$HOME/.local/bin:$PATH"
```

### Build errors

Ensure all dependencies are installed:

```bash
shards install
```

If issues persist, try cleaning and rebuilding:

```bash
rm -rf lib/
shards install
shards build --release
```

## Next Steps

Once Hwaro is installed, proceed to the [Quick Start](/getting-started/quick-start/) guide to create your first site.