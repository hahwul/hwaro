+++
title = "페이지"
description = "프론트 매터 메타데이터가 있는 마크다운으로 페이지 생성"
weight = 1
toc = true
+++

페이지는 사이트의 HTML 페이지가 되는 마크다운 파일입니다. 이 문서는 **콘텐츠 작성 방법** — 프론트 매터 필드, 마크다운 문법, 파일 구성을 다룹니다. 이 필드를 템플릿에서 읽는 방법은 [데이터 모델](/ko/templates/data-model/)을 참고합니다.

## 기본 구조

```markdown
+++
title = "My Page"
date = "2024-01-15"
+++

Your content in **Markdown**.
```

`+++` 블록이 TOML 프론트 매터입니다. YAML(`---` 구분자)과 JSON(파일 맨 앞의 최상위 `{...}` 객체)도 지원합니다. 그 아래 내용이 HTML로 변환됩니다.

```markdown
---
title: "My Page"
date: "2024-01-15"
---

Your content in **Markdown**.
```

```markdown
{
  "title": "My Page",
  "date": "2024-01-15"
}

Your content in **Markdown**.
```

JSON은 파일 맨 앞에서 처음으로 짝이 맞는 `{...}`가 프론트 매터가 되며, 별도 구분자가 필요 없습니다. 파일은 반드시 `{`로 시작해야 합니다(앞 공백 불가).

## 프론트 매터

### 필수

| 필드 | 타입 | 설명 |
|-------|------|-------------|
| title | string | 페이지 제목 |

### 주요 필드

| 필드 | 타입 | 기본값 | 설명 |
|-------|------|---------|-------------|
| date | string | — | 발행일. `YYYY-MM-DD`, 시간 포함 가능(`YYYY-MM-DD HH:MM:SS` 또는 RFC 3339 datetime). 따옴표 없는 TOML/YAML 날짜도 허용 |
| description | string | — | SEO 설명 |
| draft | bool | false | 프로덕션 빌드에서 제외 |
| template | string | "page" | 사용할 템플릿 |
| weight | int | 0 | 정렬 순서(낮을수록 앞) |
| image | string | — | 소셜 공유용 대표 이미지 |
| tags | array | [] | 태그 택소노미 항목 |
| categories | array | [] | 카테고리 택소노미 항목 |

### 전체 필드

| 필드 | 타입 | 설명 |
|-------|------|-------------|
| updated | string | 마지막 수정일 |
| slug | string | 커스텀 URL 슬러그 |
| path | string | 커스텀 URL 경로 |
| aliases | array | 이 페이지로 리다이렉트할 URL 목록 |
| authors | array | 작성자 이름 |
| toc | bool | 목차 표시 |
| in_search_index | bool | 검색 포함 여부 |
| in_sitemap | bool | 사이트맵 포함 여부 |
| insert_anchor_links | bool | 헤딩 앵커 추가 |
| redirect_to | string | 페이지를 이 URL로 리다이렉트 |
| render | bool | 페이지를 출력으로 렌더링(기본값: true) |
| expires | date | 이 날짜 이후 자동 제외 |
| series | string | 묶음용 시리즈 이름 |
| series_weight | int | 시리즈 내 정렬 순서 |
| extra | table | 커스텀 메타데이터 |

## 예시

### 블로그 글

```markdown
+++
title = "Getting Started with Crystal"
date = "2024-01-15"
description = "Learn Crystal programming basics"
tags = ["crystal", "tutorial"]
authors = ["Alice Smith"]
image = "/images/crystal-guide.png"
+++

Crystal is a fast, compiled language...
```

### 초안

```markdown
+++
title = "Work in Progress"
draft = true
+++

Not visible in production.
```

초안 포함 빌드: `hwaro build --drafts`

### 만료 콘텐츠

```markdown
+++
title = "Limited Time Offer"
expires = 2025-12-31
+++

Automatically excluded from builds after the expiry date.
```

만료된 콘텐츠 포함 빌드: `hwaro build --include-expired`

만료까지 7일 이내인 페이지는 빌드 경고를 냅니다.

### 미래 날짜 콘텐츠

`date`가 미래인 페이지는 빌드에서 자동으로 빠집니다. 콘텐츠 예약 발행에 유용합니다.

```markdown
+++
title = "Coming Soon"
date = 2099-01-01
+++

Published only after the date arrives.
```

미래 콘텐츠 포함 빌드: `hwaro build --include-future`

### 시리즈 글

```markdown
+++
title = "Part 1: Introduction"
series = "Crystal Tutorial"
series_weight = 1
+++

First part of the series.
```

`config.toml`에서 `[series]`를 켜면 빌드 시점에 `page.series_index`(1부터 시작하는 위치)와 `page.series_pages`(시리즈의 전체 페이지)가 계산됩니다. 둘 다 템플릿 전용 값이며 프론트 매터 필드가 아닙니다. [데이터 모델](/ko/templates/data-model/)을 참고합니다.

