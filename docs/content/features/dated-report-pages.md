+++
title = "Dated Report Pages"
description = "A worked example: one JSON API to /reports/2026/09/ pages, with charts"
weight = 24
toc = true
+++

A worked example that puts three features together: a JSON API becomes one
page per month, published at `/reports/2026/09/`, each page rendering its own
chart. No data files are committed, and `config.toml` is written once — a new
month appears because the API returns one more record, not because anyone
edited the site.

The three pieces are [remote data](/features/remote-data/) (fetch the payload),
[content generation](/features/content-generation/) (turn records into pages)
and a `[permalinks]` token pattern (shape the URLs). Each is documented on its
own page; this one shows them wired together.

## One Source, One Array

Have the endpoint return a single array with one record per month. Each record
carries its identity, its display label, its date, and its own datapoints:

```json
[
  {
    "id": "2026-09",
    "label": "September 2026",
    "date": "2026-09-01",
    "summary_md": "Signups held steady while churn fell for the third month.",
    "datapoints": [
      {"day": "2026-09-01", "signups": 412, "churn": 18},
      {"day": "2026-09-08", "signups": 455, "churn": 15},
      {"day": "2026-09-15", "signups": 501, "churn": 12}
    ]
  },
  {
    "id": "2026-08",
    "label": "August 2026",
    "date": "2026-08-01",
    "summary_md": "A quiet month after the launch spike.",
    "datapoints": [{"day": "2026-08-04", "signups": 380, "churn": 22}]
  }
]
```

The nesting lives **inside** the payload, not in the keys, and that is
deliberate. A `[[data.remote]]` key may contain only letters, digits, `_` and
`-`, so there is no remote equivalent of a `data/reports/2026/09.json` tree:

```toml
[[data.remote]]
key = "reports.2026"   # Error [HWARO_E_CONFIG]: key may contain only
                       # letters, digits, '_' and '-'
```

Local `data/` subdirectories do nest (`data/reports/2026.json` →
`site.data.reports.2026`), but remote keys are flat by design — the key also
names a cache file. Splitting the API into `reports_2026_09`,
`reports_2026_10`, … would work, but every month would then need a new
`[[data.remote]]` entry *and* a new `[[content.generate]]` rule, which is
exactly the monthly config edit this setup exists to avoid. One array, one
key, one rule.

## config.toml

Three blocks, written once:

```toml
[[data.remote]]
key = "reports"                        # site.data.reports
url = "https://api.example.com/reports"
cache = "1h"                           # reuse a fresh payload between builds
on_error = "warn-and-use-cache"        # a flaky API can't break the build

[[content.generate]]
source = "reports"                     # the whole array
section = "reports"                    # pages land in the reports section
slug = "id"                            # "2026-09"
title = "label"                        # "September 2026"
date = "date"                          # "2026-09-01" — required by the pattern
body = "summary_md"                    # optional markdown body

[permalinks]
"reports" = "/reports/:year/:month/"   # /reports/2026/09/
```

A few points worth spelling out:

- `source = "reports"` names the array itself. A nested array uses a dotted
  path (`"reports.months"`); anything that is not an array is a hard error.
- `slug = "id"` is slugified (`2026-09` stays `2026-09`) and only decides the
  page's **content path**, `content/reports/2026-09.md`. The published URL
  comes from the permalink pattern.
- `date` is not optional here. `:year` and `:month` expand from the page date,
  and a record without one fails the build by name:

  ```
  Error [HWARO_E_CONTENT]: reports/2026-09.md matches [permalinks] rule
  "reports" (pattern '/reports/:year/:month/') which requires a date, but the
  page has none.
  ```

- Generated pages follow the same publishing rules as authored ones, so a
  record dated in the future stays out of the build until that date arrives.
  Dating each record to the first of its month publishes it as soon as the
  month opens.

