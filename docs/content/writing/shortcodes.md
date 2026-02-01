+++
title = "Shortcodes"
weight = 4
+++

Shortcodes are reusable template snippets you can use in Markdown content.

## Using Shortcodes

Two syntax patterns work in content files:

```markdown
{%raw%}{{ shortcode_name(arg1="value", arg2="value") }}{%endraw%}
```

Or explicitly:

```markdown
{%raw%}{{ shortcode("shortcode_name", arg1="value") }}{%endraw%}
```

## Creating Shortcodes

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

## Argument Syntax

Arguments support multiple quote styles:

```markdown
{%raw%}{{ alert(type="warning", message="Double quotes") }}
{{ alert(type='info', message='Single quotes') }}
{{ alert(type=danger, message=No quotes for simple values) }}{%endraw%}
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
