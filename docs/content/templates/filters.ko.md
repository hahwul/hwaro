+++
title = "필터"
description = "파이프 연산자로 템플릿의 값 변환"
weight = 4
toc = true
+++

필터는 템플릿에서 값을 변환합니다. 파이프 `|` 연산자로 적용합니다.

Hwaro는 표준 Crinja(Jinja2) 내장 필터 — `upper`, `lower`, `join`, `map`, `select`, `batch` 등 — 위에 자체 필터를 얹어 제공하므로, 아래 어디서든 두 종류 모두 사용할 수 있습니다.

## 문법

```jinja
{{ value | filter }}
{{ value | filter(arg="value") }}
{{ value | filter1 | filter2 }}
```

## 텍스트 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| upper | 대문자로 변환 | {{ "hello" \| upper }} → HELLO |
| lower | 소문자로 변환 | {{ "HELLO" \| lower }} → hello |
| capitalize | 첫 글자를 대문자로 | {{ "hello" \| capitalize }} → Hello |
| trim | 앞뒤 공백 제거 | {{ "  hi  " \| trim }} → hi |
| replace | 텍스트 치환 | {{ "hello" \| replace("l", "x") }} → hexxo |
| slugify | URL 슬러그로 변환 | {{ "Hello World" \| slugify }} → hello-world |
| truncate_words | 단어 수 제한. `end`로 말줄임 문자 지정(기본 `...`) | {{ text \| truncate_words(20, end="…") }} |

## HTML 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| safe | HTML을 이스케이프하지 않음 | {{ content \| safe }} |
| strip_html | HTML 태그 제거 | {{ html \| strip_html }} |
| markdownify | 마크다운 렌더링 | {{ text \| markdownify }} |
| xml_escape | XML 이스케이프 | {{ text \| xml_escape }} |

`markdownify`는 사이트의 [`[markdown]`](/ko/features/markdown-extensions/)
설정 중 safe 모드와 `smart_punctuation`을 따르므로, 같은 텍스트가 페이지
본문에서 렌더링되는 결과와 일치합니다. 나머지 확장 파이프라인(각주, 정의
목록, 컨테이너 등)은 적용되지 않습니다.

## 배열 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| length | 길이 | {{ items \| length }} |
| first | 첫 요소 | {{ items \| first }} |
| last | 마지막 요소 | {{ items \| last }} |
| reverse | 순서 뒤집기 | {{ items \| reverse }} |
| sort | 배열 정렬 | {{ items \| sort }} |
| join | 요소 이어 붙이기 | {{ tags \| join(", ") }} |
| split | 문자열 분할 | {{ "a,b,c" \| split(pat=",") }} |
| where | 필드 값으로 객체 필터링 | {{ posts \| where(attribute="draft", value=false) }} |
| sort_by | 필드로 객체 정렬 | {{ posts \| sort_by(attribute="date", reverse=true) }} |
| group_by | 필드로 객체 그룹화 | {{ posts \| group_by(attribute="section") }} |

## 컬렉션 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| unique | 중복 제거 | {{ items \| unique }} |
| flatten | 중첩 배열 평탄화 | {{ nested \| flatten }} |
| compact | nil/빈 값 제거 | {{ items \| compact }} |

## 수학 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| ceil | 올림하여 정수로 | {{ 3.2 \| ceil }} → 4 |
| floor | 내림하여 정수로 | {{ 3.8 \| floor }} → 3 |

## i18n 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| t | 키 번역 | {{ "nav.home" \| t }} |
| pluralize | 단수/복수형 선택 | {{ count \| pluralize(singular="item", plural="items") }} |

`t` 필터는 `i18n/` 디렉터리의 TOML 파일에서 번역 키를 찾습니다. 현재 페이지의 언어를 먼저 보고 기본 언어로 폴백하며, 번역이 없으면 키 자체를 반환합니다. i18n 파일 구성은 [다국어](/ko/features/multilingual/)를 참고합니다.

## 디버그 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| inspect | 디버그용 표현 | {{ value \| inspect }} |

## URL 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| absolute_url | base를 포함한 전체 URL | {{ "/about/" \| absolute_url }} |
| relative_url | base_url 접두사 추가 | {{ "/img.png" \| relative_url }} |
| active_path | 이 URL이 현재 페이지(또는 그 상위)인지 | {{ item.url \| active_path }} |

`active_path`는 URL(보통 [메뉴](/ko/features/menus/) 엔트리의 `item.url`)을 현재 페이지와 비교합니다. 기본은 정확히 일치할 때만 참이고, `ancestor=true`를 넘기면 하위 페이지도 매칭합니다.

