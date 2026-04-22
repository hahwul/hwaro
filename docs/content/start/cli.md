+++
title = "CLI"
description = "Commands for creating, building, and serving your site"
weight = 3
toc = true
+++

Hwaro provides commands for creating, building, and serving your site.

## Global flags

These flags work with every top-level command and control how the CLI
writes to the terminal. They are especially useful for scripts, CI logs,
and AI agents that want clean output.

| Flag / Env var | Description |
|----------------|-------------|
| `-q`, `--quiet` | Suppress informational output and the startup banner. Warnings and errors still appear on stderr. |
| `NO_COLOR` (env) | When set to any non-empty value, suppresses ANSI color codes from every command's output. Follows the [no-color.org](https://no-color.org) cross-tool convention. |

Colors are also disabled automatically when stdout is not a TTY (for
example when piping to `cat`, redirecting to a file, or running inside
most CI systems). Set `NO_COLOR=1` to force-disable color everywhere;
no extra flag is needed.

```bash
# Silent build for scripts and CI — only warnings/errors surface.
hwaro build --quiet

# Plain ASCII (no ANSI escapes) even when stdout is a TTY.
NO_COLOR=1 hwaro doctor
```

### Error taxonomy

Classified failure paths emit a stable error code plus a matching
process exit code so scripts, CI, and agents can branch reliably
without parsing human messages.

In text mode the error line is prefixed with the code:

```
Error [HWARO_E_USAGE]: missing <path> argument
```

Under `--json` (or `--quiet`) the classified error is emitted as a
structured payload on stdout:

```json
{
  "status": "error",
  "error": {
    "code": "HWARO_E_USAGE",
    "category": "usage",
    "message": "missing <path> argument",
    "hint": "Usage: hwaro new <path> [options] — run 'hwaro new --help' for details."
  }
}
```

Unclassified failures keep the legacy `Error: <message>` format and
exit code `1`, so this is a strictly additive contract.

| Code | Category | Exit | Description |
|------|----------|------|-------------|
| `HWARO_E_USAGE` | usage | 2 | Bad/missing flag, missing required argument, unknown command |
| `HWARO_E_CONFIG` | config | 3 | `config.toml` missing, unparseable, or invalid |
| `HWARO_E_TEMPLATE` | template | 4 | Crinja template render error |
| `HWARO_E_CONTENT` | content | 5 | Content file parse error, invalid frontmatter |
| `HWARO_E_IO` | io | 6 | Filesystem access error (missing dir, permission denied) |
| `HWARO_E_NETWORK` | network | 7 | Deploy upload, remote scaffold fetch failure |
| `HWARO_E_INTERNAL` | internal | 70 | Unrecoverable bug or unexpected state |
| *(unclassified)* | — | 1 | Legacy/generic failure path |
| *(success)* | — | 0 | Command completed normally |

## Commands

### init

Create a new site:

