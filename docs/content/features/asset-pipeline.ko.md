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
| `source_dir` | string | `"static"` | 소스 파일이 있는 디렉터리 |
| `output_dir` | string | `"assets"` | 빌드 출력 내 출력 하위 디렉터리 |

### 번들 정의

`[[assets.bundles]]` 항목 하나가 출력 파일 하나를 정의합니다.

| 필드 | 타입 | 설명 |
|-------|------|-------------|
| `name` | string | 출력 파일명(예: `"main.css"`) |
| `files` | array | `source_dir` 기준 상대 경로의 소스 파일 |

파일은 나열한 순서대로 이어 붙입니다.

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

## 동작 방식

1. Initialize 단계에서 파이프라인이 `source_dir`의 소스 파일을 읽습니다
2. 각 번들에 나열된 파일을 순서대로 이어 붙입니다
3. `minify`가 활성화되어 있으면 CSS/JS별 압축을 적용합니다
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
