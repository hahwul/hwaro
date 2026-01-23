+++
title = "Taxonomies"
description = "Organize content with tags, categories, and custom taxonomies"
+++


Taxonomies are a powerful way to classify and organize your content. Hwaro supports tags, categories, and custom taxonomies to help visitors discover related content.

## What are Taxonomies?

A taxonomy is a classification system. Common examples include:

- **Tags** — Keywords describing the content (e.g., "crystal", "tutorial", "beginner")
- **Categories** — Broad groupings (e.g., "Tutorials", "News", "Documentation")
- **Authors** — Content creators
- **Series** — Multi-part content collections

## Configuring Taxonomies

Define taxonomies in your `config.toml`:

```toml
[[taxonomies]]
name = "tags"
feed = true

[[taxonomies]]
name = "categories"
paginate_by = 10

[[taxonomies]]
name = "authors"
feed = false
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | string | required | Taxonomy name (used in URLs and front matter) |
| `feed` | bool | `false` | Generate RSS feed for this taxonomy |
| `paginate_by` | int | `0` | Items per page (0 = no pagination) |
| `sitemap` | bool | `true` | Include in sitemap |

## Using Taxonomies in Content

Add taxonomy terms to your content's front matter:

```markdown
+++
title = "Getting Started with Crystal"
tags = ["crystal", "programming", "beginner"]
categories = ["Tutorials"]
authors = ["John Doe"]
+++


This tutorial covers the basics...
```

### Multiple Terms

Assign multiple terms to any taxonomy:

```markdown
+++
title = "Advanced API Design"
tags = ["api", "rest", "graphql", "best-practices"]
categories = ["Backend", "Architecture"]
+++
```

## Generated Pages

Hwaro automatically generates pages for each taxonomy:

### Taxonomy Index Page

Lists all terms in a taxonomy:

- URL: `/{taxonomy}/`
- Example: `/tags/`, `/categories/`, `/authors/`
- Template: `taxonomy.ecr`

### Term Pages

Lists all content with a specific term:

- URL: `/{taxonomy}/{term}/`
- Example: `/tags/crystal/`, `/categories/tutorials/`
- Template: `taxonomy_term.ecr`

## URL Structure

Given this content:

```markdown
+++
title = "My Post"
tags = ["crystal", "web"]
categories = ["Tutorials"]
+++
```

Hwaro generates:

```
/tags/                  # All tags
/tags/crystal/          # Posts tagged "crystal"
/tags/web/              # Posts tagged "web"
/categories/            # All categories
/categories/tutorials/  # Posts in "Tutorials"
```

## Taxonomy Templates

### taxonomy.ecr

Template for taxonomy index pages (listing all terms):

```erb
<%= render "header" %>
<main>
  <h1><%= page_title %></h1>
  <p>Browse content by <%= page_title.downcase %>:</p>
  
  <ul class="taxonomy-list">
    <%= content %>
  </ul>
</main>
<%= render "footer" %>
```

### taxonomy_term.ecr

Template for individual term pages (listing content with that term):

```erb
<%= render "header" %>
<main>
  <h1><%= page_title %></h1>
  
  <div class="term-content">
    <%= content %>
  </div>
</main>
<%= render "footer" %>
```

## Taxonomy Feeds

Generate RSS feeds for taxonomy terms by setting `feed = true`:

```toml
[[taxonomies]]
name = "tags"
feed = true
```

This creates feeds at:

- `/tags/crystal/rss.xml`
- `/tags/web/rss.xml`

Visitors can subscribe to specific topics.

## Pagination

For taxonomies with many items, enable pagination:

```toml
[[taxonomies]]
name = "tags"
paginate_by = 10
```

This creates paginated term pages:

- `/tags/crystal/` — First 10 items
- `/tags/crystal/page/2/` — Items 11-20
- `/tags/crystal/page/3/` — Items 21-30

## Common Taxonomies

### Tags

Fine-grained keywords for content:

```toml
[[taxonomies]]
name = "tags"
feed = true
```

```markdown
+++
tags = ["javascript", "typescript", "react", "frontend"]
+++
```

### Categories

Broad content groupings:

```toml
[[taxonomies]]
name = "categories"
paginate_by = 20
```

```markdown
+++
categories = ["Tutorials", "Backend"]
+++
```

### Authors

Track content creators:

```toml
[[taxonomies]]
name = "authors"
feed = true
```

```markdown
+++
authors = ["Jane Smith", "John Doe"]
+++
```

### Series

Group multi-part content:

```toml
[[taxonomies]]
name = "series"
```

```markdown
+++
title = "Part 1: Introduction"
series = ["Building a Blog"]
+++
```

## Styling Taxonomies

### Tag Cloud

Create a tag cloud with CSS:

```css
.taxonomy-list {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  list-style: none;
  padding: 0;
}

.taxonomy-list li a {
  display: inline-block;
  padding: 0.25rem 0.75rem;
  background: var(--bg-subtle);
  border-radius: 100px;
  font-size: 0.875rem;
  text-decoration: none;
  transition: background 0.2s;
}

.taxonomy-list li a:hover {
  background: var(--primary);
  color: white;
}
```

### Category Badges

Style categories as badges:

```css
.category-badge {
  display: inline-block;
  padding: 0.2rem 0.6rem;
  background: var(--primary);
  color: white;
  border-radius: 4px;
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
```

## Displaying Taxonomies in Content

Show tags/categories on blog posts in your template:

```erb
<article>
  <h1><%= page_title %></h1>
  
  <div class="meta">
    <span class="tags">
      <!-- Tags would be rendered here from content -->
    </span>
  </div>
  
  <%= content %>
</article>
```

## Best Practices

### Choose Meaningful Names

Use clear, consistent taxonomy names:

```
✓ tags, categories, authors, series
✗ t, cats, auth, s
```

### Keep Terms Consistent

Standardize term naming across content:

```
✓ "JavaScript" (consistent)
✗ "javascript", "Javascript", "JS" (inconsistent)
```

### Don't Over-Tag

Limit tags to truly relevant terms:

```
✓ tags = ["crystal", "web-development", "api"]
✗ tags = ["crystal", "programming", "code", "software", "tech", "web", "api", "tutorial", "guide", "howto"]
```

### Use Hierarchical Categories

For complex sites, use categories for broad topics:

```markdown
categories = ["Documentation"]  # Broad
tags = ["installation", "linux", "docker"]  # Specific
```

## Advanced Usage

### Excluding from Sitemap

Remove a taxonomy from the sitemap:

```toml
[[taxonomies]]
name = "internal-tags"
sitemap = false
```

### Section-Specific Taxonomies

Use different tags for different sections:

```markdown
+++
tags = ["news", "update"]
+++

+++
tags = ["api", "reference"]
+++
```

All tags still appear at `/tags/`, but content is filtered appropriately on term pages.

## Next Steps

- Learn about [SEO Features](/guide/seo/) to optimize taxonomy pages
- Explore [Templates](/guide/templates/) for customizing taxonomy appearance
- See [Configuration Reference](/reference/config/) for all taxonomy options