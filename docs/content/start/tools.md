+++
title = "Tools & Completion"
weight = 5
toc = true
+++

Hwaro includes utility tools for content management and shell completion scripts for a better CLI experience.

## Tool Commands

The `hwaro tool` command provides utility subcommands for working with content files.

### convert — Frontmatter Converter

Convert frontmatter between YAML and TOML formats across your content files.

```bash
# Convert all frontmatter to YAML
hwaro tool convert toYAML

# Convert all frontmatter to TOML
hwaro tool convert toTOML

# Convert only in a specific directory
hwaro tool convert toYAML -c posts

# Output result as JSON
hwaro tool convert toYAML --json
```

**Options:**

| Flag | Description |
|------|-------------|
| -c, --content DIR | Limit conversion to a specific content directory |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

**JSON output example:**

```json
{
  "success": true,
  "message": "Converted 5 files to YAML",
  "converted_count": 5,
  "skipped_count": 2,
  "error_count": 0
}
```

**Example — TOML to YAML:**

Before:

```markdown
+++
title = "My Post"
date = "2024-01-15"
tags = ["crystal", "tutorial"]
+++

Content here.
```

After `hwaro tool convert toYAML`:

```markdown
---
title: "My Post"
date: "2024-01-15"
tags:
  - crystal
  - tutorial
---

Content here.
```

### list — Content Lister

List content files filtered by status.

```bash
# List all content files
hwaro tool list all

# List only draft files
hwaro tool list drafts

# List only published files
hwaro tool list published

# List files in a specific directory
hwaro tool list all -c posts

# Output result as JSON
hwaro tool list all --json
```

**Options:**

| Flag | Description |
|------|-------------|
| -c, --content DIR | Limit listing to a specific content directory |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

**JSON output example:**

```json
[
  {
    "path": "content/blog/my-post.md",
    "title": "My Post",
    "draft": false,
    "date": "2024-06-15T00:00:00+00:00"
  },
  {
    "path": "content/blog/draft-post.md",
    "title": "Draft Post",
    "draft": true,
    "date": "2024-06-10T00:00:00+00:00"
  }
]
```

**Filters:**

| Filter | Description |
|--------|-------------|
| all | Show all content files |
| drafts | Show only files with `draft = true` |
| published | Show only files with `draft = false` or no draft field |

### deadlink — Dead Link Checker

Check for broken external and internal links in your content files.

```bash
hwaro tool deadlink

# Output result as JSON
hwaro tool deadlink --json
```

**Options:**

| Flag | Description |
|------|-------------|
| -j, --json | Output result as JSON |
| -h, --help | Show help |

This command:

1. Scans all Markdown files in the `content/` directory
2. Finds external URLs (http/https links) and internal links (relative/absolute paths)
3. Sends concurrent HEAD requests to external URLs
4. Verifies internal link targets exist on disk (checks `.md`, `_index.md`, `index.md`)
5. Reports broken or unreachable links

**Example output:**

```
Starting dead link check in 'content'...
----------------------------------------
✘ Found 3 dead links (out of 50 total):
[DEAD] content/blog/post.md
  └─ URL: https://old-site.com/page
  └─ Status: 404
[DEAD] content/blog/post.md
  └─ URL: ../missing-page (internal)
  └─ Internal link target not found
[DEAD] content/about.md
  └─ URL: /images/photo.png (internal)
  └─ Image not found
----------------------------------------
```

**Link types checked:**

| Type | Description |
|------|-------------|
| External | `http://` and `https://` links — checked via HTTP HEAD |
| Internal | Relative and absolute path links — checked on filesystem |
| Images | `![alt](path)` image references — checked on filesystem |

**JSON output example:**

```json
{
  "dead_links": [
    {
      "link": {
        "file": "content/blog/post.md",
        "url": "https://old-site.com/page",
        "kind": "external"
      },
      "status": 404,
      "error": null
    },
    {
      "link": {
        "file": "content/about.md",
        "url": "/images/photo.png",
        "kind": "image"
      },
      "status": -1,
      "error": "Image not found"
    }
  ],
  "total_links": 50,
  "external_links": 30,
  "internal_links": 20,
  "dead_link_count": 2
}
```

### doctor — Site Diagnostics

Diagnose configuration and content issues in your Hwaro site.

