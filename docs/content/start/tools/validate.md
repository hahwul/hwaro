+++
title = "validate"
description = "Validate content frontmatter and markup"
weight = 8
+++

Validate content files for frontmatter completeness, accessibility, and structural correctness.

```bash
# Validate all content files
hwaro tool validate

# Validate a specific content directory
hwaro tool validate -c posts

# Fail CI on any warning, or cap the allowed warning count
hwaro tool validate --strict
hwaro tool validate --max-warnings 5

# Output as JSON
hwaro tool validate --json
```

## Options

| Flag | Description |
|------|-------------|
| -c, --content-dir DIR | Content directory (default: content) |
| --strict | Treat warnings as errors when computing the exit code |
| --max-warnings N | Exit non-zero when warning count exceeds N (default: unlimited) |
| -j, --json | Output result as JSON |
| -h, --help | Show help |

## What It Checks

- Missing `title` in frontmatter
- Missing `description` in frontmatter
- Markdown images with empty alt text (`![](url)`) and raw HTML `<img>` elements with no `alt` attribute (an explicit `alt=""` marks a decorative image and is accepted); code blocks, inline code and HTML comments are not scanned
- Broken internal links: `@/` paths the build cannot resolve — the exact source path of a published page, as with `tool check-links`
- Frontmatter parse errors (TOML/YAML/JSON)
- Invalid date formats
- Mixed-case tags (e.g., `Crystal` instead of `crystal`)
- Draft files (reported as info)
- Violations of the [front-matter schema](/writing/schema/) when `config.toml`
  declares `[[content.schema]]`: the build's own check over the pages a default
  build publishes, so validate and `hwaro build` report the same violations.
  validate reads the `config.toml` next to the content directory, and only when
  it declares a schema; a malformed schema exits with the config error code (3)

## Example Output

```
hwaro: validate content

content/blog/draft.md:
      [warn] Missing description in frontmatter
      [info] File is marked as draft

content/about.md:
      [warn] Image missing alt text: ![](photo.jpg)
      [info] Tag has mixed case: "Crystal" (consider lowercase)

checked: 0 errors, 2 warnings, 2 info
```

In a color terminal the findings use `⚠`/`✗`/`ℹ` glyphs under an `hwaro validate`
heading, and the closing line is a severity-colored `✦ checked` outcome. The
command exits non-zero when error-level issues are found, so it can gate CI.

Exit codes mirror `hwaro doctor`: error-level findings exit with the content
error code (5), while warning-driven failures from `--strict` or
`--max-warnings` exit with the generic code (1), so a consumer can still tell a
broken file from a tightened gate. Both flags apply to `--json` runs too.

With `-q`/`--quiet` the report is suppressed, but each error and warning is
still printed to stderr as one `file: message` line, so a failing quiet run
says why it failed.

## Rule IDs

| ID | Level | Description |
|----|-------|-------------|
| `content-title-missing` | warning | Missing or "Untitled" title |
| `content-description-missing` | warning | Missing description |
| `content-alt-text-missing` | warning | Image without alt text |
| `content-internal-link-broken` | warning | Broken `@/` internal link |
| `content-date-invalid` | warning | Unrecognized date format |
| `content-frontmatter-toml-error` | error | TOML frontmatter parse error |
| `content-frontmatter-yaml-error` | error | YAML frontmatter parse error |
| `content-frontmatter-json-error` | error | JSON frontmatter parse error |
| `content-read-error` | error | Failed to read content file |
| `content-tag-mixed-case` | info | Tag has mixed case |
| `content-draft` | info | File marked as draft |
| `content-schema-violation` | error | Front matter violates its `[[content.schema]]` |

## JSON Output

```json
{
  "findings": [
    {
      "file": "content/blog/draft.md",
      "line": null,
      "rule": "content-description-missing",
      "severity": "warning",
      "message": "Missing description in frontmatter"
    }
  ]
}
```

A schema violation carries its `line` (null for a missing field). When
`[[content.schema]]` is declared, a `defaults` object lists, per file, the
defaults a build applies to that page's missing fields:

```json
{
  "findings": [],
  "defaults": {
    "content/posts/b.md": { "status": "draft" }
  }
}
```
