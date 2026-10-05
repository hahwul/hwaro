+++
title = "Front Matter Schema"
description = "Declare the front matter each section requires, with types, enums, bounds and defaults"
weight = 6
toc = true
+++

A front-matter schema turns a typo or a missing field into a build error with the file and line, instead of a key that quietly lands in `extra`. Schemas are declared per section in `config.toml` and are off until you add one.

## Declaring a Schema

```toml
[[content.schema]]
sections = ["posts", "docs/**"]   # section-path globs; "" is the root
strict = false                    # true: unknown top-level keys are errors

[content.schema.fields.author]
type = "string"
required = true

[content.schema.fields.status]
type = "string"
enum = ["draft", "review", "final"]
default = "draft"

[content.schema.fields."extra.rating"]
type = "int"
min = 1
max = 5
```

### Schema keys

| Key | Type | Description |
|-----|------|-------------|
| sections | string or array | Section path globs. A page's section is its directory under `content/` (`posts/hello.md` → `posts`, a bundle `posts/hello/index.md` → `posts`, `about.md` → `""`). `"docs/**"` matches `docs` and everything below it; `"**"` matches every page |
| strict | bool | When true, a top-level key that is neither a [known front-matter field](/writing/pages/) nor declared in `fields` is an error. Keys under `[extra]` are always allowed |
| fields | table | One `[content.schema.fields.<name>]` table per field |

### Field keys

| Key | Description |
|-----|-------------|
| type | Required. `string`, `int`, `float`, `bool`, `date`, `array` or `table` |
| required | `true`: the field must be present |
| enum | Allowed values (string, int and float fields) |
| min / max | Bounds: the value for `int`/`float`, the length for `string`/`array` |
| default | Applied when the field is missing, before templates run |

## Matching

A page is checked against the **first** schema (in config order) whose `sections` match its section, the same "first match wins" rule as `[permalinks]`. A page that matches no schema is not checked. Only regular pages are checked, not section `_index.md` files, and only pages the build publishes: a draft is checked when you build with `--drafts`.

Validation runs after front matter and [cascade](/writing/sections/#cascade) are applied, so a value a parent section cascades counts as present.

## Field Names

- `extra.<key>` names a key in `page.extra`. Only one level nests: `extra.author.name` is not allowed. Quote the dotted name in the table header: `[content.schema.fields."extra.rating"]`.
- A name without `extra.` names a known front-matter field (`description`, `weight`, `tags`, …) when there is one. Otherwise it names the `extra` key of that name: Hwaro stores an unknown top-level key such as `author = "x"` in `page.extra`, so `fields.author` matches both `author = "x"` and `[extra] author = "x"`.

## Types

| Type | Accepts |
|------|---------|
| string | A string |
| int | An integer. `4.0` is **not** an int |
| float | A floating-point number. `4` is **not** a float; write `4.0` |
| bool | `true` / `false` |
| date | What the `date` field accepts: a TOML/YAML datetime, or a string such as `2024-01-15`, `2024-01-15 10:00:00` or RFC 3339 |
| array | A list |
| table | A table / mapping |

## Defaults

When a field is missing, its `default` is set on the page before rendering, so templates see it: `{{ page.extra.status }}` for an extra key, or the typed property (`{{ page.description }}`) for a known field. Defaults can fill extra keys and these known fields: `description`, `image`, `template`, `draft`, `render`, `toc`, `insert_anchor_links`, `in_sitemap`, `in_search_index`, `weight`, `series`, `series_weight`, `tags`, `authors`, `updated`. Fields such as `slug`, `path` and `date` are resolved while the page is parsed, so a default on them is a config error.

A default must satisfy its own field (type, enum, bounds). A field with a default is never reported missing.

## Errors

Every violation across every page is collected, then the build fails once (`HWARO_E_CONTENT`, exit 5) with the list sorted by file:

```
Error [HWARO_E_CONTENT]: 4 front-matter schema violations:
  content/posts/a.md: field "author": required but missing
  content/posts/a.md:3: field "status": "bogus" is not one of "draft", "review", "final"
  content/posts/a.md:4: field "autor": unknown front-matter key — did you mean "author"?
  content/posts/b.md:6: field "extra.rating": 9 is greater than the maximum 5
```

The line is the key's line in the front matter; a missing field names the file only. Under `strict`, an unknown key gets a "did you mean" against the known and declared fields.

A malformed schema (unknown `type`, an `enum` the type can't carry, `min` greater than `max`, an unknown key in a field table, a default of the wrong type) is a config error (`HWARO_E_CONFIG`, exit 3).

In `hwaro serve`, a violation shows in the browser error overlay like other content errors; saving the fixed file rebuilds and clears it.

## Doctor and Validate

[`hwaro doctor`](/start/tools/doctor/) and [`hwaro tool validate`](/start/tools/validate/) run the same check over the pages a default build publishes and report the same violations as `content-schema-violation` errors. `tool validate --json` also lists the defaults each page takes:

```json
{
  "findings": [
    {
      "file": "content/posts/a.md",
      "line": 3,
      "rule": "content-schema-violation",
      "severity": "error",
      "message": "line 3: field \"status\": \"bogus\" is not one of \"draft\", \"review\", \"final\""
    }
  ],
  "defaults": {
    "content/posts/b.md": { "status": "draft" }
  }
}
```

## See Also

- [Pages](/writing/pages/) — the known front-matter fields
- [Sections](/writing/sections/) — `[cascade]`
- [Configuration](/start/config/)