```bash
hwaro tool doctor

# Check only a specific content directory
hwaro tool doctor -c posts

# Output result as JSON
hwaro tool doctor --json
```

This command checks:

**Config diagnostics:**

- `base_url` is not set
- `base_url` doesn't start with `http://` or `https://`
- `base_url` has a trailing slash
- `title` is still the default value
- `feeds.enabled` is true but `feeds.filename` is empty
- `sitemap.changefreq` has an invalid value
- `sitemap.priority` is out of range (0.0–1.0)
- Duplicate taxonomy names
- Duplicate language codes
- Invalid `search.format` value

**Template diagnostics:**

- Templates directory not found
- Required templates missing (`page.html`, `section.html`)
- Unclosed block tags (`if`, `for`, `block`, `macro` without matching `end`)
- Mismatched `{{ }}` variable tags

**Content diagnostics:**

- Missing `title` in frontmatter
- Missing `description` in frontmatter
- Missing `date` in frontmatter
- Images without alt text (`![](url)`)
- Broken internal links (relative/absolute paths that don't resolve)
- Frontmatter parse errors (TOML/YAML)
- Draft files (reported as info)

**Structure diagnostics:**

- Section directories missing `_index.md`

**Options:**

| Flag | Description |
|------|-------------|
| -c, --content DIR | Content directory to check |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

**Example output:**

```
Running diagnostics...

Config:
  ⚠ config.toml: base_url is not set
  ⚠ config.toml: feeds.enabled is true but feeds.filename is not set

Content:
  ⚠ content/blog/draft.md: Missing description in frontmatter
  ℹ content/blog/draft.md: File is marked as draft
  ⚠ content/about.md: Image missing alt text: ![](photo.jpg)

Found 0 error(s), 3 warning(s), 1 info(s)
```

**JSON output example:**

```json
{
  "issues": [
    {
      "level": "warning",
      "category": "config",
      "file": "config.toml",
      "message": "base_url is not set"
    },
    {
      "level": "warning",
      "category": "content",
      "file": "content/blog/draft.md",
      "message": "Missing description in frontmatter"
    },
    {
      "level": "info",
      "category": "content",
      "file": "content/blog/draft.md",
      "message": "File is marked as draft"
    }
  ],
  "summary": {
    "errors": 0,
    "warnings": 2,
    "infos": 1,
    "total": 3
  }
}
```

---

## Shell Completion

Hwaro can generate completion scripts for your shell, providing tab completion for commands, subcommands, and flags.

### Supported Shells

| Shell | Command |
|-------|---------|
| Bash | `hwaro completion bash` |
| Zsh | `hwaro completion zsh` |
| Fish | `hwaro completion fish` |

### Installation

#### Bash

Add to your `~/.bashrc`:

```bash
eval "$(hwaro completion bash)"
```

Or save to a file:

```bash
hwaro completion bash > /etc/bash_completion.d/hwaro
```

#### Zsh

Add to your `~/.zshrc`:

```bash
eval "$(hwaro completion zsh)"
```

Or save to your fpath:

```bash
hwaro completion zsh > ~/.zsh/completions/_hwaro
```

#### Fish

Add to your `~/.config/fish/config.fish`:

```fish
hwaro completion fish | source
```

Or save to the completions directory:

```bash
hwaro completion fish > ~/.config/fish/completions/hwaro.fish
```

### What Gets Completed

The completion scripts provide tab completion for:

- **Commands**: `hwaro <TAB>` → `init`, `build`, `serve`, `new`, `deploy`, `tool`, `completion`
- **Subcommands**: `hwaro tool <TAB>` → `convert`, `list`, `check`
- **Flags**: `hwaro build <TAB>` → `--output-dir`, `--drafts`, `--minify`, etc.
- **Positional arguments**: `hwaro completion <TAB>` → `bash`, `zsh`, `fish`
- **Positional choices**: `hwaro tool convert <TAB>` → `toYAML`, `toTOML`

### Automatic Updates

Completion scripts are generated dynamically from command metadata. When you update Hwaro to a new version with new commands or flags, regenerating the completion script will automatically include them.

```bash
# Regenerate after updating hwaro
eval "$(hwaro completion bash)"
```

## See Also

- [CLI](/start/cli/) — Full CLI command reference
- [Configuration](/start/config/) — Site configuration
- [Build Hooks](/features/build-hooks/) — Custom build commands