```bash
hwaro init my-site
hwaro init my-site --scaffold blog
hwaro init my-site --scaffold docs
hwaro init my-site --scaffold book
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
| --scaffold TYPE | Built-in (`simple`, `bare`, `blog`, `blog-dark`, `docs`, `docs-dark`, `book`, `book-dark`) or remote source (`github:user/repo[/path]`, URL) |
| --agents MODE | AGENTS.md content mode: `remote` (lightweight, default) or `local` (full embedded reference) |
| -f, --force | Force creation even if directory is not empty |
| --skip-agents-md | Skip creating AGENTS.md file |
| --skip-sample-content | Skip creating sample content files |
| --skip-taxonomies | Skip taxonomies configuration and templates |
| --include-multilingual LANGS | Enable multilingual support (e.g., `en,ko,ja`) |
| --minimal-config | Generate minimal `config.toml` without comments or optional sections |
| --list-scaffolds | List available built-in scaffolds and exit |
| --json | Emit machine-readable JSON output (with --list-scaffolds) |

### new

Create a new content file:

```bash
hwaro new content/about.md
hwaro new content/blog/my-post.md
hwaro new -t "My Post Title"
hwaro new posts/my-post.md -a posts
hwaro new my-post.md --section blog --draft --tags "go,web" --date 2026-03-22
```

Creates a Markdown file with front matter template. Supports **archetypes** for customizable templates.

**Options:**

| Flag | Description |
|------|-------------|
| -t, --title TITLE | Content title |
| --date DATE | Content date (default: now, e.g. `2026-03-22`) |
| --draft | Mark as draft |
| --tags TAGS | Comma-separated tags |
| -s, --section NAME | Section directory (e.g. `blog`, `docs`) |
| -a, --archetype NAME | Archetype to use |
| --bundle | Create a leaf-bundle directory (`foo/index.md`) instead of a single file |
| --no-bundle | Force a single file (`foo.md`); overrides `[content.new].bundle = true` |
| --list-archetypes | List archetypes in the current project and exit |
| --json | Emit machine-readable JSON output (archetypes listing and classified errors) |

**Archetypes:**

Archetypes are template files in `archetypes/` directory that define default front matter for new content:

- `archetypes/default.md` - Default template for all content
- `archetypes/posts.md` - Used for `hwaro new posts/...`
- `archetypes/tools/develop.md` - Used for `hwaro new tools/develop/...`

Archetype files support placeholders: `{{ title }}`, `{{ date }}`, `{{ draft }}`, `{{ tags }}`

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
| -o, --output DIR | Output directory (default: public) |
| --base-url URL | Temporarily override `base_url` from `config.toml` |
| -d, --drafts | Include draft content |
| --include-expired | Include expired content |
| --include-future | Include future-dated content |
| --minify | Minify output files (see below) |
| --no-parallel | Disable parallel processing |
| --cache | Enable incremental build caching (see below) |
| --full | Force a complete rebuild, clearing the cache |
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

- **HTML**: Removes comments and trailing whitespace, collapses excessive blank lines. Preserves all indentation, newlines, inter-tag whitespace, and content structure.
- **JSON**: Removes whitespace and newlines for compact output.
- **XML**: Removes whitespace between tags for smaller file sizes.

Code blocks (`<pre>`, `<code>`) and script/style content are always preserved intact.

**HTML minification is intentionally conservative.** Prior attempts at aggressive HTML reduction (stripping indentation, collapsing whitespace between tags, etc.) caused content-rendering regressions even with `<pre>`/`<script>`/`<style>` protection. If you need aggressive HTML minification for deployment, post-process the output of `public/` with a dedicated minifier (e.g. `html-minifier-terser`, `minify-html`) rather than relying on `--minify`.

**About `--cache` (Incremental Build):**

When enabled, Hwaro tracks file modification times and content checksums in a `.hwaro_cache.json` file at the project root. On subsequent builds, only files that have changed since the last build are re-rendered. The cache also tracks template and config checksums — if templates or `config.toml` change, all entries are automatically invalidated and every page is rebuilt.

Use `--full` together with `--cache` to force a clean rebuild while still saving the cache for the next run:

```bash
hwaro build --cache --full
```

See [Incremental Build](/features/incremental-build/) for details.

**About `-i, --input`:**

When specified, Hwaro changes its working directory to the given path before building. This lets you build a site located in another directory without `cd`-ing into it first.

- All site sources (`config.toml`, `content/`, `templates/`, `static/`) are read from the input directory.
- **Without `-o`:** The default output directory `public/` is created inside the input directory (i.e., the site's own `public/` folder). This is the natural behavior — `hwaro build -i ../my-site` produces `../my-site/public/`.
- **With `-o`:** The output path is resolved relative to **your current directory** (not the input directory), so `hwaro build -i ../my-site -o ./dist` writes output to `./dist` in your shell's CWD.
- If `-i` is omitted, behavior is unchanged — the current directory is used.

### serve

Start a development server with live reload (enabled by default):

```bash
hwaro serve
hwaro serve --port 8080
hwaro serve --open
hwaro serve --access-log
hwaro serve --no-live-reload
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
| --include-expired | Include expired content |
| --include-future | Include future-dated content |
| -v, --verbose | Show detailed output |
| --debug | Print debug information after each rebuild |
| --access-log | Show HTTP access log (e.g. GET requests) |
| --no-error-overlay | Disable in-browser error overlay (default: enabled) |
| --live-reload | Enable browser live reload on file changes (default: enabled; kept for backwards compatibility) |
| --no-live-reload | Disable browser live reload on file changes |
| --cache | Enable build caching (skip unchanged files) |
| --stream | Enable streaming build to reduce memory usage |
| --memory-limit SIZE | Memory limit for streaming build (e.g. `2G`, `512M`) |
| --skip-cache-busting | Disable cache busting query parameters on CSS/JS resources |
| --skip-og-image | Skip auto OG image generation |
| --skip-image-processing | Skip image resizing and LQIP generation |
| --profile | Print phase-by-phase and per-template build timing |

The server watches for file changes and rebuilds automatically. It uses **smart rebuild strategies** based on what changed:

| Change Type | Strategy | Description |
|-------------|----------|-------------|
| `config.toml` | Full rebuild | Rebuilds entire site |
| `content/` only | Incremental | Rebuilds only affected content pages |
| `templates/` only | Template re-render | Re-renders all pages with existing content |
| `static/` only | Static copy | Copies only changed static files |
| Mixed / new / deleted files | Full rebuild | Rebuilds entire site |

