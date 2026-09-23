### Fixed
- `hwaro serve` writes the versioned parent redirect stub (`/docs/` → the latest version's root, `[versions] latest_at_root = false`) as soon as an authored `content/docs/_index.md` is drafted. The incremental rebuild re-rendered only pages whose switcher links moved, not the latest root that gained the alias, and still counted the drafted page as the URL's owner, so `/docs/` returned 404 until a full rebuild.

### Changed
- The sitemap, feed, llms and search files are now recorded in the `--cache` metadata. Rolling back to an older dev binary with the same version number after a `--cache` build can therefore drop those files for one build; they regenerate on the next.
