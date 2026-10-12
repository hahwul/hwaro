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
`hwaro --version` (also `hwaro -v`, `hwaro -V`, or `hwaro version`) to confirm the binary is
installed and which version you are targeting. This skill is written against
**Hwaro 0.20.x** (current `main`). If a flag below is missing from your binary,
it is newer than your install — `hwaro <command> --help` is always the
authoritative list for the version you have.

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
├── public/             # BUILD OUTPUT (`hwaro build`). Never edit by hand; it is regenerated.
├── .hwaro/             # Tool state: serve output (.hwaro/serve), serve cache, remote data… Self-gitignored.
└── .hwaro_cache.json   # `hwaro build --cache` state.
```

Front matter is TOML (`+++ … +++`), YAML (`--- … ---`), or JSON (a `{…}` object
as the very first byte of the file). `<!-- more -->` marks
the summary cutoff; without it (and without `description`) `page.summary` is an
automatic 70-word excerpt of the body (`[content] summary_length`, `0` disables;
`page.summary_truncated` tells whether it was cut). `public/` is generated —
edit sources, then rebuild.

## Agent-safe output contract

Hwaro is built to be driven by scripts and agents. **Prefer the machine
contract over scraping human text.**

- **`-j` / `--json`** — available on every top-level command (`init`, `new`,
  `build`, `serve`, `doctor`, `deploy`) and on the tool subcommands `list`,
  `stats`, `validate`, `unused-assets`, `check-links`, `convert`, `import`,
  `export`, `doctor`. It implies `--quiet`, and errors become the JSON error
  payload below. Discovery flags pair with it: `init --list-scaffolds`,
  `new --list-archetypes`, `deploy --list-targets`. Parse the JSON; do not
  regex the pretty output.
  - `build --json` prints one summary object:
    `{"status":"ok","pages_generated":…,"duration_ms":…,"cache_hits":…,"raw_files_processed":…,"pages_not_published":…}`.
  - `serve --json` prints the ready event as one line
    (`{"event":"ready","url":…,"pid":…}`); without it the line is
    `hwaro serve: ready url=… pid=…`. Wait for that line, not for a sleep.
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
hwaro init my-site                       # default scaffold (simple)
hwaro init my-site --scaffold blog       # simple | bare | blog | docs | book
hwaro init my-site --scaffold github:user/repo        # remote scaffold (GitHub shorthand or full URL)
hwaro init --list-scaffolds --json       # discover built-ins programmatically
```

Useful flags: `--agents remote|local` (AGENTS.md mode, default `remote`),
`--skip-agents-md`, `--include-multilingual en,ko,ja`, `--minimal-config` /
`--full-config` (fully commented config), `--skip-sample-content`,
`--skip-taxonomies`, `-f/--force` (non-empty dir, keeps existing files),
`--clean` (wipe the target first; refuses a dir containing `.git`). `--wizard`
is TTY-only — don't use it from an agent.
Remote scaffolds fetch `config.toml`, `templates/`, `static/`, `data/`, `i18n/`,
`archetypes/`, and the content *structure* (front matter only); a
`/tree/<branch>/` URL selects the branch. Set `GITHUB_TOKEN` to avoid rate
limits or to read a private repository.

### B. Create content — `hwaro new`

```bash
hwaro new content/blog/my-post.md            # path-based (the content/ prefix is optional)
hwaro new my-post.md -s blog --draft --tags "crystal,web" --date 2026-03-22
hwaro new posts/my-post.md -t "My Post Title"  # title sets front matter, not the path
hwaro new posts/launch.md --bundle           # leaf bundle (posts/launch/index.md) for co-located assets
hwaro new --list-archetypes --json
```

Front matter comes from `archetypes/` (matched by `-a`, then by path, then
`archetypes/default.md`, then a built-in). Use `--bundle` when a page owns
images/assets; use `--no-bundle` to force a single file. The wizard fills the
default archetype's `{{ description }}` placeholder; the flag form leaves it empty.

