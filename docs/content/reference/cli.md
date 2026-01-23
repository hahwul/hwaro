+++
title = "CLI Commands"
description = "Complete reference for all Hwaro command-line commands"
toc = true
+++


Complete reference for all Hwaro command-line commands and options.

## Global Options

These options are available for all commands:

| Option | Description |
|--------|-------------|
| `-v, --verbose` | Show detailed output including generated files |
| `-h, --help` | Show help information |
| `--version` | Show version number |

## hwaro init

Initialize a new Hwaro project.

### Usage

```bash
hwaro init [path] [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `path` | Directory to create the project in (default: current directory) |

### Options

| Option | Description |
|--------|-------------|
| `--scaffold TYPE` | Project scaffold type (default: `simple`) |
| `--force` | Overwrite existing files without prompting |
| `--skip-sample-content` | Don't create sample content files |

### Scaffold Types

| Type | Description |
|------|-------------|
| `simple` | Minimal site with basic structure |
| `blog` | Blog-focused with posts section and RSS feed |
| `docs` | Documentation site with sidebar navigation |

### Examples

```bash
hwaro init

hwaro init my-site

hwaro init my-docs --scaffold docs

hwaro init my-blog --scaffold blog

hwaro init my-site --force

hwaro init my-site --skip-sample-content
```

### Generated Structure

After running `hwaro init my-site --scaffold docs`:

```
my-site/
├── config.toml           # Site configuration
├── content/              # Markdown content
│   ├── index.md          # Homepage
│   ├── getting-started/
│   │   ├── _index.md
│   │   └── ...
│   └── guide/
│       └── ...
├── templates/            # ECR templates
│   ├── header.ecr
│   ├── footer.ecr
│   ├── page.ecr
│   └── section.ecr
└── static/               # Static assets
```

---

## hwaro build

Build the static site.

### Usage

```bash
hwaro build [options]
```

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--output-dir DIR` | `-o DIR` | Output directory (default: `public`) |
| `--drafts` | `-d` | Include draft content |
| `--minify` | | Minify HTML, JSON, and XML output |
| `--no-parallel` | | Disable parallel file processing |
| `--cache` | | Enable build caching for faster rebuilds |
| `--skip-highlighting` | | Disable syntax highlighting |
| `--verbose` | `-v` | Show detailed output |

### Examples

```bash
hwaro build

hwaro build --minify

hwaro build --drafts

hwaro build --output-dir dist

hwaro build --cache

hwaro build --skip-highlighting

hwaro build --verbose

hwaro build --minify --cache
```

### Build Process

The build command:

1. **Reads configuration** from `config.toml`
2. **Runs pre-build hooks** (if configured)
3. **Collects content** from `content/` directory
4. **Parses front matter** and extracts metadata
5. **Transforms content** (Markdown → HTML)
6. **Renders templates** with content
7. **Generates SEO files** (sitemap, feeds, robots.txt)
8. **Copies static files** from `static/` directory
9. **Writes output** to the output directory
10. **Runs post-build hooks** (if configured)

### Output

```
my-site/public/
├── index.html
├── about/
│   └── index.html
├── blog/
│   ├── index.html
│   └── my-post/
│       └── index.html
├── sitemap.xml
├── rss.xml
├── robots.txt
├── search.json
└── css/
    └── style.css
```

### Caching

When `--cache` is enabled:

- Hwaro tracks file modification times
- Unchanged files are skipped during rebuild
- Cache is stored in `.hwaro-cache/`
- Significantly faster for incremental changes

---

## hwaro serve

Start a local development server with live reload.

### Usage

```bash
hwaro serve [options]
```

### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--port PORT` | `-p PORT` | Server port (default: `3000`) |
| `--bind HOST` | `-b HOST` | Bind address (default: `0.0.0.0`) |
| `--open` | | Open browser after starting server |
| `--drafts` | `-d` | Include draft content |
| `--verbose` | `-v` | Show detailed output |

### Examples

```bash
hwaro serve

hwaro serve --port 8080

hwaro serve --bind 127.0.0.1

hwaro serve --open

hwaro serve --drafts

hwaro serve --port 4000 --open
```

### Features

The development server provides:

- **Auto-rebuild** — Automatically rebuilds when files change
- **Live reload** — Browser refreshes automatically after rebuild
- **Draft preview** — Preview draft content with `--drafts`
- **Error display** — Shows build errors in the terminal

### Watched Directories

The server watches these directories for changes:

- `content/` — Markdown content files
- `templates/` — ECR templates
- `static/` — Static assets
- `config.toml` — Configuration file

### Network Access

By default, the server binds to `0.0.0.0`, making it accessible from other devices on your network. To restrict access to localhost only:

```bash
hwaro serve --bind 127.0.0.1
```

---

## hwaro new

Create a new content file with front matter template.

### Usage

```bash
hwaro new [path]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `path` | Path for the new content file (relative to project root) |

### Examples

```bash
hwaro new content/about.md

hwaro new content/blog/my-first-post.md

hwaro new content/docs/guides/deployment.md
```

### Generated Content

The command creates a new Markdown file with front matter:

```markdown
+++
title = "My First Post"
date = "2024-01-15T10:30:00Z"
draft = true
+++

Write your content here...
```

### Notes

- The `title` is derived from the filename
- The `date` is set to the current time
- New content is marked as `draft = true` by default
- Parent directories are created if they don't exist

---

## Environment Variables

Hwaro respects these environment variables:

| Variable | Description |
|----------|-------------|
| `HWARO_CONFIG` | Path to configuration file |
| `NO_COLOR` | Disable colored output |

### Examples

```bash
HWARO_CONFIG=custom-config.toml hwaro build

NO_COLOR=1 hwaro build
```

---

## Exit Codes

| Code | Description |
|------|-------------|
| `0` | Success |
| `1` | General error |
| `2` | Configuration error |
| `3` | Build error |

---

## Command Chaining

Combine commands in your workflow:

```bash
rm -rf public && hwaro build

hwaro build --minify && rsync -av public/ server:/var/www/

hwaro serve
```

---

## Build Hooks Integration

Commands integrate with build hooks defined in `config.toml`:

```toml
[build]
hooks.pre = ["npm install"]
hooks.post = ["npm run optimize"]
```

- **Pre-hooks** run before the build starts
- **Post-hooks** run after the build completes
- Hooks run for both `build` and `serve` commands
- Pre-hook failure aborts the build
- Post-hook failure shows a warning but doesn't fail the build

---

## Tips

### Faster Builds

```bash
hwaro build --cache

hwaro build --skip-highlighting

hwaro build --cache --skip-highlighting
```

### Production Builds

```bash
hwaro build --minify
```

### Debugging

```bash
hwaro build --verbose

hwaro serve --drafts --verbose
```

### CI/CD Integration

```bash
hwaro build --minify

hwaro build --minify || exit 1
```
