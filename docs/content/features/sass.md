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
| `#{...}` interpolation | ✅ selectors, property names, values, at-rule preludes, strings, `url()` — full expressions inside; strings render unquoted at every nesting level, lists included (`#{("a", "b")}` → `a, b`) |
| Partials + `@use` | ✅ namespaces (`colors.$primary`), `as x`, `as *`, load-once, `with (...)` configuration |
| `@forward` | ✅ `show` / `hide` filters, `as prefix-*` |
| `@import` (Sass files) | ✅ classic global-merge semantics, including a partial that only `@forward`s (`@import "components"` → `components/_index.scss`); plain-CSS forms pass through |
| `@mixin` / `@include` | ✅ default values, keyword arguments, variadic `$args...` (extra keywords land in `meta.keywords()`), spreads (keywords forward through `$args...`), `@content` blocks with arguments (`@content(1px)` / `@include m using ($a)`) |
| `@function` / `@return` | ✅ user functions callable in values, defaults/keywords/variadic, recursion |
| `@extend` + `%placeholders` | ✅ simple-selector targets, compound unification, `!optional`; un-extended placeholders never emit — see deviations |
| `&` in SassScript | ✅ `if(&, "&", "")` and friends — the parent selector as a value, `null` at the root |
| Control flow | ✅ `@if` / `@else if` / `@else`, `@each` (with destructuring), `@for` (`through`/`to`, descending), `@while` |
| SassScript expressions | ✅ arithmetic (`+ - * / %`, classic slash-division rule), comparisons, `and`/`or`/`not`, strings, lists, maps — see deviations for `/` |
| Unit conversion | ✅ `px`/`cm`/`mm`/`q`/`in`/`pt`/`pc`, `deg`/`grad`/`rad`/`turn`, `s`/`ms`, `Hz`/`kHz`, `dpi`/`dpcm`/`dppx` convert in arithmetic, comparisons, `==`, and `math.*` |
| Nested properties | ✅ `font: 12px serif { family: sans; }` → `font`, `font-family` (recursive) |
| Built-in functions | ✅ `sass:math` (incl. `log` / `hypot` / trigonometry), `sass:string` (incl. `insert` / `split`), `sass:list` (incl. `zip` / `set-nth` / `slash` / `is-bracketed`), `sass:map` (incl. `set` / `deep-merge` / `deep-remove`), `sass:meta` (incl. `keywords` / `variable-exists` / `function-exists` / `mixin-exists` / `content-exists` / `get-function` / `call`), `sass:selector` (string-level `parse` / `nest` / `append` / `unify` / `replace` / `is-superselector` / `simple-selectors` — `replace` shares the `@extend` subset's limits: compound `$original` only, no pseudo-class recursion, first prefix order only), `sass:color` subset (incl. `channel` / `hwb` / `ie-hex-str`) + legacy global names (`map-get`, `nth`, `darken`, `if()`, …) |
| Module constants | ✅ `math.$pi`, `math.$e`, `math.$epsilon`, `math.$max-safe-integer`, `math.$min-safe-integer`, `math.$max-number`, `math.$min-number` |
| `@debug` / `@warn` / `@error` | ✅ `@error` fails the build with a located message |
| `@at-root` | ✅ selector and block forms, `#{&}` suffixing, `(with: ...)` / `(without: ...)` queries |
| `@media` / `@supports` in rules | ✅ bubbled out of nesting automatically; nested `@media` merge with `and` (comma lists cross-multiply); feature values evaluate expressions |
| `@keyframes`, `@font-face`, custom properties | ✅ pass through correctly |
| Plain CSS | ✅ any valid `.css` compiles to itself (whitespace-normalized) |

Unknown functions (`var()`, `clamp()`, `color-mix()`, …) pass through untouched — arguments still evaluate (`translate($x * 2, -50%)` works), a static `calc()` folds to its number (see deviations), and a whole-token `url($v)` / `url(ns.$img)` substitutes the variable (`$` is not valid in a raw URL). A `$` embedded in a larger url token (`url(plain$x.png)`) is valid plain CSS and passes through byte-identical — dart-sass hard-errors there, and evaluates expression contents like `url($a + $b)` that Hwaro keeps verbatim.

```scss
@use "sass:math";
$breakpoints: (sm: 640px, md: 768px, lg: 1024px);

@function rem($px, $base: 16px) { @return math.div($px, $base) * 1rem; }

@mixin respond($name) {
  @if not map-has-key($breakpoints, $name) { @error "unknown breakpoint #{$name}"; }
  @media (min-width: map-get($breakpoints, $name)) { @content; }
}

@each $name, $bp in $breakpoints {
  .container-#{$name} { max-width: $bp - 24px; }
}
@for $i from 1 through 12 {
  .col-#{$i} { width: math.percentage(math.div($i, 12)); }
}
.hero {
  font-size: rem(28px);
  @include respond(md) { font-size: rem(40px); }
}
```

### Colors

Color functions operate on hex literals (`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`), the CSS color keywords (`red`, `rebeccapurple`, `transparent`), and the legacy comma spellings `rgb(…)` / `rgba(…)` / `hsl(…)` / `hsla(…)` — a color built from `hsl()` remembers its declared hue/saturation, so `hue(hsl(221, 14%, 100%))` answers `221deg`:

```scss
$brand: #336699;

.button {
  background: $brand;
  border-color: darken($brand, 10%);      // #264d73
  color: scale-color($brand, $lightness: 60%);
  box-shadow: 0 1px 2px rgba($brand, 0.4); // rgba(51, 102, 153, 0.4)
}
```

| Group | Functions |
|-------|-----------|
| Lightness | `darken`, `lighten` |
| Saturation | `saturate`, `desaturate`, `grayscale` |
| Hue | `adjust-hue`, `complement` |
| Blending | `mix`, `invert` |
| Alpha | `rgba($color, $alpha)`, `opacify` / `fade-in`, `transparentize` / `fade-out` |
| Compound | `adjust-color`, `scale-color`, `change-color` |
| Components | `red`, `green`, `blue`, `hue`, `saturation`, `lightness`, `alpha` / `opacity`, `color.channel` |
| Misc | `ie-hex-str`, `color.hwb` (both `color.hwb($h $w $b)` and `color.hwb($h, $w, $b)`) |

The same functions are available under `sass:color` with the modern names — `color.adjust`, `color.scale`, `color.change`, `color.mix`, `color.complement`, `color.grayscale`, `color.invert`, and the component getters:

```scss
@use "sass:color";
.a { border-color: color.scale(#336699, $lightness: -20%); }
```

A computed color serializes as `#rrggbb` when opaque and `rgba(r, g, b, a)` otherwise. A color you *don't* modify keeps the exact spelling you wrote — `#FFF` stays `#FFF`.

Colors compare by channel across spellings: `#ffffff == #FFF`, `red == #f00`, and `rgb(255, 0, 0) == #ff0000` are all true (dart-sass semantics).

### @extend

`@extend` works on simple-selector targets — a class, `%placeholder`, id, element, or pseudo — which covers how real stylesheets (Bootstrap included) use it. The target's compound is unified with the extender's final compound, ancestor compounds are prepended, and un-extended `%placeholder` rules never reach the output:

```scss
%visually-hidden { position: absolute; clip: rect(0 0 0 0); }
.sr-only { @extend %visually-hidden; }
// → .sr-only { position: absolute; clip: rect(0 0 0 0); }
```

A missing target fails the build with a located error; append `!optional` to tolerate it. See the deviations list for how the subset differs from dart-sass's full extend algorithm.

### Not supported (yet)

Compound units (`px*em`, `px/s` — multiplication/division that would need numerator/denominator unit lists), `@forward ... with (...)`, `math.random` / `unique-id()` (builds must stay deterministic), the indented `.sass` syntax, and source maps.

**Unsupported directives fail the build with a located error** — Hwaro never emits silently broken CSS:

```
Error [HWARO_E_CONTENT]: Sass: static/css/style.scss:14:3: @forward ... with (...) is not supported
```

### Expression semantics

The compiler's first duty is the plain-CSS guarantee, so expressions follow a two-tier policy:

- **Value contexts are lenient.** A declaration or variable value is evaluated only when it visibly computes something — an operator between numbers, a call to a known function. Anything else, and anything that *fails* to evaluate (`$a + 2em` with incompatible units, `min(100% - 10px, 20rem)`), keeps its verbatim text exactly as before. Existing stylesheets compile byte-identically.
- **New syntax is strict.** `@if`/`@while` conditions, `@each`/`@for` headers, `@return`, and `@use ... with` report every failure as a located build error.

### Deviations from dart-sass

- `/` follows the classic Sass division rule (dart-sass 1.x): it divides when an operand is a variable, a known function call, or parenthesized, or when the slash sits in a computing context (adjacent arithmetic, a Sass function argument, a variable declaration, interpolation, control flow). Literal-only slashes (`font: 12px/1.5`, `grid-area: 1 / 2`) stay verbatim **with the author's spacing** — dart-sass reprints them compacted (`1/2`).
- Values are stored as CSS text between evaluations; types are re-derived on use. An unquoted string that *looks* like a list (`"a, b"` unquoted) is treated as one.
- Unit arithmetic converts within the standard groups (length, angle, time, frequency, resolution), the left operand's unit winning. Compound units (`1px * 1em`, `math.div(1px, 1s)`) are not modeled and fall back to verbatim text.
- `and`/`or` in *value* positions only operate on real booleans — `font-family: Franklin and Marshall` stays text. Conditions have full Sass truthiness.
- Global `min()`/`max()`/`round()`/`abs()` evaluate only when all arguments are statically comparable numbers; CSS forms (`min(5vw, 100px)`, `round(up, 101px, 10px)`) pass through.
- `rgb()`/`rgba()`/`hsl()`/`hsla()` are **not** folded in their CSS forms: `rgb(0, 0, 0)` stays verbatim where dart-sass would emit `black` (a color *function* handed such a literal still reads it as a color). Only the Sass-only `rgba($color, $alpha)` spelling — which is not valid CSS — evaluates. Likewise `grayscale()`, `invert()`, `saturate()` and `opacity()` are color functions when handed a color and plain CSS filters when handed a number (`filter: grayscale(50%)` passes through).
- A computed color serializes with integer channels — by CSS keyword when the rounded channels match one exactly (`mix(red, blue)` → `purple`, aliases in dart's spelling: `aqua`, `gray`, `fuchsia`), else as hex/`rgba()`. dart-sass 1.79+ keeps fractional channels instead (`mix(red, blue)` is `rgb(50%, 0%, 50%)` there), so the keyword form matches dart only when the computation lands on exact integers; values are off by at most one per channel either way.
- Built-in functions accept their documented keyword names (`list.append($l, x, $separator: comma)`, `string.slice($string: …, $start-at: 2)`, `darken($c, $amount: 10%)`, `map.get($map: …, $key: …)`). Variadic builtins (`math.min`, `list.zip`, `map.set`, `selector.nest`) stay positional. User-defined `@mixin`/`@function` keyword arguments work normally.
- `@extend` is a practical subset of dart-sass's algorithm: targets must be simple selectors, extends apply document-wide (dart-sass scopes them per module and forbids crossing `@media` boundaries), and when both the extended selector and the extender have ancestor compounds only the first prefix order is emitted (dart-sass "weaves" both). Shared leading prefixes merge (`.nav %p` extended by `.nav > .c` → `.nav > .c`).
- A `calc()` whose contents fold to a single static number is simplified the way dart-sass does — `calc(10px + 5px * 2)` → `20px`, `calc(9 / 21 * 100%)` → `42.8571428571%`, nested `calc`/`min`/`max`/`clamp` included (`clamp` bounds win at exact boundaries, unit spelling included). Anything not fully foldable keeps its verbatim text: `calc(100% - 20px)`, `var()`, interpolated `calc(#{…})`, unitless↔united addition or clamp, `+`/`-` without surrounding whitespace (invalid CSS that dart-sass errors on), and division producing NaN. `@supports (width: calc(…))` never folds — the query tests calc support itself. A slash after a literal `calc()` (`font: calc(16px)/1.5`) stays verbatim like every literal slash.
- Variables in at-rule preludes and values substitute directly (`@media (min-width: $bp)` works); selectors and property names require `#{...}` interpolation (same as dart-sass).
- At-rule preludes evaluate expressions only inside `(feature: value)` spans; the query structure itself stays verbatim.
- `@media` nested inside `@media` merges the conditions with `and` (comma lists cross-multiply outer-major; type-conflicting pairs are dropped). Queries the merge can't express (`not …`) and nestings interrupted by another at-rule (`@supports`) keep the literal nested form — valid modern CSS — where dart-sass drops or rewrites them.
- `&` substitution is textual — `&__elem` concatenates without validating the compound selector.
- Custom property values are verbatim: `$var` stays literal, only `#{...}` interpolates (dart-sass semantics), but leading/trailing whitespace is trimmed.
- `@import` of the same file re-emits its CSS each time (classic Sass behavior); `@use` loads once.
- Configuring a module that itself uses `@forward` (`@use "lib" with (...)`) is an error rather than silently ignored.
- Output with non-ASCII content gets a single leading `@charset "UTF-8";`; source `@charset` declarations are dropped (dart-sass behavior).
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
