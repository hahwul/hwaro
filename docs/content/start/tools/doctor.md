+++
title = "doctor"
description = "Diagnose config, template, and structure issues"
weight = 4
+++

Diagnose configuration, template, and structure issues in your Hwaro site.

> For content validation (frontmatter, alt text, internal links), use [`hwaro tool validate`](/start/tools/validate/).

```bash
hwaro doctor

# Check a content directory other than ./content
hwaro doctor -c src/content

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

- `base_url` is not set, or has a trailing slash
- `title` is still a placeholder (`Hwaro Site`, `My Hwaro Site`)
- `sitemap.changefreq` has an invalid value
- `sitemap.priority` is out of range (0.0 to 1.0), or not a finite number (`inf`, `nan`)
- Duplicate taxonomy names, or language codes that differ only in case (`en` / `EN`)
- Invalid `search.format`, `markdown.math_engine` or `pwa.cache_strategy` value
- `default_language` with no matching `[languages.<code>]` block
- `deployment.target` / `[related] taxonomies` referencing something undefined
- `[[menus.*]]` entries whose `parent` names no identifier in the same menu
- `[[versions.list]]` entries whose content path does not exist
- Referenced files and directories that don't exist (`[og] default_image`,
  `[pwa] icons`, `[auto_includes] dirs`, `[[assets.bundles]] files`, …).
  Values that carry their own origin (`https://…`, `//cdn…`, `data:…`) are
  left alone, since doctor can't validate a remote URL.
  - `[og] default_image` and `[pwa] icons` are URL paths, so they must name a
    file the site publishes: one under `static/` (copied to the site root), a
    `content/` file that `[content.files]` publishes, or a file in the last
    build output. A `static/` prefix on `default_image` is reported, because the
    file publishes without it.
  - `[auto_includes] dirs` are looked up under `static/`, as the build does.
- SCSS sources the build never compiles (a root `sass/` directory, or entry
  files under `static/` while `[sass]` is off)
