+++
title = "Shortcodes"
description = "Learn how to use and create reusable shortcodes in Hwaro"
toc = true
+++

Shortcodes are reusable content snippets that you can embed in your Markdown files. They allow you to add rich, dynamic components without writing complex HTML in your content.

## What are Shortcodes?

Shortcodes bridge the gap between simple Markdown and complex HTML. Instead of writing verbose HTML, you use a simple syntax:

```jinja
{{ alert(type="info", message="This is an informational message.") }}
```

This renders as a styled alert box without cluttering your Markdown with HTML.

## Using Shortcodes

### Basic Syntax

Hwaro supports two shortcode syntax patterns:

**Direct call (recommended):**

```jinja
{{ shortcode_name(param1="value1", param2="value2") }}
```

**Explicit call:**

```jinja
{{ shortcode("shortcode_name", param1="value1", param2="value2") }}
```

### Parameter Formats

Shortcode arguments support multiple formats:

- Double quotes: `param="value"`
- Single quotes: `param='value'`
- Unquoted values: `param=value`

```jinja
{{ alert(type="warning", message="Be careful!") }}
{{ figure(src='/images/photo.jpg', alt='Photo') }}
{{ button(href=/docs/, text=Documentation) }}
```

## Built-in Shortcodes

### Alert

Display styled alert boxes for notices, warnings, and tips:

```jinja
{{ alert(type="info", message="This is an informational note.") }}

{{ alert(type="warning", message="Be careful with this operation!") }}

{{ alert(type="tip", message="Pro tip: Use keyboard shortcuts.") }}

{{ alert(type="note", message="Important information here.") }}

{{ alert(type="danger", message="This action cannot be undone.") }}
```

**Parameters:**

- `type` (required): Alert type: `info`, `warning`, `tip`, `note`, `danger`
- `message` (required): The alert message text (supports HTML with `| safe` filter)

### Figure

Display images with captions:

```jinja
{{ figure(src="/images/screenshot.png", alt="App screenshot", caption="The main dashboard view") }}
```

**Parameters:**

- `src` (required): Image source path
- `alt` (required): Alt text for accessibility
- `caption` (optional): Caption displayed below the image
- `class` (optional): Additional CSS class

### YouTube

Embed YouTube videos:

```jinja
{{ youtube(id="dQw4w9WgXcQ") }}
```

**Parameters:**

- `id` (required): YouTube video ID
- `title` (optional): Video title for accessibility

### Button

Create styled button links:

```jinja
{{ button(href="/getting-started/", text="Get Started", style="primary") }}
```

**Parameters:**

- `href` (required): Link URL
- `text` (required): Button text
- `style` (optional): Button style: `primary`, `secondary`, `outline`

## Creating Custom Shortcodes

Create your own shortcodes by adding Jinja2 templates to the `templates/shortcodes/` directory.

### Simple Shortcode

Create `templates/shortcodes/highlight.html`:

```jinja
<mark class="highlight">{{ text }}</mark>
```

Use it in content:

```jinja
{{ highlight(text="Important text here") }}
```

### Shortcode with Conditional Logic

Create `templates/shortcodes/alert.html`:

```jinja
{% if type and message %}
<div class="alert alert-{{ type }}">
  {{ message | safe }}
</div>
{% endif %}
```

Use it:

```jinja
{{ alert(type="info", message="<strong>Note:</strong> This is important.") }}
```

### Shortcode with Default Values

Create `templates/shortcodes/button.html`:

```jinja
<a href="{{ href }}" class="btn btn-{{ style | default(value='primary') }}">
  {{ text }}
</a>
```

Use it:

```jinja
{{ button(href="/docs/", text="Documentation") }}
{{ button(href="/buy/", text="Buy Now", style="secondary") }}
```

### Complex Shortcode Example

Create `templates/shortcodes/card.html`:

```jinja
<div class="card{% if class %} {{ class }}{% endif %}">
  {% if image %}
  <img src="{{ image }}" alt="{{ title }}" class="card-image">
  {% endif %}
  <div class="card-body">
    <h3 class="card-title">{{ title }}</h3>
    {% if description %}
    <p class="card-description">{{ description }}</p>
    {% endif %}
    {% if link %}
    <a href="{{ link }}" class="card-link">Learn more →</a>
    {% endif %}
  </div>
</div>
```

Use it:

```jinja
{{ card(title="Fast Builds", description="Hwaro builds your site in milliseconds.", link="/features/speed/", image="/images/speed.svg") }}
```

### Image Gallery Shortcode

Create `templates/shortcodes/images.html`:

```jinja
{% set images_arr = src | split(pat=",") %}
{% set alt_text = alt | default(value="") %}
<div class="images-grid">
    {% for image in images_arr %}
    <div class="images-grid-item">
        <img src="{{ image | trim }}" alt="{{ alt_text }}" loading="lazy">
    </div>
    {% endfor %}
</div>
```

