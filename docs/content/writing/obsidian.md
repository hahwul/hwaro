+++
title = "Wikilinks & Backlinks"
description = "Build an Obsidian vault or wiki-style notes as is: wikilinks, image embeds, note transclusion, foldable callouts and page.backlinks"
weight = 7
toc = true
+++

Hwaro can build a folder of Obsidian-style notes without converting it first. Two switches, both off by default:

```toml
[markdown]
wikilinks = true   # [[links]], ![[embeds]], foldable callouts

[content]
backlinks = true   # page.backlinks
```

To convert a vault into plain Markdown once instead, use [`hwaro tool import obsidian`](/start/tools/import/).

## Wikilinks

| Syntax | Links to |
|--------|----------|
| `[[Page]]` | the page named `Page` |
| `[[Page\|text]]` | the same page, shown as `text` |
| `[[Page#Heading]]` | a heading on that page |
| `[[Page#Heading\|text]]` | a heading, with custom text |
| `[[#Heading]]` | a heading on the current page |

Without an alias, the link text is the target as written (`[[Page#Heading]]` shows `Page > Heading`). Inside a table, escape the alias pipe as `\|`. A block reference (`[[Page#^id]]`) links to the page itself.

### How a target is found

A target matches a page, case-insensitively, by:

- its file name without the extension and language suffix (`about.ko.md` answers to `about`);
- its directory name, for a bundle (`setup/index.md`) or section (`guides/_index.md`);
- its content path (`[[docs/setup]]`), when the target contains a `/`.

Titles are not used. When several pages match, Hwaro prefers, in order: a page in the linking page's language, a page in the same directory, the shortest path, then the first path alphabetically. If more than one page in the same language matches, the build warns once per link and names every candidate.

`#Heading` becomes the same id the build gives that heading, so `[links] broken_anchors` checks it like any other fragment link.

### What gets rewritten

A resolved wikilink turns into an ordinary internal link (`[text](@/path.md#heading)`) before Markdown rendering. Render hooks, `base_path`, the external-link policy and the `[links]` checks therefore treat it exactly like an `@/` link.

A wikilink is left as written wherever Markdown would not make a link either: fenced or indented code, inline code (including a code span over two lines), raw HTML blocks, HTML tags and their attributes, HTML comments, math (`$…$`, `$$…$$` and `\(…\)` with `[markdown] math` on), and after a backslash (`\[[not a link]]`). Wikilinks inside a shortcode call or body are not rewritten either.

A target with a file extension other than `.md` (`[[report.pdf]]`, `![[report.pdf]]`) links to that published file, found the same way as an [image embed](#image-embeds).

A target that matches no page or file renders as `<span class="wikilink wikilink-missing">text</span>` and goes through `[links] broken_internal`: a warning by default, or a build error with `broken_internal = "error"`.

## Image Embeds

| Syntax | Result |
|--------|--------|
| `![[photo.png]]` | the image, with the file name as alt text |
| `![[photo.png\|300]]` | 300 pixels wide |
| `![[photo.png\|300x200]]` | 300 × 200 |
| `![[photo.png\|A view]]` | alt text `A view` |

Hwaro looks for the file first among the page's own bundle files, then by name among every published file: bundle files of published pages, `[content.files]` and `static/`. A file in a draft or otherwise unpublished bundle is not found. Ambiguous names follow the same rules as page links.

An embed becomes a Markdown image (with a `{width=… height=…}` attribute block for a size), so render-image hooks, responsive `srcset` and `[image_processing] dimensions` apply. An explicit width keeps the automatic dimensions from overriding it.

Turning on `wikilinks` also enables `{…}` attribute blocks on ordinary Markdown images, as `[markdown] attributes` does (`![alt](x.png){.wide}`).

## Note Embeds (Transclusion)

A note embed on a line of its own pulls the note's Markdown into the page:

| Syntax | Result |
|--------|--------|
| `![[note]]` | the whole note body |
| `![[note#Setup]]` | the `Setup` heading through the line before the next heading of the same or a higher level |

The text is rendered as if written in place, like [`include_md`](/writing/shortcodes/#include-md): shortcodes in it expand and its headings join the page's table of contents. It is wrapped in `<div class="transclusion" data-source="/note/">…</div>`, where `data-source` is the note's URL. A note can embed others, including another heading of itself, up to 8 levels deep; a cycle is a build error.

An embed that is not alone on its line, or names a heading the note does not have, renders as a link to the note. An embed inside display math (`$$`) or a raw HTML block is left as it is. A target that matches no note is handled like any [unresolved wikilink](#wikilinks). The embedding page is re-rendered when the note changes, on a warm `--cache` build and in `hwaro serve`.

## Foldable Callouts

With `wikilinks` on, an [admonition](/features/markdown-extensions/) with a fold marker renders as a `<details>` element:

```markdown
> [!TIP]- Collapsed by default
> Hidden until opened.

> [!NOTE]+ Open by default
> Shown, and can be closed.
```

```html
<details class="admonition admonition-tip">
<summary class="admonition-title">Collapsed by default</summary>
<p>Hidden until opened.</p>
</details>
```

The classes are the admonition classes, so existing admonition CSS styles both. A callout without `+` or `-` renders as before.

## Backlinks

`page.backlinks` lists the published pages, in the same language, that link to the page. The newest page comes first (pages without a date last), then by path. A page's links to itself are ignored, and each linking page appears once.

```jinja
{% if page.backlinks %}
<aside class="backlinks">
  <h2>Linked from</h2>
  <ul>
  {% for p in page.backlinks %}
    <li><a href="{{ p.url }}">{{ p.title }}</a></li>
  {% endfor %}
  </ul>
</aside>
{% endif %}
```

Links are read from each page's Markdown source:

- `@/path.md` links;
- wikilinks (when `[markdown] wikilinks` is on);
- Markdown and HTML links whose URL is a page's URL (`[x](/docs/setup/)`, `href="../setup/"`).

Links produced by shortcodes or templates are not counted, and neither are links written inside a shortcode call or body (they are not rewritten, so they are not counted either).

`--cache` builds and `hwaro serve` re-render a page when its backlinks change, for example when another page adds or removes a link to it.
