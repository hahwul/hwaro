+++
title = "Upgrading to 1.0"
description = "What changes for a site built with Hwaro 0.22, and how to check your own"
weight = 6
toc = true
+++

This page lists what a site owner can observe when moving from 0.22 to 1.0. A site made by `hwaro init` whose templates you have not changed builds to the same output; the items below matter when you wrote your own templates, call hwaro from scripts, or rely on one of the behaviours named here.

## Check your site

1. **Before upgrading**, build with 0.22 into a directory you keep: `hwaro build -o /tmp/site-0.22`.
2. Upgrade, then run `hwaro doctor`. `hwaro doctor --fix` removes the leftover `[plugins]` section.
3. Build with 1.0 and read the warnings: `hwaro build -o /tmp/site-1.0`.
4. Compare the two: `diff -r /tmp/site-0.22 /tmp/site-1.0`. Every difference should be one of the items on this page.

To see only what template escaping changes, follow [Coming from 0.x](/templates/syntax/#coming-from-0x).

## Changes that need action

### Templates escape by default

Templates whose output is HTML or XML now escape every printed value unless it is safe, as Jinja2 does. Text your templates printed raw (`{{ page.title }}` with `&`, `<` or a quote in it) is escaped, which is what you want. Author HTML you print as markup now shows as text:

```jinja
{{ page.extra.banner }}          {# 0.22: markup    1.0: &lt;b&gt;…&lt;/b&gt; #}
{{ page.extra.banner | safe }}   {# markup in both #}
```

In practice this is most often a translated string or a data value that carries a tag, printed through `t`:

```toml
# i18n/en.toml
lede = "Every request becomes a <b>flow</b>."
```

```jinja
<p>{{ "home.lede" | t }}</p>          {# 1.0: the <b> shows as text #}
<p>{{ "home.lede" | t | safe }}</p>   {# markup, in 0.22 and in 1.0 #}
```

Adding `| safe` does not change what 0.22 prints, so you can make the change before upgrading.

The values Hwaro renders as HTML (`content`, `page.summary`, `toc`, the `*_tags` variables, pagination) print as before, and `| e` on them still escapes them, so `{{ p.summary | escape | xml_escape }}` in a feed template keeps working. JSON, text and CSV outputs do not change.

To keep the 0.22 behaviour for the whole site:

```toml
[templates]
autoescape = false
```

With that setting a site renders byte for byte as it did in 0.22. See [HTML Escaping](/templates/syntax/#html-escaping) for the rules and for a way to list every place the default changes on your site.

### `[plugins]` was removed

The section was read and never used, and every `config.toml` written by an older `hwaro init` has it. Each command now prints:

```
Key 'plugins' in config.toml was removed in 1.0 — hwaro does not read it; delete the [plugins] section to silence this warning.
```

Delete the section, or run `hwaro doctor --fix`.

### Removed commands and flags

Scripts and CI jobs that call these now stop with exit code 2.

| 0.22 | 1.0 | Use instead |
|---|---|---|
| `hwaro tool ci github-actions` | `unknown command 'tool ci'` | `hwaro tool platform github-pages` (writes the same workflow file) |
| `hwaro tool doctor` | `unknown command 'tool doctor'` | `hwaro doctor` (same flags) |
| `hwaro serve --live-reload` | `Invalid option: --live-reload` | Drop the flag. Live reload is on by default; `--no-live-reload` turns it off. |

Regenerate shell completions with `hwaro completion <shell>`.

### `hwaro serve` needs a `config.toml`

Without one it used to warn and serve defaults. It now stops with `config.toml not found` and exit code 3, as `hwaro build` does. Run it from the project directory or pass `-i DIR`.

### `hwaro serve` behind a tunnel or a reverse proxy

The dev server answers only `Host` names it recognises: loopback addresses, the machine name, the bind address and the host in `base_url`. Any other name gets `403`. Pass `--allow-host NAME` or set `allowed_hosts` under `[serve]` for the name your tunnel or proxy uses. See [CLI](/start/cli/).

### Template tests with an operator after the argument

A test argument written without parentheses is one value, as in Jinja2:

```jinja
{% if page.url is startswith "/blog" ~ "/" %}    {# now: (page.url is startswith "/blog") ~ "/" — always true #}
{% if page.url is startswith("/blog" ~ "/") %}   {# what was meant #}
```

The build warns at each such place and prints the parenthesised form to use. Output is not changed for you.

### Variables from `{% include … without context %}`

A `{% set %}` or `{% macro %}` at the top level of a partial included `without context` used to stay visible to the including template, and to later pages built by the same worker, so the same sources could build differently from run to run. It now ends with the partial, as with any other include. A template that read such a variable finds it undefined; share variables and macros with `{% import %}` or `{% from %}`.

### File names stored in decomposed form (NFD)

Page URLs and output file names are now in composed form (NFC) whatever form the file system stored. Names made by some macOS tools are stored decomposed, which affects Korean and accented names in particular. If such a site was published with decomposed URLs, those URLs no longer exist after a 1.0 build. Add each old spelling to the page's [`aliases`](/writing/pages/#url-aliases), which are kept exactly as written, or redirect on the server.

### `include_code` and `include_md`

They refuse files under `.git/` and dotenv files (`.env` and `.env.*`, except `.env.example`, `.env.sample` and `.env.template`). A page that included one now fails the build.

### `hwaro tool unused-assets --delete` in scripts

Outside an interactive terminal it needs `--force`; it no longer accepts a piped `y`.

### Dates

A `date` outside the documented forms (`YYYY-MM-DD`, `YYYY-MM-DD HH:MM:SS`, RFC 3339), such as one with a two-digit year or an offset past ±23:59, gets the "not a recognised date" warning and the page is treated as undated. Some of these were read silently before. A written UTC offset is always honoured.

## Output changes you may notice

- **Redirect stubs leave listings.** A page with `redirect_to` no longer appears in section listings, taxonomy pages, pagination counts or previous/next links, so a later page moves up one position.
- **RSS item descriptions.** `&`, `<` and `>` in a plain-text description are HTML-escaped before the XML escaping (`R&D` becomes `R&amp;amp;D`), because feed readers render the element as HTML.
- **Sites served under a path** (`base_url = "https://example.com/docs"`) that also have a section or static folder named like that path: a link written `/docs/p/` that points at `content/docs/p.md` is now `/docs/docs/p/`, the address the page is published at. Check the links of such a site.
- **Language feeds without a language home page** link to the site root instead of a URL that was never built.
- **Menus.** `active_path(ancestor=true)` marks a language's home entry open only on the home page, not on every page of that language.
- **Render hooks.** `absolute_url` and `get_url` return full URLs with `base_url` inside `templates/hooks/render-*.html`.
- **Pipe tables** follow GFM: cells beyond the header's column count are dropped.
- **Images.** Animated PNGs are published unchanged instead of being resized. Images are identified by content, not by extension, and a file that claims an impossible size is skipped instead of stopping the build.
- **Math, Mermaid and client-side highlighting tags** reference exact versions and carry `integrity` and `crossorigin`.
- **Code blocks** keep a non-ASCII character that the language's highlighter does not recognise (`→`, `✓`, a combining accent) instead of printing it as `���`.
- **Page URLs** percent-encode `<` and `>`.
- **`truncate`, excerpts and summaries** never cut inside a character (Hangul written as jamo, combining marks, emoji sequences), so a cut may land one character earlier.
- **Sitemaps above 50,000 URLs** are split into `sitemap-1.xml`, `sitemap-2.xml`, … behind a sitemap index.
- **Service worker (`[pwa]`).** Non-GET requests are ignored and the cache name changes, so visitors' caches refresh once.
- **Blog scaffold.** Undated posts no longer print an empty `<time>`, and the tag page link has text. Templates copied by an older `hwaro init` are your files and keep their own markup.
- **`urlize`** does not link `javascript:`, `vbscript:`, `file:` or non-image `data:` URLs.
- **Filters and functions that now do what Jinja2 does:** `default(default_value="x")`, `unique(case_sensitive=true)`, `trim("x")`, indexing a string (`"héllo"[1]`), `join`/`reverse`/`list`/`batch`/`slice`/`replace` on an undefined value (empty instead of a failed build), `replace` on numbers, and `{# {{ x }} #}` comments.

## New warnings and errors

- A TOML front matter block that opens with `+++` and is never closed is reported. The file was always published as body text.
- A misspelled keyword argument on a filter or function (`get_page(pth=…)`) is reported once per build and ignored.
- Front matter errors name the line in the file.
- An unreadable `templates/` directory, or a template file a page needs, fails the build. Unreadable `content/`, `static/` or `data/` directories give a warning.
- Unknown command-line flags print `Invalid option: --x` with a pointer to `--help`.
- `hwaro doctor` notes a site that has its own templates and does not set `[templates] autoescape`.

## Scripts and CI

- `-q` / `--quiet` no longer hides a command's answer: `tool list`, `tool stats`, `tool unused-assets`, `init --list-scaffolds`, `new --list-archetypes`, `deploy --list-targets` and every `--help` print their result.
- Usage text shown with a usage error goes to stderr; stdout stays empty. The exit code is still 2.
- `.hwaro_cache.json` stores relative paths. The first 1.0 build with `--cache` ignores the old cache and rebuilds once.
- `hwaro tool import`: WordPress keeps the old permalink in `aliases` and decodes HTML entities in titles and excerpts; Notion reads Created, Date and Tags into front matter; Hexo, Astro, Eleventy and Jekyll keep unmapped front matter keys under `[extra]`.
