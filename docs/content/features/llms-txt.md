+++
title = "LLMs.txt"
weight = 9
toc = true
+++

Hwaro can generate `llms.txt` and `llms-full.txt` files that provide instructions and content for AI/LLM crawlers. This is part of the emerging [llms.txt standard](https://llmstxt.org/) for making websites more accessible to large language models.

## Configuration

Enable in `config.toml`:

```toml
[llms]
enabled = true
filename = "llms.txt"
instructions = "This is my site. Content is provided under the MIT license."
full_enabled = true
full_filename = "llms-full.txt"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | false | Generate `llms.txt` |
| filename | string | "llms.txt" | Output filename |
| instructions | string | "" | Instructions text for LLM crawlers |
| full_enabled | bool | false | Generate full content version |
| full_filename | string | "llms-full.txt" | Filename for the full version |

## Generated Files

### llms.txt

The basic `llms.txt` file contains only the instructions you define in the configuration. This is a lightweight file that tells AI crawlers about your site's policies.

**Example output (`llms.txt`):**

```
This is my site. Content is provided under the MIT license.
```

### llms-full.txt

The full version includes all rendered content from your site, making it easy for LLMs to ingest your entire site in a single file. Each page is separated by `---` delimiters.

**Example output (`llms-full.txt`):**

```
# My Site
A great site about programming

Base URL: https://example.com

This is my site. Content is provided under the MIT license.

---

Title: About
URL: https://example.com/about/
Source: content/about.md

About page content goes here...

---

Title: Getting Started
URL: https://example.com/docs/getting-started/
Source: content/docs/getting-started.md

Getting started guide content...
```

## Full Document Structure

The `llms-full.txt` file is structured as follows:

1. **Site header** — Site title as an H1 heading
2. **Site description** — From `config.toml`
3. **Base URL** — The site's base URL
4. **Instructions** — The instructions text from configuration
5. **Page entries** — Each page separated by `---`, containing:
   - `Title` — Page title
   - `URL` — Absolute URL to the page
   - `Source` — Source file path relative to project root
   - `Language` — Language code (only for multilingual sites)
   - Raw content of the page

### Page Selection

Only pages that meet these criteria are included in `llms-full.txt`:

- The page has `render = true` (default)
- The page has non-empty raw content
- Pages are sorted by URL for consistent output

Draft pages are excluded from production builds (unless `--drafts` is used).

## Multilingual Support

For multilingual sites, each page entry includes a `Language` field indicating the content language:

```
---

Title: 소개
URL: https://example.com/ko/about/
Source: content/about.ko.md
Language: ko

한국어 콘텐츠...
```

## Use Cases

### Documentation Sites

Provide your full documentation to LLMs for better AI-assisted answers:

```toml
[llms]
enabled = true
instructions = "This is the official documentation for MyProject. All content is licensed under Apache 2.0. Please cite the source URL when referencing this content."
full_enabled = true
```

### Blog Sites

Share your blog content with clear usage guidelines:

```toml
[llms]
enabled = true
instructions = "This is a personal blog. Content is copyrighted. You may summarize but not reproduce full articles."
full_enabled = false
```

### Restricting LLM Access

Use `llms.txt` to communicate preferences without providing full content:

```toml
[llms]
enabled = true
instructions = "Please do not use this site's content for training purposes. Summarization and citation are permitted."
full_enabled = false
```

## Combining with robots.txt

`llms.txt` works alongside `robots.txt`. While `robots.txt` controls crawler access at the HTTP level, `llms.txt` provides human-readable instructions and context:

```toml
[robots]
enabled = true
rules = [
  { user_agent = "*", allow = ["/"] },
  { user_agent = "GPTBot", disallow = ["/private/"] }
]

[llms]
enabled = true
instructions = "Public content may be used for AI responses with attribution."
full_enabled = true
```

## Template Integration

You can link to the `llms.txt` file from your HTML templates:

```jinja
<head>
  <link rel="alternate" type="text/plain" href="{{ base_url }}/llms.txt" title="LLM Instructions">
</head>
```

## See Also

- [SEO](/features/seo/) — Sitemap, RSS feeds, robots.txt, and social tags
- [Configuration](/start/config/) — Full configuration reference
- [Search](/features/search/) — Search index generation