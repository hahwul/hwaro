+++
title = "Syntax Highlighting"
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
| JavaScript | `javascript`, `js` |
| TypeScript | `typescript`, `ts` |
| Python | `python`, `py` |
| Ruby | `ruby`, `rb` |
| Go | `go`, `golang` |
| Rust | `rust`, `rs` |
| Crystal | `crystal`, `cr` |
| HTML | `html` |
| CSS | `css` |
| JSON | `json` |
| YAML | `yaml`, `yml` |
| TOML | `toml` |
| Markdown | `markdown`, `md` |
| Shell | `bash`, `sh`, `shell` |
| SQL | `sql` |

## Configuration

Configure in `config.toml`:

```toml
[highlight]
enabled = true
theme = "monokai"
line_numbers = false
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | bool | `true` | Enable syntax highlighting |
| `theme` | string | `"monokai"` | Color theme |
| `line_numbers` | bool | `false` | Show line numbers |

## Themes

Available themes:

- `monokai` — Dark theme (default)
- `github` — Light GitHub style
- `dracula` — Dark purple theme
- `solarized-dark` — Solarized dark
- `solarized-light` — Solarized light

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
