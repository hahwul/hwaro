+++
title = "Archetypes"
description = "Content templates for consistent front matter and structure"
weight = 5
toc = true
+++

Archetypes are content templates that define default front matter and content structure for new pages. When you create content with `hwaro new`, archetypes provide consistent starting points.

`hwaro init` ships a starter `archetypes/default.md` (and scaffold-specific archetypes like `posts.md` for the blog scaffold) so `hwaro new` picks up TOML front matter with a `description` field out of the box. Edit or extend them to match your site's conventions.

## Overview

Archetypes live in the `archetypes/` directory at your project root:

```
my-site/
├── archetypes/
│   ├── default.md      # Default template
│   ├── posts.md        # For content/posts/
│   └── tools/
│       └── develop.md  # For content/tools/develop/
├── content/
├── templates/
└── config.toml
```

## Creating Archetypes

An archetype is a Markdown file with front matter and optional content. Use placeholders that get replaced when creating new content.

### Available Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{ title }}` | Content title (from `-t` flag or filename) |
| `{{ date }}` | Current date and time |
| `{{ draft }}` | Draft status (`true` for drafts/ directory) |

### Example Archetype

Create `archetypes/posts.md`:

```markdown
+++
title = "{{ title }}"
date = {{ date }}
draft = false
authors = ["Your Name"]
tags = []
categories = []
+++

# {{ title }}

Write your introduction here.

## Main Content

Add your content...
```

## Archetype Matching

When you run `hwaro new`, archetypes are matched in this order:

### 1. Explicit Flag (`-a`)

```bash
hwaro new -t "My Article" -a posts
```

Uses `archetypes/posts.md` regardless of the output path.

### 2. Path-Based Matching

```bash
hwaro new posts/hello-world.md
```

Checks for `archetypes/posts.md`.

### 3. Nested Path Matching

```bash
hwaro new tools/develop/mytool.md
```

Tries in order:
1. `archetypes/tools/develop.md`
2. `archetypes/tools.md`
3. `archetypes/default.md`

### 4. Default Archetype

If no specific archetype matches, uses `archetypes/default.md`.

### 5. Built-in Template

If no archetypes exist, uses the built-in default template. The format and
default fields of that template are controlled by `[content.new]` in
`config.toml`:

```toml
[content.new]
front_matter_format = "toml"         # "toml" (default) or "yaml"
default_fields = ["description"]      # extra keys to scaffold with empty values
bundle = false                        # true: scaffold foo/index.md instead of foo.md
```

Fields that overlap with the built-ins (`title`, `date`, `draft`, `tags`)
are ignored so they aren't duplicated with empty values.

### Leaf-bundle (directory) layout

When you plan to add multilingual siblings (`index.ko.md`) or colocated
images next to a page, you want the directory-per-page layout:

```
content/abcd/
└── index.md
```

Pick the layout per invocation, per archetype, or per site:

- **CLI:** `hwaro new posts/hello.md --bundle` (or `--no-bundle` to force
  the single-file form).
- **Archetype:** put `<!-- hwaro: bundle -->` as the first line of the
  archetype so any `hwaro new` using it defaults to bundle mode. The
  directive is stripped from the generated content.
- **Config:** `bundle = true` under `[content.new]` sets the house style.

Priority is CLI > archetype > config > single-file (the default).

## Usage Examples

### Basic Usage

```bash
# Uses path-based archetype matching
hwaro new posts/my-first-post.md

# Specify title explicitly
hwaro new posts/my-post.md -t "My First Post"

# Use specific archetype
hwaro new -t "Quick Note" -a posts
```

### Creating Different Content Types

```bash
# Blog post (uses archetypes/posts.md)
hwaro new posts/new-article.md

# Documentation (uses archetypes/docs.md)
hwaro new docs/getting-started.md

# Tool page (uses archetypes/tools.md or archetypes/tools/develop.md)
hwaro new tools/develop/my-tool.md
```

## Recommended Archetypes

### Blog Posts (`archetypes/posts.md`)

```markdown
+++
title = "{{ title }}"
date = {{ date }}
draft = false
authors = []
tags = []
categories = []
description = ""
image = ""
+++

# {{ title }}

Introduction paragraph.

## Content
```

### Documentation (`archetypes/docs.md`)

```markdown
+++
title = "{{ title }}"
date = {{ date }}
weight = 10
toc = true
+++

Brief description of this documentation page.

## Overview

## Usage

## Examples
```

### Default (`archetypes/default.md`)

```markdown
+++
title = "{{ title }}"
date = {{ date }}
draft = {{ draft }}
+++

# {{ title }}
```

## Tips

- **Consistent metadata**: Define all commonly used front matter fields in archetypes
- **Section-specific**: Create archetypes for each content section with relevant defaults
- **Nested organization**: Use subdirectories in `archetypes/` to match your content structure
- **Draft handling**: The `{{ draft }}` placeholder is `true` when creating in `drafts/` directory

## See Also

- [Pages](/writing/pages/) — Front matter fields reference
- [CLI](/start/cli/) — The `hwaro new` command