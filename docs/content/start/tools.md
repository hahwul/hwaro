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
```

**Options:**

| Flag | Description |
|------|-------------|
| -c, --content DIR | Limit conversion to a specific content directory |
| -h, --help | Show help |

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
```

**Options:**

| Flag | Description |
|------|-------------|
| -c, --content DIR | Limit listing to a specific content directory |
| -h, --help | Show help |

**Filters:**

| Filter | Description |
|--------|-------------|
| all | Show all content files |
| drafts | Show only files with `draft = true` |
| published | Show only files with `draft = false` or no draft field |

### deadlink — Dead Link Checker

Check for broken external links in your content files.

```bash
hwaro tool deadlink
```

This command:

1. Scans all Markdown files in the `content/` directory
2. Finds external URLs (http/https links)
3. Sends concurrent HEAD requests to each URL
4. Reports broken or unreachable links

**Example output:**

```
Checking links in content/...
Found 42 external links in 15 files

✓ https://example.com (200)
✓ https://crystal-lang.org (200)
✗ https://old-site.com/page (404)
✗ https://broken-link.invalid (Connection refused)

Results: 40 OK, 2 broken
```

### doctor — Site Diagnostics

Diagnose configuration and content issues in your Hwaro site.

```bash
hwaro tool doctor

# Check only a specific content directory
hwaro tool doctor -c posts
```

This command checks:

**Config diagnostics:**

- `base_url` is not set
- `title` is still the default value
- `feeds.enabled` is true but `feeds.filename` is empty
- `sitemap.changefreq` has an invalid value
- `sitemap.priority` is out of range (0.0–1.0)
- Duplicate taxonomy names
- Invalid `search.format` value

**Content diagnostics:**

- Missing `title` in frontmatter
- Missing `description` in frontmatter
- Missing `date` in frontmatter
- Images without alt text (`![](url)`)
- Frontmatter parse errors (TOML/YAML)
- Draft files (reported as info)

**Options:**

| Flag | Description |
|------|-------------|
| -c, --content DIR | Content directory to check |
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