+++
title = "Remote Data Sources"
description = "Fetch HTTP(S) data into site.data at build time"
weight = 22
toc = true
+++

`[[data.remote]]` fetches an HTTP(S) payload into `site.data` before templates
render. It fits a JSON API, a small headless CMS endpoint, or another
single-request source: templates stay offline and every network dependency is
declared in `config.toml`.

For data committed with the site, use files in `data/` instead. Remote and
local data have the same template interface, so moving a key between them does
not require template changes.

## Quick Start

```toml
[[data.remote]]
key = "team"                # exposed as site.data.team
url = "https://api.example.com/team"
format = "json"             # optional when the response identifies its format
headers = { Authorization = "Bearer ${API_TOKEN}" }
cache = "1h"                # reuse a fresh cached payload
on_error = "fail"           # fail | warn-and-use-cache | warn-and-skip
```

```jinja
{% for person in site.data.team %}
  <h2>{{ person.name }}</h2>
  <p>{{ person.role }}</p>
{% endfor %}
```

## Configuration Reference

| Field | Required | Meaning |
|-------|----------|---------|
| `key` | yes | Name under `site.data`. It accepts letters, digits, `_`, and `-`; each key is unique case-insensitively. |
| `url` | yes | Absolute `http://` or `https://` URL. Other schemes are rejected when loading config. |
| `format` | no | `json`, `toml`, `yaml`, or `csv`. When omitted, Hwaro uses the response `Content-Type`, then the final URL extension after redirects. Set it explicitly if neither identifies a format. |
| `headers` | no | Extra request headers. They are treated as credentials: never logged, and dropped if a redirect leaves the original origin. |
| `cache` | no | Disk-cache TTL such as `"90s"`, `"30m"`, `"1h"`, `"7d"`, or `"1h30m"`. A fresh cache skips the request. |
| `on_error` | no | Fetch/parse failure policy: `fail` (default), `warn-and-use-cache`, or `warn-and-skip`. |

CSV data becomes an array of rows; each row is an array of trimmed strings,
matching `load_data()` for local CSV files.

## Environment Variables

`${VAR}` placeholders in `url` and `headers` are expanded from the environment.
Unlike ordinary config interpolation, a missing variable here fails the build
and names the variable, preventing a request with an accidental empty token.
Use `${VAR:-default}` where a safe fallback exists. Expansion happens only when
a build fetches the source, so `hwaro deploy`, `hwaro new`, and `hwaro tool ...`
do not require those variables.

## Cache, Offline Builds, and Serve

Payloads live in `.hwaro/remote_data/`, outside the directories watched by
`hwaro serve`. The cache survives `hwaro build --full` and is ignored by Git.

- With `cache` set, builds reuse a payload while its TTL is fresh. Without it,
  each new `hwaro build` refetches, while retaining the last successful payload
  for `warn-and-use-cache`.
- `warn-and-use-cache` warns and uses any saved payload when a fetch or parse
  fails. `warn-and-skip` warns and leaves `site.data.<key>` unset; guard that
  key in templates. `fail` stops the build.
- In one `hwaro serve` session, an unchanged source is held in memory. A
  TTL-controlled source is retried on the first full rebuild after expiry. If
  that refresh fails, serve keeps the previously loaded payload so editing can
  continue offline.
- A changed payload invalidates cached pages in the same way an edited local
  `data/` file does.

Each source allows 10 seconds to connect, 30 seconds per read, and 120 seconds
overall across redirects and the full response body. Timeout failures follow
the selected `on_error` policy.

## Boundaries and Collisions

Remote sources are intentionally config-only: `load_data()` and shortcodes
cannot fetch URLs. For pagination, POST requests, authentication flows, or
reshaping several responses, use a [pre-build hook](/features/build-hooks/#fetching-data-from-an-api)
to write a local file under `data/`.

A remote key cannot share a name with a local data file. For example,
`data/team.json` and `key = "team"` are a configuration error; Hwaro names both
sources rather than silently choosing one.

To turn a remote array into pages, combine it with
[Content Generation](/features/content-generation/). Generated pages take part
in listings, taxonomies, feeds, search, sitemap, and output formats just like
authored content.

## See Also

- [Data Model](/templates/data-model/#data-files) — local `data/` files and template access
- [Content Generation](/features/content-generation/) — materialize data records as pages
- [Build Hooks](/features/build-hooks/) — multi-step or non-GET integrations
