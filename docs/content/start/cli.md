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

**Options:**

| Flag | Description |
|------|-------------|
| --scaffold NAME | Use a scaffold template: simple, blog, docs |

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
```

**Options:**

| Flag | Description |
|------|-------------|
| -o, --output-dir DIR | Output directory (default: public) |
| -d, --drafts | Include draft content |
| --minify | Minify HTML, JSON, XML output (experimental) |
| --no-parallel | Disable parallel processing |
| --cache | Enable build caching |
| --skip-highlighting | Disable syntax highlighting |
| -v, --verbose | Show detailed output |

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
| -b, --bind HOST | Bind address (default: 0.0.0.0) |
| -p, --port PORT | Port number (default: 3000) |
| --open | Open browser after starting |
| -d, --drafts | Include draft content |
| -v, --verbose | Show detailed output |

The server watches for file changes and rebuilds automatically.

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

## Examples

```bash
# Development workflow
hwaro serve --drafts --verbose

# Production build
hwaro build

# Custom output directory
hwaro build -o dist

# Preview on specific port
hwaro serve -p 8000 --open
```

## Global Options

| Flag | Description |
|------|-------------|
| -h, --help | Show help |
| -v, --verbose | Verbose output |
