+++
title = "Sass/SCSS"
description = "순수 Crystal로 구현된 내장 SCSS 컴파일 — 외부 도구가 필요 없습니다"
weight = 16
toc = true
+++

Hwaro는 빌드 시점에 순수 Crystal로 구현된 내장 컴파일러로 SCSS를 컴파일합니다. dart-sass 바이너리 설치도, npm 툴체인도, C 라이브러리도 필요 없습니다 — 외부 의존성 없음이라는 Hwaro의 철학 그대로입니다.

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
- **감시** — `hwaro serve`는 `.scss` 변경 시 다시 컴파일합니다. 파셜을 수정하면 모든 엔트리를 다시 컴파일합니다(의존성 그래프가 없습니다 — 정적 사이트 규모에서는 전체 재컴파일도 충분히 빠릅니다). 컴파일 오류는 브라우저 오류 오버레이에 표시됩니다.

## 설정

| 옵션 | 타입 | 기본값 | 설명 |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | SCSS 컴파일 활성화 |
| `minify` | bool | `true` | 컴파일된 CSS 압축(에셋 파이프라인과 같은 압축기 사용) |

## 지원 범위

Hwaro는 실용적인 SCSS 부분집합을 구현합니다 — 직접 작성하는 사이트 스타일시트에서 실제로 쓰이는 기능들입니다.

| 기능 | 지원 |
|---------|---------|
| `$variables` | ✅ `!default` / `!global`, 렉시컬 스코프와 섀도잉 지원 |
| 중첩 규칙 | ✅ 셀렉터 목록 포함(카테시안 조합) |
| `&` 부모 셀렉터 | ✅ `&:hover`, `&.mod`, BEM `&__elem` / `&--mod` |
| `#{...}` 보간 | ✅ 셀렉터, 속성 이름, 값, at-규칙 서두, 문자열, `url()` — 내부에서 전체 표현식 평가 |
| 파셜 + `@use` | ✅ 네임스페이스(`colors.$primary`), `as x`, `as *`, 1회 로드, `with (...)` 설정 |
| `@forward` | ✅ `show` / `hide` 필터, `as prefix-*` |
| `@import`(Sass 파일) | ✅ 클래식 전역 병합 시맨틱, 순수 CSS 형태는 그대로 통과 |
| `@mixin` / `@include` | ✅ 기본값, 키워드 인자, 가변 인자 `$args...`, 스프레드, `@content` 블록 |
| `@function` / `@return` | ✅ 값 안에서 호출 가능한 사용자 함수, 기본값/키워드/가변 인자, 재귀 |
| 제어 흐름 | ✅ `@if` / `@else if` / `@else`, `@each`(구조 분해 포함), `@for`(`through`/`to`, 내림차순), `@while` |
| SassScript 표현식 | ✅ 산술(`+ - * %`), 비교, `and`/`or`/`not`, 문자열, 리스트, 맵 — `/`는 차이점 참고 |
| 내장 함수 | ✅ `sass:math`, `sass:string`, `sass:list`, `sass:map`, `sass:meta`, `sass:color` 부분집합 + 레거시 전역 이름(`map-get`, `nth`, `darken`, `if()` 등) |
| `@debug` / `@warn` / `@error` | ✅ `@error`는 위치 정보가 담긴 메시지로 빌드를 실패시킴 |
| `@at-root` | ✅ 셀렉터 형태와 블록 형태(`with:`/`without:` 쿼리는 제외) |
| 규칙 안의 `@media` / `@supports` | ✅ 중첩 밖으로 자동 버블링, 피처 값에서 표현식 평가 |
| `@keyframes`, `@font-face`, 커스텀 속성 | ✅ 올바르게 통과 |
| 순수 CSS | ✅ 유효한 `.css`는 그대로 컴파일(공백 정규화) |

알 수 없는 함수(`calc()`, `var()`, `clamp()`, `color-mix()` 등)는 손대지 않고 그대로 통과합니다 — 인자는 평가됩니다(`translate($x * 2, -50%)` 동작).

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

색상 함수는 hex 리터럴(`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`)과 CSS 색상 키워드(`red`, `rebeccapurple`, `transparent`)에 동작합니다.

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
| 성분 조회 | `red`, `green`, `blue`, `hue`, `saturation`, `lightness`, `alpha` / `opacity` |

같은 함수들을 `sass:color` 모듈의 최신 이름으로도 쓸 수 있습니다 — `color.adjust`, `color.scale`, `color.change`, `color.mix`, `color.complement`, `color.grayscale`, `color.invert`, 그리고 성분 조회 함수들입니다.

```scss
@use "sass:color";
.a { border-color: color.scale(#336699, $lightness: -20%); }
```

계산된 색상은 불투명하면 `#rrggbb`로, 그렇지 않으면 `rgba(r, g, b, a)`로 직렬화됩니다. *수정하지 않은* 색상은 작성한 철자를 그대로 유지합니다 — `#FFF`는 `#FFF`로 남습니다.

두 색상이 색상으로서 비교되는 것은 색상 함수가 만들어낸 값일 때뿐입니다. 리터럴끼리의 `#ffffff == #FFF`는 여전히 일반 텍스트 비교이므로 false입니다. `==`가 모든 리터럴을 파싱하게 만들면 지금 잘 컴파일되는 스타일시트의 `@if` 분기가 뒤집히는데, 순수 CSS 보장이 이를 허용하지 않습니다.

### 미지원 (아직)

