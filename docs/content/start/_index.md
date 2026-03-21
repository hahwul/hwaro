+++
title = "Start"
description = "Get up and running with Hwaro"
+++

## What is Hwaro?

Hwaro is a lightweight and fast static site generator (SSG) written in [Crystal](https://crystal-lang.org). It processes Markdown content with TOML front matter and Jinja2-compatible templates (Crinja) to build high-performance static sites.

Hwaro is designed to help you **build your own website without relying on pre-made themes**. Instead of picking a theme and tweaking it, you craft your templates and styles from scratch, giving you full control over every aspect of your site. With parallel builds, incremental caching, and a dev server with live reload, Hwaro keeps the development experience fast and smooth.

## Quick Start

```bash
# Install (see Installation for all methods)
brew tap hwaro/hwaro && brew install hwaro

# Create a new site
hwaro init my-site --scaffold blog
cd my-site

# Start dev server with live reload
hwaro serve
```

Open `http://localhost:3000` to preview your site.

## Why "Hwaro"?

Hwaro (화로) is the Korean word for **Furnace** — the same name used in Minecraft's Korean localization. In the game, the Furnace is an essential tool that transforms raw materials into useful items. Hwaro aims to serve the same role for static sites: feed in your content, and it crafts a complete website.

![Hwaro in Minecraft](/images/hwaro-minecraft.webp)
