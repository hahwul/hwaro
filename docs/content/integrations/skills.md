+++
title = "Agent Skills"
description = "Drop-in SKILL.md files for Claude Code, Cursor, OpenCode, Codex, and other skill-aware agents."
weight = 1
toc = true
+++

Hwaro ships two [Agent Skills](https://github.com/hahwul/hwaro/tree/main/skills)
— self-contained `SKILL.md` files that teach a skill-aware AI agent how to work
with Hwaro. Once installed, the agent loads the relevant skill automatically
when it detects a Hwaro task.

| Skill | What it teaches |
|-------|-----------------|
| **`hwaro`** | Operating the CLI — scaffolding (`init`), content (`new`), preview (`serve`), production builds (`build`), and the `doctor`/`tool`/`deploy` subcommands. Emphasizes the agent-safe output contract: `--json`, `--quiet`, `NO_COLOR`, and the classified `HWARO_E_*` error/exit codes, plus safe `config.toml` and Crinja template edits. |
| **`hwaro-design`** | Designing and restyling a site. It **reads your brief, declares a one-line Design Read, and sets three design dials** (asking questions only when your intent is genuinely ambiguous), then produces distinctive, production-grade design within Hwaro's Crinja templates and CSS-variable token system — under a strict anti-slop discipline and a mechanical pre-flight check that filter out generic AI aesthetics. |

## Install with `npx skills`

The [`skills` CLI](https://www.npmjs.com/package/skills) is the easiest way to
install and keep skills up to date. Adding the repo installs **both** Hwaro
skills (`hwaro` and `hwaro-design`).

```bash
# Add to the current project — prompts you to pick the agent (.claude/skills, .cursor/, …)
npx skills add hahwul/hwaro

# Install globally for every project
npx skills add hahwul/hwaro -g

# Target a specific agent (e.g. Claude Code)
npx skills add hahwul/hwaro -a claude-code

# Non-interactive — good for CI
npx skills add hahwul/hwaro -g -a claude-code -y
```

Update or remove later by skill name:

```bash
npx skills update hwaro hwaro-design
npx skills remove hwaro hwaro-design
```

## Install manually

If you would rather not use `npx`, copy the files straight from the repository.
For **Claude Code** the target path is `~/.claude/skills/<name>/SKILL.md`:

```bash
# hwaro — the CLI skill
mkdir -p ~/.claude/skills/hwaro
curl -o ~/.claude/skills/hwaro/SKILL.md \
  https://raw.githubusercontent.com/hahwul/hwaro/main/skills/hwaro/SKILL.md

# hwaro-design — the design skill
mkdir -p ~/.claude/skills/hwaro-design
curl -o ~/.claude/skills/hwaro-design/SKILL.md \
  https://raw.githubusercontent.com/hahwul/hwaro/main/skills/hwaro-design/SKILL.md
```

Other agents use different skill directories (for example `.cursor/` or a
project-local `skills/` folder) — check your agent's documentation for the
correct location.

## What the skills cover

### `hwaro` — driving the CLI

- **When it triggers:** any Hwaro task, or a directory with `config.toml` plus
  `content/` and `templates/`.
- **Output contract:** prefer `--json` and branch on the classified exit codes
  (`HWARO_E_USAGE`, `HWARO_E_CONFIG`, `HWARO_E_TEMPLATE`, `HWARO_E_CONTENT`, …)
  instead of scraping human-readable text.
- **Workflows:** `init` scaffolds, `new` + archetypes, the `serve` live-reload
  dev loop, production `build` (`--minify`, `--cache`, `--base-url`, env
  overrides), `doctor` / `tool validate` / `tool check-links`, content tools,
  `tool platform`, and `deploy`.
- **Safe edits:** TOML config rules and Crinja template gotchas (`| safe`, nil
  guards, `url_for`/`asset` for URLs), plus a verify-by-exit-code loop.

### `hwaro-design` — designing the site

- **Design Read first:** reads your brief and declares a one-line design
  direction plus three dials (`DESIGN_VARIANCE` / `MOTION_INTENSITY` /
  `VISUAL_DENSITY`) before writing any CSS. It asks a short, focused question
  round only when your intent is genuinely ambiguous — and runs a full taste
  interview only when you ask for one — so the result reflects **your** taste
  rather than a default.
- **Anti-slop discipline:** an extensive list of hard bans on the signatures of
  AI-generated design — em-dashes in page copy, eyebrow-label overuse, repeated
  section layouts, hero-overflow, fake screenshots built from `<div>`s,
  AI-purple gradients, decorative dots and locale strips, "Jane Doe" demo
  content — plus layout, copy-density, and imagery rules, all enforced by a
  mechanical pre-flight checklist before anything is declared done.
- **Hwaro mechanics:** Crinja template structure, the three CSS-delivery options
  (inline, `[auto_includes]`, the `[assets]` pipeline), the shared `light-dark()`
  design-token vocabulary all built-in scaffolds theme through (light and dark
  come automatically; retheme by overriding the token pairs), responsive images
  via `resize_image`, and static-site motion via CSS scroll-driven animations
  and `IntersectionObserver` — no framework required.

## Prerequisite

Install the Hwaro CLI so the agent can actually run builds and previews — see
[Installation](/start/installation/). A skill is only as useful as the binary it
drives.

The `hwaro` skill complements your project's `AGENTS.md`: the skill is portable
guidance that travels with the agent across any Hwaro project, while `AGENTS.md`
(generated by [`hwaro tool agents-md`](/start/tools/agents-md/)) carries
project-specific conventions. Agents should read `AGENTS.md` first — it can
override the skill's defaults.

## Authoring tips

Both skills live under [`skills/`](https://github.com/hahwul/hwaro/tree/main/skills)
in the Hwaro repository. When contributing:

- Write for **agent interaction patterns** — what to run, when, and how to
  recover — rather than duplicating the full CLI/template reference (link to
  these docs instead).
- Keep the `description` front matter precise: it is what the agent reads to
  decide *when* to load the skill.
- Open a pull request on [GitHub](https://github.com/hahwul/hwaro).

## See Also

- [CLI Reference](/start/cli/) — every command and flag the `hwaro` skill drives.
- [AGENTS.md](/start/tools/agents-md/) — per-project instructions for AI agents.
- [Templates](/templates/) — the data model, functions, and filters the design skill builds on.
