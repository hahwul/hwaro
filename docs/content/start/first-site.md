+++
title = "First Site"
description = "Create your first Hwaro site in 5 minutes"
weight = 2
toc = true
+++

Create your first Hwaro site in 5 minutes.

## 1. Create Project

```bash
hwaro init my-site --scaffold blog
cd my-site
```

Built-in scaffolds:

| Scaffold | Description |
|----------|-------------|
| `simple` | Landing pages, small sites (default) |
| `bare` | Minimal structure with semantic HTML only |
| `blog` | Posts with tags and categories |
| `docs` | Documentation with sidebar |
| `book` | Book with chapters, prev/next navigation, keyboard shortcuts |

Every scaffold shares one design-token system built on CSS `light-dark()` pairs,
so each site automatically follows the reader's OS color scheme — light for
light, dark for dark, with no extra setup. The styled scaffolds also ship a
theme switcher in the header: it cycles auto → light → dark, persists the
choice in `localStorage`, and applies it before first paint so there is no
flash. To force one scheme permanently (a dark-only site), add
`:root { color-scheme: dark; }` at the end of the generated `css/style.css`.

{% preview_gallery() %}
<a class="preview-item" href="/images/scaffolds/scaffold-simple.png" target="_blank" rel="noopener"><img src="/images/scaffolds/scaffold-simple.png" alt="simple scaffold" width="1280" height="800" loading="lazy"><div class="preview-label"><code>simple</code> — Landing pages, small sites</div></a>
<a class="preview-item" href="/images/scaffolds/scaffold-bare.png" target="_blank" rel="noopener"><img src="/images/scaffolds/scaffold-bare.png" alt="bare scaffold" width="1280" height="800" loading="lazy"><div class="preview-label"><code>bare</code> — Minimal structure, semantic HTML only</div></a>
<a class="preview-item" href="/images/scaffolds/scaffold-blog.png" target="_blank" rel="noopener"><img src="/images/scaffolds/scaffold-blog.png" alt="blog scaffold" width="1280" height="800" loading="lazy"><div class="preview-label"><code>blog</code> — Posts with tags and categories</div></a>
<a class="preview-item" href="/images/scaffolds/scaffold-docs.png" target="_blank" rel="noopener"><img src="/images/scaffolds/scaffold-docs.png" alt="docs scaffold" width="1280" height="800" loading="lazy"><div class="preview-label"><code>docs</code> — Documentation with sidebar</div></a>
<a class="preview-item" href="/images/scaffolds/scaffold-book.png" target="_blank" rel="noopener"><img src="/images/scaffolds/scaffold-book.png" alt="book scaffold" width="1280" height="800" loading="lazy"><div class="preview-label"><code>book</code> — Book with chapters</div></a>
{% end %}

> **Tip:** Looking for a more complete starting point? Check out the [Hwaro Examples](https://examples.hwaro.hahwul.com/) for ready-made boilerplates you can use right away.

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

> **Tip:** run `hwaro new` with no arguments to open an interactive wizard that
> suggests a path and collects the title, description, tags, and more for you.

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
hwaro build
```

Deploy the `public/` directory to any static host. See [Deploy to GitHub Pages](/deploy/github-pages/) for a quick setup.

## Next Steps

- [CLI Commands](/start/cli/) — All available commands
- [Configuration](/start/config/) — Full config reference
- [Writing Content](/writing/) — Pages, sections, taxonomies
- [Deploy](/deploy/) — Hosting and deployment guides