**About live reload:**

Live reload is **enabled by default**. The server injects a small WebSocket client script into every HTML response, and after each successful rebuild, connected browsers automatically refresh the page — no manual reload needed. The client uses exponential backoff (1s–30s) for reconnection, so restarting the server won't break the connection permanently.

Pass `--no-live-reload` to disable this behaviour (useful for testing production-like delivery locally). The `--live-reload` flag is kept as a no-op alias for backwards compatibility with existing invocations.

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
| --json | Emit machine-readable JSON output (with --list-targets) |

### doctor

Diagnose config, template, and structure issues (top-level shortcut):

```bash
hwaro doctor               # Diagnose config, template, and structure issues
hwaro doctor --fix         # Add missing config sections to config.toml
```

**Exit codes.** `doctor` returns a classified exit code based on the most
severe issue reported, so CI pipelines can gate on it directly:

| Outcome | Exit |
|---|---|
| No issues, warnings only, or info-level findings | `0` |
| Config errors (missing/broken `config.toml`) | `3` (`HWARO_E_CONFIG`) |
| Template errors (missing required file, unclosed tags) | `4` (`HWARO_E_TEMPLATE`) |
| Content errors (malformed front matter, when the check lands) | `5` (`HWARO_E_CONTENT`) |
| Other error-level issues | `1` |

Warnings (empty `base_url`, trailing slash, duplicate taxonomy names, etc.)
are advisory and never change the exit code.

For content validation, use `hwaro tool validate`. See [doctor](/start/tools/doctor/) for details.

### tool

Utility tools for content management:

```bash
# Content tools
hwaro tool list all             # List all content files
hwaro tool list drafts          # List draft files
hwaro tool convert to-yaml      # Convert frontmatter to YAML
hwaro tool convert to-toml      # Convert frontmatter to TOML
hwaro tool check-links          # Check for dead external links
hwaro tool stats                # Show content statistics
hwaro tool validate             # Validate content frontmatter and markup
hwaro tool unused-assets        # Find unreferenced static files

# Site tools
hwaro tool platform netlify       # Generate Netlify config
hwaro tool platform vercel        # Generate Vercel config
hwaro tool platform cloudflare    # Generate Cloudflare Pages config
hwaro tool platform github-pages  # Generate GitHub Pages deploy workflow
hwaro tool platform gitlab-ci     # Generate GitLab CI config
hwaro tool doctor                 # Diagnose config/template/structure issues
hwaro tool import hugo /path      # Import from Hugo
hwaro tool import jekyll /path    # Import from Jekyll
hwaro tool export hugo            # Export to Hugo format
hwaro tool export jekyll          # Export to Jekyll format
hwaro tool agents-md --write      # Write AGENTS.md to file

# JSON output
hwaro tool list all --json
hwaro tool stats --json
hwaro tool validate --json
hwaro tool unused-assets --json
hwaro tool doctor --json
hwaro tool check-links --json
```

**Subcommands:**

| Category | Subcommand | Description |
|----------|------------|-------------|
| Content | [list](/start/tools/list/) | List content files by status (all, drafts, published) |
| Content | [convert](/start/tools/convert/) | Convert frontmatter between YAML and TOML formats |
| Content | [check-links](/start/tools/check-links/) | Check for dead links in content files |
| Content | [stats](/start/tools/stats/) | Show content statistics |
| Content | [validate](/start/tools/validate/) | Validate content frontmatter and markup |
| Content | [unused-assets](/start/tools/unused-assets/) | Find unreferenced static files |
| Site | [platform](/start/tools/platform/) | Generate platform config and CI/CD workflow files |
| Site | [doctor](/start/tools/doctor/) | Diagnose config, template, and structure issues |
| Site | import | Import content from WordPress, Jekyll, Hugo, Notion, Obsidian, Hexo, Astro, or Eleventy |
| Site | [export](/start/tools/export/) | Export content to Hugo or Jekyll |
| Site | [agents-md](/start/tools/agents-md/) | Generate or update AGENTS.md file |

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

# Development without live reload (production-like serving)
hwaro serve --no-live-reload

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

# Incremental build (skip unchanged files)
hwaro build --cache

# Force full rebuild and repopulate cache
hwaro build --cache --full

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

## See Also

- [Configuration](/start/config/) — Config options that CLI flags override
- [Build Hooks](/features/build-hooks/) — Pre/post build commands
- [Tools & Completion](/start/tools/) — Utility subcommands
