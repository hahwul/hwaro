+++
title = "Sass/SCSS"
description = "순수 Crystal로 구현된 내장 SCSS 컴파일. 외부 도구가 필요 없습니다"
weight = 16
toc = true
+++

Hwaro는 빌드 시점에 순수 Crystal로 구현된 내장 컴파일러로 SCSS를 컴파일합니다. dart-sass 바이너리 설치도, npm 툴체인도, C 라이브러리도 필요 없습니다. 외부 의존성 없음이라는 Hwaro의 철학 그대로입니다.

## 빠른 시작

```toml
[sass]
enabled = true
```

SCSS 파일을 `static/` 아래에 둡니다.

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

파셜이 아닌 모든 `*.scss`는 출력에서 같은 경로의 `.css`로 컴파일되므로(`static/css/style.scss` → `/css/style.css`), 스타일시트 URL이 안정적으로 유지됩니다.

```html
<link rel="stylesheet" href="{{ url_for(path="/css/style.css") }}">
```

## 규칙

- **엔트리** — 이름이 `_`로 시작하지 않는 `*.scss` 파일은 출력의 같은 상대 경로에 `.css`로 컴파일됩니다.
- **파셜** — `_*.scss` 파일은 단독으로 컴파일되지 않고 게시되지도 않습니다. `@use`/`@import`로만 접근할 수 있습니다.
- **원본 소스는 게시되지 않음** — `[sass]`가 활성화된 동안 `.scss` 파일은 정적 파일 그대로 복사되는 대상에서 제외됩니다.
- **번들** — `[[assets.bundles]]`의 `files` 항목에 `.scss` 파일을 지정할 수 있습니다. `[sass]`가 활성화된 동안에는 이어 붙이기 전에 컴파일된 뒤 일반적인 압축(minify) → 핑거프린트 파이프라인을 거칩니다. `[sass]`가 비활성화되면 번들 항목은 그대로 이어 붙입니다(미리 컴파일했거나 지원 범위를 벗어난 소스를 위한 탈출구).
- **감시** — `hwaro serve`는 `.scss` 변경 시 다시 컴파일합니다. 파셜을 수정하면 모든 엔트리를 다시 컴파일합니다(의존성 그래프가 없습니다. 정적 사이트 규모에서는 전체 재컴파일도 충분히 빠릅니다). 컴파일 오류는 브라우저 오류 오버레이에 표시됩니다.

## 설정

| 옵션 | 타입 | 기본값 | 설명 |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | SCSS 컴파일 활성화 |
| `minify` | bool | `true` | 컴파일된 CSS 압축(에셋 파이프라인과 같은 압축기 사용) |

## 지원 범위

Hwaro는 실용적인 SCSS 부분집합을 구현합니다. 직접 작성하는 사이트 스타일시트에서 실제로 쓰이는 기능들입니다.

