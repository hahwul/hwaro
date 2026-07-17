+++
title = "Syntax Highlighting"
description = "Automatic syntax highlighting for code blocks"
weight = 7
+++

Code blocks in Markdown are automatically syntax highlighted.

## Usage

Use fenced code blocks with a language identifier:

````markdown
```javascript
function greet(name) {
  console.log(`Hello, ${name}!`);
}
```
````

## Supported Languages

Common languages:

| Language | Identifiers |
|----------|-------------|
| JavaScript | javascript, js |
| TypeScript | typescript, ts |
| Python | python, py |
| Ruby | ruby, rb |
| Go | go, golang |
| Rust | rust, rs |
| Crystal | crystal, cr |
| HTML | html |
| CSS | css |
| JSON | json |
| YAML | yaml, yml |
| TOML | toml |
| Markdown | markdown, md |
| Shell | bash, sh, shell |
| SQL | sql |

## Configuration

Configure in `config.toml`:

```toml
[highlight]
enabled = true
theme = "github-dark"
use_cdn = true
mode = "server"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | true | Enable syntax highlighting |
| theme | string | "github" | Highlight.js theme name |
| use_cdn | bool | true | Load assets from CDN (false = local files) |
| mode | string | "server" | `"server"` highlights at build time; `"client"` highlights in the browser via Highlight.js |
| line_numbers | bool | false | Add line numbers to every fenced code block by default (see below) |
| copy | bool | false | Add a copy-to-clipboard button to fenced code blocks (see below) |

## Server-Side Highlighting (Default)

With `mode = "server"` (the default), code blocks are highlighted during
the build — no JavaScript ships to the browser, and code is colored even
with JavaScript disabled.

The build-time highlighter emits Highlight.js-compatible CSS classes, so
every theme above keeps working unchanged: `{{ highlight_css }}` still
injects the theme stylesheet, while `{{ highlight_js }}` becomes empty.

Over 250 languages are supported (via [Tartrazine](https://github.com/ralsina/tartrazine)
lexers, ported from Pygments/Chroma). Code blocks in languages without a
lexer fall back to plain, unhighlighted output.

## Client-Side Highlighting

Set `mode = "client"` to highlight in the browser with Highlight.js
instead:

```toml
[highlight]
mode = "client"
theme = "github-dark"
```

In client mode `{{ highlight_js }}` injects the Highlight.js script (from
the CDN or your local assets, see below), and code blocks ship as plain
`<pre><code class="language-...">` markup for the browser to colorize.

## Line Numbers and Highlighted Lines

A fenced code block's language can be followed by an options block —
`{...}` — to add line numbers and/or highlight specific lines:

````markdown
```python {linenos=true, hl_lines="2-4 7", linenostart=5}
def main():
    setup()
    run()
    teardown()
    return 0
