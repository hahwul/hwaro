### Fixed
- JS minification: a regex literal after an expression keyword (`return /\/*$/.test(u)`) was read as division, and a `/*` or `//` in its body swallowed the rest of the file, including every later file of the bundle
- JS minification: a `/` inside a regex character class (`/^[^\\/]*\//`) no longer ends the literal early and turns its closing `\//` into a line comment
- CSS minification: dropping a comment between two tokens of a declaration value no longer fuses them (`margin:1px/**/2px` became `1px2px`, and `font:12px/**/Arial` lost its family). Selectors and at-rule preludes are unchanged: `div/**/p` does not become the descendant selector `div p`
- HTML minification: `<link href=/favicon.ico />` no longer becomes `href=/favicon.ico/`. The space before `/>` is kept after an unquoted attribute value
- HTML minification: comments and line-final spaces inside attribute values are left alone (`data-x="<!-- keep -->"` used to become empty)
- Asset pipeline: relative `url(...)` values in bundled CSS are rebased onto the bundle's location when they point at a file beside the source stylesheet in `static/` (`url(img/x.png)` from `static/css/a.css` used to 404 from `/assets/`). Text inside CSS strings and comments is left alone
- SEO: a page-bundle `image = "cover.png"` now resolves to the bundle asset in `og:image`, `twitter:image`, JSON-LD and `seo.og_image`, instead of `/cover.png`
- SEO: the path of a site-relative `og:image`, `twitter:image` and JSON-LD image URL is percent-encoded like `og:url`. A `?query` or `#fragment` is kept as written, and external image URLs are left untouched on all three