| 기능 | 지원 |
|---------|---------|
| `$variables` | ✅ `!default` / `!global`, 렉시컬 스코프와 섀도잉 지원 |
| 중첩 규칙 | ✅ 셀렉터 목록 포함(카테시안 조합) |
| `&` 부모 셀렉터 | ✅ `&:hover`, `&.mod`, BEM `&__elem` / `&--mod` |
| `#{...}` 보간 | ✅ 셀렉터, 속성 이름, 값, at-규칙 서두, 문자열, `url()`. 내부에서 전체 표현식 평가. 문자열은 리스트 안까지 모든 중첩 수준에서 따옴표를 벗겨 출력합니다(`#{("a", "b")}` → `a, b`) |
| 파셜 + `@use` | ✅ 네임스페이스(`colors.$primary`), `as x`, `as *`, 1회 로드, `with (...)` 설정 |
| `@forward` | ✅ `show` / `hide` 필터, `as prefix-*` |
| `@import`(Sass 파일) | ✅ 클래식 전역 병합 시맨틱. `@forward`만 하는 파셜(`@import "components"` → `components/_index.scss`)도 포함하며, 순수 CSS 형태는 그대로 통과 |
| `@mixin` / `@include` | ✅ 기본값, 키워드 인자, 가변 인자 `$args...`(남는 키워드는 `meta.keywords()`로 전달), 스프레드(키워드는 `$args...`를 통해 그대로 전달), 인자를 받는 `@content` 블록(`@content(1px)` / `@include m using ($a)`) |
| `@function` / `@return` | ✅ 값 안에서 호출 가능한 사용자 함수, 기본값/키워드/가변 인자, 재귀 |
| `@extend` + `%placeholders` | ✅ 단순 셀렉터 타깃, 컴파운드 통합, `!optional`. 확장되지 않은 플레이스홀더는 출력되지 않음(차이점 참고) |
| SassScript의 `&` | ✅ `if(&, "&", "")` 패턴. 부모 셀렉터를 값으로, 루트에서는 `null` |
| 제어 흐름 | ✅ `@if` / `@else if` / `@else`, `@each`(구조 분해 포함), `@for`(`through`/`to`, 내림차순), `@while` |
| SassScript 표현식 | ✅ 산술(`+ - * / %`, 클래식 슬래시 나눗셈 규칙), 비교, `and`/`or`/`not`, 문자열, 리스트, 맵(`/`는 차이점 참고) |
| 단위 변환 | ✅ `px`/`cm`/`mm`/`q`/`in`/`pt`/`pc`, `deg`/`grad`/`rad`/`turn`, `s`/`ms`, `Hz`/`kHz`, `dpi`/`dpcm`/`dppx`가 산술·비교·`==`·`math.*`에서 변환됨 |
| 중첩 속성 | ✅ `font: 12px serif { family: sans; }` → `font`, `font-family` (재귀 적용) |
| 내장 함수 | ✅ `sass:math`(`log` / `hypot` / 삼각함수 포함), `sass:string`(`insert` / `split` 포함), `sass:list`(`zip` / `set-nth` / `slash` / `is-bracketed` 포함), `sass:map`(`set` / `deep-merge` / `deep-remove` 포함), `sass:meta`(`keywords` / `variable-exists` / `function-exists` / `mixin-exists` / `content-exists` / `get-function` / `call` 포함), `sass:selector`(문자열 수준의 `parse` / `nest` / `append` / `unify` / `replace` / `is-superselector` / `simple-selectors` — `replace`는 `@extend` 부분집합과 같은 제약을 공유합니다: `$original`은 컴파운드만, 의사 클래스 재귀 없음, 첫 번째 접두 순서만), `sass:color` 부분집합(`channel` / `hwb` / `ie-hex-str` 포함) + 레거시 전역 이름(`map-get`, `nth`, `darken`, `if()` 등) |
| 모듈 상수 | ✅ `math.$pi`, `math.$e`, `math.$epsilon`, `math.$max-safe-integer`, `math.$min-safe-integer`, `math.$max-number`, `math.$min-number` |
| `@debug` / `@warn` / `@error` | ✅ `@error`는 위치 정보가 담긴 메시지로 빌드를 실패시킴 |
| `@at-root` | ✅ 셀렉터 형태와 블록 형태, `#{&}` 접미, `(with: ...)` / `(without: ...)` 쿼리 |
| 규칙 안의 `@media` / `@supports` | ✅ 중첩 밖으로 자동 버블링, 중첩된 `@media`는 `and`로 병합(쉼표 목록은 교차 조합), 피처 값에서 표현식 평가 |
| `@keyframes`, `@font-face`, 커스텀 속성 | ✅ 올바르게 통과 |
| 순수 CSS | ✅ 유효한 `.css`는 그대로 컴파일(공백 정규화) |

알 수 없는 함수(`var()`, `clamp()`, `color-mix()` 등)는 손대지 않고 그대로 통과합니다. 인자는 평가되고(`translate($x * 2, -50%)` 동작), 정적인 `calc()`는 하나의 숫자로 접히며(차이점 참고), 토큰 전체를 이루는 `url($v)` / `url(ns.$img)`는 변수가 치환됩니다(`$`는 원시 URL에 쓸 수 없는 문자입니다). 더 큰 url 토큰 안에 `$`가 박혀 있는 형태(`url(plain$x.png)`)는 유효한 순수 CSS이므로 바이트 단위로 그대로 통과합니다. dart-sass는 여기서 오류를 내고, 반대로 `url($a + $b)`처럼 표현식이 들어간 내용은 dart-sass가 평가하지만 Hwaro는 원문 그대로 둡니다.

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

### 색상

색상 함수는 hex 리터럴(`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`), CSS 색상 키워드(`red`, `rebeccapurple`, `transparent`), 그리고 레거시 콤마 철자 `rgb(…)` / `rgba(…)` / `hsl(…)` / `hsla(…)`에 동작합니다. `hsl()`로 만든 색상은 선언된 색조/채도를 기억하므로 `hue(hsl(221, 14%, 100%))`는 `221deg`를 답합니다.

