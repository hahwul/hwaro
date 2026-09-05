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

The dev shell brings its own Crystal, `shards`, `just`, and `crystal2nix`, so
`just build` and `just test` work with nothing else installed.

### As a flake input

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.hwaro.url = "github:hahwul/hwaro";

  outputs = { nixpkgs, hwaro, ... }: {
    # `hwaro.packages.<system>.hwaro`, or add `hwaro.overlays.default` to your
    # nixpkgs overlays and use `pkgs.hwaro`.
  };
}
```

Supported systems are `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`
(nixpkgs-unstable no longer supports Intel macOS). The flake pins the official
Crystal toolchain, so no compiler has to be built from source.

## Pre-built Binary

Pre-built binaries for macOS and Linux are available on the [GitHub Releases](https://github.com/hahwul/hwaro/releases) page.

1. Download the binary for your platform from the [latest release](https://github.com/hahwul/hwaro/releases/latest).
2. Move the binary to a directory in your PATH. **On macOS the download is a
   tarball, not a bare binary. See [macOS](#macos) below before moving
   anything.**

```bash
# Example for Linux (amd64)
chmod +x hwaro-v*-linux-x86_64
sudo mv hwaro-v*-linux-x86_64 /usr/local/bin/hwaro
```

### macOS

The macOS download is a tarball, not a bare binary. It extracts to `hwaro`
plus a `lib/` directory holding the bundled OpenSSL, and the binary loads
those through `@executable_path/lib`, so **`lib/` has to travel with it**.
Move the whole extracted directory, not just the binary:

```bash
tar -xzf hwaro-v*-osx-arm64.tar.gz
sudo mkdir -p /usr/local/libexec/hwaro
sudo cp -R hwaro lib /usr/local/libexec/hwaro/
sudo ln -sf /usr/local/libexec/hwaro/hwaro /usr/local/bin/hwaro
```

The symlink is safe: macOS resolves it before computing `@executable_path`,
so the dylibs are still found. Homebrew installs the tarball the same way.

> **v0.20.0 only.** That release's macOS tarball shipped with an invalid code
> signature on its bundled dylibs, and Apple Silicon kills the process at
> launch with `zsh: killed hwaro` and no other diagnostic. Clearing quarantine
> on its own does not fix it, because the signature is stale as well; re-signing
> on its own can also leave you stuck, because re-signing a quarantined file
> resets its approval. Do both, in this order, from the extracted directory:
>
> ```bash
> xattr -dr com.apple.quarantine hwaro lib
> codesign --force --sign - lib/*.dylib hwaro
> ```
>
> A patch release will carry the fix, after which no manual step is needed.

## From Source

### Prerequisites

- [Crystal](https://crystal-lang.org/install/) 1.21+
- Git

### Build

```bash
git clone https://github.com/hahwul/hwaro
cd hwaro
shards install
shards build --release --no-debug
```

The binary is created at `./bin/hwaro`.

> Requires Crystal **1.21 or newer**. Parallel page rendering is enabled in
> `src/main.cr`, which resizes Crystal's default execution context, so no build
> flag is needed. Set `CRYSTAL_WORKERS=N` to override the worker count (it
> defaults to the CPU count). Do not pass the old `-Dpreview_mt` flag:
> Crystal 1.21 deprecated it and its scheduler can hang at process exit.
>
> For `hwaro build` (any install method, not just source builds), Hwaro
> tunes the Boehm GC at startup (`GC_MARKERS=1` and
> `GC_INITIAL_HEAP_SIZE=256M`). We measured 3-5x faster builds on
> allocation-heavy sites, at the cost of a higher peak memory floor during
> the build. Exporting either variable overrides the built-in default, and
> the heap presize is skipped when `--memory-limit` is used. See the
> [global flags table](@/start/cli.md) for details.

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
