+++
title = "Directory Structure"
+++

A Hwaro project has the following structure:

```
my-site/
├── config.toml          # Site configuration
├── content/             # Markdown content
│   ├── index.md         # Homepage
│   ├── about.md         # /about/
│   └── blog/            # Section
│       ├── _index.md    # /blog/
│       └── post.md      # /blog/post/
├── templates/           # Jinja2 templates
│   ├── base.html        # Base template
│   ├── page.html        # Page template
│   ├── section.html     # Section template
│   └── shortcodes/      # Shortcode templates
├── static/              # Static assets
│   └── assets/
│       ├── css/
│       └── js/
└── public/              # Build output (generated)
```

## Directories

### content/

Markdown files with TOML front matter. Directory structure maps to URLs:

| File | URL |
|------|-----|
| `content/index.md` | `/` |
| `content/about.md` | `/about/` |
| `content/blog/_index.md` | `/blog/` |
| `content/blog/post.md` | `/blog/post/` |

### templates/

Jinja2 templates for rendering content:

| Template | Purpose |
|----------|---------|
| `base.html` | Common HTML structure |
| `page.html` | Regular pages |
| `section.html` | Section index pages |
| `index.html` | Homepage (optional) |
| `taxonomy.html` | Taxonomy listing |
| `taxonomy_term.html` | Taxonomy term page |
| `404.html` | Error page |

### static/

Files copied directly to output. `static/css/style.css` becomes `/css/style.css`.

### public/

Generated output directory. Deploy this folder.

## Special Files

| File | Purpose |
|------|---------|
| `config.toml` | Site configuration |
| `_index.md` | Section index content |
| `index.md` | Page content |