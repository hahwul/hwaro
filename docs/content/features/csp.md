+++
title = "Content Security Policy"
description = "Generate a strict CSP from each page's inline script and style hashes"
weight = 28
toc = true
+++

`[csp]` writes a Content-Security-Policy for every page Hwaro builds. It
hashes each inline `<script>` and `<style>` in the final HTML and lists the
hashes in the policy, so the site can drop `'unsafe-inline'` and still run
its own inline code. A script injected into a page later (an XSS payload, a
compromised third-party tag) has no matching hash and is blocked.

## Quick Start

```toml
[csp]
enabled = true
```

This writes a `_headers` file to the output root, with one rule per page:

```
/blog/hello/
  Content-Security-Policy: default-src 'self'; script-src 'self' 'sha256-hI0C…='; style-src 'self' 'sha256-G7+h…='; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'
```

Netlify and Cloudflare Pages read this file. On any other host, use
`mode = "meta"`, which puts the policy in each page instead.

## Configuration

```toml
[csp]
enabled = false                  # default off
mode = "headers"                 # headers | meta
headers_file = "_headers"        # headers mode: path under the output root
report_only = false              # headers mode: Content-Security-Policy-Report-Only

[csp.directives]                 # merged over the defaults below
img-src = "'self' data: https://images.example.com"
```

