+++
title = "CLI"
weight = 3
toc = true
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

You can also use a remote scaffold from a GitHub repository:

```bash
# GitHub shorthand
hwaro init my-site --scaffold github:user/repo
hwaro init my-site --scaffold github:user/repo/docs

# Full URL
hwaro init my-site --scaffold https://github.com/user/repo
hwaro init my-site --scaffold https://github.com/user/repo/tree/main/docs
```

Remote scaffolds fetch `config.toml`, `templates/`, `static/`, and content structure from the repository. Content files keep only front matter (metadata) so you can see the expected page structure without the original body text. Set `GITHUB_TOKEN` environment variable to avoid API rate limits.

**Options:**

| Flag | Description |
|------|-------------|
| --scaffold TYPE | Built-in (`simple`, `blog`, `docs`) or remote source (`github:user/repo[/path]`, URL) |
| -f, --force | Force creation even if directory is not empty |
| --skip-agents-md | Skip creating AGENTS.md file |
| --skip-sample-content | Skip creating sample content files |
| --skip-taxonomies | Skip taxonomies configuration and templates |
| --include-multilingual LANGS | Enable multilingual support (e.g., `en,ko,ja`) |

### new

Create a new content file:

```bash
hwaro new content/about.md
hwaro new content/blog/my-post.md
hwaro new -t "My Post Title"
hwaro new posts/my-post.md -a posts
```

Creates a Markdown file with front matter template. Supports **archetypes** for customizable templates.

**Options:**

| Flag | Description |
|------|-------------|
| -t, --title TITLE | Content title |
| -a, --archetype NAME | Archetype to use |

**Archetypes:**

Archetypes are template files in `archetypes/` directory that define default front matter for new content:

- `archetypes/default.md` - Default template for all content
- `archetypes/posts.md` - Used for `hwaro new posts/...`
- `archetypes/tools/develop.md` - Used for `hwaro new tools/develop/...`

Archetype files support placeholders: `{{ title }}`, `{{ date }}`, `{{ draft }}`

Example archetype (`archetypes/posts.md`):
```
---
title: "{{ title }}"
date: {{ date }}
draft: false
tags: []
---

# {{ title }}
```

Archetype matching priority:
1. Explicit `-a` flag (e.g., `-a posts` uses `archetypes/posts.md`)
2. Path-based matching (e.g., `posts/hello.md` checks `archetypes/posts.md`)
3. Nested paths try parent archetypes (e.g., `tools/dev/x.md` tries `tools/dev.md`, then `tools.md`)
4. Falls back to `archetypes/default.md`
5. Uses built-in template if no archetype found

### build

Build the site to `public/`:

```bash
hwaro build
hwaro build --drafts
hwaro build --minify
hwaro build -i /path/to/my-site
hwaro build -i /path/to/my-site -o ./dist
```

**Options:**

| Flag | Description |
|------|-------------|
| -i, --input DIR | Project directory to build (default: current directory) |
| -o, --output-dir DIR | Output directory (default: public) |
| --base-url URL | Temporarily override `base_url` from `config.toml` |
| -d, --drafts | Include draft content |
| --minify | Minify output files (see below) |
| --no-parallel | Disable parallel processing |
| --cache | Enable build caching (see below) |
| --skip-highlighting | Disable syntax highlighting |
| --skip-cache-busting | Disable cache busting query parameters on CSS/JS resources |
| --stream | Enable streaming build to reduce memory usage |
| --memory-limit SIZE | Memory limit for streaming build (e.g. `2G`, `512M`) |
| -v, --verbose | Show detailed output |
| --profile | Print phase-by-phase and per-template build timing |
| --debug | Print debug information after build |

**About `--stream` / `--memory-limit` (Streaming Build):**

For sites with thousands of pages, loading all rendered HTML into memory at once can cause high memory usage. Streaming build processes pages in batches during the Render phase, releasing rendered HTML after each batch is written to disk.

- `--stream` enables streaming with a default batch size of 50 pages.
- `--memory-limit SIZE` enables streaming and calculates the batch size automatically based on the given limit (heuristic: ~50KB per page). Accepts `G`, `M`, `K` suffixes (e.g. `2G`, `512M`, `256K`).
- You can also set the `HWARO_MEMORYLIMIT` environment variable as a fallback. The CLI flag overrides the env var.

| `--stream` | `--memory-limit` | `HWARO_MEMORYLIMIT` | Result |
|---|---|---|---|
| - | - | - | Normal build |
| yes | - | - | Streaming, batch=50 |
| - | 2G | - | Streaming, batch≈20000 |
| - | - | 1G | Streaming, batch≈10000 |
| yes | 512M | - | Streaming, batch≈5000 |
| - | 2G | 1G | CLI wins (2G) |

The build output is identical — streaming only affects memory usage during the build.

**About `--minify`:**

The minify flag performs conservative optimization on generated files:

- **HTML**: Removes comments and trailing whitespace, collapses excessive blank lines. Preserves all indentation, newlines, and content structure.
- **JSON**: Removes whitespace and newlines for compact output.
- **XML**: Removes whitespace between tags for smaller file sizes.

Code blocks (`<pre>`, `<code>`) and script/style content are always preserved intact.

**About `--cache`:**

When enabled, Hwaro tracks file modification times in a `.hwaro_cache.json` file at the project root. On subsequent builds, only files that have changed since the last build are re-processed. The cache uses millisecond-precision mtime comparison and also verifies that the output file still exists. Use `hwaro build --cache` to enable, or set `cache = true` in `[build]` config.

**About `-i, --input`:**

