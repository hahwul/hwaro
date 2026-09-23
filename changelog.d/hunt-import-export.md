### Fixed
- TOML: fractional seconds of any precision (`2024-03-05T10:20:30.123Z`) parse instead of failing the build with "expected microsecond digit"
- TOML: an offset date-time keeps its UTC offset, so `date = 2024-03-05T08:20:30+09:00` prints `2024-03-05` like the same value in YAML front matter, instead of the previous day in UTC
- TOML: a local time (`t = 07:32:00`) is read as that string, instead of being dated to the day the build ran; an out-of-range local time is a parse error instead of a crash
- `tool import hugo`: JSON front matter is read (it used to land in the body); a leaf bundle with `slug` stays a bundle under the slugged directory; `url` maps to `path` (a `.html` address also becomes an alias)
- `tool import jekyll`: a literal `permalink` maps to `path`, `redirect_from` to `aliases`, `last_modified_at` to `updated`, and `image: {path: …}` to `image`
- `tool export hugo`: `path` maps to `url`
- `tool export jekyll`: `path`, `aliases` and `updated` map to `permalink`, `redirect_from` and `last_modified_at`
