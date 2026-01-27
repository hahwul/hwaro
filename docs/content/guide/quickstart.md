+++
title = "Quickstart"
toc = true
+++

This walkthrough assumes you want a **docs-style site** (sidebar, structured sections). If you want a smaller site, use `--scaffold simple` instead.

## 1) Create a project

```bash
hwaro init my-site --scaffold docs
cd my-site
```

## 2) Run the dev server

```bash
hwaro serve
```

Open `http://localhost:3000`.

## 3) Add a page

Create a new Markdown file:

```bash
hwaro new content/overview.md
```

Then edit it:

```markdown
+++
title = "Overview"
description = "What this service does"
+++

Hello from Hwaro.
```

You should get `/overview/`.

## 4) Add a section (docs-style)

Sections are folders with an `_index.md`.

```bash
mkdir -p content/guides
cat > content/guides/_index.md <<'EOF'
+++
title = "Guides"
+++

Short how-to guides for this service.
EOF
```

Add a page inside the section:

```bash
hwaro new content/guides/getting-started.md
```

You should get `/guides/` and `/guides/getting-started/`.

## 5) Configure the site

Edit `config.toml`:

```toml
title = "My Service"
description = "Docs for My Service"
base_url = "https://example.com"
```

- While developing, `base_url = ""` is fine.
- For production, always set `base_url` to the final URL.

See: [Configuration](/getting-started/configuration/).

## 6) Build for production

```bash
hwaro build --minify
```

Deploy the generated `public/` directory.

## Next

- How content maps to URLs: [Directory Structure](/getting-started/directory-structure/)
- Content primitives: [Content](/content/)
- GitHub Pages deployment: [Github Pages](/deployment/github-pages/)
