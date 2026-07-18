+++
title = "시리즈"
description = "글을 순서 있는 시리즈로 묶어 차례대로 읽게 하기"
weight = 9
+++

관련 글을 순서 있는 시리즈로 묶어 독자가 콘텐츠를 차례대로 따라갈 수 있게 합니다.

## 설정

`config.toml`에서 활성화합니다.

```toml
[series]
enabled = true
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | false | 시리즈 묶기 활성화 |

## 시리즈에 글 지정

프론트 매터로 글을 시리즈에 지정합니다.

```toml
+++
title = "Part 1: Getting Started"
series = "Building a CLI Tool"
series_weight = 1
+++
```

| 필드 | 타입 | 기본값 | 설명 |
|-------|------|---------|-------------|
| series | string | — | 이 글이 속할 시리즈 이름 |
| series_weight | int | 0 | 시리즈 내 순서(낮을수록 앞) |

시리즈 안의 글은 `series_weight`, 날짜, 제목 순으로 정렬됩니다.

## 템플릿 변수

시리즈에 속한 각 페이지는 다음 변수를 갖습니다.

| 변수 | 타입 | 설명 |
|----------|------|-------------|
| series | string | 시리즈 이름 |
| series_index | int | 시리즈 내 위치(1부터 시작) |
| series_pages | array | 같은 시리즈의 모든 페이지(정렬됨) |

## 템플릿에서 사용

### 시리즈 내비게이션

```jinja
{% if series %}
<nav class="series-nav">
  <h3>{{ series }}</h3>
  <ol>
    {% for p in series_pages %}
    <li{% if p.url == page.url %} class="current"{% endif %}>
      <a href="{{ p.url }}">{{ p.title }}</a>
    </li>
    {% endfor %}
  </ol>
</nav>
{% endif %}
```

### 이전 / 다음 링크

```jinja
{% if series_pages | length > 1 %}
<div class="series-pager">
  {% if series_index > 1 %}
    <a href="{{ series_pages[series_index - 2].url }}">← Previous</a>
  {% endif %}
  <span>Part {{ series_index }} of {{ series_pages | length }}</span>
  {% if series_index < series_pages | length %}
    <a href="{{ series_pages[series_index].url }}">Next →</a>
  {% endif %}
</div>
{% endif %}
```

## 예시

글이 세 개 있다고 하면:

```
content/
  tutorials/
    cli-part1.md   # series = "CLI Tool", series_weight = 1
    cli-part2.md   # series = "CLI Tool", series_weight = 2
    cli-part3.md   # series = "CLI Tool", series_weight = 3
```

각 글의 `series_pages`에는 세 글이 순서대로 모두 담기고, `series_index`는 각각 1, 2, 3이 됩니다.

## 함께 보기

- [페이지](/ko/writing/pages/) — 시리즈용 프론트 매터 필드
- [관련 글](/ko/features/related-posts/) — 콘텐츠 추천
- [데이터 모델](/ko/templates/data-model/) — 시리즈 템플릿 변수
