+++
title = "Menus"
description = "Hugo-style named navigation menus, config-defined or front-matter-registered"
weight = 11
toc = true
+++

Named navigation menus, resolved into a tree and exposed to templates via `site.menus` / `get_menu()`. A menu can be fully defined in `config.toml`, built entirely from page/section front matter, or both at once — entries from both sources are merged into the same tree.

There's no automatic derivation from sections (Hugo's `sectionPagesMenu`) — see [Follow-ups](#follow-ups).

## Configuring a Menu

```toml
[[menus.main]]
name = "Posts"
url = "/posts/"
weight = 1

[[menus.main]]
name = "About"
url = "/about/"
weight = 2
identifier = "about"
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| name | string | — | **Required.** Display label. An entry missing `name` is skipped with a warning. |
| url | string | "" | Root-relative (`/posts/`) or absolute `http(s)://`/`//` URL. |
| weight | int | 0 | Sort order within the menu (ascending), then by `name`, then `identifier`. |
| identifier | string | `name` | Unique key other entries reference via `parent`. |
| parent | string | none | Another entry's `identifier`, to nest this entry under it. |

Each `[[menus.<name>]]` block is a separate named menu — add `[[menus.footer]]` for a second menu, rendered with `get_menu(name="footer")`.

## Registering a Page/Section from Front Matter

A page or section can join a menu without touching `config.toml`:

```toml
+++
title = "My Post"
menus = ["main"]
+++
```

`menus` (or the singular alias `menu` — `menus` wins if both are present) also accepts a single string (`menus = "main"`) or table form for per-field overrides:

```toml
+++
title = "My Post"

[menus.main]
name = "Featured Post"
weight = 1
parent = "posts"
+++
```

All table-form fields are optional and fall back to the page's own data: `name` defaults to `page.title`, `weight` to `0`, `identifier` to the resolved `name`, and `parent` to none (a root entry).

A page/section may register into **any** menu name, including one `config.toml` never declares — a fully front-matter-defined menu is a legal, supported setup on its own (`hwaro doctor` only flags an undeclared name when config declares at least one menu elsewhere, on the theory that a site with zero `[[menus.*]]` blocks is intentionally going all-in on front matter).

## Hierarchy

Entries with a `parent` become children of the entry whose `identifier` matches. Render nested menus by walking `item.children`:

```jinja
<ul>
{% for item in get_menu(name="main") %}
  <li>
    <a href="{{ item.href }}">{{ item.name }}</a>
    {% if item.children %}
    <ul>
      {% for child in item.children %}
      <li><a href="{{ child.href }}">{{ child.name }}</a></li>
      {% endfor %}
    </ul>
    {% endif %}
  </li>
{% endfor %}
</ul>
```

A `parent` that doesn't match any `identifier` in the same menu (a typo, or a stale reference) doesn't fail the build — the entry is promoted to the root level instead, with a build-log warning. `hwaro doctor` also flags this in `config.toml` before you build (see [Doctor](/start/tools/doctor/)). A duplicate `identifier` keeps the last-declared entry; the earlier one is dropped.

## Per-Language Menus

A `[languages.<code>]` block with no menus table inherits the global `[[menus.*]]` set wholesale. Declaring `[[languages.<code>.menus.<name>]]` **replaces** that menu entirely for that language — it does not merge with the global set:

```toml
[[menus.main]]
name = "Posts"
url = "/posts/"

[languages.ko]
language_name = "한국어"

[[languages.ko.menus.main]]
name = "글"
url = "/ko/posts/"
```

`get_menu()` resolves against the **current page's** language, falling back to the default language when that language has no entries for the requested menu name. `site.menus` is always the default language's menus — use `get_menu()` inside templates that render on non-default-language pages.

Front-matter registrations follow the registering page/section's own language; they're folded into whichever language's menu set they belong to, independent of any per-language config override.

## Active-State Styling

The `active_path` filter compares a menu entry's `url` against the current page:

```jinja
{% for item in get_menu(name="main") %}
<a href="{{ item.href }}"{% if item.url | active_path %} aria-current="page"{% endif %}>{{ item.name }}</a>
{% endfor %}
```

Pass `ancestor=true` to also match descendant pages (useful for keeping a parent nav item highlighted/expanded while browsing inside its section):

```jinja
<a href="{{ item.href }}"{% if item.url | active_path(ancestor=true) %} class="open"{% endif %}>{{ item.name }}</a>
```

The root path (`/`) only ever matches exactly, even with `ancestor=true` — otherwise the home nav item would read as active/open on every page of the site. External entries never match (there's no "current page" for them to be an ancestor of). See [Filters › URL Filters](/templates/filters/#url-filters).

## `href` vs `url`

Every entry exposes both:

- **`url`** — the bare, root-relative path (or untouched external URL) as configured/registered. Comparable to `page.url` — this is what `active_path` compares against.
- **`href`** — the value to actually put in an `<a href>`. For internal entries this is `url` prefixed with the site's `base_path` (the path component of `base_url`, e.g. `/repo` for a project site deployed at `https://user.github.io/repo/`), so links resolve correctly under a subpath deployment. External entries are untouched — `href` and `url` are identical.

Always render `item.href`, and compare against `item.url` (as `active_path` does internally) — mixing them up either breaks subpath deploys (using `url` in `href`) or never matches the current page (using `href` in an `active_path`-style comparison).

## Entry Reference

| Field | Type | Description |
|-------|------|--------------|
| name | String | Display label |
| url | String | Bare root-relative path, or untouched external URL |
| href | String | `url` with `base_path` applied (internal) or unchanged (external) — use this in `<a href>` |
| identifier | String | Unique key within the menu |
| weight | Int | Sort order |
| external | Bool | `true` for `http://`, `https://`, or `//` URLs |
| children | Array\<Entry\> | Nested entries (see [Hierarchy](#hierarchy)) |
| page | Page? | The registering page/section's data, when the entry came from front matter and resolves to a `Page` (nil for config-only entries, and for entries registered on a `Section`'s `_index.md`) |

## Follow-ups

- **`sectionPagesMenu`-style auto-derivation** — Hugo can auto-populate a menu from every top-level section without any `[[menus.*]]` or front-matter registration. Hwaro doesn't do this yet; every entry must be explicit (config or front matter).

## See Also

- [Templates: Functions](/templates/functions/#get-menu) — `get_menu()` reference
- [Templates: Filters](/templates/filters/#url-filters) — `active_path` reference
- [Templates: Data Model](/templates/data-model/#menus) — `site.menus` and the Entry shape
- [Configuration](/start/config/#menus) — `[[menus.*]]` config reference
- [Doctor](/start/tools/doctor/) — `menu-parent-undefined` / `menu-undeclared` validators
