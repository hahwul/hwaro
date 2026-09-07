### Fixed
- Hugo and Jekyll exports now parse JSON front matter, preserving metadata and respecting draft filtering; malformed JSON headers report export errors.
- `tool list`, `tool convert`, `tool check-links`, `tool stats`, `tool validate`, and `tool unused-assets` reject unexpected positional arguments, including arguments after `--`, instead of silently ignoring them.
