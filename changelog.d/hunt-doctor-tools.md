### Fixed
- `tool check-links`: scan `.markdown` files and resolve `@/` links against exact content paths.
- Content tools: include uppercase Markdown files when listing, validating, and collecting asset references.
- `tool validate`: normalize titled and angle-bracket internal links, and report missing `alt` text on raw HTML images.
- `tool platform cloudflare`: generate the Cloudflare Pages `pages_build_output_dir` setting.
