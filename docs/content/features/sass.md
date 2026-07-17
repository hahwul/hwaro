+++
title = "Sass/SCSS"
description = "Built-in SCSS compilation — pure Crystal, no external tools"
weight = 16
toc = true
+++

Hwaro compiles SCSS at build time with a built-in, pure-Crystal compiler. There is no dart-sass binary to install, no npm toolchain, and no C library — consistent with Hwaro's zero-external-dependency philosophy.

## Quick Start

```toml
[sass]
enabled = true
```

Put SCSS files under `static/`:

```
static/
├── css/
│   ├── _variables.scss   # partial — never published
│   ├── _mixins.scss      # partial — never published
│   └── style.scss        # entry — compiles to /css/style.css
```

```scss
// static/css/style.scss
@use "variables";
@use "mixins";

.card {
  color: variables.$primary;
  &:hover { color: variables.$accent; }

  @include mixins.respond(768px) {
    padding: 2rem;
  }
}
```

Every non-partial `*.scss` compiles to a sibling `.css` in the output (`static/css/style.scss` → `/css/style.css`), so stylesheets keep stable URLs:

```html
<link rel="stylesheet" href="{{ url_for(path="/css/style.css") }}">
```

## Rules

- **Entries** — `*.scss` files whose name does not start with `_` compile to a sibling `.css` at the same relative path in the output.
- **Partials** — `_*.scss` files never compile standalone and never publish; they are only reachable via `@use`/`@import`.
- **Raw sources are not published** — while `[sass]` is enabled, `.scss` files are excluded from the verbatim static copy.
- **Bundles** — `[[assets.bundles]]` `files` entries may name `.scss` files; while `[sass]` is enabled they compile before concatenation and then flow through the normal minify → fingerprint pipeline. With `[sass]` disabled, bundle entries concatenate verbatim (the escape hatch for pre-compiled or out-of-subset sources).
- **Watch** — `hwaro serve` recompiles on `.scss` changes. Editing a partial recompiles every entry (there is no dependency graph — whole-tree recompilation is fast at static-site scale). Compile errors appear in the browser error overlay.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | Enable SCSS compilation |
| `minify` | bool | `true` | Minify compiled CSS (same minifier as the asset pipeline) |

## Supported Subset

Hwaro implements a practical SCSS subset — the features hand-written site stylesheets actually use:

| Feature | Support |
|---------|---------|
| `$variables` | ✅ with `!default` / `!global`, lexical scoping and shadowing |
| Nested rules | ✅ including selector lists (cartesian combination) |
| `&` parent selector | ✅ `&:hover`, `&.mod`, BEM `&__elem` / `&--mod` |
| `#{...}` interpolation | ✅ selectors, property names, values, at-rule preludes, strings, `url()` |
| Partials + `@use` | ✅ namespaces (`colors.$primary`), `as x`, `as *`, load-once |
| `@import` (Sass files) | ✅ classic global-merge semantics; plain-CSS forms pass through |
| `@mixin` / `@include` | ✅ default values, keyword arguments, `@content` blocks |
| `@media` / `@supports` in rules | ✅ bubbled out of nesting automatically |
| `@keyframes`, `@font-face`, custom properties | ✅ pass through correctly |
| Plain CSS | ✅ any valid `.css` compiles to itself (whitespace-normalized) |

Unknown functions (`calc()`, `var()`, `rgba()`, `clamp()`, `color-mix()`, …) pass through untouched.

### Not supported (yet)

Control flow (`@if`/`@else`/`@each`/`@for`/`@while`), SassScript arithmetic and comparison operators, built-in function modules (`math.*`, `color.*`, string/list/map functions), `@function`, `@extend`, `@forward`, `@use ... with (...)`, variadic arguments (`$args...`), `@content(args)` / `using`, nested properties (`font: { family: ... }`), the indented `.sass` syntax, and source maps.

**Unsupported directives fail the build with a located error** — Hwaro never emits silently broken CSS:

```
Error [HWARO_E_CONTENT]: Sass: static/css/style.scss:14:3: @if is not supported by hwaro's Sass subset (yet)
```

### Deviations from dart-sass

- Variables in at-rule preludes and values substitute directly (`@media (min-width: $bp)` works); selectors and property names require `#{...}` interpolation (same as dart-sass).
- `@media` nested inside `@media` emits literally nested blocks (dart-sass merges the conditions).
- `&` substitution is textual — `&__elem` concatenates without validating the compound selector.
- Custom property values are verbatim: `$var` stays literal, only `#{...}` interpolates (dart-sass semantics), but leading/trailing whitespace is trimmed.
- `@import` of the same file re-emits its CSS each time (classic Sass behavior); `@use` loads once.
- Declarations placed *after* a nested rule merge into the parent's single output block (`.a { color: red; .b {} color: blue; }` emits one `.a` block); dart-sass splits them in source order. Avoid relying on cascade order between a parent's trailing declarations and its nested rules.
- Values are substituted as text: interpolating a variable whose value contains an unbalanced quote character can confuse downstream whitespace/quote handling. Keep quote characters inside quoted strings.
- Only lowercase `.scss` extensions are treated as Sass sources; other casings publish verbatim like any static file.

## Errors

Compile failures are classified content errors (exit code 5) with `path:line:column` locations:

```
Error [HWARO_E_CONTENT]: Sass: static/css/_mixins.scss:7:12: undefined variable: "$primry"
```

During `hwaro serve`, errors show in the browser overlay and the previous output stays on disk.

## Interplay with Other Features

- **Asset pipeline** — compiled standalone entries keep stable (non-fingerprinted) URLs and resolve through `asset()`'s passthrough. For fingerprinting, reference the `.scss` file from a bundle instead.
- **Build hooks** — Tailwind/PostCSS and full dart-sass projects can still run through `[build] hooks.pre` and point Hwaro at the compiled output.
- **Cache** — Sass recompiles on every full build (it does not participate in the incremental page cache). Deleting an entry `.scss` leaves its previously compiled `.css` in a stale output dir; clean builds remove it.
