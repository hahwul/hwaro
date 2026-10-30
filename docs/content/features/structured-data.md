+++
title = "Structured Data"
description = "Extended Schema.org JSON-LD support for rich search results"
weight = 2
toc = true
+++

Hwaro automatically generates JSON-LD structured data for rich search results. Beyond the default Article and BreadcrumbList types, you can enable additional Schema.org types.

## Auto-Generated (Always)

Every page gets page-level JSON-LD that matches its kind:

- **Article** — content pages: headline, dates, description, author, image
- **CollectionPage** — listing pages (section indexes, taxonomy and term pages, or a page with `[extra] og_type = "website"`): name, URL, description, consistent with the `og:type="website"` on the same page
- **WebSite** — the home page, in place of an Article (see below)
- **BreadcrumbList** — auto-generated from page hierarchy/ancestors (not on the home page)

The 404 page gets no page-level JSON-LD, and a page without a title gets no Article.

Available as template variables: `{{ jsonld }}`, `{{ jsonld_article }}`, `{{ jsonld_breadcrumb }}`

## Site-Wide Schemas

Generated once and available on all pages. Both need `base_url` and render as an empty string without it.

### WebSite + SearchAction

Enables the sitelinks search box in Google. Automatically includes `SearchAction` when `[search]` is enabled. Its target is `<base_url>/?q={search_term_string}`, so your site needs a page that reads the `q` query parameter (the built-in search UI does not).

The home page's `{{ jsonld }}` already includes this schema, so output `{{ jsonld_website }}` yourself only where you don't use `{{ jsonld }}`.

```jinja
{{ jsonld_website }}
```

### Organization

Basic organization info from site config. Uses `og.default_image` as logo if set.

```jinja
{{ jsonld_organization }}
```

## Page-Specific Schemas

Set `schema_type` in front matter to auto-detect and include additional types. The value is case-insensitive: `FAQ` or `FAQPage` for an FAQ page, `HowTo` or `how-to` for a how-to.

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

Or an array of tables:
```toml
[[extra.faq]]
question = "What is Hwaro?"
answer = "A fast static site generator."
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

Or an array of tables:
```toml
[[extra.howto_steps]]
name = "Install"
text = "Run the install command."
```

Auto-included in `{{ jsonld }}` when `schema_type = "HowTo"`. Also available as `{{ jsonld_howto }}`.

## Template Variables

| Variable | Scope | Description |
|----------|-------|-------------|
| `jsonld` | per-page | All applicable JSON-LD combined (Article or CollectionPage + Breadcrumb + extended type; WebSite on the home page) |
| `jsonld_article` | per-page | Article schema only (CollectionPage on listing pages; empty on the home page) |
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
</head>
```

`{{ jsonld }}` already carries the WebSite schema on the home page; adding `{{ jsonld_website }}` next to it would emit it twice there.

## See Also

- [SEO](/features/seo/) — Sitemaps, feeds, OpenGraph, and canonical tags
- [Configuration](/start/config/) — Full config reference
