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
| `#{...}` 보간 | ✅ 셀렉터, 속성 이름, 값, at-규칙 서두, 문자열, `url()` |
| 파셜 + `@use` | ✅ 네임스페이스(`colors.$primary`), `as x`, `as *`, 1회 로드 |
| `@import`(Sass 파일) | ✅ 클래식 전역 병합 시맨틱, 순수 CSS 형태는 그대로 통과 |
| `@mixin` / `@include` | ✅ 기본값, 키워드 인자, `@content` 블록 |
| 규칙 안의 `@media` / `@supports` | ✅ 중첩 밖으로 자동 버블링 |
| `@keyframes`, `@font-face`, 커스텀 속성 | ✅ 올바르게 통과 |
| 순수 CSS | ✅ 유효한 `.css`는 그대로 컴파일(공백 정규화) |

알 수 없는 함수(`calc()`, `var()`, `rgba()`, `clamp()`, `color-mix()` 등)는 손대지 않고 그대로 통과합니다.

### 미지원 (아직)

제어 흐름(`@if`/`@else`/`@each`/`@for`/`@while`), SassScript 산술·비교 연산자, 내장 함수 모듈(`math.*`, `color.*`, 문자열/리스트/맵 함수), `@function`, `@extend`, `@forward`, `@use ... with (...)`, 가변 인자(`$args...`), `@content(args)` / `using`, 중첩 속성(`font: { family: ... }`), 들여쓰기 방식의 `.sass` 문법, 소스맵은 지원하지 않습니다.

**미지원 지시문은 위치 정보가 담긴 오류와 함께 빌드를 실패시킵니다** — Hwaro는 조용히 깨진 CSS를 내보내지 않습니다.

```
Error [HWARO_E_CONTENT]: Sass: static/css/style.scss:14:3: @if is not supported by hwaro's Sass subset (yet)
```

### dart-sass와의 차이

- at-규칙 서두와 값 안의 변수는 직접 치환됩니다(`@media (min-width: $bp)` 동작). 셀렉터와 속성 이름에는 `#{...}` 보간이 필요합니다(dart-sass와 동일).
- `@media` 안에 중첩된 `@media`는 문자 그대로 중첩된 블록으로 출력됩니다(dart-sass는 조건을 병합).
- `&` 치환은 텍스트 기반입니다 — `&__elem`은 결합 셀렉터를 검증하지 않고 이어 붙입니다.
- 커스텀 속성 값은 그대로 유지됩니다: `$var`는 리터럴로 남고 `#{...}`만 보간됩니다(dart-sass 시맨틱). 다만 앞뒤 공백은 잘라냅니다.
- 같은 파일을 여러 번 `@import`하면 그때마다 CSS를 다시 내보냅니다(클래식 Sass 동작). `@use`는 한 번만 로드합니다.
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
