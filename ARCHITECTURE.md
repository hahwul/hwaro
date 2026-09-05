# Hwaro architecture map

A working map for people and coding agents: what lives where, how the build
pipeline is wired, and — most useful — **which files to touch to add X**.
`AGENTS.md` carries the rules; this file carries the geography.

## Layout

```
src/
  main.cr                 process entry: sizes the fiber execution context, runs the CLI
  hwaro.cr                explicit require list (ordered) + VERSION; new part files are
                          required from their OWNER file, never from here
  cli/                    Runner + CommandRegistry, FlagInfo/CommandInfo metadata
    commands/             one class per top-level command (init/build/serve/new/deploy/…)
    commands/tool/        `hwaro tool <sub>` subcommands; deadlink_command/ is a split owner
  config/options/         typed option structs (BuildOptions, ServeOptions, …)
  models/                 Page, Section, Site, Toc, Deployment, GitInfo, Config
    config/               one file per config.toml section family (class + loader)
  content/
    processors/           Markdown/HTML/JSON/XML processors, template engine, syntax highlighting
      markdown/           Markdown processor parts (front matter, taxonomy fields, html post)
      markdown_extensions/ one file per pre/post-processing pass (footnotes, math, …)
      filters/            Crinja filter modules (glob-required by template.cr)
    hooks/                lifecycle hookables (SEO, taxonomy, Sass, assets, PWA, AMP, OG, images)
    seo/                  sitemap, feeds, robots, llms, JSON-LD, meta tags, OG images (+ PNG renderer)
    pagination/           Paginator + paginated page renderer
    search.cr, taxonomies.cr, menus.cr, i18n.cr, multilingual.cr, versions.cr
  core/
    lifecycle/            Manager, HookPoint/phases, BuildContext, Hookable/HookResult
    build/                Builder (+ builder/ parts), Cache/CacheManager, ShortcodeProcessor,
                          TemplateDeps, DataDisk, RemoteData, ContentGenerate, GitInfo
      phases/             one module per pipeline phase, included into Builder
        render/           Render phase parts (fingerprints, fan-out, template vars, …)
  services/               everything the CLI does that is not a build
    doctor.cr + doctor/   diagnostics registry, check families, --fix
    deployer.cr + deployer/  deploy pipelines (directory sync, command targets, validation)
    server/               dev server: handlers, ChangeSet, watcher, rebuild dispatch, live reload
    scaffolds/            `hwaro init` scaffolds (Base + simple/bare/blog/docs/book + remote)
    importers/ exporters/ WordPress/Jekyll/Hugo/Notion/Obsidian/Hexo/Astro/Eleventy; Jekyll/Hugo
    defaults/             sample config/content/templates/AGENTS.md for init
    content_lister/stats/validator, creator (`hwaro new`), frontmatter_converter, …
  assets/                 asset pipeline (bundling/fingerprinting) and the Sass compiler
    sass/                 scanner → parser → AST → evaluator (+ functions, color, extend, importer)
  utils/                  Logger, PathUtils, TextUtils, FileSafe, FrontmatterScanner/Writer,
                          OutputGuard, DevMarker, Profiler, minifiers, …
  ext/                    vendored patches for markd/crinja/toml/tartrazine + stb_image bindings
spec/
  spec_helper.cr          requires src/hwaro and spec/support/*
  support/                shared helpers: config_helper, sass_helper, build_helper (build_site)
  unit/<mirror of src>/   e.g. spec/unit/core/build/phases/render_spec.cr tests
                          src/core/build/phases/render.cr; regressions/ holds cross-cutting sweeps
  functional/             end-to-end builds through Builder#run and the bin/hwaro binary
docs/                     the documentation site (built with hwaro itself; en + ko)
scripts/                  verify_byte_identity.sh, check_no_toplevel_effects.sh,
                          changelog_assemble.cr, benchmark_run.cr, version_*.cr
changelog.d/              one changelog fragment per PR (see its README)
```