```scss
$brand: #336699;

.button {
  background: $brand;
  border-color: darken($brand, 10%);      // #264d73
  color: scale-color($brand, $lightness: 60%);
  box-shadow: 0 1px 2px rgba($brand, 0.4); // rgba(51, 102, 153, 0.4)
}
```

| 분류 | 함수 |
|------|------|
| 명도 | `darken`, `lighten` |
| 채도 | `saturate`, `desaturate`, `grayscale` |
| 색상(Hue) | `adjust-hue`, `complement` |
| 혼합 | `mix`, `invert` |
| 알파 | `rgba($color, $alpha)`, `opacify` / `fade-in`, `transparentize` / `fade-out` |
| 복합 | `adjust-color`, `scale-color`, `change-color` |
| 성분 조회 | `red`, `green`, `blue`, `hue`, `saturation`, `lightness`, `alpha` / `opacity`, `color.channel` |
| 기타 | `ie-hex-str`, `color.hwb`(`color.hwb($h $w $b)`와 `color.hwb($h, $w, $b)` 모두) |

같은 함수들을 `sass:color` 모듈의 최신 이름으로도 쓸 수 있습니다. `color.adjust`, `color.scale`, `color.change`, `color.mix`, `color.complement`, `color.grayscale`, `color.invert`, 그리고 성분 조회 함수들입니다.

```scss
@use "sass:color";
.a { border-color: color.scale(#336699, $lightness: -20%); }
```

계산된 색상은 불투명하면 `#rrggbb`로, 그렇지 않으면 `rgba(r, g, b, a)`로 직렬화됩니다. *수정하지 않은* 색상은 작성한 철자를 그대로 유지하므로 `#FFF`는 `#FFF`로 남습니다.

색상은 표기가 달라도 채널 값으로 비교됩니다. `#ffffff == #FFF`, `red == #f00`, `rgb(255, 0, 0) == #ff0000`은 모두 true입니다(dart-sass 시맨틱).

### @extend

`@extend`는 단순 셀렉터 타깃(클래스, `%placeholder`, id, 요소, 의사 클래스)에 동작합니다. Bootstrap을 포함한 실제 스타일시트의 사용 방식을 전부 커버합니다. 타깃이 속한 컴파운드는 확장자의 마지막 컴파운드와 통합되고, 조상 컴파운드는 앞에 붙으며, 확장되지 않은 `%placeholder` 규칙은 출력에 등장하지 않습니다.

```scss
%visually-hidden { position: absolute; clip: rect(0 0 0 0); }
.sr-only { @extend %visually-hidden; }
// → .sr-only { position: absolute; clip: rect(0 0 0 0); }
```

타깃을 찾지 못하면 위치 정보가 담긴 오류로 빌드가 실패합니다. `!optional`을 붙이면 허용됩니다. dart-sass의 전체 extend 알고리즘과의 차이는 아래 차이점 목록을 참고하세요.

### 미지원 (아직)

복합 단위(`px*em`, `px/s`처럼 분자·분모 단위 목록이 필요한 곱셈·나눗셈), `@forward ... with (...)`, `math.random` / `unique-id()`(빌드는 결정적이어야 합니다), 들여쓰기 방식의 `.sass` 문법, 소스맵은 지원하지 않습니다.

**미지원 지시문은 위치 정보가 담긴 오류와 함께 빌드를 실패시킵니다** — Hwaro는 조용히 깨진 CSS를 내보내지 않습니다.

```
Error [HWARO_E_CONTENT]: Sass: static/css/style.scss:14:3: @forward ... with (...) is not supported
```

### 표현식 시맨틱

이 컴파일러의 첫 번째 의무는 순수 CSS 보장이므로, 표현식은 두 단계 정책을 따릅니다.

- **값 컨텍스트는 관대(lenient)합니다.** 선언이나 변수 값은 눈에 보이게 무언가를 계산할 때(숫자 사이의 연산자, 알려진 함수 호출)만 평가됩니다. 그 외의 값, 그리고 평가에 *실패*하는 값(단위가 안 맞는 `$a + 2em`, `min(100% - 10px, 20rem)`)은 이전과 똑같이 원문 텍스트를 유지합니다. 기존 스타일시트는 바이트 단위로 동일하게 컴파일됩니다.
- **새 구문은 엄격(strict)합니다.** `@if`/`@while` 조건, `@each`/`@for` 헤더, `@return`, `@use ... with`는 모든 실패를 위치 정보가 담긴 빌드 오류로 보고합니다.

### dart-sass와의 차이

