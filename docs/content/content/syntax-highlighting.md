+++
title = "Syntax Highlighting"
+++

Hwaro uses Highlight.js for code block syntax highlighting.

## Enable Highlighting

In `config.toml`:

```toml
[highlight]
enabled = true
theme = "github-dark"
use_cdn = true
```

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `enabled` | `false` | Enable highlighting |
| `theme` | `"github"` | Highlight.js theme |
| `use_cdn` | `true` | Load from CDN |

## Available Themes

- `github` — GitHub light
- `github-dark` — GitHub dark
- `monokai` — Monokai
- `atom-one-dark` — Atom One Dark
- `atom-one-light` — Atom One Light
- `vs2015` — Visual Studio 2015
- `nord` — Nord
- `dracula` — Dracula
- `tomorrow-night` — Tomorrow Night

See all themes at [highlightjs.org](https://highlightjs.org/static/demo/).

## Template Variables

Add these to your template:

```jinja
<head>
  {{ highlight_css }}
</head>
<body>
  <!-- content -->
  {{ highlight_js }}
</body>
```

Or use combined variable:

```jinja
{{ highlight_tags }}
```

## Writing Code Blocks

Use fenced code blocks with language hint:

````markdown
```javascript
function greet(name) {
  console.log(`Hello, ${name}!`);
}
```
````

## Supported Languages

Common languages:

| Language | Hint |
|----------|------|
| JavaScript | `javascript` or `js` |
| TypeScript | `typescript` or `ts` |
| Python | `python` or `py` |
| Ruby | `ruby` or `rb` |
| Go | `go` |
| Rust | `rust` or `rs` |
| Crystal | `crystal` or `cr` |
| HTML | `html` |
| CSS | `css` |
| JSON | `json` |
| YAML | `yaml` |
| TOML | `toml` |
| Bash | `bash` or `sh` |
| SQL | `sql` |
| Markdown | `markdown` or `md` |

## Disable Per-Build

Skip highlighting for faster builds:

```bash
hwaro build --skip-highlighting
```
