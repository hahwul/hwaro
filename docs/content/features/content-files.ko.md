+++
title = "콘텐츠 파일"
description = "content 디렉터리의 마크다운 이외 파일 게시"
weight = 21
toc = true
+++

`content/` 디렉터리에 놓인 마크다운 이외 파일을 출력 디렉터리로 자동 게시할 수 있습니다. 이미지, PDF처럼 콘텐츠 옆에 함께 두는 에셋을 다룰 때 유용합니다.

## 설정

`config.toml`에서 콘텐츠 파일 게시를 활성화합니다:

```toml
[content.files]
allow_extensions = ["jpg", "jpeg", "png", "gif", "svg", "webp", "pdf"]
disallow_extensions = ["psd", "ai"]
disallow_paths = ["drafts/**", "**/_*"]
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| allow_extensions | array | [] | 게시할 파일 확장자 |
| disallow_extensions | array | [] | 제외할 파일 확장자 |
| disallow_paths | array | [] | 제외할 경로의 글롭(glob) 패턴 |

## 동작 방식

콘텐츠 파일 게시가 활성화되면 Hwaro는 `content/`의 마크다운 이외 파일을 디렉터리 구조를 유지한 채 출력 디렉터리로 복사합니다.

### 예시

```
content/
├── about/
│   ├── index.md          → /about/index.html
│   ├── team-photo.jpg    → /about/team-photo.jpg
│   └── resume.pdf        → /about/resume.pdf
├── blog/
│   ├── _index.md         → /blog/index.html
│   └── my-post/
│       ├── index.md      → /blog/my-post/index.html
│       ├── diagram.svg   → /blog/my-post/diagram.svg
│       └── screenshot.png → /blog/my-post/screenshot.png
└── index.md              → /index.html
```

파일은 대응하는 출력 경로로 그대로 복사되며, `content/` 접두사는 자동으로 제거됩니다.

## 확장자 매칭

### 허용 목록

`allow_extensions`에 있는 확장자의 파일만 게시됩니다:

```toml
[content.files]
allow_extensions = ["jpg", "jpeg", "png", "gif", "svg", "webp"]
```

확장자는 정규화되므로 `"jpg"`와 `".jpg"` 둘 다 쓸 수 있습니다.

### 차단 목록

`disallow_extensions`로 특정 확장자를 제외합니다:

```toml
[content.files]
allow_extensions = ["jpg", "png", "gif", "svg"]
disallow_extensions = ["psd", "ai", "sketch"]
```

차단 목록이 허용 목록보다 우선합니다.

### 경로 제외

글롭 문법으로 경로 패턴에 맞는 파일을 제외합니다:

```toml
[content.files]
disallow_paths = ["drafts/**", "**/_*", "private/**"]
```

| 패턴 | 매칭 대상 |
|---------|---------|
| `drafts/**` | `content/drafts/` 아래 모든 파일 |
| `**/_*` | 밑줄로 시작하는 모든 파일 |
| `private/**` | `content/private/` 아래 모든 파일 |

경로는 `content/` 디렉터리 기준 상대 경로로 매칭됩니다.

## 콘텐츠 파일 참조

### 마크다운에서

같은 위치에 둔 파일은 상대 경로로 참조합니다:

```markdown
![Team Photo](team-photo.jpg)

[Download Resume](resume.pdf)

![Diagram](diagram.svg)
```

### 템플릿에서

페이지 번들에서는 함께 둔 에셋을 `page.assets`로도 쓸 수 있습니다:

```jinja
{% for asset in page.assets %}
  {% if asset is matching("[.](jpg|png|gif)$") %}
    <img src="{{ get_url(path=asset) }}" alt="Asset">
  {% endif %}
{% endfor %}
```

## 콘텐츠 파일 vs 정적 파일

| 항목 | 콘텐츠 파일 (`content/`) | 정적 파일 (`static/`) |
|---------|---------------------------|--------------------------|
| 콘텐츠와 같은 위치에 배치 | ✅ 가능 | ❌ 불가 |
| 설정 필요 | ✅ 필요 | ❌ 불필요 (기본으로 복사, 불필요 파일은 필터링) |
| 확장자 필터링 | ✅ 지원 | ❌ 미지원 |
| 경로 필터링 | ✅ 지원 (`disallow_paths`) | ✅ 지원 (`[static]` `exclude`) |
| 적합한 용도 | 페이지별 에셋 | 사이트 전역 에셋 |

특정 페이지에 속한 에셋(스크린샷, 다이어그램, 첨부 파일)에는 **콘텐츠 파일**을, 사이트 전역 에셋(CSS, JS, 로고, 파비콘)에는 **정적 파일**을 사용합니다. 불필요한 파일이나 특정 경로를 제외하는 방법은 [설정](/ko/start/config/)의 `[static]` 섹션을 참고하면 됩니다.

## 팁

- **페이지 번들**: 구성을 깔끔하게 유지하려면 [페이지 번들](/ko/writing/pages/)을 사용합니다 — `index.md`와 그 에셋을 한 디렉터리에 함께 둡니다.
- **이미지 포맷**: 일반적인 웹 이미지 포맷을 포함합니다: `["jpg", "jpeg", "png", "gif", "svg", "webp"]`.
- **보안**: `disallow_paths`로 소스 파일이나 초안이 게시되지 않게 막습니다.
- **최소한만 허용**: 실제로 필요한 확장자만 허용합니다. 대용량 소스 파일이 실수로 게시되는 일을 막을 수 있습니다.

## 함께 보기

- [이미지 처리](/ko/features/image-processing/) — 자동 이미지 리사이즈
- [페이지](/ko/writing/pages/) — 페이지 번들과 에셋 배치
- [섹션](/ko/writing/sections/) — 섹션 에셋
- [설정](/ko/start/config/) — 전체 설정 레퍼런스
