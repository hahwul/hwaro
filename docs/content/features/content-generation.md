+++
title = "Content Generation"
description = "Materialize site.data records into real pages with [[content.generate]]"
weight = 22
toc = true
+++

`[[content.generate]]` turns each record of a `site.data` array — a local `data/` file or a [remote data source](/templates/data-model/#remote-data-sources) — into a real content page. Point a rule at an array of records, say which fields become the slug, title and body, and every record builds into a page.

Generated pages are **first-class content**: they join the build at the same point authored files do, so section listings, `[permalinks]` patterns, taxonomies, feeds, the search index, the sitemap, OG images and output formats all apply to them exactly as they do to files in `content/`. Combined with `[[data.remote]]`, this builds an entire section from a headless CMS or any JSON API — no files committed, no scripts.

## Quick Start

```toml
# config.toml
[[content.generate]]
source = "products.items"       # site.data.products.items — must be an array
section = "products"            # pages land at /products/<slug>/
slug = "sku"                    # record field (slugified)
title = "name"                  # record field
body = "description_md"         # record field holding markdown
date = "released"               # optional
description = "{{ item.name }} — {{ item.price }} USD"  # optional, templated
taxonomies = { tags = "categories" }                    # optional
```

```json
// data/products.json
{"items": [
  {"sku": "blue-widget", "name": "Blue Widget", "price": 19.99,
   "released": "2024-01-15", "description_md": "A **blue** widget.",
   "categories": ["gadgets"]}
]}
```

One build later, `/products/blue-widget/` exists — rendered with your `page.html`, listed by the `products` section, tagged under `/tags/gadgets/`, present in the RSS feed, search index and sitemap.

## Fields or Templates

Every value spec (`slug`, `title`, `body`, `date`, `description`, and each `taxonomies` value) accepts one of two forms:

- **A field name** — `slug = "sku"` reads the record's `sku` field. Dotted paths reach into nested objects: `slug = "meta.id"`. A field that does not exist is a **hard error naming the record and the keys that do exist** — typos never silently generate wrong pages. A field that exists but holds `null` or `""` simply omits the optional value (records without a date are fine); for required specs (`slug`, `title`) it is an error.
- **A template** — any spec containing `{{` or `{%` renders as a template with the record bound to `item`, with all of hwaro's filters available: `slug = "{{ item.sku | slugify }}"`, `title = "{{ item.name | title }}"`.

## Rule Reference

| Key | Required | Meaning |
|-----|----------|---------|
| `source` | yes | Dotted path to an array under `site.data` (`"products"` or `"products.items"`). Anything else — a missing key, a table — is a hard error spelling out what was found. |
| `section` | yes | Target section. Pages get the path `<section>/<slug>.md`, so an existing `content/<section>/_index.md` lists them and `[permalinks]` patterns for the section apply. |
| `slug` | yes | Field or template producing each page's slug. The result is slugified; duplicates within or across rules are a hard error naming both records. |
| `title` | yes | Field or template producing the page title. |
| `body` | no | Field or template producing the page's **markdown** body. Shortcodes, syntax highlighting and every markdown extension run on it. |
| `body_template` | no | Alternative to `body`: a template file from `templates/`, rendered with the record as `item`. The output is markdown. Mutually exclusive with `body`. |
| `date` | no | Field or template producing the page date — same formats authored front matter accepts. Future dates keep the page out of a default build, exactly like authored content. |
| `description` | no | Field or template for the page description. |
| `taxonomies` | no | Table of `taxonomy = "spec"`. A field holding an array contributes every element as a term; a scalar contributes one; `null`/`""` contributes none. |

## The Whole Record in Templates

Templates see the full source record as `page.extra.item` — no need to map every field through the rule:

```html
{% if page.synthesized %}
<p class="price">{{ page.extra.item.price }} USD</p>
<p class="stock">{{ page.extra.item.inventory.count }}</p>
{% endif %}
```

`page.synthesized` is `true` on generated pages and `false` everywhere else, so shared templates can branch. Guard `page.extra.item` reads with it — authored pages have no `item`.

## Collisions

An authored file always wins a contested path: if `content/products/red-widget.md` exists, a generated page for the same slug is dropped with a warning, never the other way around. Two records producing the same slug fail the build, naming both records.

## Rebuilds and Caching

Generated content moves with its data. Editing a `data/` file (or a changed `[[data.remote]]` payload) invalidates cached pages the same way a config edit does, and `hwaro serve` triggers a rebuild on data edits. Under `build --cache`, generated pages are always re-rendered — they have no source file to fingerprint — while authored pages keep their cache behavior.

If a record disappears from the data, its page is gone from the next build's page set, but a previously written file may linger in a `--cache`/preserved output directory (the same is true for a renamed authored file). A full build (`hwaro build`) starts from a clean output directory.

## Tooling

`hwaro tool list` includes generated pages with their provenance (`products/blue-widget.md ← data.products.items`), planned from local data files. Rules backed by a `[[data.remote]]` key that has not been fetched yet are noted rather than listed row by row — run a build to materialize them.

## Errors

Every failure names the rule, the record (1-based, in data order) and what to fix:

```
Error [HWARO_E_CONTENT]: [[content.generate]] "products.items": record #37: missing field 'skuu' (available: categories, name, price, released, sku).
```

A rule whose `source` is missing or not an array fails the build too — a typo must never silently generate zero pages.