When specified, Hwaro changes its working directory to the given path before building. This lets you build a site located in another directory without `cd`-ing into it first.

- All site sources (`config.toml`, `content/`, `templates/`, `static/`) are read from the input directory.
- **Without `-o`:** The default output directory `public/` is created inside the input directory (i.e., the site's own `public/` folder). This is the natural behavior — `hwaro build -i ../my-site` produces `../my-site/public/`.
- **With `-o`:** The output path is resolved relative to **your current directory** (not the input directory), so `hwaro build -i ../my-site -o ./dist` writes output to `./dist` in your shell's CWD.
- If `-i` is omitted, behavior is unchanged — the current directory is used.

### serve

Start a development server with live reload:

```bash
hwaro serve
hwaro serve --port 8080
hwaro serve --open
hwaro serve --access-log
hwaro serve --live-reload
hwaro serve -i /path/to/my-site
hwaro serve -i /path/to/my-site -p 8080
```

**Options:**

| Flag | Description |
|------|-------------|
| -i, --input DIR | Project directory to serve (default: current directory) |
| -b, --bind HOST | Bind address (default: 0.0.0.0) |
| -p, --port PORT | Port number (default: 3000) |
| --base-url URL | Temporarily override `base_url` from `config.toml` |
| --minify | Serve minified output |
| --open | Open browser after starting |
| -d, --drafts | Include draft content |
| -v, --verbose | Show detailed output |
| --debug | Print debug information after each rebuild |
| --access-log | Show HTTP access log (e.g. GET requests) |
| --live-reload | Enable browser live reload on file changes |
| --skip-cache-busting | Disable cache busting query parameters on CSS/JS resources |
| --profile | Print phase-by-phase and per-template build timing |

The server watches for file changes and rebuilds automatically. It uses **smart rebuild strategies** based on what changed:

| Change Type | Strategy | Description |
|-------------|----------|-------------|
| `config.toml` | Full rebuild | Rebuilds entire site |
| `content/` only | Incremental | Rebuilds only affected content pages |
| `templates/` only | Template re-render | Re-renders all pages with existing content |
| `static/` only | Static copy | Copies only changed static files |
| Mixed / new / deleted files | Full rebuild | Rebuilds entire site |

**About `--live-reload`:**

When enabled, the server injects a small WebSocket client script into every HTML response. After each successful rebuild, connected browsers automatically refresh the page — no manual reload needed. The client uses exponential backoff (1s–30s) for reconnection, so restarting the server won't break the connection permanently.

When `-i` is specified, the server operates as if you had `cd`-ed into the given directory — watching and serving from that project root.

### deploy

Deploy the generated site to configured targets.

```bash
hwaro deploy [target ...]
hwaro deploy --dry-run
```

**Options:**

| Flag | Description |
|------|-------------|
| -s, --source DIR | Source directory to deploy (default: deployment.source_dir or public) |
| --dry-run | Show planned changes without writing |
| --confirm | Ask for confirmation before deploying |
| --force | Force upload/copy (ignore file comparisons) |
| --max-deletes N | Maximum number of deletes (default: deployment.maxDeletes or 256, -1 disables) |
| --list-targets | List configured deployment targets and exit |

### tool

Utility tools for content management:

```bash
hwaro tool convert toYAML       # Convert frontmatter to YAML
hwaro tool convert toTOML       # Convert frontmatter to TOML
hwaro tool list all             # List all content files
hwaro tool list drafts          # List draft files
hwaro tool list published       # List published files
hwaro tool deadlink             # Check for dead external links
hwaro tool doctor               # Diagnose config and content issues

# JSON output
hwaro tool list all --json
hwaro tool doctor --json
hwaro tool deadlink --json
hwaro tool convert toYAML --json
```

**Subcommands:**

| Subcommand | Description |
|------------|-------------|
| convert | Convert frontmatter between YAML and TOML formats |
| list | List content files by status (all, drafts, published) |
| deadlink | Check for dead links in content files |
| doctor | Diagnose config and content issues |

**Common Options:**

| Flag | Description |
|------|-------------|
| -c, --content DIR | Limit to specific content directory |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

See [Tools & Completion](/start/tools/) for detailed usage.

### completion

Generate shell completion scripts:

```bash
hwaro completion bash    # Bash completion script
hwaro completion zsh     # Zsh completion script
hwaro completion fish    # Fish completion script
```

**Installation:**

```bash
# Bash (add to ~/.bashrc)
eval "$(hwaro completion bash)"

# Zsh (add to ~/.zshrc)
eval "$(hwaro completion zsh)"

# Fish (add to ~/.config/fish/config.fish)
hwaro completion fish | source
```

See [Tools & Completion](/start/tools/) for detailed installation instructions.

## Examples

```bash
# Development workflow
hwaro serve --drafts --verbose

# Development with HTTP access log
hwaro serve --access-log

# Development with auto browser refresh
hwaro serve --live-reload

# Production build
hwaro build

# Custom output directory
hwaro build -o dist

# Preview on specific port
hwaro serve -p 8000 --open

# Build a site in another directory
hwaro build -i ~/projects/my-blog

# Build a remote project and output to current directory
hwaro build -i ~/projects/my-blog -o ./output

# Streaming build for large sites
hwaro build --stream
hwaro build --memory-limit 512M

# Streaming build with env var
HWARO_MEMORYLIMIT=1G hwaro build

# Serve a site from another directory
hwaro serve -i ~/projects/my-blog --open
```

## Global Options

| Flag | Description |
|------|-------------|
| -h, --help | Show help |
| -v, --verbose | Verbose output |