Running `hwaro new` with no `<path>` opens an interactive wizard in a TTY — but
that never triggers in agent/CI runs (no TTY), where it instead exits with
`HWARO_E_USAGE`. **Always pass an explicit path** — `posts/<slug>.md` and
`content/posts/<slug>.md` land in the same place.

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
`--fast` to skip OG-image/image-resize work, `--fast-start` on large sites,
`--header "Name: value"` to mimic production headers, `-b 0.0.0.0` to bind
beyond localhost. This is the loop to use while iterating.

`serve` builds into **`.hwaro/serve/`**, not `public/`, with the dev URL baked
into every link — it never touches the deployable build, and `hwaro deploy`
refuses that directory. To inspect real output, run `hwaro build`. When an
agent starts `serve` in the background, wait for the ready line (see above) and
kill that exact PID when done.

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
- `--cache`, `--jobs`, and `--stream` never change the rendered output — only
  speed/memory (`--minify` changes bytes, not content). Leave `--jobs` unset:
  the render worker count is chosen automatically from the site's shape.
- Large sites: `--stream` / `--memory-limit 512M` reduce peak memory.
- Faster local/CI builds: `--skip-og-image`, `--skip-image-processing`,
  `--skip-highlighting`.
- `[build] hooks.pre` / `hooks.post` in `config.toml` run shell commands around
  every build (also on `serve`'s full rebuilds).

### E. Diagnose & validate

```bash
hwaro doctor                 # config/template/structure issues; gate CI on exit code (0/3/4/5; 1 under --strict/--max-warnings)
hwaro doctor --fix           # normalize config values (base_url trailing slash, sitemap priority…)
hwaro doctor --approve       # add recommended config.toml sections (--full does both)
hwaro doctor --fix --dry-run # preview config.toml changes without writing
hwaro tool validate --json   # content front matter + markup (+ [[content.schema]] rules)
hwaro build -q && hwaro tool check-links --json  # dead internal/external links and #anchors
```

`doctor` returns a classified exit code by worst issue, so CI can gate on it
directly. Warnings (placeholder title, empty base_url, duplicate taxonomy names)
are advisory and don't fail the exit code unless you pass `--strict` or
`--max-warnings N` (then exit `1`). `tool validate` mirrors that. `check-links`
exits non-zero on dead links; anchor checks read the built HTML, so build first
(`--internal-only`, `--external-only`, `--skip-anchors`, `--ignore-url PATTERN`
narrow it).

### F. Maintain content — `hwaro tool …`

```bash
hwaro tool list drafts --json        # all | drafts | published; --sort date|title|path, -n N
hwaro tool stats --json              # word counts, page totals, top tags
hwaro tool convert to-yaml           # to-yaml | to-toml | to-json (front matter, in place)
hwaro tool unused-assets --json      # unreferenced files under static/ (--delete -f removes them)
hwaro tool agents-md --write         # (re)generate AGENTS.md (--remote = links-only; -f keeps site-specific section)
hwaro tool import hugo /path/to/hugo-site     # also: jekyll, wordpress, notion, obsidian, hexo, astro, eleventy
hwaro tool export jekyll                       # also: hugo (writes to export/ by default)
```

`-c, --content-dir DIR` scopes most tools to a subtree; import/export `--json`
emit a per-file manifest. `--dry-run` previews convert/import/export without
writing; import skips existing files unless `--force`. `tool ci` is deprecated
— use `tool platform github-pages`. Run `hwaro tool <name> --help` for
specifics.

### G. Platform config & deploy

```bash
hwaro tool platform github-pages     # netlify | vercel | cloudflare | github-pages | gitlab-ci | codeberg-pages (--stdout to preview)
hwaro deploy --list-targets --json
hwaro deploy prod --dry-run          # preview planned changes
hwaro deploy prod                    # deploy to a configured target (positional or -t, repeatable)
```

`hwaro tool platform <host>` writes the CI/host config; `hwaro deploy` pushes
`public/` (or `deployment.source_dir`, or `-s DIR`) to targets declared as
`[[deployment.targets]]` in `config.toml` — `path`/`file://` copy locally,
`s3://`/`gs://`/`az://` run the cloud CLI, `command` runs a shell command.
`--max-deletes N` guards against runaway deletions (default 256, `-1` disables
the cap).

**`--confirm` is interactive.** Without a TTY (or under `--json`) it fails with
`HWARO_E_USAGE` instead of prompting, so agents must not pass it. A `command`
target containing shell metacharacters also asks for confirmation; in a
non-interactive run only `--force` skips that check — get the user's approval
first. Deploying is outward-facing: run `--dry-run` and confirm with the user
before the real deploy.

## Editing config.toml safely

`config.toml` is the trusted source of truth. It is TOML — preserve types and
section structure; a syntax error fails the build with `HWARO_E_CONFIG` (exit
`3`). Sections by area:

- **Site & build:** `[build]` (incl. `hooks.pre`/`hooks.post`), `[markdown]`,
  `[content]` (`summary_length`…), `[permalinks]`, `[links]`, `[static]`,
  `[serve]`, `[plugins]`, `[doctor]`.
- **Content model:** `[[taxonomies]]`, `[[menus.<name>]]`, `[pagination]`,
  `[series]`, `[related]`, `[content.files]`, `[content.new]`,
  `[[content.schema]]` (per-section front-matter rules),
  `[[content.generate]]` (pages from `site.data`), `[[data.remote]]` (fetch
  data at build time), `[outputs]` (extra JSON/XML/TXT/CSV outputs),
  `languages.*` (multilingual), `[versions]` + `[[versions.list]]` (versioned
  docs), `[git]` (`page.git` + `updated` fallback; needs a full-depth checkout).
- **Output & SEO:** `[sitemap]`, `[robots]`, `[feeds]`, `[og]` /
  `[og.auto_image]`, `[search]`, `[llms]`, `[pwa]`, `[amp]`.
- **Assets:** `[highlight]`, `[assets]`, `[sass]`, `[auto_includes]`,
  `[image_processing]`, `[privacy]` (self-host third-party assets), `[csp]`.
- **Deploy:** `[deployment]` + `[[deployment.targets]]`.

After editing, run `hwaro doctor`; `--fix` normalizes values (e.g. a base_url
trailing slash) and `--approve` (or `--full`) adds recommended sections. When
unsure of a key, check the [config reference](https://hwaro.hahwul.com/start/config/)
— its "Feature Configuration Reference" table links every section's page.

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
- **URLs:** build links with `{{ url_for(path='/about/') }}` (alias `get_url`),
  `{{ "/x.png" | relative_url }}` / `| absolute_url`, and assets with
  `{{ asset(name='main.css') }}` so `base_url`/subpaths and fingerprints
  resolve correctly. Never hardcode the domain. Mark the current nav item with
  `{% if item.url | active_path %}`.
- The data model (`site`, `section`, `page`, `paginator`, `seo`), functions
  (`get_page`, `get_section`, `get_taxonomy`, `get_taxonomy_url`, `get_menu`,
  `load_data`, `env`, `now`, `asset_integrity`, `resize_image`), filters, and
  tests are documented under [Templates](https://hwaro.hahwul.com/templates/);
  Markdown render hooks are `templates/hooks/render-*.html` (link, image, heading, code block, blockquote, table).

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
- **Don't deploy or diff `.hwaro/serve/`:** it is dev output with the dev
  `base_url` baked in. Build with `hwaro build` and inspect `public/`.
- **`hwaro new` needs a path,** not just a title (`-t` only sets front matter).
- **Interactive flags hang or fail in agent runs:** avoid `init --wizard`,
  `deploy --confirm`, `tool unused-assets --delete` without `-f`.

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
