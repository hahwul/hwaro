+++
title = "페이지네이션"
description = "긴 콘텐츠 목록을 여러 페이지로 분할"
weight = 6
+++

긴 콘텐츠 목록을 여러 페이지로 나눕니다.

## 설정

### 사이트 전역 기본값

`config.toml`에서 기본 페이지네이션 동작을 설정합니다.

```toml
[pagination]
enabled = false
per_page = 10
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | false | 페이지네이션 전역 활성화 |
| per_page | int | 10 | 페이지당 기본 항목 수 |

### 섹션 페이지네이션

섹션 프론트 매터에서 활성화합니다.

```toml
+++
title = "Blog"
paginate = 10
paginate_path = "page"
+++
```

| 필드 | 타입 | 기본값 | 설명 |
|-------|------|---------|-------------|
| paginate | int | — | 페이지당 항목 수 |
| paginate_path | string | "page" | 페이지 URL 패턴 |

### 생성되는 URL

`/blog/` 섹션 기준:

| 페이지 | URL |
|------|-----|
| 1 | /blog/ |
| 2 | /blog/page/2/ |
| 3 | /blog/page/3/ |

`paginate_path = "p"`인 경우:

| 페이지 | URL |
|------|-----|
| 1 | /blog/ |
| 2 | /blog/p/2/ |
| 3 | /blog/p/3/ |

## 템플릿 변수

### pagination

미리 렌더링된 페이지네이션 HTML:

```jinja
{{ pagination | safe }}
```

### paginator

커스텀 렌더링을 위한 페이지네이션 객체:

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| paginator.paginate_by | Int | 페이지당 항목 수 |
| paginator.base_url | String | 페이지네이션 기준 URL |
| paginator.number_pagers | Int | 전체 페이저(페이지) 수 |
| paginator.first | String | 첫 페이저 URL |
| paginator.last | String | 마지막 페이저 URL |
| paginator.previous | String? | 이전 페이저 URL |
| paginator.next | String? | 다음 페이저 URL |
| paginator.pages | Array | 현재 페이저에 담긴 페이지 배열 |
| paginator.current_index | Int | 현재 페이저 인덱스(1부터 시작) |
| paginator.total_pages | Int | 전체 페이지 수 |

### pagination_obj

페이지네이션 마크업을 처음부터 직접 만들 수 있도록 개별 필드를 담은 구조화된 페이지네이션 객체:

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| pagination_obj.html | String | 미리 렌더링된 페이지네이션 HTML(`pagination`과 동일) |
| pagination_obj.current_page | Int | 현재 페이지 번호(1부터 시작) |
| pagination_obj.total_pages | Int | 전체 페이지 수 |
| pagination_obj.per_page | Int | 페이지당 항목 수 |
| pagination_obj.total_items | Int | 전체 페이지를 합친 항목 수 |
| pagination_obj.has_previous | Bool | 이전 페이지 존재 여부 |
| pagination_obj.has_next | Bool | 다음 페이지 존재 여부 |
| pagination_obj.previous_url | String | 이전 페이지 URL(없으면 빈 문자열) |
| pagination_obj.next_url | String | 다음 페이지 URL(없으면 빈 문자열) |
| pagination_obj.first_url | String | 첫 페이지 URL |
| pagination_obj.last_url | String | 마지막 페이지 URL |

```jinja
{% if pagination_obj.has_previous %}
  <a href="{{ pagination_obj.previous_url }}">← Newer</a>
{% endif %}
<span>Page {{ pagination_obj.current_page }} of {{ pagination_obj.total_pages }}</span>
{% if pagination_obj.has_next %}
  <a href="{{ pagination_obj.next_url }}">Older →</a>
{% endif %}
```

## 템플릿 예시

### 간단한 내비게이션

미리 렌더링된 `pagination` 변수를 사용합니다.

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ section.title }}</h1>

<ul>
{% for p in section.pages %}
  <li><a href="{{ p.url }}">{{ p.title }}</a></li>
{% endfor %}
</ul>

{{ pagination | safe }}
{% endblock %}
```

### 커스텀 페이지네이션

`paginator` 객체로 페이지네이션 UI를 직접 만듭니다.

```jinja
{% if paginator.number_pagers > 1 %}
<nav class="pagination">
  {% if paginator.current_index > 1 %}
  <a href="{{ paginator.first }}">« First</a>
  {% endif %}

  {% if paginator.previous %}
  <a href="{{ paginator.previous }}" class="prev">‹ Prev</a>
  {% endif %}

  <span class="current">
    Page {{ paginator.current_index }} of {{ paginator.number_pagers }}
  </span>

  {% if paginator.next %}
  <a href="{{ paginator.next }}" class="next">Next ›</a>
  {% endif %}

  {% if paginator.current_index < paginator.number_pagers %}
  <a href="{{ paginator.last }}">Last »</a>
  {% endif %}
</nav>
{% endif %}
```

## 페이지가 많을 때의 줄임표

페이지가 7개를 넘으면 내장 페이지네이션 내비게이션이 UI를 간결하게 유지하기 위해 줄임표(`...`)를 자동으로 넣습니다. 현재 페이지를 중심으로 페이지 번호 5개의 슬라이딩 윈도가 표시되고, 첫 페이지와 마지막 페이지는 항상 보입니다.

예를 들어 20페이지 중 5페이지에서는:

```
« Prev  1 ... 3  4  [5]  6  7 ... 20  Next »
```

## SEO 링크

Hwaro는 페이지네이션된 페이지에 `<link rel="prev">`와 `<link rel="next">` 태그를 생성합니다. `<head>`에 포함하면 됩니다.

```jinja
<head>
  {{ pagination_seo_links | safe }}
</head>
```

출력:

```html
<link rel="prev" href="https://example.com/blog/page/2/">
<link rel="next" href="https://example.com/blog/page/4/">
```

## 택소노미 페이지네이션

택소노미 항목 페이지는 `config.toml`의 `paginate_by`로 페이지네이션을 지원합니다.

```toml
[[taxonomies]]
name = "tags"
paginate_by = 20
```

각 항목 목록(예: `/tags/crystal/`)이 20개씩 페이지로 나뉘고, 이후 페이지는 `/tags/crystal/page/2/`에 생성됩니다. 택소노미 템플릿에서도 동일한 `pagination`, `paginator` 템플릿 변수를 사용할 수 있습니다.

## CSS 예시

```css
.pagination {
  display: flex;
  gap: 1rem;
  justify-content: center;
  margin: 2rem 0;
}

.pagination a {
  padding: 0.5rem 1rem;
  border: 1px solid #ddd;
  text-decoration: none;
}

.pagination a:hover {
  background: #f0f0f0;
}

.pagination .current {
  padding: 0.5rem 1rem;
  font-weight: bold;
}
```

## 함께 보기

- [섹션](/ko/writing/sections/) — 섹션 설정
- [택소노미](/ko/writing/taxonomies/) — 택소노미 페이지네이션
- [데이터 모델](/ko/templates/data-model/) — 섹션 변수
