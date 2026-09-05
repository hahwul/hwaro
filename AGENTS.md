# Hwaro - Agent Instructions

Hwaro is a fast, lifecycle-driven static site generator written in Crystal
(>= 1.21): a hook-based build pipeline, pluggable content processors,
multi-layer caching and fiber-parallel rendering. **`ARCHITECTURE.md` is the
map** — directory layout, the build pipeline, every registry, and a
"where does X go" table. This file is the rules.

## Build, test, lint

```bash
just build              # shards install && shards build → bin/hwaro
just test               # crystal spec — the whole suite, ONE process
just test-file PATH     # one spec file (or file:line) in its own compiler cache
just test-dir DIR       # every spec under a directory, same isolation
just check              # crystal tool format --check + bin/ameba   (CI gates on both)
just fix                # crystal tool format + bin/ameba --fix
just baseline           # build main into ../hwaro-baseline/bin/hwaro
just verify             # byte-identity gate: baseline vs bin/hwaro (add --serve --deploy)
just changelog          # merge changelog.d/ fragments into CHANGELOG.md (--check to validate)
just dev                # serve the docs site (bin/hwaro serve -i docs)
```

- Run the suite as a **single** `crystal spec` process per compiler cache.
  `crystal spec` links every run to the same fixed path under
  `~/.cache/crystal`, so two concurrent invocations clobber each other's
  binary and produce plausible-looking nonsense. `just test-file` /
  `just test-dir` set their own `CRYSTAL_CACHE_DIR`, so they are safe to run
  alongside `just test`.
- `spec/functional/**` spawns `bin/hwaro`; rebuild it (`shards build`) before
  trusting a functional run, or the specs test the old binary (some skip
  silently when it is missing).
- `bin/ameba` is built by `just ameba` (ameba 1.7 ships no executable).
- Anything that changes `shard.lock` must be followed by `just nix-update`.
  `flake.nix` reads the version and minimum Crystal from `shard.yml`.
- Parallelism comes from Crystal's execution contexts: `src/main.cr` sizes the
  default `Fiber::ExecutionContext::Parallel` (honours `CRYSTAL_WORKERS`).
  **Never reintroduce `-Dpreview_mt`** — its legacy scheduler can spin forever
  at process exit. Code that mutates shared state from worker fibers guards
  it with a `Mutex`; directory creation goes through `Utils::FileSafe.mkdir_p`.

## Behaviour-preserving changes (refactors, splits, dedups)

Generated output is the contract. Before opening a structural PR:

1. `just baseline` once (a `main` binary in a sibling worktree), then
   `just verify` — it inits and builds every scaffold, builds `docs/` and a
   generated corpus (cold and warm `--cache`), runs every importer,
   convert/export, and diffs `--help`/`--json` surfaces. `--serve` and
   `--deploy` add the incremental-rebuild and deploy tiers.
2. `scripts/check_no_toplevel_effects.sh` (run by `just verify`) enforces the
   file-split convention; `spec/unit/registration_order_spec.cr` pins every
   hand-maintained registry.
3. Move-only commits first (`git diff --color-moved=dimmed-zebra` should show
   only moves), edits in separate commits. A regression spec added with a fix
   must be shown failing on the pre-fix code.

### Splitting a large file

Parts live in a directory named after the owner (`render.cr` → `render/*.cr`)
and **only reopen the same type**; the owner keeps its path, its ivars, its
load-time statements (`Registry.register`, …) and an explicit, ordered
`require "./render/x"` list. No globs, no new mixin modules, no ivar
declarations in parts. Full rules and the current list of split owners are
in `ARCHITECTURE.md`.

## Coding patterns

### Security
- HTML/XML output: `Utils::TextUtils.escape_xml(value)` or `HTML.escape(value)`.
- Inline JS: escape `</` → `<\/` in JSON data to prevent `</script>` breakout.
- Front matter and config values: safe casts (`.as_s?`, `.as_bool?`, `.as_i?`,
  `.as_a?`) on `TOML::Any` / `YAML::Any` / `JSON::Any`, never unchecked `.as_s`.
- Crinja filter args: `.to_s`, not `.as_s`.
- Paths: `PathUtils.sanitize_path` for user-provided or content-derived paths;
  config.toml is a trusted boundary (do not guard config path escapes).
- Vendored shard bugs (markd, crinja, toml, tartrazine) are patched in
  `src/ext/`, not worked around at call sites.

### Performance
- Prefer `String.build` with char-by-char iteration over chained `.gsub`.
- Bounded substrings (`html[pos, n]`) instead of `html[pos..]` in loops.
- Cache `Crinja::Value` arrays per section/page; clear them at every reset
  point (see `invalidate_caches_for_pages`).
- Tartrazine is not thread-safe: syntax highlighting goes through
  `ServerHighlighter`'s mutex.

### Logging
- `Logger.action(label, message, color)` for file operations,
  `Logger.progress(current, total)`, `Logger.outcome`, `Logger::Receipt`,
  `Logger.timed(message, &block)`; levels `debug`/`info`/`warn`/`error`/`success`.
- Every command honours `--quiet`/`-q` (info/action/progress/success and the
  banner off; warn/error still on stderr) and `NO_COLOR`. `--json` commands
  route failures through `Runner.exit_with_error_payload`.
- Machine-readable lines (`hwaro serve: ready url=…`, `--json` envelopes) are
  contracts; keep their bytes.

### Registries
Registries are explicit lists (`Hooks.all`, `register_default_commands`,
`register_sub`, `SECTION_LOADERS`, `CHECK_GROUPS`, …) on purpose — they are
what a reader greps for. Add one line in the right position; the
registration-order spec tells you if a merge broke it.

### Tests
- `spec/unit/<mirror of src>/…_spec.cr`: the test for `src/a/b/c.cr` lives in
  `spec/unit/a/b/c_spec.cr`; cross-cutting sweeps go in `spec/unit/regressions/`.
- `spec/support/`: shared helpers — `load_config` / `expect_config_error`
  (config_helper), `compile` / `compile_with` (sass_helper), `build_site`
  (build_helper: temp project, `Builder#run`, yields for assertions). Add a
  helper there instead of redefining it per file (a second top-level `def`
  silently wins, so duplicates are a trap).
- Specs that need a private method reopen the class in the spec file
  (`class Hwaro::Core::Build::Builder … def test_x`).
- Logger output is captured (`Logger.io = IO::Memory.new` in spec_helper);
  `with_captured_log { }` returns it. No fixtures directory — inline data in
  `Dir.mktmpdir`.

## Changelog and docs
- Do not edit `CHANGELOG.md` in a PR; add `changelog.d/<slug>.md` with
  `### Added|Changed|Deprecated|Removed|Fixed|Security` headings and bullets
  (see `changelog.d/README.md`). `just changelog` merges them at release time.
- User-facing changes update the docs site in both languages:
  `docs/content/**.md` and the matching `.ko.md`.
- PRs that resolve issues use `Closes #N` / `Fixes #N`.
- Commit messages: no AI attribution lines.

## Documentation site (`docs/`)
Build: `bin/hwaro build -i docs` → `docs/public/`; preview local edits with
`hwaro serve -i docs` (built docs use absolute production asset URLs). Never
run a production build while serving.

- `docs/content/` — Markdown pages (start, writing, templates, features, deploy), bilingual.
- `docs/data/sidebar.yml` / `sidebar_ko.yml` — navigation.
- `docs/templates/` — Jinja2 templates; the landing page uses its own template.
- `docs/static/assets/css/` — numbered by load order.
- Front matter is TOML (`+++`) by convention; `weight` orders pages, `toc = true` for long ones.
