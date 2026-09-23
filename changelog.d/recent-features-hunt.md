### Fixed
- `hwaro build --cache` removes the page of a `[[content.generate]]` record that disappeared from its data. Generated pages have no source file, so nothing recorded their output and the page stayed published and deployed on every later warm build.
- `hwaro serve` drops a page's `<!-- more -->` summary once the marker is deleted. The re-parse kept the old marker summary, so every listing showed it instead of the description or automatic excerpt until restart.
- `hwaro serve` refreshes the version switcher (`page.version_links`) and an old version's canonical link when a counterpart in another version is re-slugged, drafted or turned `render = false`. The unchanged version's page kept linking and canonicalizing to a URL that no longer existed.
- `hwaro serve` refreshes translation links (`page.translations`, the language switcher, sitemap hreflang alternates) when one translation is re-slugged or retitled. The other languages' pages, and the edited page's own switcher, kept the old URL and title.
- `hwaro build --cache` removes search outputs the `[search]` config no longer publishes: `search.json` after `single_file = false` or a `filename` change, the `search/` shard directory after `shards = "none"`, and everything once search is disabled.

- `hwaro build --cache` and `hwaro serve` stop publishing sitemap, feed and llms files the config no longer produces: `sitemap.xml` once `[sitemap]` is disabled or renamed, the main feed once `[feeds]` is disabled, a section feed once the section drops `generate_feeds` (including through an incremental serve edit), a language feed once the language stops generating one, and `llms.txt` / `llms-full.txt` once disabled. Only a cold build removed them before.

### Security
- `[[data.remote]]` keeps configured headers dropped for the rest of a redirect chain once a redirect leaves the original origin. A third-party host could previously redirect back to the origin and choose which origin URL received the credential.