Use it:

```jinja
{{ images(src="/img/photo1.jpg, /img/photo2.jpg, /img/photo3.jpg", alt="Gallery") }}
```

## Available Filters in Shortcodes

Shortcode templates have access to all Crinja/Jinja2 filters:

**Built-in Filters:**
- `{{ text | upper }}` - Convert to uppercase
- `{{ text | lower }}` - Convert to lowercase
- `{{ text | capitalize }}` - Capitalize first letter
- `{{ text | length }}` - Get length
- `{{ list | join(", ") }}` - Join array elements
- `{{ list | first }}` - Get first element
- `{{ list | last }}` - Get last element

**Custom Hwaro Filters:**
- `{{ text | split(pat=",") }}` - Split string by separator
- `{{ html | safe }}` - Mark content as safe (no escaping)
- `{{ text | trim }}` - Remove leading/trailing whitespace
- `{{ value | default(value="fallback") }}` - Provide default value if empty
- `{{ text | slugify }}` - Convert to URL slug
- `{{ text | truncate_words(50) }}` - Truncate by word count
- `{{ url | absolute_url }}` - Make URL absolute with base_url
- `{{ html | strip_html }}` - Remove HTML tags
- `{{ text | markdownify }}` - Render markdown to HTML
- `{{ text | xml_escape }}` - XML escape special characters

## Styling Shortcodes

Add CSS for your shortcodes in your stylesheets:

```css
/* Alert styles */
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
.alert-tip {
  background: rgba(34, 197, 94, 0.1);
  border-color: #22c55e;
}
.alert-danger {
  background: rgba(239, 68, 68, 0.1);
  border-color: #ef4444;
}

/* Button styles */
.btn {
  display: inline-block;
  padding: 0.5rem 1rem;
  border-radius: 6px;
  text-decoration: none;
  font-weight: 500;
}
.btn-primary {
  background: #e53935;
  color: white;
}
.btn-secondary {
  background: #27272a;
  color: white;
  border: 1px solid #3f3f46;
}

/* Card styles */
.card {
  background: #18181b;
  border: 1px solid #27272a;
  border-radius: 12px;
  overflow: hidden;
}
.card-body {
  padding: 1.5rem;
}
.card-title {
  margin: 0 0 0.5rem 0;
}
.card-link {
  color: #e53935;
}

/* Image grid styles */
.images-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 1rem;
}
.images-grid-item img {
  width: 100%;
  height: auto;
  border-radius: 8px;
}
```

## Best Practices

### 1. Keep Shortcodes Simple

Each shortcode should do one thing well:

```jinja
{# Good: Single purpose #}
{{ alert(type="warning", message="Save your work!") }}

{# Avoid: Too many responsibilities #}
{{ complex_widget(type="alert", animate="true", delay="500", theme="dark") }}
```

### 2. Use Meaningful Names

Choose descriptive names that indicate what the shortcode does:

```jinja
{# Good #}
{{ youtube(id="...") }}
{{ code_block(lang="python") }}
{{ warning(message="...") }}

{# Avoid #}
{{ yt(id="...") }}
{{ cb(lang="python") }}
{{ w(message="...") }}
```

### 3. Provide Defaults

Make shortcodes forgiving with sensible defaults:

```jinja
<div class="alert alert-{{ type | default(value='info') }}">
  {{ message }}
</div>
```

### 4. Use Conditional Rendering

Handle missing parameters gracefully:

```jinja
{% if type and message %}
<div class="alert alert-{{ type }}">
  {{ message | safe }}
</div>
{% endif %}
```

### 5. Document Your Shortcodes

Create a reference page for your custom shortcodes:

```markdown
+++
title = "Shortcode Reference"
+++

## Alert
Display styled alert boxes.

**Usage:**
{{ alert(type="info", message="Your message") }}

**Parameters:**
- `type` (required): info, warning, tip, danger
- `message` (required): The alert text
```

## Troubleshooting

### Shortcode Not Rendering

1. Check the shortcode syntax is correct: `{{ name(param="value") }}`
2. Verify the template file exists in `templates/shortcodes/`
3. Ensure the filename matches the shortcode name (e.g., `alert.html` for `{{ alert(...) }}`)
4. Check for syntax errors in the template file

### Parameters Not Working

1. Use quotes around parameter values with spaces
2. Check parameter names match what the template expects
3. Verify you're using the correct filter syntax

### HTML Not Rendering

If HTML in parameters appears escaped, use the `safe` filter:

```jinja
{{ message | safe }}
```

### Filter Not Found

If you get a "no filter with name X registered" error, check that:
1. You're using a valid filter name
2. The filter syntax is correct (e.g., `split(pat=",")` not `split(",")`)

## Next Steps

- Explore [Templates](/guide/templates/) to understand the template system
- Learn about [Content Management](/guide/content-management/) for organizing content
- See [Taxonomies](/guide/taxonomies/) for content classification