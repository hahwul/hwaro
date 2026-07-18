+++
title = "섹션"
description = "디렉터리 섹션으로 관련 콘텐츠 묶기"
weight = 2
toc = true
+++

섹션은 관련 콘텐츠를 묶는 디렉터리입니다. `_index.md` 파일이 필요합니다.

## 섹션 생성

```
content/
└── blog/
    ├── _index.md     # Section index → /blog/
    ├── first.md      # Page → /blog/first/
    └── second.md     # Page → /blog/second/
```

## 섹션 인덱스

모든 섹션에는 `_index.md`가 필요합니다:

```markdown
+++
title = "Blog"
description = "Latest articles"
sort_by = "date"
+++

Welcome to my blog.
```

## 프론트 매터

| 필드 | 타입 | 기본값 | 설명 |
|-------|------|---------|-------------|
| title | string | — | 섹션 제목(필수) |
| description | string | — | 섹션 설명 |
| template | string | "section" | 사용할 템플릿 |
| page_template | string | — | 하위 페이지의 기본 템플릿 |
| sort_by | string | "date" | 정렬 기준: date, weight, title ([정렬 방향](#정렬-방향) 참고) |
| reverse | bool | false | 기본 정렬 방향 뒤집기 ([정렬 방향](#정렬-방향) 참고) |
| paginate | int | — | 한 페이지에 표시할 항목 수 |
| paginate_path | string | "page" | 페이저 URL의 경로 세그먼트(기본값이면 `/blog/page/2/` 형태) |
| transparent | bool | false | 페이지를 상위 섹션으로 넘김 |
| generate_feeds | bool | false | RSS 피드 생성 |
| redirect_to | string | — | 섹션을 렌더링하는 대신 이 URL로 가는 HTML 리다이렉트 페이지 생성 |
| draft | bool | false | 프로덕션에서 제외 |
| weight | int | 0 | 섹션 정렬 순서 |
| cascade | table | — | 하위 항목이 상속하는 기본값 ([캐스케이드](#캐스케이드) 참고) |

## 캐스케이드

섹션의 `[cascade]` 테이블은 그 아래 모든 페이지와 섹션의 프론트 매터 기본값을 정합니다. 페이지 자신의 프론트 매터가 항상 우선하고, 더 깊은 캐스케이드가 얕은 캐스케이드를 덮어씁니다. 캐스케이드를 선언한 섹션 자신은 영향을 받지 않습니다.

```toml
+++
title = "Blog"

[cascade]
template = "post"
tags = ["blog"]

[cascade.extra]
banner = "default-banner.png"
+++
```

이제 이 섹션 아래 모든 페이지는 `post` 템플릿으로 렌더링되고, `blog` 태그를 가지며, `page.extra.banner`를 노출합니다 — 페이지가 해당 필드를 직접 지정하지 않았을 때에 한합니다. `extra`와 `taxonomies`는 키 단위로 병합됩니다: 페이지 자신의 키가 우선하고, 캐스케이드된 키가 빈자리를 채웁니다.

캐스케이드 가능한 키: `template`, `draft`, `render`, `toc`, `insert_anchor_links`, `in_sitemap`, `in_search_index`, `tags`, `taxonomies`, `authors`, `extra`. URL에 영향을 주는 키(`slug`, `path`, `aliases`)는 캐스케이드할 수 없으며 경고와 함께 무시됩니다.

다국어 사이트에서 캐스케이드는 자기 언어 트리 안에서만 적용됩니다 — `_index.ko.md`는 `.ko` 페이지에, `_index.md`는 기본 언어 페이지에 캐스케이드됩니다.

## 정렬 방향

`sort_by` 값마다 자연스러운 기본 방향이 다르며, 작성자가 보통 기대하는 방향에 맞춰져 있습니다:

| `sort_by` | 기본 순서 | `reverse = true`일 때 |
|-----------|---------------|------------------------|
| `date`    | 최신순(내림차순) | 오래된 순 |
| `weight`  | 낮은 weight 우선(오름차순) | 높은 weight 우선 |
| `title`   | A → Z(오름차순) | Z → A |

`reverse`는 선택한 `sort_by`의 자연스러운 방향을 그대로 뒤집습니다. 예를 들어 `date`로 정렬한 블로그 인덱스는 기본이 최신순이고, `reverse = true`를 주면 오래된 순으로 바뀝니다.

```toml
+++
title = "Blog"
sort_by = "date"
# reverse = false (기본값) → 최신순
# reverse = true           → 오래된 순
+++
```

## 예시

### 페이지네이션이 있는 블로그

```toml
+++
title = "Blog"
sort_by = "date"
paginate = 10
paginate_path = "p"
+++
```

생성 결과: `/blog/`, `/blog/p/2/`, `/blog/p/3/`

기본값 `paginate_path = "page"`를 쓰면 URL은 `/blog/page/2/`, `/blog/page/3/`, … 형태가 됩니다 — 1페이지는 항상 섹션 URL에 그대로 있습니다.

### 문서

```toml
+++
title = "Docs"
page_template = "doc-page"
sort_by = "weight"
+++
```

모든 페이지가 `doc-page.html` 템플릿을 사용하고 weight 순으로 정렬됩니다.

### 피드가 있는 섹션

```toml
+++
title = "News"
generate_feeds = true
+++
```

`/news/rss.xml`을 생성합니다.

## 전체 프론트 매터 레퍼런스

모든 필드를 한 블록에 모았습니다. 복사한 뒤 필요 없는 항목을 지우면 됩니다.

```toml
+++
title = "Section Title"
description = "Section description"
template = "section"
page_template = "custom-page"
sort_by = "date"
reverse = false
paginate = 10
paginate_path = "page"
transparent = false
generate_feeds = true
redirect_to = ""
draft = false
weight = 0
+++
```

## 중첩 섹션

섹션은 다른 섹션을 포함할 수 있습니다:

```
content/
└── docs/
    ├── _index.md           # /docs/
    ├── getting-started/
    │   ├── _index.md       # /docs/getting-started/
    │   └── install.md      # /docs/getting-started/install/
    └── guides/
        ├── _index.md       # /docs/guides/
        └── deploy.md       # /docs/guides/deploy/
```

템플릿에서 하위 섹션에 접근:

```jinja
{% for sub in section.subsections %}
<a href="{{ sub.url }}">{{ sub.title }}</a>
<small>({{ sub.pages_count }})</small>
{% endfor %}
```

## 템플릿 변수

섹션 페이지(`_index.md`)를 렌더링할 때 다음 변수를 쓸 수 있습니다:

| 변수 | 타입 | 설명 |
|----------|------|-------------|
| section.title | String | 현재 섹션 제목 |
| section.description | String | 현재 섹션 설명 |
| section.pages | Array<Page> | 현재 섹션 목록에 표시되는 페이지 |
| section.pages_count | Int | `section.pages`의 항목 수 |
| section.list | String | 미리 렌더링된 HTML 목록(`section_list`와 동일한 값) |
| section.subsections | Array<Section> | 직계 하위 섹션(`title`, `description`, `url`, `pages_count`) |
| section.assets | Array<String> | 섹션과 함께 둔 에셋 |
| section.page_template | String | 하위 페이지의 기본 템플릿 이름 |
| section.paginate_path | String | 페이지네이션 경로 세그먼트 |
| section.redirect_to | String | 설정된 경우 리다이렉트 대상 |
| section_list | String | `section.list`와 동일 |
| pagination | String | 미리 렌더링된 페이지네이션 HTML |
| paginator | Object | 구조화된 페이지네이션 객체 — [데이터 모델 › Paginator](/ko/templates/data-model/) 참고 |

현재 섹션 URL은 `page.url`을 사용합니다.

### `section.list` / `section_list`

```jinja
<ul class="auto-list">
  {{ section.list | safe }}
</ul>
```

`paginator`로 커스텀 페이지네이션 UI를 만드는 방법은 [데이터 모델 › Paginator](/ko/templates/data-model/)를 참고합니다.

## 투명 섹션

`transparent = true`를 주면 페이지가 상위 섹션에 합쳐집니다:

```toml
+++
title = "2024 Posts"
transparent = true
+++
```

페이지가 상위 섹션의 `section.pages` 목록에 나타납니다.

## 에셋 코로케이션

일반 페이지처럼 섹션에도 에셋을 함께 둘 수 있습니다. 마크다운이 아닌 파일을 `_index.md`와 같은 디렉터리에 넣으면 됩니다.

**구조 예시:**

```text
content/
└── gallery/
    ├── _index.md       <-- The section index
    ├── banner.jpg      <-- Section asset
    └── icon.png        <-- Section asset
```

이 에셋은 섹션 기준 상대 위치로 출력 디렉터리에 복사됩니다.

### 템플릿에서 에셋 접근

템플릿에서는 `section.assets`로 섹션 에셋 목록에 접근합니다. 파일의 상대 경로 배열(콘텐츠 디렉터리 기준)을 반환합니다.

```jinja
<!-- In section.html -->
<div class="gallery">
  {% for asset in section.assets %}
    <img src="{{ get_url(path=asset) }}" alt="Section Asset">
  {% endfor %}
</div>
```

## 섹션 vs 페이지

| 파일 | 유형 | URL |
|------|------|-----|
| _index.md | 섹션 인덱스 | `/blog/` |
| index.md | 일반 페이지 | `/blog/` |

하위 페이지 목록이 필요하면 `_index.md`를 사용합니다.

## 함께 보기

- [페이지](/ko/writing/pages/) — 개별 콘텐츠 파일과 프론트 매터
- [택소노미](/ko/writing/taxonomies/) — 태그와 카테고리로 콘텐츠 분류
- [데이터 모델](/ko/templates/data-model/) — 템플릿에서의 섹션 속성