- Build output that cannot back a route check (see
  [Build output as evidence](#build-output-as-evidence))

**Template diagnostics:**

- Templates directory not found
- `page.html` missing (an error: pages would render as raw content). A
  `default.html` counts, because the build uses it in place of `page.html`.
- `section.html` missing (a warning: section pages render with `page.html`)
- Template syntax errors, reported by the same Crinja parser the build uses
  (block shortcodes such as `{% alert(type="info") %}…{% end %}`, which the
  build expands before parsing, are not errors; an unknown tag such as a
  misspelled `{% includ %}` is)

**Content diagnostics:**

- Content directory not found (the build would produce no pages)
- Front matter that fails to parse (TOML/YAML)
- Front matter registering a menu name no `[[menus.*]]` declares. A page in
  another language is checked against that language's
  `[[languages.<code>.menus.*]]` when it declares its own menus.
- Front matter `template` (or a section's `page_template` or `[cascade]
  template`) naming a template that does not exist, which the build silently
  replaces with the default

**Structure diagnostics:**

- Section directories missing `_index.md`

**Translation report** (sites with more than one language):

- A page or section that exists in the default language but has no
  counterpart in another configured language (`translation-missing`)
- A translation with no default-language original (`translation-orphan`)

Pages are paired exactly as the build pairs `page.translations` (same base
name without the language suffix, so `about.md`, `about.en.md` and
`about.ko.md` belong together), and only pages a default build publishes
count: a draft or future-dated page neither has nor provides a translation.
Both are `info` level, so `--strict` never fails on a partial translation.
The human report groups them per language with counts:

```
Translations:
  ko: 2 missing · 1 without original
  [info] content/about.md: No 'ko' translation
  [info] content/blog/_index.md: No 'ko' translation
  [info] content/notes.ko.md: 'ko' translation has no 'en' original
```

In `--json` each of these issues also carries a `language` field. Silence
either kind with `[doctor] ignore`.

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
    [ok]   versions (content paths exist)
    [ok]   markdown / pwa (valid enums)
    [ok]   image processing (widths set)
    [ok]   deployment / related (refs resolve)
    [ok]   menus (parent references)
    [ok]   referenced files & dirs
    [ok]   build output (route evidence)
    [ok]   sass (sources & enablement)

  templates/
    [ok]   required files (page.html, section.html)
    [ok]   template syntax

  content/
    [ok]   directory present
    [ok]   front matter (TOML/YAML parse)
    [ok]   front matter menus (declared in config)
    [ok]   front matter templates (exist)
    [info] section index files (_index.md)
    [ok]   translations (pages in every language)

Config:
  [warn] config.toml: base_url is not set

Structure:
  [info] content/docs: Section directory missing _index.md: docs/

checked: 0 errors, 1 warning, 1 info

Tip: Use 'hwaro tool validate' for content checks
```

A check whose scan never ran renders as `[--] … (skipped)` rather than as a
passing check, for example `template syntax` when `templates/` is missing.

In a color terminal the check lines use `✓`/`⚠`/`✗`/`ℹ` glyphs under an
`hwaro doctor` heading, and the summary is a severity-colored `✦ checked` outcome
line. A clean run ends with `checked: no issues found — your site looks great`.

## Build Output as Evidence

`[pwa] offline_page` and `[pwa] precache_urls` are routes, not files. Doctor
resolves them against `content/` first and, for values that carry an
extension such as a compiled stylesheet or a resized image variant, against
the last build in `[build] output_dir` (`public/` by default).

That tree has to come from `hwaro build`. Since Hwaro 0.19, `hwaro serve`
builds into `.hwaro/serve/` and leaves `output_dir` alone, so in a serve-only
workflow it is either absent or frozen at an old build. Doctor now says so
instead of leaving you to guess:

- **Absent or empty** — reported as `build-output-unusable`, alongside the
  route it could not validate: *"public/ holds no build output — run `hwaro
  build` first"*.
- **`hwaro serve` output** (a leftover `.hwaro-dev` marker) — never used as
  evidence, the same rule `hwaro deploy` applies. `hwaro build` clears the
  marker.
- **Older than your newest source file** — reported as `build-output-stale`
  when a route was accepted from it, because a page you deleted still has its
  `index.html` standing in that tree.

Both are `info` level and appear only when the tree actually mattered: a site
that references no build-generated path never hears about `public/`.

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

> `ignore` only silences **warning** and **info** issues. Error-level rules
> (marked ✗ below) report problems that will fail `hwaro build` anyway, so
> listing one cannot disable the CI gate. Doctor keeps reporting it and warns
> that the entry has no effect.

### Available Rule IDs

Rows marked ✗ are error level and **cannot** be ignored.

| ID | Category | Description |
|----|----------|-------------|
| `config-not-found` | config | Config file not found ✗ |
| `config-parse-error` | config | Failed to parse config ✗ |
| `base-url-missing` | config | base_url is not set |
| `base-url-trailing-slash` | config | base_url has trailing slash |
| `title-default` | config | Title is still a scaffold placeholder |
| `sitemap-changefreq-invalid` | config | Invalid sitemap.changefreq |
| `sitemap-priority-range` | config | sitemap.priority out of range |
| `taxonomy-duplicate` | config | Duplicate taxonomy name |
| `language-duplicate` | config | Duplicate language code |
| `search-format-invalid` | config | Unsupported search.format |
| `default-language-undefined` | config | default_language has no `[languages.<code>]` block |
| `markdown-math-engine-invalid` | config | Unsupported markdown.math_engine |
| `pwa-cache-strategy-invalid` | config | Unsupported pwa.cache_strategy |
| `pwa-display-invalid` | config | Unsupported pwa.display |
| `image-processing-widths-empty` | config | image_processing enabled but widths is empty (silent no-op) |
| `deployment-target-undefined` | config | deployment.target names no `[[deployment.targets]]` |
| `related-taxonomy-undefined` | config | `[related]` references an undefined taxonomy |
| `menu-parent-undefined` | config | Menu entry's `parent` matches no identifier in that menu |
| `version-path-missing` | config | A `[[versions.list]]` path does not exist under `content/` |
| `config-path-missing` | config | Referenced file does not exist |
| `config-dir-missing` | config | Referenced directory does not exist |
| `build-output-unusable` | config | `[build] output_dir` could not validate a route (absent, or `hwaro serve` output) |
| `build-output-stale` | config | A route was accepted from build output older than the sources |
| `sass-dir-not-scanned` | config | SCSS files under a root `sass/` directory, which the build never scans |
| `sass-disabled-with-sources` | config | SCSS entry files under `static/` while `[sass]` is off |
| `missing-config-*` | config_missing | Missing config section (e.g. `missing-config-pwa`) |
| `template-dir-missing` | template | Templates directory not found ✗ |
| `template-required-missing` | template | `page.html` (or `default.html`) missing ✗ |
| `template-section-missing` | template | `section.html` missing; sections render with `page.html` |
| `template-syntax-error` | template | Template fails to parse ✗ |
| `template-read-error` | template | Failed to read template ✗ |
| `content-dir-missing` | content | Content directory not found |
| `content-frontmatter-invalid` | content | Front matter fails to parse ✗ |
| `content-read-error` | content | Failed to read content file ✗ |
| `menu-undeclared` | content | Front matter menu name not declared in config |
| `content-template-missing` | content | Front matter `template` / `page_template` / `[cascade] template` names a missing template |
| `structure-missing-index` | structure | Section missing _index.md |
| `translation-missing` | i18n | Page or section has no counterpart in a configured language |
| `translation-orphan` | i18n | Translation has no default-language original |

An entry that matches no rule id is reported as having no effect, so a typo
in this list never passes silently.

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
  },
  "exit_code": 0
}
```
