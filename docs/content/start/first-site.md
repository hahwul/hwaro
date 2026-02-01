+++
title = "First Site"
weight = 2
+++

Create your first Hwaro site in 5 minutes.

## 1. Create Project

```bash
hwaro init my-site --scaffold blog
cd my-site
```

Scaffolds available:
- `simple` — Landing pages, small sites
- `blog` — Posts with tags and categories
- `docs` — Documentation with sidebar

## 2. Start Development Server

```bash
hwaro serve
```

Open `http://localhost:3000`. Changes reload automatically.

## 3. Project Structure

```
my-site/
├── config.toml      # Site configuration
├── content/         # Markdown content
│   ├── index.md     # Homepage
│   └── blog/        # Blog section
│       ├── _index.md
│       └── hello.md
├── templates/       # Jinja2 templates
├── static/          # Static files (CSS, JS, images)
└── public/          # Generated output
```

## 4. Edit Configuration

Open `config.toml`:

```toml
title = "My Site"
description = "A site built with Hwaro"
base_url = "https://example.com"
```

## 5. Create a Page

```bash
hwaro new content/about.md
```

Edit `content/about.md`:

```markdown
+++
title = "About"
+++

Welcome to my site!
```

Visit `http://localhost:3000/about/`.

## 6. Create a Section

Sections group related content. Create a blog section:

```bash
mkdir -p content/blog
```

Create `content/blog/_index.md`:

```markdown
+++
title = "Blog"
sort_by = "date"
+++

My blog posts.
```

Create `content/blog/first-post.md`:

```markdown
+++
title = "My First Post"
date = "2024-01-15"
tags = ["hello"]
+++

Hello, world!
```

Visit `http://localhost:3000/blog/`.

## 7. Build for Production

```bash
hwaro build --minify
```

Deploy the `public/` directory to any static host.

## Next Steps

- [CLI Commands](/start/cli/) — All available commands
- [Configuration](/start/config/) — Full config reference
- [Writing Content](/writing/) — Pages, sections, taxonomies