| Key | Default | Meaning |
|-----|---------|---------|
| `enabled` | `false` | Turn CSP generation on. When it is off the output is unchanged. |
| `mode` | `"headers"` | `headers` writes a [`_headers` file](#headers-mode); `meta` injects a [`<meta>` tag](#meta-mode) into each page. |
| `headers_file` | `"_headers"` | The headers file, relative to the output directory. |
| `report_only` | `false` | Send `Content-Security-Policy-Report-Only` instead, so violations are reported but not blocked. Headers mode only: browsers ignore a report-only policy in `<meta>`, so `report_only` with `mode = "meta"` is a config error. |
| `[csp.directives]` | see below | Directive name = source list, as one string. |

### Directives

Without `[csp.directives]` every page gets:

| Directive | Value |
|-----------|-------|
| `default-src` | `'self'` |
| `script-src` | `'self'` + the page's script hashes |
| `style-src` | `'self'` + the page's style hashes |
| `img-src` | `'self' data:` |
| `font-src` | `'self'` |
| `connect-src` | `'self'` |
| `object-src` | `'none'` |
| `base-uri` | `'self'` |
| `frame-ancestors` | `'self'` |

A directive you set replaces the default. For `script-src` and `style-src`
your value is kept and the page's hashes are added after it. An empty string
removes a default directive (`frame-ancestors = ""`); any other directive with
an empty value is written without sources, which is how you add
`upgrade-insecure-requests = ""`. Values may not contain `;` or `,`.

`'unsafe-inline'` has no effect next to hashes: browsers ignore it as soon as
a directive lists a hash. Do not count on it as a fallback.

## What Gets Hashed

Hwaro reads every HTML page it wrote, after all other output processing:
`--minify`, the [`[privacy]`](/features/privacy/) rewrite, AMP links, taxonomy
pages, the 404 page and alias redirects. The hash is `sha256` over the bytes
between the tags, exactly as the browser will hash them. Each page gets only
its own hashes.

- **`<script>`** without a `src`, whose `type` is absent, empty, a
  JavaScript MIME type, `module`, `importmap` or `speculationrules`. These
  are the types the browser checks against `script-src`.
- **JSON-LD and other data blocks** (`application/ld+json`,
  `text/template`, …) are not executed, so they get no hash and need none.
- **`<style>`** bodies, in `style-src`.
- **`style="…"` attributes.** A hash allows an attribute only together with
  `'unsafe-hashes'`, so a page with style attributes gets a
  `style-src-attr 'unsafe-hashes' 'sha256-…'` directive that lists them. The
  `style-src` directive for elements stays strict.
- **Event handler attributes** (`onclick="…"`, `onload="…"`) cannot be
  allowed by a hash-based policy. Hwaro prints a warning that names the
  pages that have them. Move the code into a script and attach it with
  `addEventListener`. Hwaro's own templates and the `hwaro init` scaffolds
  contain none.

Content inside HTML comments, `<noscript>`, `<textarea>` and `<title>` is not
markup to the browser, so nothing in it is hashed.

## Hosts for Hwaro's Features

When a page uses a feature that loads from another host, that host is added
to the page's policy. A host is added only when its URL is in the page's
final HTML, so a CDN that [`[privacy]`](/features/privacy/) moved to your
own site, or a shortcode the page does not use, adds nothing.

| Feature | Added |
|---------|-------|
| `[highlight]` with `use_cdn = true` (cdnjs) | `script-src`, `style-src` `https://cdnjs.cloudflare.com` |
| `[markdown] math`, KaTeX | `script-src`, `style-src`, `font-src` `https://cdn.jsdelivr.net` |
| `[markdown] math`, MathJax | `script-src`, `font-src` `https://cdn.jsdelivr.net` |
| `[markdown] mermaid` | `script-src` `https://cdn.jsdelivr.net` |
| `youtube` shortcode | `frame-src` `https://www.youtube.com` |
| `vimeo` shortcode | `frame-src` `https://player.vimeo.com` |
| `gist` shortcode | `script-src` `https://gist.github.com`, `style-src` `https://github.githubassets.com` |
| `tweet` shortcode | `script-src`, `frame-src` `https://platform.twitter.com` |
| `codepen` shortcode | `frame-src` `https://codepen.io` |

A directive that is not set starts from the value the browser would have
fallen back to (`frame-src` from `child-src`, then `default-src`), so adding a
frame host keeps `'self'`.

Anything else your templates load from another host needs its own entry in
`[csp.directives]`.

## Headers Mode

`mode = "headers"` writes one rule per page to `headers_file`, in the
format Netlify and Cloudflare Pages read. Paths are the page URLs and include
the `base_url` subpath: `/`, `/blog/hello/`, `/404.html`.

If `static/_headers` exists, it is not replaced. Hwaro writes your file
first, unchanged, and appends its own rules after a
`# Content-Security-Policy generated by Hwaro ([csp])` comment. When your
file already has a block for a page's path that sets
`Content-Security-Policy` (or `Content-Security-Policy-Report-Only` with
`report_only`), your block wins and Hwaro writes no rule for that path.

Hosts combine every rule that matches a request. A `/*` rule of your own that
also sets `Content-Security-Policy` is therefore sent as a second policy,
and the browser enforces both, so do not set one alongside `[csp]`.

Rules are per page because the format cannot list several paths in one rule.
On this documentation site (about 160 pages in two languages) the file is about
50 KB. Cloudflare Pages reads at most 100 rules; Hwaro warns when the file
has more. Netlify has no such limit. For larger sites on Cloudflare, use meta
mode.

A host serves `404.html` at the missing URL, where no rule matches, so the
404 page gets no policy in headers mode.

## Meta Mode

`mode = "meta"` injects the policy into each page as the first child of
`<head>`, right after a leading `<meta charset>` (which must stay within the
first 1024 bytes):

```html
<head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src &apos;self&apos;; …">
```

Browsers ignore `frame-ancestors`, `report-uri` and `sandbox` in a `<meta>`
policy, so Hwaro leaves them out, and warns when you set one of them
yourself. Pages without a `<head>` get no policy.

## Builds, Cache and Serve

- **`--cache`.** A cached page is hashed from the HTML already on disk, so
  a warm build writes the same `_headers` file and the same pages as a cold
  build.
- **`[build] hooks.post`.** The policy is computed before post-build hooks
  run. If a hook changes a page's inline scripts or styles, Hwaro warns that
  the page's policy no longer matches. Change the HTML in a template or in
  `hooks.pre` instead.
- **`hwaro serve`.** No policy is written. The live-reload client and the
  error overlay are inline and dev-only.
- **`static/` and `[content.files]` HTML** are your files, published
  unchanged, and get no policy.
- **AMP pages** are skipped: the AMP runtime adds styles while the page runs,
  and a hash-based policy would block them.
- **KaTeX.** With `[csp]` on, `{{ math_tags }}` starts KaTeX from a small
  inline script instead of an `onload` attribute, so it can be hashed.

## Limitations

- Styles that a script creates at run time (a `<style>` element, or a
  `style` attribute set through `setAttribute` or `innerHTML`) are blocked.
  Mermaid and MathJax do this, so their output renders without its styles;
  KaTeX works. Setting `element.style.color` from a script is allowed.
- `javascript:` URLs are blocked like event handler attributes.
- The feature host table covers Hwaro's own features. Embeds in your own
  templates or Markdown need their hosts in `[csp.directives]`.
- Pages that use the same policy still get a rule each in headers mode.
