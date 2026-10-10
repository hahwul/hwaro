+++
title = "에셋 파이프라인"
description = "내장 CSS/JS 번들링, 압축, 핑거프린트"
weight = 17
toc = true
+++

Hwaro에는 CSS와 JS 파일을 번들링·압축(minify)·핑거프린트해 프로덕션에 바로 쓸 수 있는 출력물을 만드는 에셋 파이프라인이 내장되어 있습니다.

## 기능

- **번들링** — 여러 CSS/JS 파일을 하나의 번들로 결합
- **압축** — 주석과 공백을 제거해 파일 크기 축소
- **핑거프린트** — 캐시 버스팅을 위한 콘텐츠 해시 파일명(예: `style.a1b2c3d4.css`)
- **템플릿 헬퍼** — `{{ asset(name="style.css") }}`가 핑거프린트된 경로로 해석

## 설정

`config.toml`에 `[assets]` 섹션을 추가합니다.

```toml
[assets]
enabled = true
minify = true
fingerprint = true

[[assets.bundles]]
name = "main.css"
files = ["css/reset.css", "css/style.css"]

[[assets.bundles]]
name = "app.js"
files = ["js/util.js", "js/app.js"]
```

번들 `files`에는 `.scss` 소스도 지정할 수 있습니다. `[sass]`가 활성화된 동안에는 [Sass/SCSS](/ko/features/sass/) 내장 컴파일러로 컴파일된 뒤 이어 붙고, 다른 CSS와 똑같이 압축·핑거프린트됩니다. 이런 번들은 출력이 올바른 타입으로 제공되도록 `.css` 확장자로 이름을 짓습니다.