- `/`는 클래식 Sass 나눗셈 규칙(dart-sass 1.x)을 따릅니다. 피연산자가 변수이거나 알려진 함수 호출이거나 괄호로 감싸여 있을 때, 또는 슬래시가 계산 문맥(인접한 산술, Sass 함수 인자, 변수 선언, 보간, 제어 흐름)에 놓일 때 나눗셈이 됩니다. 리터럴끼리의 슬래시(`font: 12px/1.5`, `grid-area: 1 / 2`)는 **작성자가 쓴 공백 그대로** 유지됩니다. dart-sass는 이를 붙여서(`1/2`) 다시 출력합니다.
- 값은 평가 사이에 CSS 텍스트로 저장되고 사용 시점에 타입이 다시 유도됩니다. 리스트처럼 *보이는* 따옴표 없는 문자열(`"a, b"`를 unquote한 값)은 리스트로 취급됩니다.
- 단위 산술은 표준 그룹(길이, 각도, 시간, 주파수, 해상도) 안에서 변환되며, 왼쪽 피연산자의 단위가 결과 단위가 됩니다. 복합 단위(`1px * 1em`, `math.div(1px, 1s)`)는 모델링하지 않고 원문 텍스트로 남습니다.
- *값* 위치의 `and`/`or`는 실제 불리언에만 동작하므로 `font-family: Franklin and Marshall`은 텍스트로 남습니다. 조건식에서는 Sass의 완전한 truthiness를 따릅니다.
- 전역 `min()`/`max()`/`round()`/`abs()`는 모든 인자가 정적으로 비교 가능한 숫자일 때만 평가됩니다. CSS 형태(`min(5vw, 100px)`, `round(up, 101px, 10px)`)는 그대로 통과합니다.
- `rgb()`/`rgba()`/`hsl()`/`hsla()`는 CSS 형태 그대로 두고 접지 **않습니다**. dart-sass는 `rgb(0, 0, 0)`을 `black`으로 내보내지만 여기서는 원문이 유지됩니다(색상 *함수*가 그런 리터럴을 받으면 색상으로 읽기는 합니다). 유효한 CSS가 아닌 Sass 전용 `rgba($color, $alpha)` 철자만 평가됩니다. 마찬가지로 `grayscale()`, `invert()`, `saturate()`, `opacity()`는 색상을 받으면 색상 함수, 숫자를 받으면 순수 CSS 필터로 취급됩니다(`filter: grayscale(50%)`는 그대로 통과).
- 계산된 색상은 정수 채널로 직렬화됩니다. 반올림한 채널이 CSS 키워드와 정확히 일치하면 키워드로(`mix(red, blue)` → `purple`, 별칭은 dart의 표기를 따라 `aqua`, `gray`, `fuchsia`), 그렇지 않으면 hex/`rgba()`로 출력합니다. dart-sass 1.79+는 대신 소수 채널을 유지하므로(거기서 `mix(red, blue)`는 `rgb(50%, 0%, 50%)`) 키워드 형태는 계산 결과가 정확한 정수로 떨어질 때만 dart와 일치하며, 어느 쪽이든 채널당 최대 1 차이입니다.
- 내장 함수는 문서화된 키워드 이름을 받습니다(`list.append($l, x, $separator: comma)`, `string.slice($string: …, $start-at: 2)`, `darken($c, $amount: 10%)`, `map.get($map: …, $key: …)`). 가변 인자 내장 함수(`math.min`, `list.zip`, `map.set`, `selector.nest`)는 위치 인자만 받습니다. 사용자 정의 `@mixin`/`@function`의 키워드 인자는 정상 동작합니다.
- `@extend`는 dart-sass 알고리즘의 실용적 부분집합입니다: 타깃은 단순 셀렉터여야 하고, 확장은 문서 전역에 적용되며(dart-sass는 모듈 단위로 스코프를 나누고 `@media` 경계를 넘는 확장을 금지), 확장 대상과 확장자 양쪽에 조상 컴파운드가 있으면 첫 번째 접두 순서만 출력합니다(dart-sass는 두 순서를 모두 "위빙"). 공유하는 선행 접두는 병합됩니다(`.nav %p`를 `.nav > .c`로 확장 → `.nav > .c`).
- 내용 전체가 하나의 정적 숫자로 접히는 `calc()`는 dart-sass와 같은 방식으로 단순화됩니다. `calc(10px + 5px * 2)` → `20px`, `calc(9 / 21 * 100%)` → `42.8571428571%`이며 중첩된 `calc`/`min`/`max`/`clamp`도 포함합니다(`clamp`는 경계값에서 경계가 이기고, 단위 표기도 유지됩니다). 완전히 접히지 않는 것은 원문 텍스트를 유지합니다: `calc(100% - 20px)`, `var()`, 보간이 들어간 `calc(#{…})`, 단위 없는 값과 단위 있는 값의 덧셈이나 clamp, 앞뒤 공백이 없는 `+`/`-`(dart-sass가 오류를 내는 잘못된 CSS), NaN이 나오는 나눗셈이 그렇습니다. `@supports (width: calc(…))`는 절대 접지 않습니다. 이 쿼리는 calc 지원 여부 자체를 검사하기 때문입니다. 리터럴 `calc()` 뒤의 슬래시(`font: calc(16px)/1.5`)는 다른 리터럴 슬래시와 마찬가지로 그대로 유지됩니다.
- at-규칙 서두와 값 안의 변수는 직접 치환됩니다(`@media (min-width: $bp)` 동작). 셀렉터와 속성 이름에는 `#{...}` 보간이 필요합니다(dart-sass와 동일).
- at-규칙 서두에서는 `(feature: value)` 구간 안에서만 표현식이 평가됩니다. 쿼리 구조 자체는 원문 그대로 유지됩니다.
- `@media` 안에 중첩된 `@media`는 조건이 `and`로 병합됩니다(쉼표 목록은 바깥쪽을 우선으로 교차 조합하고, 타입이 충돌하는 쌍은 버립니다). 병합으로 표현할 수 없는 쿼리(`not …`)나 중간에 다른 at-규칙(`@supports`)이 끼어든 중첩은 문자 그대로 중첩된 형태를 유지합니다. 유효한 최신 CSS이며, dart-sass는 이런 경우를 버리거나 다시 씁니다.
- `&` 치환은 텍스트 기반이라 `&__elem`은 결합 셀렉터를 검증하지 않고 이어 붙입니다.
- 커스텀 속성 값은 그대로 유지됩니다: `$var`는 리터럴로 남고 `#{...}`만 보간됩니다(dart-sass 시맨틱). 다만 앞뒤 공백은 잘라냅니다.
- 같은 파일을 여러 번 `@import`하면 그때마다 CSS를 다시 내보냅니다(클래식 Sass 동작). `@use`는 한 번만 로드합니다.
- 자체적으로 `@forward`를 사용하는 모듈을 설정(`@use "lib" with (...)`)하는 것은 조용히 무시되는 대신 오류입니다.
- 출력에 비ASCII 내용이 있으면 맨 앞에 `@charset "UTF-8";`가 한 번 붙습니다. 소스에 쓴 `@charset` 선언은 제거됩니다(dart-sass 동작).
- 값은 텍스트로 치환됩니다: 짝이 맞지 않는 따옴표 문자가 들어 있는 변수를 보간하면 이후의 공백/따옴표 처리가 꼬일 수 있습니다. 따옴표 문자는 따옴표로 감싼 문자열 안에만 둡니다.
- 소문자 `.scss` 확장자만 Sass 소스로 취급합니다. 다른 대소문자 조합은 일반 정적 파일처럼 그대로 게시됩니다.