`:year`, `:month` and `:day` are zero-padded date tokens; the full token list
is in [Configuration › Token patterns](/start/config/#token-patterns). Tokens
must be whole path segments — `/reports/:year-:month/` is a config error, not
a pattern.

## One Record Per Month

`/reports/:year/:month/` has no `:slug` segment, so the month **is** the
identity of the page. Two records landing in the same month produce the same
URL, and Hwaro warns and writes only one of them:

```
[WARN] Duplicate output path '/reports/2026/09/' — 'reports/2026-09.md'
collides with 'reports/2026-09-late.md' and is not written
```

If the API can emit more than one record per month, either aggregate upstream
or put `:slug` back in the pattern (see [Variants](#variants) below).

## The Chart Template

Point the section at a template and every generated page in it renders with
that template:

```toml
# content/reports/_index.md
+++
title = "Monthly Reports"
description = "Signups and churn, one page per month"
sort_by = "date"
page_template = "report"
+++

Reports are published on the first of each month.
```

`templates/report.html` reads the month's own datapoints from
`page.extra.item` — the whole source record, without the rule having to map
every field:

```jinja
<h1>{{ page.title | e }}</h1>

{% if page.synthesized %}
<script id="report-data" type="application/json">
  {{ page.extra.item.datapoints | jsonify }}
</script>
<canvas id="report-chart"></canvas>
<script>
  const points = JSON.parse(document.getElementById("report-data").textContent);
  new Chart(document.getElementById("report-chart"), {
    type: "line",
    data: {
      labels: points.map(p => p.day),
      datasets: [{ label: "Signups", data: points.map(p => p.signups) }]
    }
  });
</script>
{% endif %}

{{ content }}
```

Two details make this safe:

- `page.synthesized` is `true` only on generated pages. `page_template`
  applies to every page in the section, including an authored
  `content/reports/notes.md` that has no `item`, so guard the `page.extra.item`
  reads with it.
- `jsonify` serializes the real value tree and escapes `</`, so the data island
  cannot break out of the `<script>` element.

Any chart library works the same way; Hwaro's part ends at handing the page its
own rows. The full array also stays available as `site.data.reports`, so a
site-wide overview chart can iterate every month from the same fetch.

## What a Build Produces

```
$ hwaro build
  Generated 2 page(s) from data.reports
  ...
  built: 3 content pages

public/reports/index.html            # the section listing
public/reports/2026/08/index.html
public/reports/2026/09/index.html
```

The section index lists the months because generated pages are first-class
content: `sort_by = "date"` orders them newest first, and `reverse = true`
switches the listing to oldest first. They join taxonomies, feeds, the search
index, the sitemap, OG images and output formats on the same terms as authored
pages.

## Variants

### A page per day

Return one record per day and swap the month token for the day token:

```toml
[permalinks]
"reports" = "/reports/:year/:month/:day/"   # /reports/2026/09/08/
```

Nothing else changes: `id` becomes `"2026-09-08"`, `date` becomes that day, and
the same rule generates the pages. Use `:slug` instead of `:day`
(`/reports/:year/:month/:slug/`) when a day can hold several named reports —
the URL then carries the slugified `id`, so the records only have to be unique,
not one per day.

### An API that only serves one month at a time

`[[data.remote]]` is one URL, one request. When the data arrives month by
month — a paginated endpoint, one URL per month, or several endpoints to merge
— fetch and combine it into a single file under `data/` with a pre-build hook,
then point `source` at that file instead:

```toml
[build]
hooks.pre = ["./scripts/fetch-reports.sh"]   # writes data/reports.json

[[content.generate]]
source = "reports"                           # now site.data.reports from data/
section = "reports"
slug = "id"
title = "label"
date = "date"
```

The rule, the template and the permalink pattern are unchanged — only where
`site.data.reports` comes from. See
[Build Hooks › Fetching Data from an API](/features/build-hooks/#fetching-data-from-an-api)
for the hook's contract, including why `curl -f` matters.

## See Also

- [Remote Data Sources](/features/remote-data/) — fetching, caching and error policy
- [Content Generation](/features/content-generation/) — the full `[[content.generate]]` reference
- [Configuration › Permalinks](/start/config/#permalinks) — token patterns and rule ordering
- [Sections](/writing/sections/) — `sort_by`, `page_template` and section listings
- [Build Hooks](/features/build-hooks/) — multi-request or non-GET data fetching
