+++
title = "Content Management"
description = "Learn how to organize, write, and manage content in Hwaro"
+++


Hwaro uses a file-based content system where each Markdown file becomes a page on your site. This guide covers everything you need to know about organizing and writing content.

## Content Directory Structure

All content files live in the `content/` directory. The directory structure maps directly to your site's URL structure:

```
content/
├── index.md                    # → /
├── about.md                    # → /about/
├── contact.md                  # → /contact/
├── blog/                       # Section
│   ├── _index.md               # → /blog/
│   ├── first-post.md           # → /blog/first-post/
│   └── second-post.md          # → /blog/second-post/
├── docs/                       # Section
│   ├── _index.md               # → /docs/
│   ├── getting-started/        # Nested section
│   │   ├── _index.md           # → /docs/getting-started/
│   │   └── installation.md     # → /docs/getting-started/installation/
│   └── guides/
│       └── ...
└── products/
    └── ...
```

## Front Matter

Every content file begins with front matter in TOML format, enclosed by `+++` delimiters:

```markdown
+++
title = "My Page Title"
date = "2024-01-15"
description = "A brief description for SEO"
draft = false
tags = ["tutorial", "guide"]
categories = ["documentation"]
image = "/images/featured.png"
+++

Your Markdown content goes here...
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | Page title, used in templates and meta tags |

### Optional Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `date` | string | — | Publication date (YYYY-MM-DD format) |
| `description` | string | — | Page description for SEO and social sharing |
| `draft` | bool | `false` | If true, page is excluded from production builds |
| `tags` | array | `[]` | Tags for this content |
| `categories` | array | `[]` | Categories for this content |
| `image` | string | — | Featured image for social sharing |
| `layout` | string | — | Override the default template |
| `weight` | int | `0` | Sort order (lower numbers appear first) |

## Sections

Sections are directories containing related content. They help organize your site into logical groups.

### Creating a Section

1. Create a directory in `content/`:

```bash
mkdir content/blog
```

2. Add a section index file (`_index.md`):

```markdown
+++
title = "Blog"
description = "Latest news and articles"
+++


Welcome to our blog. Here you'll find our latest articles and updates.
```

The `_index.md` file defines the section's metadata and content for the section index page.

### Section Templates

Sections use the `section.ecr` template by default. The section template has access to:

- `section_list` — HTML list of pages in this section
- All standard template variables

## Writing Content

### Markdown Syntax

Hwaro supports standard Markdown syntax:

```markdown
## Heading 2
### Heading 3

Regular paragraph with **bold**, *italic*, and `code`.

- Unordered list item
- Another item
  - Nested item

1. Ordered list
2. Second item

[Link text](https://example.com)

![Image alt text](/images/photo.jpg)

> Blockquote

---

| Table | Header |
|-------|--------|
| Cell  | Cell   |
```

### Code Blocks

Use fenced code blocks with language hints for syntax highlighting:

````markdown
```javascript
function greet(name) {
  console.log(`Hello, ${name}!`);
}
```
````

Supported languages include: javascript, typescript, python, ruby, go, rust, crystal, bash, html, css, json, yaml, toml, and many more.

### Raw HTML

You can include raw HTML in your Markdown:

```markdown
This is Markdown.

<div class="custom-component">
  <p>This is raw HTML.</p>
</div>

Back to Markdown.
```

Note: If `markdown.safe = true` in your config, raw HTML will be stripped.

## Links and References

### Internal Links

Link to other pages using absolute paths:

```markdown
[Installation Guide](/getting-started/installation/)
[About Us](/about/)
[Blog Post](/blog/my-post/)
```

### External Links

Standard Markdown links work for external URLs:

```markdown
[Crystal Language](https://crystal-lang.org)
```

### Anchor Links

Link to headings within a page:

```markdown
[Jump to Features](#features)
```

## Images and Assets

### Static Files

Place images and other assets in the `static/` directory:

```
static/
├── images/
│   ├── logo.png
│   └── photos/
│       └── team.jpg
├── css/
│   └── custom.css
└── js/
    └── scripts.js
```

Files in `static/` are copied directly to the output:

- `static/images/logo.png` → `/images/logo.png`
- `static/css/custom.css` → `/css/custom.css`

### Using Images

Reference images in your Markdown:

```markdown
![Company Logo](/images/logo.png)

![Team Photo](/images/photos/team.jpg)
```

### Image Attributes

Add alt text for accessibility:

```markdown
![A group photo of our team at the annual retreat](/images/team.jpg)
```

## Drafts

Mark content as draft to exclude it from production builds:

```markdown
+++
title = "Work in Progress"
draft = true
+++
```

To preview drafts during development:

```bash
hwaro serve --drafts
hwaro build --drafts
```

## Content Organization Tips

### Use Meaningful Names

File and directory names become URLs, so use descriptive, URL-friendly names:

```
✓ content/blog/getting-started-with-crystal.md
✗ content/blog/post1.md

✓ content/docs/api-reference/
✗ content/docs/api_ref/
```

### Group Related Content

Use sections to group related content:

```
content/
├── tutorials/        # Learning content
│   ├── beginner/
│   ├── intermediate/
│   └── advanced/
├── reference/        # API documentation
├── blog/             # Blog posts
└── changelog/        # Version history
```

### Use Taxonomies

Organize content with tags and categories:

```markdown
+++
title = "Building REST APIs"
tags = ["api", "rest", "tutorial"]
categories = ["Backend"]
+++
```

## Creating Content with CLI

Use the `hwaro new` command to create content files:

```bash
hwaro new content/about.md

hwaro new content/blog/my-new-post.md

hwaro new content/docs/guides/deployment.md
```

This creates files with a front matter template ready for editing.

## Date-Based Content

For blogs or news sections, use dates in filenames or front matter:

### Option 1: Front Matter Date

```markdown
+++
title = "Product Launch Announcement"
date = "2024-03-15"
+++
```

### Option 2: Filename Date

```
content/blog/2024-03-15-product-launch.md
```

Content can be sorted by date in templates using the `date` field.

## Best Practices

1. **Always include a title** — Every page should have a clear title
2. **Write descriptions** — Add descriptions for better SEO
3. **Use headings properly** — Start with H1, follow hierarchy
4. **Keep URLs clean** — Use lowercase, hyphens, no special characters
5. **Organize by topic** — Group related content in sections
6. **Preview before publishing** — Use `hwaro serve --drafts` to review
7. **Use meaningful image names** — `team-photo-2024.jpg` not `IMG_1234.jpg`

## Next Steps

- Learn about [Templates](/guide/templates/) to customize how content is rendered
- Explore [Taxonomies](/guide/taxonomies/) for content classification
- See [SEO Features](/guide/seo/) to optimize your content for search engines