```jinja
<a href="{{ item.href }}"{% if item.url | active_path %} aria-current="page"{% endif %}>{{ item.name }}</a>
<a href="{{ item.href }}"{% if item.url | active_path(ancestor=true) %} class="open"{% endif %}>{{ item.name }}</a>
```

비교 전에 양쪽 모두 끝 슬래시 하나로 정규화되므로 `/posts`와 `/posts/`는 같습니다. 루트 경로(`/`)는 `ancestor=true`여도 정확히 일치할 때만 매칭됩니다. 외부 `item.url`(`http://`, `https://`, `//`)은 절대 매칭되지 않습니다.

## 데이터 필터

| 필터 | 설명 | 예시 |
|--------|-------------|---------|
| default | 폴백 값 | {{ value \| default(value="N/A") }} |
| jsonify | JSON 인코딩 | {{ data \| jsonify }} |
| date | 날짜 포맷 | {{ page.date \| date("%Y-%m-%d") }} |

## 예시

### safe 필터

렌더링된 콘텐츠에는 항상 `safe`를 사용합니다.

```jinja
{{ content | safe }}
{{ og_tags | safe }}
{{ toc | safe }}
```

### 기본값

```jinja
{{ page.description | default(value=site.description) }}
{{ page.image | default(value="/images/default.png") }}
```

### 날짜 포맷

```jinja
<time>{{ page.date | date("%B %d, %Y") }}</time>
```

포맷 코드:
- `%Y` — 연도(2024)
- `%m` — 월(01-12)
- `%d` — 일(01-31)
- `%B` — 월 이름(January)
- `%b` — 월 축약형(Jan)

### URL 처리

```jinja
<a href="{{ page.url | absolute_url }}">Permalink</a>
<img src="{{ "/logo.png" | relative_url }}">
```

### 문자열과 체이닝

```jinja
{{ page.title | lower | slugify }}
{{ content | strip_html | truncate_words(100) }}
{{ description | default(value="No description") | upper }}

{% set tags = "a,b,c" | split(pat=",") %}
{% for tag in tags %}
  <span>{{ tag | trim }}</span>
{% endfor %}
```

### 컬렉션 질의

```jinja
{% set published = site.pages | where(attribute="draft", value=false) %}
{% set newest = published | sort_by(attribute="date", reverse=true) %}

{% for group in newest | group_by(attribute="section") %}
  <h3>{{ group.grouper }}</h3>
  <ul>
  {% for p in group.list %}
    <li><a href="{{ p.url }}">{{ p.title }}</a></li>
  {% endfor %}
  </ul>
{% endfor %}

{# Unique tags across all pages #}
{% set all_tags = site.pages | map(attribute="tags") | flatten | unique %}
```

### 번역

```jinja
{# Translate UI strings (requires i18n/*.toml files) #}
<nav>
  <a href="/">{{ "nav.home" | t }}</a>
  <a href="/blog/">{{ "nav.blog" | t }}</a>
</nav>

{# Pluralize based on count #}
<p>{{ post_count }} {{ post_count | pluralize(singular="post", plural="posts") }}</p>
```

---

## 테스트

테스트는 `{% if %}` 문에서 조건을 평가합니다.

| 테스트 | 설명 | 예시 |
|------|-------------|---------|
| startswith | ~로 시작 | `{% if page.url is startswith("/blog/") %}` |
| endswith | ~로 끝남 | `{% if page.url is endswith("/") %}` |
| containing | 포함 | `{% if page.url is containing("docs") %}` |
| matching | 정규식 일치 | `{% if asset is matching("[.](jpg\|png)$") %}` |
| empty | 비어 있음 | `{% if page.description is empty %}` |
| present | 비어 있지 않음 | `{% if page.title is present %}` |

### 테스트 예시

```jinja
{% if page.url is startswith("/blog/") %}
<span class="badge">Blog</span>
{% endif %}

{% if page.description is empty %}
<meta name="description" content="{{ site.description }}">
{% endif %}

{% if page.image is present %}
<meta property="og:image" content="{{ page.image | absolute_url }}">
{% endif %}

{% if "hero.jpg" is matching("[.](jpg|png)$") %}
<span>Image file</span>
{% endif %}
```

### 내장 테스트

```jinja
{% if value is defined %}
{% if value is none %}
{% if value is number %}
{% if value is string %}
{% if value is iterable %}
{% if value is even %}
{% if value is odd %}
```

---

## 함께 보기

- [데이터 모델](/ko/templates/data-model/) — 사용할 수 있는 변수
- [함수](/ko/templates/functions/) — 템플릿 함수
- [문법](/ko/templates/syntax/) — 템플릿 기본
