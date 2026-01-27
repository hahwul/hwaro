+++
title = "Build a Docs Site"
toc = true
+++

Docs sites feel “friendly” when readers can answer these quickly:

- Where do I start?
- What should I read next?
- How do I find things later?

This page focuses on structure and conventions that work well with Hwaro.

## Recommended information architecture

Use 4 buckets:

1. **Guide** — end-to-end tutorials (goal-oriented)
2. **Reference** — facts (CLI, config, template variables)
3. **Concepts** — how things work (sections, taxonomies, search)
4. **Deployment** — ship it

Hwaro already maps folders to URLs, so you can implement this directly in `content/`.

Example:

```
content/
├── index.md
├── guide/
│   ├── _index.md
│   └── quickstart.md
├── reference/
│   ├── _index.md
│   ├── cli.md
│   └── config.md
└── deployment/
    ├── _index.md
    └── github-pages.md
```

## Make navigation predictable

- Use `_index.md` for every section to explain what’s inside.
- Put the “most common next step” at the bottom of each page.
- Keep page titles action-oriented (`Install`, `Deploy`, `Configure Search`).

## Add search (recommended)

Enable search in `config.toml`:

```toml
[search]
enabled = true
format = "fuse_json"
fields = ["title", "content", "description"]
filename = "search.json"
```

See: [Search](/content/search/).

## Templates: start small

For a docs site, you usually only need:

- `base.html` (layout)
- `page.html` (single page)
- `section.html` (section index)

See: [Templates](/templates/) and [Built-in Templates](/templates/built-in/).

## Next

- Learn sections vs pages: [Section](/content/section/) and [Page](/content/page/)
- Production readiness: [Production Checklist](/guide/production/)