### 커스텀 템플릿

```markdown
+++
title = "Landing Page"
template = "landing"
+++

Uses `templates/landing.html` instead of `page.html`.
```

### 가중치 정렬

```markdown
+++
title = "Introduction"
weight = 1
+++
```

```markdown
+++
title = "Getting Started"
weight = 2
+++
```

weight가 낮을수록 앞에 옵니다.

### URL 별칭

```markdown
+++
title = "New Page"
aliases = ["/old-url/", "/another-old-url/"]
+++

Redirects from old URLs to this page.
```

### 커스텀 메타데이터

```markdown
+++
title = "Product Review"

[extra]
rating = 4.5
featured = true
pros = ["Fast", "Reliable"]
+++
```

템플릿에서 접근: `{{ page.extra.rating }}`

## 전체 프론트 매터 레퍼런스

모든 필드를 한 블록에 모았습니다. 복사한 뒤 필요 없는 항목을 지우면 됩니다.

```toml
+++
title = "Page Title"
date = "2024-01-15"
updated = "2024-02-01"
description = "SEO description"
draft = false
template = "page"
weight = 0
slug = "custom-slug"
path = "custom/path"
aliases = ["/old-url/"]
image = "/images/cover.png"
tags = ["tag1", "tag2"]
categories = ["category1"]
authors = ["Author Name"]
toc = true
in_search_index = true
in_sitemap = true
insert_anchor_links = true
render = true
redirect_to = ""
expires = 2025-12-31
series = "Series Name"
series_weight = 1

[extra]
custom_field = "value"
+++
```

## 콘텐츠 요약

`<!-- more -->`로 요약 범위를 지정합니다:

```markdown
+++
title = "Long Article"
+++

This is the summary shown in listings.

<!-- more -->

The full article continues here...
```

## 마크다운 문법

### 텍스트

```markdown
**bold** and *italic*
`inline code`
[link](https://example.com)
![image](/img.jpg)
```

### 목록

```markdown
- Unordered
- Items

1. Ordered
2. Items
```

### 코드 블록

````markdown
```javascript
console.log("Hello");
```
````

### 표

```markdown
| Header | Header |
|--------|--------|
| Cell   | Cell   |
```

표 셀 안에서도 인라인 마크다운이 동작합니다: **굵게**, *기울임*, `코드 스팬`, `[links](url)`, `![images](url)`, ~~취소선~~.

```markdown
| Feature        | Example                          |
|----------------|----------------------------------|
| Bold           | **important**                    |
| Italic         | *emphasis*                       |
| Code           | `config.toml`                    |
| Link           | [Hwaro](https://example.com)     |
| Image          | ![logo](/img/logo.png)           |
| Strikethrough  | ~~deprecated~~                   |
```

### 내부 링크

`@/`를 사용하면 다른 콘텐츠 페이지를 소스 경로로 링크할 수 있습니다. Hwaro가 빌드 시점에 올바른 출력 URL로 변환합니다.

```markdown
[Read the post](@/blog/my-post.md)
[About section](@/about/_index.md)
[With anchor](@/blog/my-post.md#introduction)
```

최종 URL을 몰라도 된다는 점이 장점입니다 — Hwaro가 콘텐츠 경로에서 URL을 계산합니다. 대상 페이지가 없으면 링크는 그대로 남고 빌드 중 경고가 기록됩니다.

| 문법 | 변환된 URL |
|--------|-------------|
| `@/blog/post.md` | `/blog/post/` |
| `@/blog/_index.md` | `/blog/` |
| `@/blog/post.md#section` | `/blog/post/#section` |

#### 엄격 모드

경고에서 그치지 않고 빌드를 실패시키려면 `config.toml`에서 켭니다:

```toml
[links]
broken_internal = "error"  # 기본값: "warn"
```

error 모드에서는 모든 페이지의 미해결 `@/` 링크를 모아 하나의 목록(`source.md → @/target (reason)`)으로 출력하며 빌드가 실패하고, CI용 종료 코드 5로 매핑됩니다. `hwaro serve` 중에는 실패가 에러 오버레이에 표시되고 서버는 계속 동작합니다.

`--cache` 사용 시 주의: 웜 빌드에서는 다시 렌더링된 페이지만 재검사하므로, 변경되지 않은 페이지 안의 깨진 링크는 그 페이지가 다시 렌더링될 때까지 드러나지 않습니다. 완전한 검사를 위해 CI에서는 `--cache` 없이 콜드 빌드를 실행합니다.

### 인용문

```markdown
> Quote text
```

### 어드모니션

GitHub 스타일 알림 블록(admonition)이 스타일이 적용된 콜아웃으로 렌더링됩니다. 인식하는 타입: `NOTE`, `TIP`, `IMPORTANT`, `WARNING`, `CAUTION`.

