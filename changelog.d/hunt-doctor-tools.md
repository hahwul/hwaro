### Fixed
- `tool check-links`: scan `.markdown` files and resolve `@/` links against exact content paths.
- Content tools: include uppercase Markdown files when listing, validating, and collecting asset references.
- `tool validate`: normalize titled and angle-bracket internal links, and report raw HTML `<img>` elements that have no `alt` attribute (`alt=""` is accepted as decorative). HTML comments and indented code blocks are no longer scanned for images or links, matching `tool check-links`.
- `tool platform cloudflare`: generate the Cloudflare Pages `pages_build_output_dir` setting.
