+++
title = "CLI"
weight = 3
+++

Hwaro provides commands for creating, building, and serving your site.

## Commands

### init

Create a new site:

```bash
hwaro init my-site
hwaro init my-site --scaffold blog
hwaro init my-site --scaffold docs
```

**Options:**

| Flag | Description |
|------|-------------|
| `--scaffold NAME` | Use a scaffold template: `simple`, `blog`, `docs` |

### new

Create a new content file:

```bash
hwaro new content/about.md
hwaro new content/blog/my-post.md
```

Creates a Markdown file with front matter template.

### build

Build the site to `public/`:

```bash
hwaro build
hwaro build --drafts
hwaro build --minify
```

**Options:**

| Flag | Description |
|------|-------------|
| `-o, --output-dir DIR` | Output directory (default: `public`) |
| `-d, --drafts` | Include draft content |
| `--minify` | Minify HTML, JSON, XML output |
| `--no-parallel` | Disable parallel processing |
| `--cache` | Enable build caching |
| `--skip-highlighting` | Disable syntax highlighting |
| `-v, --verbose` | Show detailed output |

### serve

Start a development server with live reload:

```bash
hwaro serve
hwaro serve --port 8080
hwaro serve --open
```

**Options:**

| Flag | Description |
|------|-------------|
| `-b, --bind HOST` | Bind address (default: `0.0.0.0`) |
| `-p, --port PORT` | Port number (default: `3000`) |
| `--open` | Open browser after starting |
| `-d, --drafts` | Include draft content |
| `-v, --verbose` | Show detailed output |

The server watches for file changes and rebuilds automatically.

## Examples

```bash
# Development workflow
hwaro serve --drafts --verbose

# Production build
hwaro build --minify

# Custom output directory
hwaro build -o dist

# Preview on specific port
hwaro serve -p 8000 --open
```

## Global Options

| Flag | Description |
|------|-------------|
| `-h, --help` | Show help |
| `-v, --verbose` | Verbose output |