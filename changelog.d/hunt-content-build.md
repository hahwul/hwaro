### Fixed
- Taxonomies: `render = false` pages no longer appear on term pages, term feeds or `get_taxonomy`, which linked a page that is never written
- Templates: the root `_index.md` now fills `section.pages`, `paginator.pages` and `section.pages_count` with its pages, as `section.list` and `get_section` already did
- Templates: the root `_index.md`'s `section.subsections` now lists the top-level sections; prev/next order is unchanged
- Multilingual: a file with an explicit default-language suffix (`about.en.md`) is now treated like the unsuffixed default. It used to drop out of its section's `section.pages`, and a suffixed `_index.en.md` listed none of its unsuffixed pages
- Feeds: section feeds now include pages from `transparent` subsections, matching the section's `section.pages`
- SEO: `redirect_to` pages are left out of `sitemap.xml`, RSS/Atom feeds, `search.json` and `llms.txt`
- Series: series are now grouped per language (and per version), so a post and its translation sharing a `series` name no longer interleave into one series with the wrong `series_index`
