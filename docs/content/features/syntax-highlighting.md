+++
title = "Syntax Highlighting"
description = "Automatic syntax highlighting for code blocks"
weight = 3
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
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | true | Enable syntax highlighting |
| theme | string | "github" | Highlight.js theme name |
| use_cdn | bool | true | Load assets from CDN (false = local files) |

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
