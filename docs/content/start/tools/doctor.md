+++
title = "doctor"
description = "Diagnose config, template, and structure issues"
weight = 4
+++

Diagnose configuration, template, and structure issues in your Hwaro site.

> For content validation (frontmatter, alt text, internal links), use [`hwaro tool validate`](/start/tools/validate/).

```bash
hwaro doctor

# Check only a specific content directory
hwaro doctor -c posts

# Normalize config values (base_url trailing slash, sitemap priority, …)
hwaro doctor --fix

# Add recommended config sections to config.toml
hwaro doctor --approve

# Do both (equivalent to --fix --approve)
hwaro doctor --full

# Preview changes without writing config.toml
hwaro doctor --full --dry-run

# Output result as JSON
hwaro doctor --json
```

> `hwaro tool doctor` also works as a backward-compatible alias.

## Options

| Flag | Description |
|------|-------------|
| -c, --content-dir DIR | Content directory to check (default: content) |
| --fix | Perform real fixes — normalize values (base_url trailing slash, sitemap priority, …) |
| --approve | Approve and add recommended optional config sections |
| --full | Both `--fix` and `--approve` |
| --dry-run | Preview changes without writing `config.toml` |
| --strict | Treat warnings as errors when computing the exit code |
| --max-warnings N | Exit non-zero when warning count exceeds N |
| -j, --json | Output result as JSON |
| -q, --quiet | Suppress info output and banner |
| -h, --help | Show help |

## What It Checks

**Config diagnostics:**

- `base_url` is not set
- `base_url` doesn't start with `http://` or `https://`
- `base_url` has a trailing slash
- `title` is still the default value
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

**Structure diagnostics:**

- Section directories missing `_index.md`

## Example Output

```
hwaro: doctor

  config.toml
    [ok]   file present & parseable
    [warn] base_url, title
    [ok]   sitemap (changefreq, priority)
    [ok]   taxonomies (duplicates)
    [ok]   search (format)
    [ok]   languages (default_language resolves)
    [ok]   markdown / pwa (valid enums)
    [ok]   deployment / related (refs resolve)
    [ok]   referenced files & dirs

  templates/
    [ok]   required files (page.html, section.html)
    [ok]   template syntax

  content/
    [ok]   front matter (TOML/YAML parse)

Config:
  [warn] config.toml: base_url is not set

Structure:
  [info] content/docs: Section directory missing _index.md: docs/

checked: 0 errors, 1 warning, 1 info

Tip: Use 'hwaro tool validate' for content checks
```

In a color terminal the check lines use `✓`/`⚠`/`✗`/`ℹ` glyphs under an
`hwaro doctor` heading, and the summary is a severity-colored `✦ checked` outcome
line. A clean run ends with `checked: no issues found — your site looks great`.

## Ignoring Known Issues

If doctor reports issues you are aware of and want to suppress, add their rule IDs to the `[doctor]` section in `config.toml`:

```toml
[doctor]
ignore = [
  "title-default",
  "structure-missing-index",
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
| `sitemap-changefreq-invalid` | config | Invalid sitemap.changefreq |
| `sitemap-priority-range` | config | sitemap.priority out of range |
| `taxonomy-duplicate` | config | Duplicate taxonomy name |
| `search-format-invalid` | config | Unsupported search.format |
| `language-duplicate` | config | Duplicate language code |
| `missing-config-*` | config_missing | Missing config section (e.g. `missing-config-pwa`) |
| `template-dir-missing` | template | Templates directory not found |
| `template-required-missing` | template | Required template missing |
| `template-unclosed-block` | template | Unclosed block tag |
| `template-mismatched-vars` | template | Mismatched variable tags |
| `template-read-error` | template | Failed to read template |
| `structure-missing-index` | structure | Section missing _index.md |

## JSON Output

```json
{
  "schema_version": 1,
  "issues": [
    {
      "id": "base-url-missing",
      "level": "warning",
      "category": "config",
      "file": "config.toml",
      "message": "base_url is not set"
    }
  ],
  "summary": {
    "errors": 0,
    "warnings": 1,
    "infos": 0,
    "total": 1
  }
}
```
