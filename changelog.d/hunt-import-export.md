### Changed
- A TOML offset date-time keeps its written offset, so date permalink tokens (`:year`/`:month`/`:day`) and year/month grouping now use the written calendar day. A URL built from the old UTC day can move (e.g. `/2024/02/29/` → `/2024/03/01/`); add the old URL to `aliases` to keep it working

### Fixed
- TOML: fractional seconds of any precision (`2024-03-05T10:20:30.123Z`) parse instead of failing the build with "expected microsecond digit"
- TOML: an offset date-time keeps its UTC offset, so `date = 2024-03-05T08:20:30+09:00` prints `2024-03-05` like the same value in YAML front matter, instead of the previous day in UTC
- TOML: an out-of-range UTC offset (`+25:00`, `+23:99`) is a parse error, like any other malformed value
- Feeds: an authored midnight with an explicit offset (`2024-03-05T00:00:00+09:00`) keeps its instant in `<pubDate>` / `<updated>`; only a date-only value is re-anchored to UTC midnight
- TOML: a local time (`t = 07:32:00`) is read as that string, instead of being dated to the day the build ran; an out-of-range local time is a parse error instead of a crash
- `tool import hugo`: JSON front matter is read (it used to land in the body); a leaf bundle with `slug` stays a bundle under the slugged directory (or in its own directory, with a warning, when the slug names another bundle); `url` maps to `path`
- `tool import jekyll`: a literal `permalink` maps to `path`, `redirect_from` to `aliases`, `last_modified_at` to `updated`, and `image: {path: …}` to `image`
- Imported `url` / `permalink` values: a `.html` address becomes an extensionless `path` plus an alias, a trailing `index.html` maps to its directory, a query/fragment is dropped, and a URL naming another kind of file is left unmapped with a warning
- `tool export hugo`: `path` maps to `url`
- `tool export jekyll`: `path`, `aliases` and `updated` map to `permalink`, `redirect_from` and `last_modified_at`
