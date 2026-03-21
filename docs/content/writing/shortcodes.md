+++
title = "Shortcodes"
description = "Reusable template snippets for Markdown content"
weight = 4
toc = true
+++

Shortcodes are reusable template snippets you can use in Markdown content. Custom shortcodes are Jinja2 templates placed in `templates/shortcodes/` — see [Template Syntax](/templates/syntax/) for the templating language reference.

## Using Shortcodes

Two syntax patterns work in content files:

```markdown
{%raw%}{{ shortcode_name(arg1="value", arg2="value") }}{%endraw%}
```

Or explicitly:

```markdown
{%raw%}{{ shortcode("shortcode_name", arg1="value") }}{%endraw%}
```

## Built-in Shortcodes

Hwaro ships with built-in shortcodes that work out of the box — no template files needed.

### youtube

Embed a YouTube video.

```markdown
{%raw%}{{ youtube(id="dQw4w9WgXcQ") }}
{{ youtube(id="dQw4w9WgXcQ", width="800", height="450") }}{%endraw%}
```

| Param | Default | Description |
|-------|---------|-------------|
| `id` | (required) | YouTube video ID |
| `width` | `560` | Player width |
| `height` | `315` | Player height |
| `title` | `YouTube Video` | Accessible title |

### vimeo

Embed a Vimeo video.

```markdown
{%raw%}{{ vimeo(id="123456789") }}{%endraw%}
```

| Param | Default | Description |
|-------|---------|-------------|
| `id` | (required) | Vimeo video ID |
| `width` | `560` | Player width |
| `height` | `315` | Player height |
| `title` | `Vimeo Video` | Accessible title |

### gist

Embed a GitHub Gist.

```markdown
{%raw%}{{ gist(user="octocat", id="abc123") }}
{{ gist(user="octocat", id="abc123", file="hello.rb") }}{%endraw%}
```

| Param | Default | Description |
|-------|---------|-------------|
| `user` | (required) | GitHub username |
| `id` | (required) | Gist ID |
| `file` | (none) | Specific file to show |

### alert / callout

Display an alert box. Use as a block shortcode to wrap content.

```markdown
{%raw%}{% alert(type="warning", title="Caution") %}Be careful with this!{% end %}
{% callout(type="tip") %}Here is a helpful tip.{% end %}{%endraw%}
```

| Param | Default | Description |
|-------|---------|-------------|
| `type` | `info` | `info`, `warning`, `danger`, `tip`, `success` |
| `title` | (none) | Optional title |

### figure

Image with optional caption.

```markdown
{%raw%}{{ figure(src="/img/photo.jpg", alt="A photo", caption="My caption") }}{%endraw%}
```

| Param | Default | Description |
|-------|---------|-------------|
| `src` | (required) | Image URL |
| `alt` | `""` | Alt text |
| `caption` | (none) | Caption below image |
| `width` | (none) | Image width |
| `height` | (none) | Image height |

### tweet

Embed a tweet.

```markdown
{%raw%}{{ tweet(user="jack", id="20") }}{%endraw%}
```

| Param | Default | Description |
|-------|---------|-------------|
| `user` | (required) | Twitter username |
| `id` | (required) | Tweet ID |

### codepen

Embed a CodePen.

```markdown
{%raw%}{{ codepen(user="chriscoyier", id="gfdDu") }}
{{ codepen(user="chriscoyier", id="gfdDu", tab="css,result", height="400") }}{%endraw%}
```

| Param | Default | Description |
|-------|---------|-------------|
| `user` | (required) | CodePen username |
| `id` | (required) | Pen ID |
| `tab` | `result` | Default tab(s) |
| `height` | `300` | Embed height |
| `title` | `CodePen Embed` | Accessible title |

> To override any built-in shortcode, create a file with the same name in `templates/shortcodes/` (e.g., `templates/shortcodes/youtube.html`). User templates always take priority.

## Creating Custom Shortcodes

Shortcode templates live in `templates/shortcodes/`.

### Example: Alert Box

Create `templates/shortcodes/alert.html`:

```jinja
{% if type and message %}
<div class="alert alert-{{ type }}">
  {{ message | safe }}
</div>
{% endif %}
```

