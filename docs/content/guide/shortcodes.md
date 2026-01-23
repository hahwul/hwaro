+++
title = "Shortcodes"
description = "Learn how to use and create reusable shortcodes in Hwaro"
toc = true
+++


Shortcodes are reusable content snippets that you can embed in your Markdown files. They allow you to add rich, dynamic components without writing complex HTML in your content.

## What are Shortcodes?

Shortcodes bridge the gap between simple Markdown and complex HTML. Instead of writing verbose HTML, you use a simple syntax:

```markdown
{{< alert type="info" message="This is an informational message." >}}
```

This renders as a styled alert box without cluttering your Markdown with HTML.

## Using Shortcodes

### Basic Syntax

Shortcodes use double curly braces with angle brackets:

```markdown
{{< shortcode_name >}}
```

### With Parameters

Pass parameters as key-value pairs:

```markdown
{{< shortcode_name param1="value1" param2="value2" >}}
```

### With Content

Some shortcodes wrap content:

```markdown
{{< shortcode_name >}}
Your content goes here.
It can span multiple lines.
{{< /shortcode_name >}}
```

## Built-in Shortcodes

### Alert

Display styled alert boxes for notices, warnings, and tips:

```markdown
{{< alert type="info" message="This is an informational note." >}}

{{< alert type="warning" message="Be careful with this operation!" >}}

{{< alert type="tip" message="Pro tip: Use keyboard shortcuts." >}}

{{< alert type="note" message="Important information here." >}}

{{< alert type="danger" message="This action cannot be undone." >}}
```

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `type` | Yes | Alert type: `info`, `warning`, `tip`, `note`, `danger` |
| `message` | Yes | The alert message text |

### Code Block

Enhanced code blocks with titles and line highlighting:

```markdown
{{< code lang="javascript" title="app.js" >}}
function greet(name) {
  console.log(`Hello, ${name}!`);
}
{{< /code >}}
```

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `lang` | No | Programming language for highlighting |
| `title` | No | Title displayed above the code block |

### Figure

Display images with captions:

```markdown
{{< figure src="/images/screenshot.png" alt="App screenshot" caption="The main dashboard view" >}}
```

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `src` | Yes | Image source path |
| `alt` | Yes | Alt text for accessibility |
| `caption` | No | Caption displayed below the image |
| `class` | No | Additional CSS class |

### YouTube

Embed YouTube videos:

```markdown
{{< youtube id="dQw4w9WgXcQ" >}}
```

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `id` | Yes | YouTube video ID |
| `title` | No | Video title for accessibility |

### Details

Collapsible content sections:

```markdown
{{< details title="Click to expand" >}}
This content is hidden by default.
Click the title to reveal it.
{{< /details >}}
```

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `title` | Yes | The clickable summary text |
| `open` | No | Set to "true" to expand by default |

## Creating Custom Shortcodes

Create your own shortcodes by adding ECR templates to the `templates/shortcodes/` directory.

### Simple Shortcode

Create `templates/shortcodes/highlight.ecr`:

```erb
<mark class="highlight"><%= params["text"] %></mark>
```

Use it in content:

```markdown
{{< highlight text="Important text here" >}}
```

### Shortcode with Content

Create `templates/shortcodes/callout.ecr`:

```erb
<div class="callout callout-<%= params["type"] || "default" %>">
  <div class="callout-title"><%= params["title"] %></div>
  <div class="callout-content">
    <%= content %>
  </div>
</div>
```

Use it:

```markdown
{{< callout type="info" title="Did you know?" >}}
Hwaro is written in Crystal, a language that combines 
Ruby-like syntax with C-like performance.
{{< /callout >}}
```

### Available Variables in Shortcodes

| Variable | Type | Description |
|----------|------|-------------|
| `params` | Hash | All parameters passed to the shortcode |
| `content` | String | Content between opening and closing tags |

### Accessing Parameters

```erb
<!-- Required parameter -->
<%= params["src"] %>

<!-- Optional with default -->
<%= params["class"] || "default-class" %>

<!-- Conditional rendering -->
<% if params["caption"] %>
  <figcaption><%= params["caption"] %></figcaption>
<% end %>
```

## Shortcode Examples

### Button Shortcode

`templates/shortcodes/button.ecr`:

```erb
<a href="<%= params["href"] %>" class="btn btn-<%= params["style"] || "primary" %>">
  <%= params["text"] %>
</a>
```

Usage:

```markdown
{{< button href="/getting-started/" text="Get Started" style="primary" >}}
{{< button href="/docs/" text="Documentation" style="secondary" >}}
```

### Card Shortcode

`templates/shortcodes/card.ecr`:

```erb
<div class="card">
  <% if params["image"] %>
    <img src="<%= params["image"] %>" alt="<%= params["title"] %>" class="card-image">
  <% end %>
  <div class="card-body">
    <h3 class="card-title"><%= params["title"] %></h3>
    <div class="card-content">
      <%= content %>
    </div>
    <% if params["link"] %>
      <a href="<%= params["link"] %>" class="card-link">Learn more →</a>
    <% end %>
  </div>
</div>
```

Usage:

```markdown
{{< card title="Fast Builds" image="/images/speed.svg" link="/features/speed/" >}}
Hwaro builds your site in milliseconds, not minutes.
{{< /card >}}
```

### Tab Group Shortcode

`templates/shortcodes/tabs.ecr`:

```erb
<div class="tabs" data-tabs>
  <div class="tab-buttons">
    <% params["labels"].split(",").each_with_index do |label, i| %>
      <button class="tab-btn<%= i == 0 ? " active" : "" %>" data-tab="<%= i %>">
        <%= label.strip %>
      </button>
    <% end %>
  </div>
  <div class="tab-content">
    <%= content %>
  </div>
</div>
```

### Grid Layout

`templates/shortcodes/grid.ecr`:

```erb
<div class="grid grid-cols-<%= params["cols"] || "2" %>" style="gap: <%= params["gap"] || "1rem" %>;">
  <%= content %>
</div>
```

Usage:

```markdown
{{< grid cols="3" gap="2rem" >}}
  <div>Column 1</div>
  <div>Column 2</div>
  <div>Column 3</div>
{{< /grid >}}
```

## Styling Shortcodes

Add CSS for your shortcodes in your templates or stylesheets:

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
```

## Best Practices

### 1. Keep Shortcodes Simple

Each shortcode should do one thing well:

```markdown
<!-- Good: Single purpose -->
{{< alert type="warning" message="Save your work!" >}}

<!-- Avoid: Too many responsibilities -->
{{< complex_widget type="alert" animate="true" delay="500" theme="dark" ... >}}
```

### 2. Use Meaningful Names

Choose descriptive names that indicate what the shortcode does:

```markdown
<!-- Good -->
{{< youtube id="..." >}}
{{< code_block lang="python" >}}
{{< warning message="..." >}}

<!-- Avoid -->
{{< yt id="..." >}}
{{< cb lang="python" >}}
{{< w message="..." >}}
```

### 3. Provide Defaults

Make shortcodes forgiving with sensible defaults:

```erb
<div class="alert alert-<%= params["type"] || "info" %>">
  <%= params["message"] %>
</div>
```

### 4. Document Your Shortcodes

Create a reference page for your custom shortcodes:

```markdown
+++
title = "Shortcode Reference"
+++


## Alert
Display styled alert boxes.

**Usage:**
{{< alert type="info" message="Your message" >}}

**Parameters:**
- `type` (required): info, warning, tip, danger
- `message` (required): The alert text
```

### 5. Test in Context

Preview shortcodes in actual content to ensure they look right:

```bash
hwaro serve
```

## Troubleshooting

### Shortcode Not Rendering

1. Check the shortcode syntax matches exactly
2. Verify the template file exists in `templates/shortcodes/`
3. Ensure the filename matches the shortcode name (e.g., `alert.ecr` for `{{< alert >}}`)

### Parameters Not Working

1. Use quotes around parameter values
2. Check parameter names match what the template expects
3. Print params for debugging: `<%= params.inspect %>`

### Content Not Appearing

For shortcodes with content:

```markdown
<!-- Ensure you use the closing tag -->
{{< callout >}}
Content here
{{< /callout >}}
```

## Next Steps

- Explore [Templates](/guide/templates/) to understand the template system
- Learn about [Content Management](/guide/content-management/) for organizing content
- See [Taxonomies](/guide/taxonomies/) for content classification