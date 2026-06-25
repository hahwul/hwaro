---
name: hwaro
description: >-
  Use when working on a Hwaro static site — scaffolding a project (hwaro init),
  creating content (hwaro new), previewing (hwaro serve), building for
  production (hwaro build), or running the doctor/tool/deploy subcommands. Also
  use when editing a Hwaro config.toml or Crinja template, or when a directory
  contains a config.toml plus content/ and templates/. Teaches the agent-safe
  output contract (--json, --quiet, NO_COLOR, classified error codes) so the CLI
  can be driven non-interactively.
---

# Hwaro

Hwaro is a fast, lightweight static site generator written in Crystal. It turns
Markdown content and [Crinja](https://github.com/straight-shoota/crinja)
(Jinja2-compatible) templates into a static `public/` directory. This skill
teaches you how to drive the `hwaro` CLI correctly and how to make safe,
verifiable edits to a Hwaro project.

> For visual design, theming, and template/CSS aesthetics, use the companion
> **`hwaro-design`** skill instead. This skill is about *operating* Hwaro; that
> one is about *how the site looks*.

## When to use this skill

Trigger this skill when the user asks to:

- Create, build, serve, or deploy a Hwaro site.
- Add or edit content (Markdown pages, sections, front matter).
- Edit `config.toml` or files under `templates/`, `static/`, `data/`, `i18n/`,
  or `archetypes/`.
- Diagnose a broken build, dead links, or invalid front matter.
- Import from / export to another generator (Hugo, Jekyll, WordPress, …).

Confirm you are in a Hwaro project before acting: a project root has a
`config.toml`, usually alongside `content/` and `templates/`. Run
`hwaro --version` (also `hwaro -V` or `hwaro version`) to confirm the binary is
installed and which version you are targeting. This skill is written against
**Hwaro 0.16.x**.

## Project layout

```
my-site/
├── config.toml         # Site configuration (TOML). The single source of truth.
├── content/            # Markdown. _index.md defines a section; index.md a leaf bundle.
├── templates/          # Crinja (.html) templates: base.html, page.html, section.html, partials/…
├── static/             # Copied verbatim to the site root (css/, js/, images/…).
├── data/               # *.yml|yaml|json|toml auto-loaded into site.data.<name> (CSV only via load_data()).
├── i18n/               # *.toml translation tables for the `t` filter (multilingual).
├── archetypes/         # Front-matter templates used by `hwaro new`.
└── public/             # BUILD OUTPUT. Never edit by hand; it is regenerated.
```

Front matter is TOML (`+++ … +++`) or YAML (`--- … ---`). `<!-- more -->` marks
the summary cutoff. `public/` is generated — edit sources, then rebuild.

## Agent-safe output contract

Hwaro is built to be driven by scripts and agents. **Prefer the machine
contract over scraping human text.**

- **`--json`** — supported by classified-error paths and by these tools:
  `tool list`, `tool stats`, `tool validate`, `tool unused-assets`,
  `tool doctor`, `tool check-links`, `tool convert`, plus `init --list-scaffolds`,
  `new --list-archetypes`, and `deploy --list-targets`. Parse the JSON; do not
  regex the pretty output.
- **`-q` / `--quiet`** — suppresses the banner and informational lines; warnings
  and errors still go to stderr. Good for CI/agent runs.
- **`NO_COLOR=1`** (env) — strips ANSI color everywhere. Color is also auto-off
  when stdout is not a TTY, so piped/redirected output is already clean.

### Branch on exit codes, not messages

Classified failures emit a stable code and a matching process exit code:

| Exit | Code | Meaning |
|------|------|---------|
| 0 | *(success)* | Completed normally |
| 1 | *(unclassified)* | Legacy/generic failure |
| 2 | `HWARO_E_USAGE` | Bad/missing flag or argument, unknown command |
| 3 | `HWARO_E_CONFIG` | `config.toml` missing, unparseable, or invalid |
| 4 | `HWARO_E_TEMPLATE` | Crinja template render error |
| 5 | `HWARO_E_CONTENT` | Content parse error / invalid front matter |
| 6 | `HWARO_E_IO` | Filesystem error (missing dir, permission denied) |
| 7 | `HWARO_E_NETWORK` | Deploy upload or remote-scaffold fetch failure |
| 70 | `HWARO_E_INTERNAL` | Unexpected/unrecoverable bug |

In text mode the error line is prefixed: `Error [HWARO_E_CONFIG]: …`. Under
`--json`/`--quiet` it is a payload: `{"status":"error","error":{"code":…,"category":…,"message":…,"hint":…}}`.
Use the exit code to decide what to fix (e.g. `3` → look at `config.toml`,
`4` → look at templates, `5` → look at the content file named in the message).

## Core workflows

### A. Scaffold a new site — `hwaro init`

```bash
hwaro init my-site                       # default scaffold
hwaro init my-site --scaffold blog       # simple | bare | blog | blog-dark | docs | docs-dark | book | book-dark
hwaro init my-site --scaffold github:user/repo        # remote scaffold (GitHub shorthand or full URL)
hwaro init --list-scaffolds --json       # discover built-ins programmatically
```

Useful flags: `--agents remote|local` (AGENTS.md mode), `--include-multilingual en,ko,ja`,
`--minimal-config`, `--skip-sample-content`, `--skip-taxonomies`, `-f/--force`.
Remote scaffolds fetch `config.toml`, `templates/`, `static/`, and the content
*structure* (front matter only). Set `GITHUB_TOKEN` to avoid rate limits.

### B. Create content — `hwaro new`

```bash
hwaro new content/blog/my-post.md            # path-based
hwaro new my-post.md -s blog --draft --tags "crystal,web" --date 2026-03-22
hwaro new -t "My Post Title"                 # title only
hwaro new posts/launch.md --bundle           # leaf bundle (posts/launch/index.md) for co-located assets
hwaro new --list-archetypes --json
```

Front matter comes from `archetypes/` (matched by `-a`, then by path, then
`archetypes/default.md`, then a built-in). Use `--bundle` when a page owns
images/assets; use `--no-bundle` to force a single file.

### C. Develop — `hwaro serve`

```bash
hwaro serve                      # http://127.0.0.1:3000, live reload ON by default
hwaro serve -p 8080 --open --drafts
hwaro serve -i ../my-site        # serve a project elsewhere without cd-ing
```

Live reload injects a WebSocket client and refreshes browsers after each
rebuild. The watcher picks a smart strategy by change type (config → full
rebuild, content → incremental, templates → re-render, static → copy). Add
`--access-log` to see requests, `--no-live-reload` for production-like serving,
`--fast-start` on large sites. This is the loop to use while iterating.

### D. Build for production — `hwaro build`

```bash
hwaro build                                  # → public/
hwaro build --minify                         # safe HTML/JSON/XML minification
hwaro build --cache                          # incremental (.hwaro_cache.json); --full forces clean rebuild
hwaro build -o dist --base-url https://example.com   # override output dir / base_url
hwaro build -e production                    # load config.production.toml override
hwaro build --drafts --include-future --include-expired
hwaro build --quiet                          # CI/agent: only warnings/errors
```

Key points:
- `--base-url` matters for **project/subpath deploys** (e.g. GitHub Pages
  `user.github.io/repo`): internal URLs must include the base path or they 404.
- `--minify`, `--cache`, `--jobs`, and `--stream` never change the rendered
  output — only speed/size/memory. For template- or shortcode-heavy sites try
  `--jobs 2` if builds feel slow.
- Large sites: `--stream` / `--memory-limit 512M` reduce peak memory.

### E. Diagnose & validate

```bash
hwaro doctor                 # config/template/structure issues; gate CI on exit code (0/3/4/5; 1 under --strict/--max-warnings)
hwaro doctor --fix           # normalize config values (base_url trailing slash, sitemap priority…)
hwaro doctor --approve       # add recommended config.toml sections (--full does both)
hwaro tool validate --json   # content front matter + markup
hwaro tool check-links --json  # dead external links
```

`doctor` returns a classified exit code by worst issue, so CI can gate on it
directly. Warnings (empty base_url, trailing slash, duplicate taxonomy names)
are advisory and never fail the exit code.

### F. Maintain content — `hwaro tool …`

```bash
hwaro tool list drafts --json        # all | drafts | published
hwaro tool stats --json              # word counts, page totals
hwaro tool convert to-yaml           # to-yaml | to-toml | to-json (front matter, in place)
hwaro tool unused-assets --json      # unreferenced files under static/
hwaro tool agents-md --write         # (re)generate AGENTS.md for AI agents
hwaro tool import hugo /path/to/hugo-site     # also: jekyll, wordpress, notion, obsidian, hexo, astro, eleventy
hwaro tool export jekyll                       # also: hugo
```

`-c, --content DIR` scopes most tools to a subtree; `-j, --json` is widely
available. Run `hwaro tool <name> --help` for specifics.

### G. Platform config & deploy

```bash
hwaro tool platform github-pages     # netlify | vercel | cloudflare | github-pages | gitlab-ci | codeberg-pages
hwaro deploy --dry-run               # preview planned changes
hwaro deploy prod --confirm          # deploy to a configured target
hwaro deploy --list-targets --json
```

`hwaro tool platform <host>` writes the CI/host config; `hwaro deploy` pushes
`public/` (or `deployment.source_dir`) to a target defined under
`[deployment]` in `config.toml`. `--max-deletes N` guards against runaway
deletions (`-1` disables the cap).

## Editing config.toml safely

`config.toml` is the trusted source of truth. It is TOML — preserve types and
section structure; a syntax error fails the build with `HWARO_E_CONFIG` (exit
`3`). Common sections: `[plugins]`, `[highlight]`, `[og]` / `[og.auto_image]`,
`[search]`, `[pagination]`, `[[taxonomies]]`, `[sitemap]`, `[feeds]`,
`[image_processing]`, `[assets]`, `[auto_includes]`, `[markdown]`, `[pwa]`,
`[deployment]`. After editing, run `hwaro doctor`; `--fix` normalizes values
(e.g. a base_url trailing slash) and `--approve` (or `--full`) adds recommended
sections. When unsure of a key, check the [config reference](https://hwaro.hahwul.com/start/config/).

## Editing templates safely

Templates under `templates/` are Crinja (Jinja2-compatible). The essentials:

- **Inheritance:** child templates `{% extends "base.html" %}` and fill
  `{% block content %}…{% endblock %}`. Partials via `{% include "partials/x.html" %}`.
- **Rendered HTML emits raw:** Hwaro disables template autoescape, so
  `{{ content }}`, `{{ og_all_tags }}`, and `{{ toc }}` output HTML directly —
  the built-in scaffolds write them with no filter. The docs show `| safe`
  (`{{ content | safe }}`) as a harmless, portable convention; keep it if you
  see it, but its absence won't escape your markup. Use the `e` filter where you
  *do* want escaping (e.g. an attribute value).
- **Always guard nil:** `{% if page.image %}…{% endif %}`; use
  `{{ page.description | default(value=site.description) }}`.
- **URLs:** build links with `{{ url_for(path='/about/') }}` /
  `{{ "/x.png" | relative_url }}` and assets with `{{ asset(name='main.css') }}`
  so `base_url`/subpaths and fingerprints resolve correctly. Never hardcode the
  domain.
- The data model (`site`, `section`, `page`, `paginator`, `seo`, functions like
  `get_page`/`get_section`/`get_taxonomy`/`resize_image`, filters, and tests) is
  documented under [Templates](https://hwaro.hahwul.com/templates/).

A template error fails the build with `HWARO_E_TEMPLATE` (exit `4`); the message
names the template and line.

## Common pitfalls

- **Subpath deploys 404:** if the site is served from a subdirectory, set
  `base_url` (or pass `--base-url`) to include the path, and generate links via
  `url_for`/`relative_url`/`asset` — not literal `/foo/`.
- **Drafts vanish in production:** `hwaro build`/`serve` exclude `draft = true`
  unless you pass `--drafts`. Likewise future-dated/expired content needs
  `--include-future` / `--include-expired`.
- **Stale output with `--cache`:** changing `config.toml` or templates
  invalidates the whole cache; if output looks stale, run `--cache --full` (or
  drop `--cache`) to force a clean rebuild.
- **Don't edit `public/`:** it is regenerated on every build. Edit sources.
- **`hwaro new` needs a section/path,** not just a title, to place a file
  predictably; prefer the explicit `content/<section>/<slug>.md` form.

## Verification loop

After any change, verify before reporting success:

1. `hwaro doctor --quiet` — catch config/template/structure regressions (gate on
   exit code).
2. `hwaro build --quiet` (add `--drafts` if previewing unpublished work) — a
   clean exit `0` means it renders.
3. For content/markup changes, `hwaro tool validate --json`; for links,
   `hwaro tool check-links --json`.
4. To eyeball the result, `hwaro serve --open` and rely on live reload.

Report the actual exit codes / JSON `status`. If a build fails, surface the
classified code and the file it names rather than guessing.

## Reference

- Docs: <https://hwaro.hahwul.com> — CLI, config, templates, features, deploy.
- LLM-oriented full reference: <https://hwaro.hahwul.com/llms-full.txt>.
- Per-project conventions live in the project's `AGENTS.md`
  (`hwaro tool agents-md` regenerates it). Read it first — it may add
  site-specific rules that override these defaults.
