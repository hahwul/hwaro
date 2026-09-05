+++
title = "Versioned Docs"
description = "Publish several documentation versions side by side with a version switcher"
weight = 23
toc = true
+++

Hwaro can publish several versions of the same documentation (v1, v2, …) from one site, with a version switcher, per-version navigation and SEO that points search engines at the current release. Versioning is **directory-based** and modeled on [multilingual](/features/multilingual/) support: a page belongs to the version whose content directory contains it.

## Configuration

```toml
[versions]
latest_at_root = true     # latest version renders at its section's natural URL
noindex_old = true        # older versions: <meta name="robots" content="noindex"> + canonical to the latest counterpart
search = "latest"         # "latest" | "all" — which versions enter search.json AND sitemap.xml
feeds = "latest"          # "latest" | "all" — which versions feed RSS/Atom
taxonomies = "latest"     # "latest" | "all" — which versions taxonomy term pages collect from

[[versions.list]]
name = "v2"               # URL segment, must be URL-safe (letters, digits, - _ . ~)
label = "2.x (latest)"    # switcher label (defaults to name)
path = "docs/v2"          # content directory relative to content/ (defaults to name)
latest = true

[[versions.list]]
name = "v1"
label = "1.x"
path = "docs/v1"
```

TOML cannot make one key both a table and an array of tables, so the switches live in `[versions]` and the entries in `[[versions.list]]`. If you only need the defaults, a bare array works too:

```toml
[[versions]]
name = "v2"
path = "docs/v2"
latest = true

[[versions]]
name = "v1"
path = "docs/v1"
```

Validation (all of these fail the build with `HWARO_E_CONFIG`):

- `name` is required, URL-safe and unique.
- `path` must be a directory relative to `content/`; two versions can neither share a path nor nest inside each other.
- Exactly one entry is `latest = true`. If none is marked, the **first** entry is the latest; two or more marked entries are an error.
- `search`, `feeds` and `taxonomies` accept only `"latest"` or `"all"`.

`hwaro doctor` warns (`version-path-missing`) when a version points at a content directory that does not exist.

## Content Structure

Each version is a normal content tree under its own directory. Files with the same path relative to the version root are treated as the same page in different versions. That is how the switcher finds counterparts.

```
content/
└── docs/
    ├── v2/
    │   ├── _index.md
    │   ├── install.md
    │   └── plugins.md      # only in v2
    └── v1/
        ├── _index.md
        ├── install.md
        └── legacy.md       # only in v1
```

### URL Mapping

The version directory is swapped for the directory the version *publishes* under. With `latest_at_root = true` (the default) the latest version takes the parent's natural URL and older versions get a `/<name>/` segment:

| Source | URL |
|--------|-----|
| `content/docs/v2/_index.md` | `/docs/` |
| `content/docs/v2/install.md` | `/docs/install/` |
| `content/docs/v1/_index.md` | `/docs/v1/` |
| `content/docs/v1/install.md` | `/docs/v1/install/` |

With `latest_at_root = false` every version keeps its segment (`/docs/v2/install/`, `/docs/v1/install/`) and `/docs/` becomes a redirect stub to the latest version's root, unless you author your own `content/docs/_index.md`, which then keeps that URL.

The URL segment is the version **name**, not the directory basename: `name = "2.x"` with `path = "docs/v2"` publishes at `/docs/2.x/…` when it is not at root. Version directories may also sit at the top level (`content/v2/…`), in which case the latest version *is* the site root.

Notes:

- With `latest_at_root = true` do not also author `content/docs/_index.md`: it claims the same `/docs/` URL as the latest version's root and the build reports a duplicate output path (the authored file wins, the version root is not written).
- `[permalinks]` rules and `slug` apply to the published path (`docs/install.md`), not the source path.
- An explicit `path = "…"` in front matter wins outright, exactly as it does for languages. A custom path is not prefixed, so keep them distinct across versions.
- Everything under a version directory is versioned: page bundles, assets, `_index.md` cascades and `[[content.generate]]` output whose target path falls inside it.

### Multilingual

Languages and versions combine: the language prefix comes first, the version after. `content/docs/v1/install.ko.md` renders at `/ko/docs/v1/install/`, and `foo.ko.md` files inside a version directory behave exactly as they do elsewhere (translations, hreflang, per-language menus).

## Template Variables

### page.version

`nil` for unversioned pages (so `{% if page.version %}` is the guard), otherwise:

| Property | Type | Description |
|----------|------|-------------|
| `.name` | String | Version name (`"v2"`) |
| `.label` | String | Display label (`"2.x (latest)"`) |
| `.latest` | Bool | Is this the latest version |
| `.url` | String | Root URL of the version in the page's language (`/docs/`, `/ko/docs/v1/`) |

### page.version_links

One entry per configured version, in config order. These are the switcher rows. Empty for unversioned pages.

| Property | Type | Description |
|----------|------|-------------|
| `.name` | String | Version name |
| `.label` | String | Display label |
| `.latest` | Bool | Is the latest version |
| `.url` | String | The **same page** in that version when it exists, else that version's root |
| `.exists` | Bool | Whether the counterpart page exists (`false` → `url` is the version root) |
| `.current` | Bool | Whether this row is the page's own version |

Counterparts are matched by path relative to the version root, in the same language: `docs/v1/install.md` ↔ `docs/v2/install.md`, `docs/v1/install.ko.md` ↔ `docs/v2/install.ko.md`. A `render = false` counterpart does not count as existing.

### versions (global)