## Build pipeline

`hwaro build` constructs a `Core::Build::Builder`, registers `Content::Hooks.all`
on its `Lifecycle::Manager`, and runs nine phase modules in order; every
phase has a `before`/`after` hook point:

```
Initialize → ReadContent → ParseContent → Transform → Render (+ OutputFormats)
          → Generate → Write → Finalize
```

- `src/core/build/builder.cr` declares **every** Builder ivar, the phase
  `include`s and the cold-build `run`. `builder/incremental.cr` holds the
  serve-mode strategies (`run_incremental`, `run_incremental_then_rerender`,
  `run_rerender`, deferred fast-start pages), `builder/serve_sync.cr` the
  static/content-file sync, `builder/seo_surfaces.cr` the sitemap/feed/search
  regeneration after a partial rebuild.
- `src/core/build/phases/<phase>.cr` is a flat `module Hwaro::Core::Build::Phases::<Phase>`
  included into Builder, so phase code reads and writes Builder ivars directly.
- `phases/render.cr` keeps the tuning constants and the ordered require list
  of `phases/render/*.cr`: orchestration, fingerprints, output_paths, fanout,
  page_pipeline, pagination, html_transforms, template_masking, crinja_values,
  global_vars, asset_tags, template_variables, seo_vars. `apply_template` is
  the module's one public entry; `build_template_variables` (per page) and
  `build_global_vars` (per site) assemble what templates see.
- `BuildContext` (`core/lifecycle/context.cr`) is the shared state container
  passed to hooks; hooks reach the builder through `ctx.builder`.

Caching: build cache (`.hwaro_cache.json`: mtime + content hash + template /
config / page-set fingerprints), compiled-template cache, Crinja value caches
(per page/section/series/ancestor, cleared at phase transitions), Site lookup
indices. `serve` builds into `.hwaro/serve/`, never into the deployable output.

## The file-split convention

Large owners are split into a directory named after the owner file:

```
src/core/build/phases/render.cr        owner: doc comment, constants, ordered `require "./render/x"`
src/core/build/phases/render/*.cr      parts: `module Hwaro::Core::Build::Phases::Render` reopened
```

Rules (enforced by `scripts/check_no_toplevel_effects.sh`):

1. The owner keeps its path, so nothing outside changes; it requires its
   parts in an explicit order (no globs) right after its own requires.
2. A part only **reopens** the same type (`module …::Render`,
   `class Hwaro::Models::Config`, `class Hwaro::Services::Doctor`). No new
   mixin modules: `private`/`protected` reach and the spec shims that reopen
   the class must keep working.
3. Ivars are declared only in the owner. Parts may read and write them.
4. Load-time statements (`Registry.register(...)`, `Scaffolds::Registry.register`,
   `extend self`) stay in the owner, after the part requires. Constants and
   method definitions are order-independent in Crystal; only executable
   top-level statements are not.
5. Split owners today: `phases/render`, `models/config`, `services/server`
   (siblings, since the owner already lives in `server/`), `services/doctor`,
   `services/deployer`, `core/build/builder`, `processors/markdown`,
   `processors/markdown_extensions`, `cli/commands/tool/deadlink_command`.

## Registries (explicit on purpose)

Hand-written lists are what an agent greps for, so they stay explicit; each
one is pinned by `spec/unit/registration_order_spec.cr`, which fails when a
merge drops or reorders an entry.

