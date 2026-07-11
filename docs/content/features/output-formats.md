+++
title = "Output Formats"
description = "Render extra per-page/per-section output formats (JSON, XML, TXT, CSV) alongside HTML"
weight = 12
toc = true
+++

Beyond the HTML page every page and section always renders, Hwaro can
additionally render sibling non-HTML files — a JSON representation of a post,
an XML feed-like listing for a section, a plain-text export, and so on. HTML
rendering is unaffected; extra formats are strictly additive.

## Configuration

```toml
[outputs]
page = []                 # e.g. ["json"] — formats every regular page emits
section = ["json"]        # formats every section index emits
sections = []              # optional allowlist of section names; empty = all
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| page | array | [] | Formats every regular page emits |
| section | array | [] | Formats every section index emits |
| sections | array | [] | Section names (and their descendants) to restrict `section` output to; empty = all sections |

Only four formats are supported — the format name IS the file extension:

```
json  txt  xml  csv
```

An unknown format name in `[outputs]` fails the build immediately with a
classified config error, rather than silently producing no output.

`sections` matches a section by name or by any of its descendants (a value of
`"posts"` also matches `"posts/reviews"`), the same rule `[feeds].sections`
uses.

## Front Matter Override

A page (or section) can override the config default with a top-level
`outputs` key in its front matter:

```toml
+++
title = "My Post"
outputs = ["json"]
+++
```

`outputs` is not a first-class front matter field — like any other unknown
top-level key, it lands in `page.extra["outputs"]` and is exposed to
templates as `page.extra.outputs`. Its *presence* in front matter always
wins over the config default, including an explicit empty list:

```toml
+++
title = "Opt this page out"
outputs = []
+++
```

suppresses every format for that one page even if `[outputs].page` is
non-empty in `config.toml`. When the key is absent entirely, the config
default (and `sections` allowlist, for sections) applies.

Because it's an ordinary `extra` value, it also cascades through a section's
`[cascade.extra]` table like any other extra field:

```toml
+++
title = "Blog"

[cascade.extra]
outputs = ["json"]
+++
```

gives every descendant page `outputs = ["json"]` unless a page sets its own.
A malformed override (not an array, or containing a name outside
`json`/`txt`/`xml`/`csv`) is ignored with a one-time build warning — the page
falls back to no extra formats rather than failing the build.

## Templates

Each enabled format is rendered from a dedicated Crinja template. Templates
are named by extension, same convention as `page.html`/`section.html`:

```
templates/page.json.jinja
templates/section.json.jinja
templates/page.xml.jinja
```

Only the final, recognized template extension (`.html`, `.j2`, `.jinja2`,
`.jinja`, `.ecr`) is stripped when Hwaro loads templates — the `.json`/`.xml`
part is kept as part of the template's name, e.g. `templates/page.json.jinja`
loads as `page.json`.

A page's own body markdown/content, `toc`, and every other value normally
available to `page.html`/`section.html` (`page`, `section`, `site`, `config`,
…) are available in the format template too — write whatever the format
needs, for example:

```jinja
{# templates/page.json.jinja #}
{
  "title": {{ page.title | tojson }},
  "url": "{{ page.url }}",
  "date": "{{ page.date }}"
}
```

```jinja
{# templates/section.json.jinja #}
{
  "title": {{ section.title | tojson }},
  "pages": [
    {% for p in section.pages %}
    "{{ p.url }}"{% if not loop.last %},{% endif %}
    {% endfor %}
  ]
}
```

### Template Selection Chain

For a given page/section and enabled format `<fmt>`, Hwaro tries, in order:

1. `<entry-template>.<fmt>` — the format-specific sibling of whatever template
   the page actually resolves to (a custom `template = "post"` front matter
   value looks for `post.json` first)
2. `section.<fmt>` — sections only
3. `page.<fmt>` — the final fallback

**A missing template for an enabled format is a hard build error.** If none
of the candidates exist, the build fails immediately and lists every
template name it tried, e.g.:

```
Error [HWARO_E_TEMPLATE]: No template found for output format 'txt' on about.md. Tried: page.txt.
Create one of: templates/page.txt.jinja.
```

This is intentional: a format enabled in config or front matter that silently
produces nothing is a worse failure mode than a loud one.

## Output Location

A format renders to a sibling `index.<fmt>` next to the page's `index.html`:

```
public/
  posts/hello/index.html
  posts/hello/index.json   <- [outputs].page = ["json"]
```

## Pagination

Formats apply once per page/section — **page 1 only**. A paginated section's
`/page/2/`, `/page/3/`, … output HTML as usual but never get their own
`index.<fmt>`; only the section's own URL does.

## `alternate_output_tags`

Every enabled format gets a `<link rel="alternate" type="…">` tag, available
as `{{ alternate_output_tags }}` in `page.html`/`section.html` (empty string
when the page has no formats):

```jinja
<head>
  {{ alternate_output_tags }}
</head>
```

renders, for a page with `outputs = ["json"]`:

```html
<link rel="alternate" type="application/json" href="https://example.com/posts/hello/index.json">
```

The href resolves through `base_url` the same way `canonical`/`hreflang`
links do, so it's correct under a subpath deployment
(`base_url = "https://user.github.io/repo"`).

## Determinism

Format templates run through the same rendering pipeline as `page.html` —
avoid `now()` or other non-deterministic values in a format template if you
want byte-identical output across builds (see
[Incremental Builds](/features/incremental-build/)).

## Known Limitation: Disabling a Format Under `--cache`

Removing a format from `[outputs]` (or from a page's front matter) does not
retroactively delete files that a *previous* build already wrote under
`--cache` — the incremental build only re-renders pages it detects as
changed, and "a format was removed from config" isn't tracked as a
per-file change. Run a full (non-incremental) build after disabling a format
to clean up the stale `index.<fmt>` files.

## See Also

- [Configuration](/start/config/) — Full config reference
- [Cascade](/writing/sections/#cascade) — `[cascade.extra]` and cascadable keys
- [Data Model](/templates/data-model/) — `page.extra`
- [Incremental Builds](/features/incremental-build/) — `--cache` semantics
