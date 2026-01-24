+++
title = "CLI Usage"
toc = true
+++

## Global Options

| Option | Description |
|--------|-------------|
| `-v, --verbose` | Show detailed output |
| `-h, --help` | Show help |
| `--version` | Show version |

## init

Create a new project.

```bash
hwaro init [path] [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--scaffold TYPE` | Project type: `simple`, `blog`, `docs` |
| `--force` | Overwrite existing files |
| `--skip-sample-content` | Skip sample content |

**Examples:**

```bash
hwaro init my-site
hwaro init my-docs --scaffold docs
hwaro init my-blog --scaffold blog
```

## build

Build the static site.

```bash
hwaro build [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-o, --output-dir DIR` | Output directory (default: `public`) |
| `-d, --drafts` | Include drafts |
| `--minify` | Minify HTML/JSON/XML |
| `--no-parallel` | Disable parallel processing |
| `--cache` | Enable caching |
| `--skip-highlighting` | Disable syntax highlighting |

**Examples:**

```bash
hwaro build
hwaro build --minify
hwaro build --drafts --cache
hwaro build -o dist
```

## serve

Start development server with live reload.

```bash
hwaro serve [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `-p, --port PORT` | Port (default: `3000`) |
| `-b, --bind HOST` | Bind address (default: `0.0.0.0`) |
| `--open` | Open browser |
| `-d, --drafts` | Include drafts |

**Examples:**

```bash
hwaro serve
hwaro serve --port 8080
hwaro serve --open --drafts
```

## new

Create a new content file.

```bash
hwaro new [path]
```

**Examples:**

```bash
hwaro new content/about.md
hwaro new content/blog/my-post.md
```

Creates a file with front matter template:

```markdown
+++
title = "My Post"
date = "2024-01-15"
draft = true
+++

Write your content here...
```

## Build Hooks

Configure in `config.toml`:

```toml
[build]
hooks.pre = ["npm install"]
hooks.post = ["npm run minify"]
```

- Pre-hooks run before build (failure aborts build)
- Post-hooks run after build (failure shows warning)
- Hooks run for both `build` and `serve`