Available on every page of a versioned site. It is a list (`{% for v in versions %}`) of `{name, label, latest, url}` entries whose `url` is each version's root in the current page's language, plus:

| Property | Description |
|----------|-------------|
| `versions.latest` | The latest version entry |
| `versions.all` | The same list as a plain array |
| `versions.size` | Number of versions |

Like `page.url`, every URL above is site-relative, so prefix it with `{{ base_url }}` (or `{{ base_path }}`) in links so [subpath deployments](/start/config/#base-url) work.

## Version Switcher Example

```jinja
{% if page.version %}
<details class="version-switch">
  <summary aria-label="Switch documentation version">
    {{ page.version.label }}
    {% if not page.version.latest %}<span class="badge">old</span>{% endif %}
  </summary>
  <ul>
    {% for v in page.version_links %}
    <li>
      <a href="{{ base_url }}{{ v.url }}"
         {% if v.current %}class="current" aria-current="page"{% endif %}
         {% if not v.exists %}title="This page does not exist in {{ v.label }} — opens the {{ v.label }} start page"{% endif %}>
        {{ v.label }}{% if v.latest %} (latest){% endif %}
      </a>
    </li>
    {% endfor %}
  </ul>
</details>

{% if not page.version.latest %}
<div class="version-banner">
  You are reading the {{ page.version.label }} documentation.
  {% for v in page.version_links %}{% if v.latest %}
  <a href="{{ base_url }}{{ v.url }}">{% if v.exists %}Read this page in {{ v.label }}{% else %}Go to the {{ v.label }} docs{% endif %}</a>
  {% endif %}{% endfor %}
</div>
{% endif %}
{% endif %}
```

A site-wide entry point that does not depend on the current page:

```jinja
<a href="{{ base_url }}{{ versions.latest.url }}">Docs ({{ versions.latest.label }})</a>
<select onchange="location.href=this.value">
  {% for v in versions %}
  <option value="{{ base_url }}{{ v.url }}">{{ v.label }}</option>
  {% endfor %}
</select>
```

## Scoping Rules

Every version is its own tree; nothing leaks across the boundary:

| Surface | Behavior |
|---------|----------|
| `page.lower` / `page.higher` | The reading order is built per `{language, version}`. The last v1 page has no "next"; it never jumps into v2. |
| `page.ancestors` (breadcrumbs) | Stop at the version root. An unversioned `docs/_index.md` is not an ancestor of `docs/v1/…`. |
| `get_section()`, `section.pages`, `section.subsections` | A version root is not a subsection or page of its unversioned parent; listings inside a version only see that version. |
| Menus (`get_menu`) | Config `[[menus.*]]` entries appear everywhere. Front-matter `menus = […]` registrations from a versioned page appear only in that version's menus; unversioned pages additionally see the **latest** version's registrations. |
| Related posts | Never cross a version boundary. |
| Taxonomies | Term pages collect from unversioned content plus the latest version (`taxonomies = "latest"`, the default). Set `taxonomies = "all"` to list every version. |

Series are not version-aware: a `series` shared by a v1 and a v2 page groups them together.

## SEO & Discovery

### Canonical and noindex

Pages of an older version emit a canonical link to their **latest counterpart** when it exists (self-canonical otherwise) and, with `noindex_old = true` (default), a `<meta name="robots" content="noindex">` right after it. Both come out of `{{ canonical_tag }}`, so templates that already print it need no change; `seo.canonical_url` follows the same rule and `seo.noindex` exposes the flag.

```html
<link rel="canonical" href="https://example.com/docs/install/">
<meta name="robots" content="noindex">
```

Latest-version pages self-canonicalize as usual. Paginated listings keep self-canonicalizing (`page/2/` of an old section is not `page/2/` of the new one). `hreflang_tags` are unaffected, since they link translations of the same version.

### Discovery surfaces

| Surface | Switch | Default |
|---------|--------|---------|
| `search.json` | `[versions] search` | latest only |
| `sitemap.xml` | `[versions] search` (same switch) | latest only |
| RSS / Atom (main, section, per-language) | `[versions] feeds` | latest only |
| Taxonomy term pages | `[versions] taxonomies` | latest only |
| `llms.txt` / `llms-full.txt` | — | always latest only |

Unversioned pages always pass. With `search = "all"` every record in `search.json` carries a `version` field (the version name) so a client can filter results to the version being read:

```js
const current = document.documentElement.dataset.version; // e.g. from data-version="{{ page.version.name }}"
const hits = results.filter((r) => !r.version || r.version === current);
```

## Build Cache, Serve and Doctor

- `[versions]` is part of the config hash and version membership is part of the page-set fingerprint, so `hwaro build --cache` rebuilds what changes when you move a file between version directories, add a counterpart (the other version's `version_links` flips `exists`) or change the switches.
- `hwaro serve` builds versioned sites like any other; edits inside a version directory are picked up incrementally.
- `hwaro doctor` reports `version-path-missing` for a `[[versions.list]]` entry whose directory is absent.

## Not Included

- Redirect rules for URLs that exist only in the latest version (an old-version 404 is a plain 404).
- Version-aware series.
- The `docs` scaffold is unchanged; add `[versions]` to a generated site by hand using the snippet above.

## See Also

- [Multilingual](/features/multilingual/) — the language layer versions compose with
- [Data Model](/templates/data-model/) — every `page.*` and global variable
- [SEO](/features/seo/) — canonical, robots and sitemap details
- [Configuration](/start/config/) — full `config.toml` reference
