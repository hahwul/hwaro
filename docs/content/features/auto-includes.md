+++
title = "Auto Includes"
description = "Automatically load CSS and JS files into all pages"
weight = 6
toc = true
+++

Auto Includes automatically load CSS and JS files from specified static directories into all pages. This eliminates the need to manually add each asset file to templates.

## Configuration

Enable in `config.toml`:

```toml
[auto_includes]
enabled = true
dirs = ["assets/css", "assets/js"]
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Enable auto includes |
| dirs | array | [] | Directories under `static/` to scan |

## Directory Structure

Place CSS and JS files in subdirectories of `static/`:

```
static/
├── assets/
│   ├── css/
│   │   ├── 01-reset.css
│   │   ├── 02-typography.css
│   │   └── 03-layout.css
│   └── js/
│       ├── 01-utils.js
│       └── 02-app.js
```

Files are scanned recursively from `static/{dir}/**/*.css` and `static/{dir}/**/*.js`.

## File Ordering

Files are included in **alphabetical order**. Use numeric prefixes to control the load order:

```
assets/css/
├── 01-reset.css        ← loaded first
├── 02-typography.css
├── 03-layout.css
└── 99-overrides.css    ← loaded last
```

## Template Variables

### CSS Only

Place in `<head>` to include only CSS files:

```jinja
<head>
  {{ auto_includes_css | safe }}
</head>
```

### JS Only

Place before `</body>` to include only JS files:

```jinja
<body>
  ...
  {{ auto_includes_js | safe }}
</body>
```

### All Assets

Include both CSS and JS together:

```jinja
{{ auto_includes | safe }}
```

| Variable | Description |
|----------|-------------|
| auto_includes_css | `<link>` tags for CSS files |
| auto_includes_js | `<script>` tags for JS files |
| auto_includes | Both CSS and JS tags combined |

## Generated Output

Given the example directory structure above, the template variables produce:

**`auto_includes_css`:**

```html
<link rel="stylesheet" href="/assets/css/01-reset.css">
<link rel="stylesheet" href="/assets/css/02-typography.css">
<link rel="stylesheet" href="/assets/css/03-layout.css">
```

**`auto_includes_js`:**

```html
<script src="/assets/js/01-utils.js"></script>
<script src="/assets/js/02-app.js"></script>
```

## Full Template Example

```jinja
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>{{ page.title }} - {{ site.title }}</title>
  {{ highlight_css | safe }}
  {{ auto_includes_css | safe }}
</head>
<body>
  {% block content %}{% endblock %}

  {{ highlight_js | safe }}
  {{ auto_includes_js | safe }}
</body>
</html>
```

## Tips

- **Separate concerns**: Use `auto_includes_css` in `<head>` and `auto_includes_js` before `</body>` for optimal page loading.
- **Multiple directories**: You can list multiple directories to scan. Each directory is scanned independently.
- **Avoid overlapping directories**: results are not deduplicated — a file reachable from two configured dirs (e.g. `assets` and `assets/css`) is included once per dir, so list non-overlapping directories.
- **Static files only**: Auto includes scan the `static/` directory. Files in `content/` are not included.

## See Also

- [Configuration](/start/config/) — Full configuration reference
- [Syntax Highlighting](/features/syntax-highlighting/) — Highlight.js asset inclusion
- [Data Model](/templates/data-model/) — Asset template variables