`@extend`, 단위 변환(`px`↔`cm`), `@at-root (with: ...)` 쿼리, `@forward ... with (...)`, `@content(args)` / `using`, `math.random` / `unique-id()`(빌드는 결정적이어야 합니다), 중첩 속성(`font: { family: ... }`), 들여쓰기 방식의 `.sass` 문법, 소스맵은 지원하지 않습니다.

**미지원 지시문은 위치 정보가 담긴 오류와 함께 빌드를 실패시킵니다** — Hwaro는 조용히 깨진 CSS를 내보내지 않습니다.

```
Error [HWARO_E_CONTENT]: Sass: static/css/style.scss:14:3: @extend is not supported by hwaro's Sass subset (yet)
```

### 표현식 시맨틱

이 컴파일러의 첫 번째 의무는 순수 CSS 보장이므로, 표현식은 두 단계 정책을 따릅니다.

- **값 컨텍스트는 관대(lenient)합니다.** 선언이나 변수 값은 눈에 보이게 무언가를 계산할 때만 — 숫자 사이의 연산자, 알려진 함수 호출 — 평가됩니다. 그 외의 값, 그리고 평가에 *실패*하는 값(단위가 안 맞는 `$a + 2em`, `min(100% - 10px, 20rem)`)은 이전과 똑같이 원문 텍스트를 유지합니다. 기존 스타일시트는 바이트 단위로 동일하게 컴파일됩니다.
- **새 구문은 엄격(strict)합니다.** `@if`/`@while` 조건, `@each`/`@for` 헤더, `@return`, `@use ... with`는 모든 실패를 위치 정보가 담긴 빌드 오류로 보고합니다.

### dart-sass와의 차이

- `/`는 **절대** 나눗셈이 아닙니다 — `font: 12px/1.5`와 `grid-area: 1 / 2`는 그대로 유지됩니다. 나눗셈은 `math.div()`를 사용합니다(슬래시 나눗셈을 제거한 dart-sass 2.0과 같은 방향).
- 값은 평가 사이에 CSS 텍스트로 저장되고 사용 시점에 타입이 다시 유도됩니다. 리스트처럼 *보이는* 따옴표 없는 문자열(`"a, b"`를 unquote한 값)은 리스트로 취급됩니다.
- 단위 산술은 동일 단위이거나 한쪽이 단위 없는 경우만 지원합니다. `px`↔`in` 변환 테이블은 없습니다.
- *값* 위치의 `and`/`or`는 실제 불리언에만 동작합니다 — `font-family: Franklin and Marshall`은 텍스트로 남습니다. 조건식에서는 Sass의 완전한 truthiness를 따릅니다.
- 전역 `min()`/`max()`/`round()`/`abs()`는 모든 인자가 정적으로 비교 가능한 숫자일 때만 평가됩니다. CSS 형태(`min(5vw, 100px)`, `round(up, 101px, 10px)`)는 그대로 통과합니다.
- `rgb()`/`rgba()`/`hsl()`/`hsla()`는 CSS 형태 그대로 두고 접지 **않습니다**. dart-sass는 `rgb(0, 0, 0)`을 `black`으로 내보내지만 여기서는 원문이 유지됩니다. 유효한 CSS가 아닌 Sass 전용 `rgba($color, $alpha)` 철자만 평가됩니다. 마찬가지로 `grayscale()`, `invert()`, `saturate()`, `opacity()`는 색상을 받으면 색상 함수, 숫자를 받으면 순수 CSS 필터로 취급됩니다(`filter: grayscale(50%)`는 그대로 통과).
- 내장 함수는 위치 인자만 받습니다. 키워드 호출(`list.append($l, x, $separator: comma)`)은 평가되지 않고 원문 그대로 남습니다 — 사용자 정의 `@mixin`/`@function`의 키워드 인자는 정상 동작합니다.
- `if()`는 두 분기를 모두 즉시 평가합니다(부수 효과가 없으므로, 선택되지 않은 분기의 `@error`로만 관찰 가능합니다).
- at-규칙 서두와 값 안의 변수는 직접 치환됩니다(`@media (min-width: $bp)` 동작). 셀렉터와 속성 이름에는 `#{...}` 보간이 필요합니다(dart-sass와 동일).
- at-규칙 서두에서는 `(feature: value)` 구간 안에서만 표현식이 평가됩니다. 쿼리 구조 자체는 원문 그대로 유지됩니다.
- `@media` 안에 중첩된 `@media`는 문자 그대로 중첩된 블록으로 출력됩니다(dart-sass는 조건을 병합).
- `&` 치환은 텍스트 기반입니다 — `&__elem`은 결합 셀렉터를 검증하지 않고 이어 붙입니다.
- 커스텀 속성 값은 그대로 유지됩니다: `$var`는 리터럴로 남고 `#{...}`만 보간됩니다(dart-sass 시맨틱). 다만 앞뒤 공백은 잘라냅니다.
- 같은 파일을 여러 번 `@import`하면 그때마다 CSS를 다시 내보냅니다(클래식 Sass 동작). `@use`는 한 번만 로드합니다.
- 자체적으로 `@forward`를 사용하는 모듈을 설정(`@use "lib" with (...)`)하는 것은 조용히 무시되는 대신 오류입니다.
- 중첩 규칙 *뒤에* 놓인 선언은 부모의 단일 출력 블록으로 병합됩니다(`.a { color: red; .b {} color: blue; }`는 `.a` 블록 하나로 출력). dart-sass는 소스 순서대로 분리합니다. 부모의 후행 선언과 중첩 규칙 사이의 캐스케이드 순서에 의존하지 않는 것이 좋습니다.
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
