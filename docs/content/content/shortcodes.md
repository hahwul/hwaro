+++
title = "Shortcodes"
toc = true
+++

Shortcodes are reusable content components that can be embedded in Markdown.

## Syntax

```jinja
{{ shortcode_name(param1="value1", param2="value2") }}
```

## Parameter Formats

```jinja
{{ alert(type="warning", message="Be careful!") }}
{{ figure(src='/images/photo.jpg', alt='Photo') }}
{{ button(href=/docs/, text=Documentation) }}
```

- Double quotes: `param="value"`
- Single quotes: `param='value'`
- Unquoted: `param=value`

## Creating Shortcodes

Create templates in `templates/shortcodes/`:

### Simple Shortcode

`templates/shortcodes/highlight.html`:

```jinja
<mark class="highlight">{{ text }}</mark>
```

Usage:

```jinja
{{ highlight(text="Important text") }}
```

### Conditional Shortcode

`templates/shortcodes/alert.html`:

```jinja
{% if type and message %}
<div class="alert alert-{{ type }}">
  {{ message | safe }}
</div>
{% endif %}
```

Usage:

```jinja
{{ alert(type="info", message="This is a note.") }}
{{ alert(type="warning", message="<strong>Warning!</strong>") }}
```

### Shortcode with Defaults

`templates/shortcodes/button.html`:

```jinja
<a href="{{ href }}" class="btn btn-{{ style | default(value='primary') }}">
  {{ text }}
</a>
```

Usage:

```jinja
{{ button(href="/docs/", text="Read Docs") }}
{{ button(href="/buy/", text="Buy Now", style="secondary") }}
```

## Common Shortcodes

### Alert

```jinja
{{ alert(type="info", message="Informational note.") }}
{{ alert(type="warning", message="Warning message.") }}
{{ alert(type="tip", message="Pro tip here.") }}
{{ alert(type="danger", message="Danger zone!") }}
```

### Figure

```jinja
{{ figure(src="/images/screenshot.png", alt="Screenshot", caption="App dashboard") }}
```

Template:

```jinja
<figure>
  <img src="{{ src }}" alt="{{ alt }}">
  {% if caption %}<figcaption>{{ caption }}</figcaption>{% endif %}
</figure>
```

### YouTube

```jinja
{{ youtube(id="dQw4w9WgXcQ") }}
```

Template:

```jinja
<div class="video-embed">
  <iframe src="https://www.youtube.com/embed/{{ id }}" allowfullscreen></iframe>
</div>
```

### Image Gallery

`templates/shortcodes/images.html`:

```jinja
{% set images_arr = src | split(pat=",") %}
<div class="images-grid">
  {% for image in images_arr %}
  <img src="{{ image | trim }}" alt="{{ alt | default(value='') }}" loading="lazy">
  {% endfor %}
</div>
```

Usage:

```jinja
{{ images(src="/img/a.jpg, /img/b.jpg, /img/c.jpg", alt="Gallery") }}
```

## Available Filters

Shortcode templates can use all Jinja2 filters:

| Filter | Description |
|--------|-------------|
| `safe` | Render HTML without escaping |
| `default(value="x")` | Fallback value |
| `split(pat=",")` | Split string |
| `trim` | Remove whitespace |
| `upper` / `lower` | Case conversion |
| `slugify` | URL slug |
| `truncate_words(n)` | Truncate text |
| `strip_html` | Remove HTML tags |
| `markdownify` | Render Markdown |

## Example CSS

```css
.alert {
  padding: 1rem;
  border-radius: 8px;
  margin: 1rem 0;
  border-left: 4px solid;
}

.alert-info {
  background: rgba(59, 130, 246, 0.1);
  border-color: #3b82f6;
}

.alert-warning {
  background: rgba(234, 179, 8, 0.1);
  border-color: #eab308;
}

.alert-danger {
  background: rgba(239, 68, 68, 0.1);
  border-color: #ef4444;
}

.btn {
  display: inline-block;
  padding: 0.5rem 1rem;
  border-radius: 6px;
  text-decoration: none;
}

.btn-primary {
  background: #e53935;
  color: white;
}
```

## Troubleshooting

**Shortcode not rendering:**
- Check filename matches: `alert.html` for `{{ alert(...) }}`
- Verify file is in `templates/shortcodes/`
- Check for template syntax errors

**HTML appearing escaped:**
- Use `{{ message | safe }}` for HTML content

**Filter not found:**
- Use correct syntax: `split(pat=",")` not `split(",")`