## 오류

컴파일 실패는 콘텐츠 오류로 분류되며(종료 코드 5), `path:line:column` 위치 정보가 함께 표시됩니다.

```
Error [HWARO_E_CONTENT]: Sass: static/css/_mixins.scss:7:12: undefined variable: "$primry"
```

`hwaro serve` 중에는 오류가 브라우저 오버레이에 표시되고, 이전 출력은 디스크에 그대로 남습니다.

## 다른 기능과의 상호작용

- **에셋 파이프라인** — 단독으로 컴파일된 엔트리는 안정적인(핑거프린트 없는) URL을 유지하고 `asset()`의 패스스루로 해석됩니다. 핑거프린트가 필요하면 번들에서 `.scss` 파일을 참조합니다.
- **빌드 훅** — Tailwind/PostCSS나 완전한 dart-sass 프로젝트는 여전히 `[build] hooks.pre`로 실행하고, 컴파일된 출력을 Hwaro가 사용하게 하면 됩니다.
- **캐시** — Sass는 전체 빌드마다 다시 컴파일됩니다(증분 페이지 캐시에 참여하지 않습니다). 엔트리 `.scss`를 삭제하면 이전에 컴파일된 `.css`가 오래된 출력 디렉터리에 남습니다. 클린 빌드는 이를 제거합니다.