| Registry | Where | Populated by |
|---|---|---|
| Content processors | `content/processors/base.cr` `Registry` | `Registry.register(X.new)` at the bottom of each processor file |
| Lifecycle hooks | `content/hooks.cr` `Hooks.all` | literal array (order = hook order) |
| CLI commands | `cli/runner.cr` `register_default_commands` | one `CommandRegistry.register` per command |
| Tool subcommands | `cli/commands/tool_command.cr` | `register_sub` calls (order = `tool --help` order) |
| Crinja filters/tests/functions | `content/processors/template.cr` | `Filters::X.register(@env)` chain, inline `@env.tests[...]`/`@env.functions[...]` |
| Scaffolds | `services/scaffolds/registry.cr` | `Registry.register(X.new)` at file bottom + `ScaffoldType` enum |
| Config sections | `models/config.cr` `SECTION_LOADERS` | one row per loader (order = load order) |
| Config snippets | `services/config_snippets.cr` `SECTION_REGISTRY` | hash literal |
| Doctor checks | `services/doctor/registry.cr` `CHECK_GROUPS` | `CheckSpec` rows (order = report order) |

## Where does X go?

Touch the files in the order listed; the last column says where the test lives.

| Adding… | Files (in order) | Test |
|---|---|---|
| a config.toml section `[foo]` | `models/config/foo.cr` (class + `load_foo`, copy an existing file) → `models/config.cr`: `property foo`, `@foo = FooConfig.new` in `initialize`, a `SectionLoader` row in `SECTION_LOADERS` → `services/config_snippets.cr` (`def self.foo` + `SECTION_REGISTRY` row) → `services/scaffolds/base.cr` if scaffolds should emit it → `docs/content/start/config.md` + `.ko.md` | `spec/unit/models/config/foo_spec.cr` |
| a top-level command | `cli/commands/foo_command.cr` (NAME/DESCRIPTION/FLAGS/`self.metadata`/`run`) → `cli/runner.cr` `register_default_commands` → `docs/content/start/cli.md` | `spec/unit/cli/commands/foo_command_spec.cr`, `spec/functional/cli_*` |
| a `tool` subcommand | `cli/commands/tool/foo_command.cr` → `cli/commands/tool_command.cr` (require + `register_sub` + the doc comment list) | `spec/unit/cli/commands/tool/foo_command_spec.cr` |
| a lifecycle hook | `content/hooks/foo_hooks.cr` (`include Lifecycle::Hookable`, `register_hooks`) → `content/hooks.cr` (require + `Hooks.all`) | `spec/unit/content/hooks/` |
| a Crinja filter | `content/processors/filters/foo_filter.cr` (`module Filters::FooFilters` with `self.register(env)`) → `template.cr` `register_custom_filters` chain | `spec/unit/content/processors/filters/filters_spec.cr` |
| a Crinja function / test | `content/processors/template.cr` (`register_custom_functions` / `register_custom_tests`) | `spec/unit/content/processors/template_spec.cr` |
| a template variable | per page: `phases/render/template_variables.cr` (`build_template_variables`); site-wide: `phases/render/global_vars.cr`; SEO/JSON-LD: `phases/render/seo_vars.cr`; gate expensive ones on `TemplateVarFeatures` (scanned in `phases/initialize.cr`) | `spec/unit/core/build/phases/render_spec.cr`, `spec/functional/render_vars_regression_spec.cr` |
| a Markdown pass | `content/processors/markdown_extensions/foo.cr` (reopen `MarkdownExtensions`) → the pass order in `markdown_extensions.cr` `preprocess`/`postprocess` → a `[markdown]` switch in `models/config/markdown.cr` if opt-in | `spec/unit/content/processors/markdown_extensions_spec.cr` |
| a front-matter field | `content/processors/markdown/frontmatter.cr` (`KNOWN_FRONT_MATTER_KEYS`, `build_front_matter_result`) → `models/page.cr` | `spec/unit/content/processors/frontmatter_parsing_spec.cr` |
| a doctor diagnostic | `services/doctor/registry.cr` (`CheckSpec` row; the position is the report position) → a `check_*` method in the matching `services/doctor/<family>_checks.cr` → `docs/content/features/doctor.md` | `spec/unit/services/doctor_spec.cr` |
| a scaffold | `services/scaffolds/foo.cr` (subclass `Base`, override what differs; `config_content` is assembled by Base) → `services/scaffolds/registry.cr` → `config/options/init_options.cr` `ScaffoldType` (+ `from_string`, `to_s`) → `docs/content/start/scaffolds.md` | `spec/unit/services/scaffolds/scaffolds_foo_spec.cr` |
| an importer | `services/importers/foo_importer.cr` (subclass `Importers::Base`, drive the loop with `import_each`) → `cli/commands/tool/import_command.cr` (require, `POSITIONAL_CHOICES`, dispatch) | `spec/unit/services/importers/foo_importer_spec.cr` |
| a SEO output file | `content/seo/foo.cr` → the hook that writes it (`content/hooks/seo_hooks.cr`) → serve regeneration in `builder/seo_surfaces.cr` if it must refresh on partial rebuilds | `spec/unit/content/seo/foo_spec.cr` |
| a serve-mode change strategy | `services/server/change_set.cr` (classification) → `services/server/rebuild.cr` (`apply_changeset`) → `builder/incremental.cr` | `spec/unit/services/server/server_spec.cr`, `spec/functional/serve_*` |
| a deploy target kind | `services/deployer/command_target.cr` (`auto_command_for_url`) or `directory_sync.cr` → `docs/content/deploy/` | `spec/unit/services/deployer_service_spec.cr` |
| a Sass builtin | `assets/sass/functions.cr` | `spec/unit/assets/sass/functions_spec.cr` |

