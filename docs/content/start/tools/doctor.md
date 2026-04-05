+++
title = "doctor"
description = "Diagnose config and content issues"
weight = 4
+++

Diagnose configuration and content issues in your Hwaro site.

```bash
hwaro doctor

# Check only a specific content directory
hwaro doctor -c posts

# Auto-fix: add missing config sections
hwaro doctor --fix

# Auto-fix with minimal sections (skip pwa, amp, assets, etc.)
hwaro doctor --fix --minimal

# Output result as JSON
hwaro doctor --json
```

> `hwaro tool doctor` also works as a backward-compatible alias.

## Options

| Flag | Description |
|------|-------------|
| -c, --content DIR | Content directory to check |
| --fix | Auto-fix issues (add missing config sections) |
| --minimal | With `--fix`, skip advanced optional sections (pwa, amp, assets, deployment, image_processing, etc.) |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

## What It Checks

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
- Images without alt text (`![](url)`)
- Broken internal links (`@/` prefixed paths that don't resolve)
- Frontmatter parse errors (TOML/YAML)
- Draft files (reported as info)

**Structure diagnostics:**

- Section directories missing `_index.md`

## Example Output

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

## Ignoring Known Issues

If doctor reports issues you are aware of and want to suppress, add their rule IDs to the `[doctor]` section in `config.toml`:

```toml
[doctor]
ignore = [
  "content-draft",
  "content-description-missing",
]
```

Use `hwaro doctor --json` to find rule IDs in the output. Ignored issues are completely excluded from both human-readable and JSON output.

### Available Rule IDs

| ID | Category | Description |
|----|----------|-------------|
| `config-not-found` | config | Config file not found |
| `config-parse-error` | config | Failed to parse config |
| `base-url-missing` | config | base_url is not set |
| `base-url-scheme` | config | base_url doesn't start with http(s) |
| `base-url-trailing-slash` | config | base_url has trailing slash |
| `title-default` | config | Title is still default value |
| `feeds-filename-missing` | config | feeds.enabled but filename empty |
| `sitemap-changefreq-invalid` | config | Invalid sitemap.changefreq |
| `sitemap-priority-range` | config | sitemap.priority out of range |
| `taxonomy-duplicate` | config | Duplicate taxonomy name |
| `search-format-invalid` | config | Unsupported search.format |
| `language-duplicate` | config | Duplicate language code |
| `missing-config-*` | config_missing | Missing config section (e.g. `missing-config-pwa`) |
| `content-title-missing` | content | Missing or "Untitled" title |
| `content-description-missing` | content | Missing description |
| `content-draft` | content | File marked as draft |
| `content-alt-text-missing` | content | Image without alt text |
| `content-internal-link-broken` | content | Broken internal link |
| `content-frontmatter-toml-error` | content | TOML frontmatter parse error |
| `content-frontmatter-yaml-error` | content | YAML frontmatter parse error |
| `content-read-error` | content | Failed to read content file |
| `template-dir-missing` | template | Templates directory not found |
| `template-required-missing` | template | Required template missing |
| `template-unclosed-block` | template | Unclosed block tag |
| `template-mismatched-vars` | template | Mismatched variable tags |
| `template-read-error` | template | Failed to read template |
| `structure-missing-index` | structure | Section missing _index.md |

## JSON Output

```json
{
  "issues": [
    {
      "id": "base-url-missing",
      "level": "warning",
      "category": "config",
      "file": "config.toml",
      "message": "base_url is not set"
    },
    {
      "id": "content-description-missing",
      "level": "warning",
      "category": "content",
      "file": "content/blog/draft.md",
      "message": "Missing description in frontmatter"
    },
    {
      "id": "content-draft",
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
