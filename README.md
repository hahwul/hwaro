<div align="center">
  <img alt="Hwaro Logo" src="docs/static/hwaro-wide.png" width="500px;">
  <p>Hwaro (화로) is a lightweight and fast static site generator written in Crystal.</p>
</div>

<p align="center">
<a href="https://github.com/hahwul/hwaro/blob/main/CONTRIBUTING.md">
<img src="https://img.shields.io/badge/CONTRIBUTIONS-WELCOME-000000?style=for-the-badge&labelColor=black"></a>
<a href="https://github.com/hahwul/hwaro/releases">
<img src="https://img.shields.io/github/v/release/hahwul/hwaro?style=for-the-badge&color=black&labelColor=black&logo=web"></a>
<a href="https://crystal-lang.org">
<img src="https://img.shields.io/badge/Crystal-000000?style=for-the-badge&logo=crystal&logoColor=white"></a>
</p>

<p align="center">
  <a href="https://hwaro.hahwul.com/getting-started/">Documentation</a> •
  <a href="https://hwaro.hahwul.com/getting-started/installation/">Installation</a> •
  <a href="https://hwaro.hahwul.com/deployment/#github-actions">Github Action</a> •
  <a href="#contributing">Contributing</a>
</p>

---

Hwaro is a lightweight static site generator written in [Crystal](https://crystal-lang.org/), focused on speed and simplicity. It provides a straightforward workflow for building high-performance websites using Markdown and Jinja2 templates.

The tool processes Markdown content with TOML front matter and utilizes the Crinja engine (a Jinja2 implementation for Crystal) to offer flexible layout management, including template inheritance and includes. To optimize build times, Hwaro incorporates parallel processing and a caching mechanism.

Core Features:
* Content & Templating: Supports Markdown-based content creation with Jinja2-compatible templating for full design control.
* Build Hooks: Supports custom commands before and after the site build process, allowing users to integrate asset minification, deployment scripts, or other pipeline tasks.
* Modern Standards: Automatically generates essential files for modern web discovery, including Sitemaps, RSS feeds, llms.txt, and AGENTS.md.
* Built-in SEO: Includes native support for OpenGraph tags and other metadata to improve search engine and social media visibility.
* Performance: Built with Crystal to ensure fast build cycles through concurrent execution.

Hwaro is designed for developers who need a reliable and efficient tool for managing blogs, documentation, or personal project sites without unnecessary complexity.

## Installation

### Homebrew

```bash
brew tap hahwul/hwaro
brew install hwaro
```

### From source

```bash
# Clone the repository
git clone https://github.com/hahwul/hwaro.git
cd hwaro

# Install dependencies 
shards install

# Build
shards build --production
```

## Contributing

Hwaro is an open-source project made with ❤️. If you would like to contribute, please check [CONTRIBUTING.md](CONTRIBUTING.md) and submit a Pull Request.

![](docs/static/CONTRIBUTORS.svg)