Also, every PR: a fragment in `changelog.d/` (not `CHANGELOG.md`), and bilingual
docs (`.md` + `.ko.md`) when user-facing.

## Invariants worth knowing before editing

- **Byte-identical output is the contract for refactors.** Run `just verify`
  (baseline binary from `main` vs `bin/hwaro`) before opening a structural PR.
- Generated URLs must include `config.base_path` (subpath deploys 404 otherwise).
- `serve` output carries a dev marker; `build`/`deploy` refuse to consume it.
- `Utils::FileSafe.mkdir_p`, never `FileUtils.mkdir_p`, on the build paths
  (check-then-create races under parallel rendering).
- Tartrazine (syntax highlighting) is not thread-safe: all calls go through
  `ServerHighlighter`'s mutex.
- Shared state mutated from render fibers needs a `Mutex`
  (`@crinja_cache_mutex`, `@page_template_hash_mutex`, …).
- Escaping: `TextUtils.escape_xml` / `HTML.escape` for markup, `</` → `<\/`
  inside inline JSON; safe casts (`as_s?`, `as_bool?`, …) on `TOML::Any`,
  `YAML::Any`, `JSON::Any`; `PathUtils.sanitize_path` on content-derived paths.
- Vendored shard fixes live in `src/ext/` (markd, crinja, toml, tartrazine).

## Known debts (deliberately not fixed in the structure refactor)

- Process-global caches without reset or mutex: `SyntaxHighlighter` result
  cache, `Processor::Markdown` body cache, `OgPngRenderer` cached font/base
  layer, `RenderHooks` fallback env. Specs only pass as one serial process.
- Layering inversions: `models/config.cr` and `models/page.cr` require
  `content/processors/*`; `utils/{debug_printer,sort_utils,redirect_html}`
  require models/content; `content/taxonomies.cr` constructs a `Builder`.
- `ServeOptions` restates 21 `BuildOptions` fields; `to_build_options` copies them.
- Six `X::Any → Y::Any` walkers (`frontmatter_writer`, `frontmatter_converter`,
  hugo/eleventy importers) share a shape but differ in nil/Time/Int32 handling.
- `exporters/base.cr` has no JSON front-matter branch (a JSON-authored page
  exports its front matter as body text) — a bug, left as-is because fixing it
  changes output.
- The five scaffold stylesheets share byte-identical rule runs interleaved
  with formatting differences; deduplicating them needs a CSS normalisation
  pass and therefore changes emitted bytes.
- Four truncation policies (feeds, page summary, search, excerpt) and two
  slugify rules (`TextUtils` for URLs, `Creator` for filenames) are
  intentionally different; do not merge them.