Use in content:

```markdown
{%raw%}{{ alert(type="warning", message="This is important!") }}{%endraw%}
```

Output:

```html
<div class="alert alert-warning">
  This is important!
</div>
```

### Example: YouTube Embed

Create `templates/shortcodes/youtube.html`:

```jinja
{% if id %}
<div class="video-container">
  <iframe 
    src="https://www.youtube.com/embed/{{ id }}"
    frameborder="0"
    allowfullscreen>
  </iframe>
</div>
{% endif %}
```

Use in content:

```markdown
{%raw%}{{ youtube(id="dQw4w9WgXcQ") }}{%endraw%}
```

### Example: Figure with Caption

Create `templates/shortcodes/figure.html`:

```jinja
<figure>
  <img src="{{ src }}" alt="{{ alt | default(value='') }}">
  {% if caption %}
  <figcaption>{{ caption }}</figcaption>
  {% endif %}
</figure>
```

Use in content:

```markdown
{%raw%}{{ figure(src="/images/photo.jpg", alt="A photo", caption="My caption") }}{%endraw%}
```

### Example: Image Gallery (Asset Colocation)

You can create a gallery that automatically lists images found in the same directory as the page (Page Bundle).

Create `templates/shortcodes/gallery.html`:

```jinja
<div class="gallery">
{% for asset in page.assets -%}
  {%- if asset is matching("[.](jpg|png)$") -%}
    {% set image = resize_image(path=asset, width=240, height=180) %}
    <a href="{{ get_url(path=asset) }}" target="_blank">
      <img src="{{ image.url }}" alt="{{ asset }}" />
    </a>
  {%- endif %}
{%- endfor %}
</div>
```

Use in content (inside a Page Bundle directory):

```markdown
{%raw%}{{ gallery() }}{%endraw%}
```

This will render a grid of all JPG and PNG images found alongside the Markdown file.

## Block Shortcodes

Block shortcodes wrap content between opening and closing tags:

```markdown
{%raw%}{% note() %}
This is the **body** content of the shortcode.
{% end %}{%endraw%}
```

The body is passed to the shortcode template as the `body` variable. Markdown conversion is **not** applied automatically — use the `markdownify` filter in your template if needed:

```jinja
<div class="note">
  {{ body | markdownify | safe }}
</div>
```

Or use the body as-is for raw content:

```jinja
<div class="note">{{ body }}</div>
```

### Nested Shortcodes

Block shortcodes can be nested up to 5 levels deep:

```markdown
{%raw%}{% outer() %}
  Some text with {{ inner(type="info") }} inside.
{% end %}{%endraw%}
```

## Argument Syntax

### Named Arguments

Arguments support multiple quote styles:

```markdown
{%raw%}{{ alert(type="warning", message="Double quotes") }}
{{ alert(type='info', message='Single quotes') }}
{{ alert(type=danger, message=No quotes for simple values) }}{%endraw%}
```

### Positional Arguments

When no `key=value` syntax is used, arguments are assigned as `_0`, `_1`, etc.:

```markdown
{%raw%}{{ youtube("dQw4w9WgXcQ") }}{%endraw%}
```

In the shortcode template, access via `{{ _0 }}`:

```jinja
<iframe src="https://www.youtube.com/embed/{{ _0 }}"></iframe>
```

## Built-in Variables

Shortcodes have access to:

- All passed arguments
- `site` object
- `page` object
- Standard filters and functions

```jinja
{# In shortcode template #}
<a href="{{ site.base_url }}/{{ url }}">{{ text }}</a>
```

## Tips

### Validate Arguments

Always check for required arguments:

```jinja
{% if not url %}
<p class="error">Missing url parameter</p>
{% else %}
<a href="{{ url }}">{{ text | default(value="Link") }}</a>
{% endif %}
```

### Use Safe Filter for HTML

When passing HTML content:

```jinja
{{ content | safe }}
```

### Organize Shortcodes

Group related shortcodes:

```
templates/shortcodes/
├── alert.html
├── youtube.html
├── figure.html
├── code/
│   ├── tabs.html
│   └── snippet.html
└── social/
    ├── twitter.html
    └── github.html
```
