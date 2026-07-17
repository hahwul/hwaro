+++
title = "Render Hooks"
description = "Override how Markdown elements render with Hugo/Zola-style template hooks"
weight = 5
toc = true
+++

Render hooks let you override how individual Markdown elements — links, images, headings, and fenced code blocks — turn into HTML, without touching hwaro's Markdown parser. Drop a template in `templates/hooks/`, and every matching element on every page renders through it instead of the built-in markup.

If you don't create any `templates/hooks/render-*` template, nothing changes: hwaro renders exactly as it always has.

## File Layout

```
templates/
└── hooks/
    ├── render-link.html       # [text](url "title")
    ├── render-image.html      # ![alt](url "title")
    ├── render-heading.html    # ## Heading
    └── render-codeblock.html  # ```lang ... ```
```

Each file is independent — add only the ones you want to override. A site with just `render-image.html` gets a custom image wrapper and stock rendering for everything else.

`blockquote` and `table` hooks are planned but not implemented yet; a `templates/hooks/render-blockquote.html` or `render-table.html` file is silently ignored today. Any other `hooks/render-*` name is unrecognized and logs a warning at build time.

## Context Variables

All values are Crinja `Value`s and — like every other hwaro template — **already HTML-escaped where that matters**. See [Rule 1](#rules) below before reaching for an `| e` filter.

### `render-link.html`

| Variable | Description |
|----------|--------------|
| `destination` | The link target, escaped. Empty string when `markdown.safe = true` and the destination uses an unsafe protocol (`javascript:`, etc.) |
| `title` | The link's `"title"` text, escaped. Empty string when absent |
| `text` | The already-rendered inner HTML of the link (may itself contain nested markup, or a hook-rendered `<img>` if the link wraps an image) |

### `render-image.html`

| Variable | Description |
|----------|--------------|
| `destination` | The image `src`, escaped (same unsafe-protocol rule as links) |
| `alt` | The image's alt text — plain text only, even if the Markdown source nested inline markup in the alt (matches CommonMark: an image's "children" never produce tags) |
| `title` | The image's `"title"` text, escaped. Empty string when absent |

### `render-heading.html`

| Variable | Description |
|----------|--------------|
| `level` | Heading level as an integer (`1`–`6`) |
| `text` | The already-rendered inner HTML of the heading |
| `id` | The heading's id — either a custom `{#id}` from the Markdown source, or an auto-generated, deduplicated slug (`heading`, `heading-1`, `heading-2`, …) |

### `render-codeblock.html`

| Variable | Description |
|----------|--------------|
| `lang` | The fence's language token, escaped (`python` in `` ```python ``). Empty string for a fence with no language |
| `options` | The raw Zola/Pandoc-style `{...}` options block after the language (see [Syntax Highlighting](/features/syntax-highlighting/)), or any trailing info-string text when there's no `{...}` block. Escaped |
| `code` | The fence body, HTML-escaped |
| `highlighted` | The server-mode syntax-highlighted body (hljs-class spans), or an empty string when `[highlight] mode` isn't `"server"`, highlighting is off, or the language has no lexer |
| `name` | The parsed `{name=...}`/`{title=...}` filename label, escaped. Empty string when absent |
| `copy` | `"true"` when the copy button applies to this block (`[highlight] copy` / per-fence `{copy=...}`, never for mermaid), empty string otherwise. The template decides what markup to emit for it |

## Default-Equivalent Templates

These four templates reproduce hwaro's stock output exactly — a useful starting point to modify from:

```jinja
{# templates/hooks/render-link.html #}
<a href="{{ destination }}"{% if title is present %} title="{{ title }}"{% endif %}>{{ text }}</a>
```

```jinja
{# templates/hooks/render-image.html #}
<img src="{{ destination }}" alt="{{ alt }}"{% if title is present %} title="{{ title }}"{% endif %} />
```

```jinja
{# templates/hooks/render-heading.html #}
<h{{ level }} id="{{ id }}">{{ text }}</h{{ level }}>
```

