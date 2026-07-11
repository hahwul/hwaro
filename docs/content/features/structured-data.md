+++
title = "Structured Data"
description = "Extended Schema.org JSON-LD support for rich search results"
weight = 2
toc = true
+++

Hwaro automatically generates JSON-LD structured data for rich search results. Beyond the default Article and BreadcrumbList types, you can enable additional Schema.org types.

## Auto-Generated (Always)

These are generated for every page:

- **Article** — headline, dates, description, author, image
- **BreadcrumbList** — auto-generated from page hierarchy/ancestors

Available as template variables: `{{ jsonld }}`, `{{ jsonld_article }}`, `{{ jsonld_breadcrumb }}`

## Site-Wide Schemas

Generated once and available on all pages:

### WebSite + SearchAction

Enables the sitelinks search box in Google. Automatically includes `SearchAction` when `[search]` is enabled.

```jinja
{{ jsonld_website }}
```

### Organization

Basic organization info from site config. Uses `og.default_image` as logo if set.

```jinja
{{ jsonld_organization }}
```

## Page-Specific Schemas

Set `schema_type` in front matter to auto-detect and include additional types:

### FAQPage

```toml
+++
title = "Frequently Asked Questions"
schema_type = "FAQ"
faq_questions = ["What is Hwaro?", "How do I install it?"]
faq_answers = ["A fast static site generator.", "Run crystal build."]
+++
```

Or use paired array format:
```toml
faq = ["Question 1", "Answer 1", "Question 2", "Answer 2"]
```

The FAQ schema is auto-included in `{{ jsonld }}` when `schema_type = "FAQ"`. You can also use `{{ jsonld_faq }}` directly.

### HowTo

```toml
+++
title = "Getting Started with Hwaro"
schema_type = "HowTo"
howto_names = ["Install", "Configure", "Build"]
howto_texts = ["Run the install command.", "Edit config.toml.", "Run hwaro build."]
+++
```

Or use paired array format:
```toml
howto_steps = ["Step Name", "Step Description", "Step 2 Name", "Step 2 Description"]
```

Auto-included in `{{ jsonld }}` when `schema_type = "HowTo"`. Also available as `{{ jsonld_howto }}`.

### Person

Use in templates for author pages:

```jinja
{{ jsonld_person }}
```

Or build manually via the template function (for author-specific pages).

## Template Variables

| Variable | Scope | Description |
|----------|-------|-------------|
| `jsonld` | per-page | All applicable JSON-LD combined (Article + Breadcrumb + extended type) |
| `jsonld_article` | per-page | Article schema only |
| `jsonld_breadcrumb` | per-page | BreadcrumbList schema only |
| `jsonld_faq` | per-page | FAQPage schema (empty if not FAQ) |
| `jsonld_howto` | per-page | HowTo schema (empty if not HowTo) |
| `jsonld_website` | global | WebSite + SearchAction schema |
| `jsonld_organization` | global | Organization schema |

## Usage in Templates

Typical placement in your base template `<head>`:

```jinja
<head>
  {{ jsonld }}
  {{ jsonld_website }}
</head>
```

## See Also

- [SEO](/features/seo/) — Sitemaps, feeds, OpenGraph, and canonical tags
- [Configuration](/start/config/) — Full config reference