```markdown
> [!NOTE]
> Pay attention to this paragraph.

> [!WARNING]
>
> Body can also live in its own paragraph.
```

출력은 `<div class="admonition admonition-{type}">`이며, 제목 문단(`<p class="admonition-title">`) 뒤에 본문이 이어집니다. 스타일은 사이트 CSS에서 지정합니다 — Hwaro는 시맨틱 마크업만 내보냅니다.

`config.toml`의 `[markdown]` 아래에 `admonitions = false`를 두면 비활성화됩니다.

제한 사항: 타입은 대소문자를 구분하며(`[!NOTE]`만 인식, `[!note]`는 안 됨), 어드모니션 본문 안에 중첩된 인용문이 있으면 바깥 어드모니션이 일찍 닫힙니다. 인라인 이스케이프는 없습니다 — 백슬래시 이스케이프(`\[!NOTE\]`)도 같은 문자를 렌더링하면서 여전히 어드모니션을 발동시키므로, 토큰을 문자 그대로 출력해야 한다면 기능 자체를 끄면 됩니다.

### 커스텀 헤딩 ID

헤딩 줄 끝에 `{#custom-id}`를 붙이면 자동 생성 슬러그를 덮어씁니다. 제목을 고쳐도 깨지지 않는 안정적인 앵커 URL이 필요할 때 유용합니다.

```markdown
## Installation Guide {#install}
```

`<h2 id="install">Installation Guide</h2>`로 렌더링됩니다. 목차와 `[link](#install)` 링크 모두 커스텀 id를 사용합니다.

id에 허용되는 문자: 영문자, 숫자, `_`, `-`, `:`. id는 영문자로 시작해야 합니다. CommonMark는 ATX 헤딩 앞에 공백을 3칸까지 허용하며, 더 깊이 들여 쓰면 그 줄이 코드 블록이 되어 `{#id}`가 적용되지 않습니다.

`config.toml`의 `[markdown]` 아래에 `heading_ids = false`를 두면 비활성화됩니다.

커스텀 헤딩 ID에는 `markdown.safe = false`가 필요합니다. safe 모드에서는 `{#id}` 문법이 출력에서 제거되고 id도 적용되지 않습니다 — safe 모드와 명시적 id가 동시에 필요하면 raw HTML 헤딩을 사용합니다. 한 페이지에 같은 `{#id}`를 두 번 쓰면 id 속성이 중복되며, 앵커는 첫 번째가 우선합니다.

`{#id}` 단축 문법은 더 일반적인 `{#id .class key=val}` 속성 블록(`[markdown] attributes = true`)의 특수한 경우이며, 속성 블록은 인라인 이미지에도 적용됩니다. [마크다운 확장](/ko/features/markdown-extensions/)을 참고합니다.

### 정의 목록

```markdown
Term
: Definition body

Another term
: Definition with **bold**, *italic*, `code`, [a link](https://example.com), and ~~strikethrough~~
: A second definition for the same term
```

용어와 정의 양쪽에서 인라인 마크다운이 동작합니다. raw HTML은 안전을 위해 이스케이프됩니다.

## 에셋 코로케이션

이미지, PDF 같은 관련 에셋을 콘텐츠 파일과 같은 디렉터리에 함께 둘 수 있습니다. 이를 **페이지 번들(Page Bundle)**이라고 부릅니다.

이 기능을 쓰려면 마크다운 파일 이름을 `index.md`(일반 페이지) 또는 `_index.md`(섹션 페이지)로 바꾸고, 페이지 이름을 딴 디렉터리 안에 넣습니다.

**구조 예시:**

```text
content/
└── blog/
    ├── my-trip/
    │   ├── index.md        <-- The page content
    │   ├── photo.jpg       <-- Asset
    │   └── data.json       <-- Asset
    └── _index.md
```

Hwaro는 페이지 번들 디렉터리의 마크다운이 아닌 파일 전부를 상대 경로를 유지한 채 출력 디렉터리로 복사합니다.

마크다운에서는 상대 경로로 이 에셋에 링크하면 됩니다:

```markdown
![My Trip Photo](photo.jpg)

[Download Data](data.json)
```

### 템플릿에서 에셋 접근

템플릿에서는 `page.assets`로 함께 둔 에셋 목록에 접근합니다. 파일의 상대 경로 배열을 반환합니다.

```jinja
{% for asset in page.assets %}
  {% if asset is matching("[.](jpg|png)$") %}
    <img src="{{ get_url(path=asset) }}" alt="Gallery Image">
  {% endif %}
{% endfor %}
```

## URL 매핑

| 파일 | URL |
|------|-----|
| content/index.md | `/` |
| content/about.md | `/about/` |
| content/blog/post.md | `/blog/post/` |

## 함께 보기

- [섹션](/ko/writing/sections/) — 관련 페이지 묶기
- [데이터 모델](/ko/templates/data-model/) — 템플릿에서의 페이지 속성