```jinja
{# templates/hooks/render-codeblock.html #}
<pre><code{% if lang is present %} class="language-{{ lang }} hljs"{% endif %}>{% if highlighted is present %}{{ highlighted }}{% else %}{{ code }}{% endif %}</code></pre>
```

Note `{% if title is present %}`, not a bare `{% if title %}` — Crinja's truthiness only treats `false`/`0`/nil as falsy, so a bare `{% if title %}` would render `title=""` even when there's no title. The custom `is present`/`is empty` tests (also used throughout hwaro's own templates) check for that correctly.

The codeblock template's ` hljs` class matches stock output under the
default config (`[highlight] enabled = true` — most Highlight.js themes key
their base styling off that class). If you've disabled highlighting
entirely, stock output emits `class="language-{{ lang }}"` with no ` hljs`;
drop it from your hook to stay byte-identical.

## Example: Figure-Wrapped Images

```jinja
{# templates/hooks/render-image.html #}
<figure>
  <img src="{{ destination }}" alt="{{ alt }}" loading="lazy" />
  {% if title is present %}<figcaption>{{ title }}</figcaption>{% endif %}
</figure>
```

Every `![alt](src "caption")` in your Markdown now renders as a captioned `<figure>` — no per-image markup needed in content files.

## Rules

1. **Values are pre-escaped — emit them verbatim.** Autoescape is off in hwaro templates (the same as everywhere else), and `destination`/`title`/`alt`/`lang`/`options`/`code` are already HTML-escaped by the renderer. Piping any of them through `| e` double-escapes; piping `text` or `highlighted` through it corrupts already-rendered HTML.
2. **Keep conventional double-quoted `href`/`src` attributes.** Everything downstream — `@/internal-page.md` link resolution, subpath (`base_path`) prefixing of root-relative links, responsive-image `srcset`/`sizes` injection, and `loading="lazy"` — runs as a plain-text pass over the *final* HTML, matching on `href="..."` / `src="..."`. A hook that emits an unquoted or single-quoted attribute, or restructures the destination into something other than a normal attribute value, opts that element out of all of it. An `@/`-prefixed `destination` must land inside `href="..."` for `InternalLinkResolver` to find and resolve it.
3. **`render-heading.html` must emit an `<hN id="{{ id }}">` element.** The TOC (`{{ toc }}` / `page.toc`) and `insert_anchor_links` both post-process the final HTML looking for `<h1>`–`<h6>` tags with an `id` attribute; a hook that renders something other than a heading tag, or drops `id`, silently falls out of both.
4. **Don't transform `{{ text }}`.** It's already-rendered HTML, and on pages using shortcodes it may contain an internal placeholder comment (`<!--HWARO-SHORTCODE-PLACEHOLDER-N-->`) that gets swapped for the shortcode's output in a later pass — filtering, truncating, or re-escaping `text` can corrupt or strand that placeholder.
5. **Mermaid owns its own fence.** With `[markdown] mermaid = true`, a `` ```mermaid `` fence always renders through the existing Mermaid pipeline (`<div class="mermaid">…</div>`), never through `render-codeblock.html` — that's the one config-decided exception to "every hook always applies to every matching element." Set `mermaid = false` to have your codeblock hook render mermaid fences like any other language instead.
6. **Hooks don't apply inside table cells, footnote bodies, definition lists, or the front-matter `description`/summary text.** Those render through a separate, simpler inline-markdown path that never touches the main Markd parser hooks attach to. This is a known limitation, not a bug.

## Incremental Builds

Editing a file under `templates/hooks/` is tracked like any other template edit for `hwaro build --cache` and `hwaro serve` — but because a hook isn't reached via `{% include %}`/`{% extends %}` from any specific page template, hwaro can't narrow down which pages it affects. An edit to any `templates/hooks/render-*.html` file re-renders **every** page, regardless of `[build] template_deps`. See [Incremental Build](/features/incremental-build/).

## See Also

- [Syntax Highlighting](/features/syntax-highlighting/) — fence language/options parsing that feeds `render-codeblock.html`
- [Markdown Extensions](/features/markdown-extensions/) — `{#custom-id}` headings and Mermaid diagrams
- [Templates Overview](/templates/) — template directory layout and selection rules