```
````

| Option | Value | Description |
|--------|-------|--------------|
| `linenos` | `true` / `false` | Show a line-number gutter. Overrides the `[highlight] line_numbers` default for this block. |
| `hl_lines` | e.g. `"2-4 7"` | Highlight these lines — space/comma-separated line numbers and/or ranges. Always the block's own **physical** 1-based lines, never shifted by `linenostart`. |
| `linenostart` | e.g. `5` | First displayed line number (default `1`). Only affects the numbers shown — it does not change which physical lines `hl_lines` highlights. |
| `hide_lines` | e.g. `"1 9-12"` | Omit these lines from the rendered output (server mode only — see below). Same syntax and physical-line semantics as `hl_lines`. |
| `copy` | `true` / `false` | Show a copy-to-clipboard button on this block. Overrides the `[highlight] copy` default. Ignored on `mermaid` fences. |
| `name` | e.g. `"main.cr"` | Filename/title label rendered above the block (`title=` is accepted as an alias). Ignored on `mermaid` fences. |

A named block is wrapped for styling (the `<pre>` inside is unchanged):

```html
<div class="code-block"><div class="code-filename">main.cr</div>
<pre><code class="language-crystal hljs">…</code></pre>
</div>
```

Scaffolded sites ship matching `.code-block` / `.code-filename` styles;
bring your own CSS otherwise.

The block accepts a couple of equivalent forms: `python {linenos=true}`,
`python{linenos=true}` (no space), or `{linenos=true}` alone (no
language). A malformed or unrecognized options block (e.g. `{oops}`) is
left as literal text in the language token, exactly as if fence options
didn't exist.

Setting `[highlight] line_numbers = true` turns line numbers on for
*every* fenced code block with a language — a per-block `{linenos=false}`
opts back out.

Hidden lines keep consuming their physical line numbers, so with
`linenos=true` the gutter shows a **gap** where lines were elided —
unlike Zola, which renumbers the remaining lines. This keeps the
documented invariant that `hl_lines` and `linenostart` always target the
block's physical lines, hidden or not (highlighting a hidden line is
simply a no-op).

Only `mode = "server"` actually removes hidden lines from the HTML. In
client mode `hide_lines` is presentational-only metadata (an inert
`data-hide-lines` attribute) — the lines remain in the page source. Do
**not** use `hide_lines` to redact secrets in client mode.

**Server vs client mode:**

- `mode = "server"` (default) renders the full result at build time: each
  line is wrapped in its own element, so line numbers and highlighted
  lines appear with no JavaScript.
- `mode = "client"` does not re-render the body — instead the
  `<pre>` tag gets `data-linenos="true"`, `data-linenostart="N"` (when
  greater than 1), `data-hl-lines="2-4 7"`, and/or
  `data-hide-lines="1 9-12"` attributes, so a client-side script or
  custom CSS can act on them. Hwaro ships no such script for client
  mode; full rendering (and actual line hiding) requires
  `mode = "server"`.

Scaffold sites style the server-mode markup out of the box. For a
non-scaffold site, or a custom theme, add:

```css
pre code .line.hl { display: inline-block; width: 100%; background: color-mix(in srgb, var(--code-keyword) 12%, transparent); }
pre code .ln { user-select: none; -webkit-user-select: none; opacity: .45; }
```

(Swap `var(--code-keyword)` for any color that fits your theme if you
aren't using the Hwaro Ember token system.)

## Copy Button

`[highlight] copy = true` adds a copy-to-clipboard button to every fenced
code block; a per-fence `{copy=false}` (or `{copy=true}` with the global
default off) overrides it:

```toml
[highlight]
copy = true
```

The markup contract: each opted-in block's `<pre>` gets a
`data-copy="true"` attribute, and `{{ highlight_js }}` injects a small
inline, dependency-free runtime (works in both server and client mode)
that wraps each `pre[data-copy]` in a `<div class="code-wrapper">` —
reusing an existing `.code-block` wrapper (named fences) as the anchor
instead — appends a `<button class="code-copy-btn">`, and copies the
code's text on click (server-mode `.ln` line-number gutters are stripped
from the copied text). The inline styles are theme-neutral
(currentColor, hover-reveal); scaffolded sites override them with
token-based styles.

`mermaid` fences never get the attribute — their `<pre>` shape is owned
by the Mermaid pipeline.

New scaffolded sites enable `copy = true` out of the box.

## Themes

Hwaro uses [Highlight.js](https://highlightjs.org/) themes. Any valid Highlight.js theme name works. Popular choices:

- `github` — Light GitHub style (default)
- `github-dark` — Dark GitHub style
- `github-dark-dimmed` — Dimmed dark GitHub style
- `monokai` — Classic dark theme
- `dracula` — Dark purple theme
- `solarized-dark` — Solarized dark
- `solarized-light` — Solarized light
- `nord` — Arctic color palette
- `tokyo-night-dark` — Tokyo Night dark

Browse all available themes at [highlightjs.org/demo](https://highlightjs.org/demo).

## CDN vs Local

When `use_cdn = true` (default), assets are loaded from cdnjs:

```html
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
```

When `use_cdn = false`, assets are loaded from local paths:

```html
<link rel="stylesheet" href="/assets/css/highlight/github-dark.min.css">
<script src="/assets/js/highlight.min.js"></script>
```

You must provide the local files yourself when using `use_cdn = false`.
In the default server mode only the theme stylesheet is referenced — the
`<script>` tags above appear only with `mode = "client"`.

## Template Integration

Include highlighting assets in templates:

```jinja
<head>
  {{ highlight_css | safe }}
</head>
<body>
  ...
  {{ highlight_js | safe }}
</body>
```

Or combined:

```jinja
<head>
  {{ highlight_tags | safe }}
</head>
```

## Build Options

Disable highlighting for faster builds:

```bash
hwaro build --skip-highlighting
```

## Plain Text Blocks

For no highlighting, omit the language or use `text`:

````markdown
```text
Plain text content
No highlighting applied
```
````

## Inline Code

Inline code uses backticks and is not highlighted:

```markdown
Use the `console.log()` function.
```

## See Also

- [Markdown Extensions](/features/markdown-extensions/) — Code blocks and language support
- [Configuration](/start/config/) — Highlight config reference
