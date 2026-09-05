# Changelog fragments

Every pull request that changes user-visible behaviour adds **one file
here** instead of editing `CHANGELOG.md`. That keeps parallel branches from
all appending to the same `## Unreleased` lines and conflicting on merge.

File name: `<branch-or-pr-slug>.md` (anything unique; the name is not
published). Contents: one or more category headings, each followed by
Markdown bullets in the same voice as `CHANGELOG.md`:

```markdown
### Added
- Search: opt-in sharded index — `[search] shards = ...` (#784)

### Fixed
- `hwaro serve`: request path restored after index rewrite (#774)
```

Categories (any subset, any order): `Added`, `Changed`, `Deprecated`,
`Removed`, `Fixed`, `Security`.

At release time `just changelog` (also run by `just version-update`)
merges every fragment into the `## Unreleased` section of `CHANGELOG.md`,
grouped by category in the order above, and deletes the fragments.
`scripts/changelog_assemble.cr --check` only validates them (CI-friendly).
