+++
title = "Archetypes"
weight = 5
toc = true
+++

Archetypes are content templates that define default front matter and content structure for new pages. When you create content with `hwaro new`, archetypes provide consistent starting points.

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
---
title: "{{ title }}"
date: {{ date }}
draft: false
author: "Your Name"
tags: []
categories: []
---

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

If no archetypes exist, uses the built-in default template.

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
---
title: "{{ title }}"
date: {{ date }}
draft: false
author: ""
tags: []
categories: []
description: ""
image: ""
---

# {{ title }}

Introduction paragraph.

## Content
```

### Documentation (`archetypes/docs.md`)

```markdown
---
title: "{{ title }}"
date: {{ date }}
weight: 10
toc: true
---

Brief description of this documentation page.

## Overview

## Usage

## Examples
```

### Default (`archetypes/default.md`)

```markdown
---
title: "{{ title }}"
date: {{ date }}
draft: {{ draft }}
---

# {{ title }}
```

## Tips

- **Consistent metadata**: Define all commonly used front matter fields in archetypes
- **Section-specific**: Create archetypes for each content section with relevant defaults
- **Nested organization**: Use subdirectories in `archetypes/` to match your content structure
- **Draft handling**: The `{{ draft }}` placeholder is `true` when creating in `drafts/` directory