| 옵션 | 타입 | 기본값 | 설명 |
|--------|------|---------|-------------|
| `enabled` | bool | `false` | 에셋 파이프라인 활성화 |
| `minify` | bool | `true` | CSS/JS 출력 압축 |
| `fingerprint` | bool | `true` | 파일명에 콘텐츠 해시 추가 |
| `source_dir` | string | `"static"` | 소스 파일이 있는 디렉터리 (프로젝트 안에 있는 한 어디를 가리켜도 `hwaro serve`가 감시합니다) |
| `output_dir` | string | `"assets"` | 빌드 출력 내 출력 하위 디렉터리 |
| `sri` | bool | `false` | Hwaro가 출력하는 로컬 CSS/JS 태그에 `integrity` 속성 추가([하위 리소스 무결성](#sri) 참고). `enabled = false`여도 동작 |

### 번들 정의

`[[assets.bundles]]` 항목 하나가 출력 파일 하나를 정의합니다.

| 필드 | 타입 | 설명 |
|-------|------|-------------|
| `name` | string | 출력 파일명(예: `"main.css"`) |
| `files` | array | `source_dir` 기준 상대 경로의 소스 파일 |

파일은 나열한 순서대로 이어 붙입니다. CSS `@import` 규칙은 첫 번째 파일에 두세요. 브라우저는 다른 규칙 뒤에 오는 `@import`를 무시하므로, 뒤쪽 파일에 있으면 빌드가 경고합니다.

CSS 번들은 원본 파일 옆이 아니라 `output_dir` 아래에 게시됩니다. `source_dir`가 `static`이면, 원본 스타일시트 옆에 있는 파일을 가리키는 상대 `url(...)`을 번들 위치에서도 같은 파일에 닿도록 고쳐 씁니다. 예를 들어 `static/css/a.css`의 `url(img/x.png)`는 `assets/main.css`에서 `url(../css/img/x.png)`가 됩니다. 절대 URL, `data:`·프로토콜 URL, 원본 옆에 해당 파일이 없는 상대 URL, CSS 문자열이나 주석 안의 `url(...)` 텍스트는 그대로 둡니다.

## 템플릿에서 사용

템플릿에서 번들된 에셋을 참조하려면 `asset()` 함수를 사용합니다.

```html
<link rel="stylesheet" href="{{ asset(name='main.css') }}">
<script src="{{ asset(name='app.js') }}"></script>
```

핑거프린트가 활성화되어 있으면 해시가 붙은 경로로 해석됩니다.

```html
<link rel="stylesheet" href="https://example.com/assets/main.a1b2c3d4.css">
```

에셋이 파이프라인 매니페스트에 없으면(예: 번들로 설정하지 않은 경우) `base_url` 아래의 경로를 그대로 반환합니다.

`asset`의 별칭으로 `asset_url`도 쓸 수 있습니다.

## 하위 리소스 무결성 {#sri}

[하위 리소스 무결성(SRI)](https://developer.mozilla.org/ko/docs/Web/Security/Subresource_Integrity)을 쓰면 페이지가 기대한 바이트와 다른 스타일시트나 스크립트를 브라우저가 거부합니다. `asset_integrity()`는 `asset()`이 가리키는 파일의 `sha384-…` 값을 돌려줍니다.

```html
<link rel="stylesheet" href="{{ asset(name='main.css') }}" integrity="{{ asset_integrity(name='main.css') }}" crossorigin="anonymous">
```

해시는 Hwaro가 출력에 쓴 바이트(압축과 핑거프린트 이후)로 계산하므로 항상 게시된 파일과 일치합니다. 다음 파일에 쓸 수 있습니다.

- 파이프라인 번들
- `static/`에서 복사된 파일. 예를 들어 `static/css/site.css`라면 `asset_integrity(name='css/site.css')`
- Sass 출력
- 페이지 번들 에셋과 `[content.files]` 파일. 예를 들어 `asset_integrity(name='posts/demo/app.js')`. 이 파일들은 렌더링 뒤에 복사되므로 원본으로 해시를 계산합니다. 복사는 바이트 그대로이며, `--minify`일 때의 `.json`, `.xml`, `.html`만 예외입니다. 이 파일들은 렌더링 뒤에 다시 쓰이므로 `asset_integrity()`가 오류를 냅니다.

이번 빌드가 게시하지 않는 이름은 템플릿 오류로 빌드가 실패합니다. 출력 디렉터리에 이전 빌드의 사본(삭제된 정적 파일, 초안이 된 페이지의 에셋)이 아직 남아 있는 `--cache` 빌드에서도 마찬가지입니다.

`sri = true`로 설정하면 Hwaro가 직접 만드는 태그에도 이 속성이 붙습니다.

```toml
[assets]
sri = true
```

- `{{ auto_includes }}`, `{{ auto_includes_css }}`, `{{ auto_includes_js }}` ([자동 인클루드](/ko/features/auto-includes/))
- `[highlight] use_cdn = false`일 때의 `{{ highlight_css }}`, `{{ highlight_js }}`, `{{ highlight_tags }}`

각 태그에는 `integrity`와 함께 `crossorigin="anonymous"`가 붙습니다. URL이 절대 `base_url`로 시작하므로, 다른 호스트(`www`와 루트 도메인, 운영 `base_url`을 그대로 쓰는 배포 미리보기)에서 페이지를 열면 교차 출처로 불러옵니다. 브라우저는 CORS 응답만 무결성을 검사할 수 있으므로 `crossorigin`이 없으면 파일을 차단합니다. 정적 호스트와 CDN은 이런 요청에 응답(`Access-Control-Allow-Origin`)하며, 직접 운영하는 서버라면 CSS와 JS에 이를 허용하세요. 같은 이유로 `asset_integrity()`로 직접 쓰는 태그에도 `crossorigin="anonymous"`를 붙이세요.

CDN 태그에는 바이트를 알 수 없으므로 `integrity`를 붙이지 않습니다. `?v=` [캐시 버스팅](/ko/features/cache-busting/) 쿼리는 해시에 영향을 주지 않습니다.

`hwaro serve`는 직접 만드는 태그에 `integrity`를 붙이지 않습니다. 페이지에는 개발 서버 자신의 주소가 들어가는데, 이를 다른 이름(`localhost`와 `127.0.0.1`, LAN 주소)으로 열 수 있기 때문입니다. `asset_integrity()`는 serve에서도 값을 돌려줍니다.

CSS나 JS 파일이 바뀌면 `hwaro build --cache`와 `hwaro serve` 모두에서 그 값을 출력하는 모든 페이지가 갱신됩니다. 값이 오래된 채로 남으면 브라우저가 에셋을 차단하기 때문입니다.

빌드 뒤에 출력된 CSS나 JS를 다시 쓰는 도구는 검사를 깨뜨립니다. `public/`을 대상으로 하는 `[build] hooks.post` 압축 도구는 해시가 출력된 뒤에 바이트를 바꿉니다. 이런 도구는 `hooks.pre`에서 `static/`에 쓰도록 실행하거나 `[assets] minify`를 쓰세요. 빌드 후 훅이 페이지에 integrity가 들어간 파일을 바꾸면 빌드가 해당 파일을 알려 주는 경고를 출력합니다.

## 사용 선택자 매니페스트(Tailwind) {#used-selector-manifest-tailwind}

Tailwind CSS v4 같은 유틸리티 CSS 도구는 HTML이 실제로 쓰는 클래스만 생성합니다. `[build] write_stats = true`로 설정하면 매 빌드가 프로젝트 루트에 `hwaro_stats.json`(Hugo의 `hugo_stats.json`과 같은 형식)을 쓰고, 렌더링된 모든 페이지(페이지, 섹션, 택소노미 페이지, 페이지네이션 페이지, 404 페이지)의 태그·클래스·id를 담습니다.

```json
{
  "htmlElements": {
    "tags": ["a", "body", "div"],
    "classes": ["flex", "mt-4", "text-lg"],
    "ids": ["main"]
  }
}
```

값은 정렬되고 중복이 제거됩니다. 파일은 내용이 바뀔 때만 다시 쓰고, `hwaro serve`는 이 파일을 소스 변경으로 보지 않으므로 재빌드 루프가 생기지 않습니다.

모든 페이지를 렌더링한 빌드는 정확한 집합을 씁니다. 일부만 렌더링한 빌드(`--cache` 적중, `serve --fast-start`, serve의 증분 재빌드)는 이전 파일에 이번에 렌더링한 내용을 더합니다. 그래서 수정되거나 삭제된 페이지만 쓰던 클래스는 모든 페이지를 렌더링하는 다음 빌드까지 목록에 남습니다. 항목이 남아도 생성되는 CSS가 조금 늘어날 뿐이고, 페이지가 쓰는 클래스가 빠지는 일은 없습니다. `--cache` 빌드를 시작할 때 파일이 없거나 읽을 수 없으면 그 빌드는 모든 페이지를 렌더링합니다.

`<script>`와 `<style>` 안의 마크업은 검사하지 않으므로, 클라이언트 쪽 템플릿(`<script type="text/template">`)의 클래스나 자바스크립트가 추가하는 클래스는 목록에 들어가지 않습니다. 이런 클래스는 Tailwind 소스에 직접 추가하세요.

### Tailwind v4 예시

Tailwind가 매니페스트를 읽게 하고 CLI를 빌드 전 훅으로 실행합니다.

```css
/* assets/tailwind.css */
@import "tailwindcss";
@source "../hwaro_stats.json";
```

```toml
[build]
write_stats = true
hooks.pre = ["npx @tailwindcss/cli -i assets/tailwind.css -o static/css/tailwind.css --minify"]
```

```html
<link rel="stylesheet" href="{{ asset(name='css/tailwind.css') }}">
```

빌드 전 훅은 이전 빌드의 매니페스트를 읽으므로, 새로 체크아웃한 저장소에서는 `hwaro build`를 두 번 실행하거나 `hwaro_stats.json`을 소스와 함께 커밋해 두세요.

`hwaro serve`에서는 `hooks.pre`가 전체 재빌드 때만 실행되고, 콘텐츠 편집은 `hwaro_stats.json`을 증분으로 갱신합니다. 글을 쓰는 동안 새 클래스를 바로 반영하려면 Tailwind를 훅 대신 감시 모드로 서버 옆에서 실행하세요.

```bash
npx @tailwindcss/cli -i assets/tailwind.css -o static/css/tailwind.css --watch
```

Tailwind가 `static/css/tailwind.css`를 다시 쓰면 서버가 이를 복사하고 페이지를 새로 고칩니다. 통계 파일은 바뀌지 않으므로 반복이 멈춥니다.

## 동작 방식

1. Initialize 단계에서 파이프라인이 `source_dir`의 소스 파일을 읽습니다
2. 각 번들에 나열된 파일을 순서대로 이어 붙입니다
3. `minify`가 활성화되어 있으면 CSS/JS별 압축을 적용합니다(`.css`, `.js`, `.mjs` 번들 대상이며, 각 항목 앞의 UTF-8 BOM은 제거됩니다)
4. `fingerprint`가 활성화되어 있으면 확장자 앞에 8자리 SHA-256 해시를 삽입합니다
5. 출력은 빌드 디렉터리의 `{output_dir}/{output_name}`에 기록됩니다
6. 원본 이름과 출력 경로를 매핑한 매니페스트가 템플릿 해석용으로 저장됩니다

### 압축

내장 압축기는 보수적이고 안전하게 동작합니다.

**CSS:**
- 주석 제거(`/* ... */`)
- 공백 축소
- `{`, `}`, `:`, `;`, `,` 주변 공백 제거
- `}` 앞의 불필요한 세미콜론 제거

**JS:**
- 문자열 밖의 한 줄 주석(`// ...`) 제거
- 여러 줄 주석(`/* ... */`) 제거
- 문자열 리터럴 보존(작은따옴표, 큰따옴표, 템플릿)
- 빈 줄 제거

더 강한 압축이 필요하면 [빌드 훅](/ko/features/build-hooks/)에서 `esbuild`나 `terser` 같은 외부 도구를 사용합니다.

## 예시

### 기본 CSS 번들

```toml
[assets]
enabled = true

[[assets.bundles]]
name = "style.css"
files = ["css/normalize.css", "css/base.css", "css/layout.css"]
```

```html
<link rel="stylesheet" href="{{ asset(name='style.css') }}">
```

### 여러 번들

```toml
[assets]
enabled = true

[[assets.bundles]]
name = "vendor.css"
files = ["css/vendor/normalize.css", "css/vendor/highlight.css"]

[[assets.bundles]]
name = "site.css"
files = ["css/base.css", "css/components.css"]

[[assets.bundles]]
name = "app.js"
files = ["js/search.js", "js/nav.js"]
```

### 핑거프린트 없는 개발 설정

```toml
[assets]
enabled = true
minify = false
fingerprint = false

[[assets.bundles]]
name = "style.css"
files = ["css/style.css"]
```

## 함께 보기

- [캐시 버스팅](/ko/features/cache-busting/) — 파이프라인을 거치지 않는 에셋을 위한 쿼리 스트링 기반 캐시 무효화
- [자동 인클루드](/ko/features/auto-includes/) — 정적 디렉터리의 CSS/JS 자동 로드
- [빌드 훅](/ko/features/build-hooks/) — 빌드 전후 외부 도구 실행
- [템플릿 함수](/ko/templates/functions/#asset-integrity) — `asset()`과 `asset_integrity()`
