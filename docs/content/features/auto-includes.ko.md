+++
title = "자동 인클루드"
description = "CSS와 JS 파일을 모든 페이지에 자동으로 불러옵니다"
weight = 20
toc = true
+++

자동 인클루드는 지정한 정적 디렉터리의 CSS/JS 파일을 모든 페이지에 자동으로 불러옵니다. 에셋 파일을 하나하나 템플릿에 추가할 필요가 없어집니다.

## 설정

`config.toml`에서 활성화합니다.

```toml
[auto_includes]
enabled = true
dirs = ["assets/css", "assets/js"]
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | false | 자동 인클루드 활성화 |
| dirs | array | [] | 스캔할 `static/` 아래 디렉터리 |

## 디렉터리 구조

CSS와 JS 파일을 `static/`의 하위 디렉터리에 둡니다.

```
static/
├── assets/
│   ├── css/
│   │   ├── 01-reset.css
│   │   ├── 02-typography.css
│   │   └── 03-layout.css
│   └── js/
│       ├── 01-utils.js
│       └── 02-app.js
```

파일은 `static/{dir}/**/*.css`와 `static/{dir}/**/*.js` 패턴으로 재귀적으로 스캔됩니다.

## 파일 순서

파일은 **알파벳 순서**로 포함됩니다. 로드 순서를 제어하려면 숫자 접두사를 사용합니다.

```
assets/css/
├── 01-reset.css        ← loaded first
├── 02-typography.css
├── 03-layout.css
└── 99-overrides.css    ← loaded last
```

## 템플릿 변수

### CSS만

CSS 파일만 포함하려면 `<head>`에 넣습니다.

```jinja
<head>
  {{ auto_includes_css | safe }}
</head>
```

### JS만

JS 파일만 포함하려면 `</body>` 앞에 넣습니다.

```jinja
<body>
  ...
  {{ auto_includes_js | safe }}
</body>
```

### 전체 에셋

CSS와 JS를 한꺼번에 포함합니다.

```jinja
{{ auto_includes | safe }}
```

| 변수 | 설명 |
|----------|-------------|
| auto_includes_css | CSS 파일용 `<link>` 태그 |
| auto_includes_js | JS 파일용 `<script>` 태그 |
| auto_includes | CSS와 JS 태그 결합 |

## 생성되는 출력

위 예시 디렉터리 구조라면 템플릿 변수는 다음을 생성합니다.

**`auto_includes_css`:**

```html
<link rel="stylesheet" href="/assets/css/01-reset.css">
<link rel="stylesheet" href="/assets/css/02-typography.css">
<link rel="stylesheet" href="/assets/css/03-layout.css">
```

**`auto_includes_js`:**

```html
<script src="/assets/js/01-utils.js"></script>
<script src="/assets/js/02-app.js"></script>
```

## 전체 템플릿 예시

```jinja
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>{{ page.title }} - {{ site.title }}</title>
  {{ highlight_css | safe }}
  {{ auto_includes_css | safe }}
</head>
<body>
  {% block content %}{% endblock %}

  {{ highlight_js | safe }}
  {{ auto_includes_js | safe }}
</body>
</html>
```

## 팁

- **역할 분리**: 페이지 로딩을 최적화하려면 `auto_includes_css`는 `<head>`에, `auto_includes_js`는 `</body>` 앞에 둡니다.
- **여러 디렉터리**: 스캔할 디렉터리를 여러 개 나열할 수 있습니다. 각 디렉터리는 독립적으로 스캔됩니다.
- **겹치는 디렉터리 피하기**: 결과는 중복 제거되지 않습니다 — 설정된 두 디렉터리(예: `assets`와 `assets/css`)에서 모두 도달할 수 있는 파일은 디렉터리마다 한 번씩 포함되므로, 겹치지 않는 디렉터리만 나열합니다.
- **정적 파일 전용**: 자동 인클루드는 `static/` 디렉터리를 스캔합니다. `content/`의 파일은 포함되지 않습니다.

## 함께 보기

- [설정](/ko/start/config/) — 설정 전체 참조
- [구문 강조](/ko/features/syntax-highlighting/) — Highlight.js 에셋 포함
- [데이터 모델](/ko/templates/data-model/) — 에셋 템플릿 변수
