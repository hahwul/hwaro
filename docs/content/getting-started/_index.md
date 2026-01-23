+++
title = "Getting Started"
+++


Welcome to Hwaro, a fast and lightweight static site generator built with Crystal. This section will guide you through installation, setup, and building your first site.

## What is Hwaro?

Hwaro (화로, meaning "fire pot" in Korean) is a modern static site generator designed for speed and simplicity. Built with the Crystal programming language, it offers:

- **Blazing fast builds** with parallel processing and smart caching
- **Markdown-first** content authoring with TOML front matter
- **Flexible ECR templates** for complete design control
- **Built-in SEO** features including sitemaps, RSS feeds, and meta tags
- **Extensible architecture** with lifecycle hooks and custom processors

## Quick Overview

Getting started with Hwaro is simple:

```bash
git clone https://github.com/hahwul/hwaro
cd hwaro && shards build --release

./bin/hwaro init my-site --scaffold docs

cd my-site && hwaro serve
```

## What You'll Learn

1. **[Installation](/getting-started/installation/)** — How to install Hwaro on your system
2. **[Quick Start](/getting-started/quick-start/)** — Create and build your first site
3. **[Configuration](/getting-started/configuration/)** — Configure your site with `config.toml`

## Prerequisites

Before installing Hwaro, ensure you have:

- [Crystal](https://crystal-lang.org/install/) 1.0 or later
- Git (for cloning the repository)
- A text editor of your choice

## Getting Help

- Check the [Guide](/guide/) for in-depth documentation
- Browse the [Reference](/reference/) for complete API details
- Report issues on [GitHub](https://github.com/hahwul/hwaro/issues)