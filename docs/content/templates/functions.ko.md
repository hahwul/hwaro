+++
title = "함수"
description = "데이터 조회와 URL 생성을 위한 내장 함수"
weight = 3
toc = true
+++

템플릿에서 데이터를 조회하고 URL을 생성하는 내장 함수입니다.

## 데이터 조회

### get_page()

경로나 URL로 아무 페이지나 가져옵니다.

```jinja
{% set about = get_page(path="about.md") %}
{% if about %}
<a href="{{ about.url }}">{{ about.title }}</a>
{% endif %}
```

**파라미터:**

| 이름 | 타입 | 설명 |
|------|------|-------------|
| path | String | 소스 상대 경로(예: `about.md`) 또는 URL 경로(예: `/about/`) |

**반환값:** Page? (못 찾으면 nil) — 표준 [Page 속성](/ko/templates/data-model/)을 노출하되, 렌더링 시점에 계산되는 필드(`permalink`, `lower`/`higher`, `ancestors`, `series_index`, `series_pages`, `related_posts`)는 제외됩니다.

**예시:**

```jinja
{# Page in root #}
{% set contact = get_page(path="contact.md") %}

{# Page in section #}
{% set intro = get_page(path="docs/introduction.md") %}

{# Match by URL #}
{% set intro_by_url = get_page(path="/docs/introduction/") %}
```

---

### get_section()

섹션 이름, 소스 경로, URL로 섹션을 가져옵니다.

```jinja
{% set blog = get_section(path="blog") %}
{% if blog %}
<h2>{{ blog.title }}</h2>
<ul>
{% for p in blog.pages %}
  <li><a href="{{ p.url }}">{{ p.title }}</a></li>
{% endfor %}
</ul>
{% endif %}
```

**파라미터:**

| 이름 | 타입 | 설명 |
|------|------|-------------|
| path | String | 섹션 이름(`blog`), 경로(`blog/_index.md`), 또는 URL(`/blog/`) |

**반환값:** Section? (못 찾으면 nil)

**반환 속성:**

| 속성 | 타입 |
|----------|------|
| title | String |
| description | String? |
| url | String |
| path | String |
| name | String |
| pages | Array<Page> |
| pages_count | Int |
| assets | Array<String> |

**예시:**

```jinja
{# Top-level section #}
{% set docs = get_section(path="docs") %}

{# Nested section #}
{% set guides = get_section(path="docs/guides") %}

{# Match by URL #}
{% set blog = get_section(path="/blog/") %}

{# Display count #}
<p>{{ docs.pages_count }} articles</p>
```

---

### get_taxonomy()

택소노미 항목과 그에 속한 페이지에 접근합니다.

```jinja
{% set tags = get_taxonomy(kind="tags") %}
{% if tags %}
<ul class="tag-cloud">
{% for term in tags.items %}
  <li>
    <a href="/tags/{{ term.slug }}/">
      {{ term.name }} ({{ term.count }})
    </a>
  </li>
{% endfor %}
</ul>
{% endif %}
```

**파라미터:**

| 이름 | 타입 | 설명 |
|------|------|-------------|
| kind | String | 택소노미 이름(예: "tags", "categories") |

**반환값:** Taxonomy? (못 찾으면 nil)

**반환 속성:**

| 속성 | 타입 |
|----------|------|
| name | String |
| items | Array<Term> |

**Term 속성:**

| 속성 | 타입 |
|----------|------|
| name | String |
| slug | String |
| pages | Array<Page> |
| count | Int |

---

### get_taxonomy_url()

택소노미 항목의 URL을 생성합니다.

```jinja
<a href="{{ get_taxonomy_url(kind='tags', term='crystal') }}">
  Crystal articles
</a>
```

**파라미터:**

| 이름 | 타입 | 설명 |
|------|------|-------------|
| kind | String | 택소노미 이름 |
| term | String | 항목 이름 |

**반환값:** String(절대 URL)

---

### get_menu()

이름 있는 메뉴의 해석된 엔트리 트리에 접근합니다([메뉴](/ko/features/menus/)).

```jinja
{% for item in get_menu(name="main") %}
<a href="{{ item.href }}"{% if item.url | active_path %} aria-current="page"{% endif %}>{{ item.name }}</a>
{% endfor %}
```

**파라미터:**

| 이름 | 타입 | 설명 |
|------|------|-------------|
| name | String | 메뉴 이름(예: "main", "footer") |

**반환값:** Array\<Entry\> — **현재 페이지**의 언어를 기준으로 해석하고, 그 언어에 `name` 메뉴 엔트리가 없으면 기본 언어로 폴백합니다. 알 수 없거나 등록되지 않은 메뉴 이름은 빈 배열을 반환하므로(nil이 아님) `{% for %}` 루프에서 오류가 나지 않습니다.

**엔트리 속성:**

| 속성 | 타입 | 설명 |
|----------|------|--------------|
| name | String | 표시 레이블 |
| url | String | 아무것도 붙지 않은 루트 상대 경로, 또는 손대지 않은 외부 URL |
| href | String | 내부 링크면 `url`에 `base_path`를 적용한 값, 외부면 그대로 — `<a href>`에는 이 값을 사용 |
| identifier | String | 메뉴 안에서 고유한 키 |
| weight | Int | 정렬 순서 |
| external | Bool | `http://`, `https://`, `//` URL이면 `true` |
| children | Array\<Entry\> | 중첩 엔트리 |
| page | Page? | 등록한 페이지의 데이터(프론트 매터로 등록된 엔트리만) |

현재 페이지와 무관하게 **기본 언어**의 메뉴가 꼭 필요할 때만 `site.menus.<name>`을 사용합니다 — 공용 내비게이션 파셜 안에서는 거의 언제나 `get_menu()`가 맞는 선택입니다.

---

## 데이터 로딩

### load_data()

외부 데이터 파일(JSON, TOML, YAML, CSV)을 불러옵니다.

```jinja
{% set menu = load_data(path="data/menu.json") %}
{% for item in menu %}
<a href="{{ item.url }}">{{ item.title }}</a>
{% endfor %}
```

**파라미터:**

| 이름 | 타입 | 설명 |
|------|------|-------------|
| path | String | 데이터 파일 경로 |

**반환값:** 파싱된 데이터 또는 nil

**지원 포맷:**

| 확장자 | 포맷 |
|-----------|--------|
| .json | JSON |
| .toml | TOML |
| .yaml, .yml | YAML |
| .csv | CSV(배열의 배열) |

**예시:**

JSON (`data/team.json`):
```json
[
  {"name": "Alice", "role": "Developer"},
  {"name": "Bob", "role": "Designer"}
]
```

```jinja
{% set team = load_data(path="data/team.json") %}
<ul>
{% for member in team %}
  <li>{{ member.name }} - {{ member.role }}</li>
{% endfor %}
</ul>
```

TOML (`data/social.toml`):
```toml
[[links]]
name = "Twitter"
url = "https://twitter.com/example"
```

```jinja
{% set social = load_data(path="data/social.toml") %}
{% for link in social.links %}
<a href="{{ link.url }}">{{ link.name }}</a>
{% endfor %}
```

---

## 환경 변수

### env()

템플릿에서 환경 변수를 읽습니다.

```jinja
{{ env("ANALYTICS_ID") }}
{{ env("API_KEY", default="none") }}
```

**파라미터:**

| 이름 | 타입 | 설명 |
|------|------|-------------|
| name | String | 환경 변수 이름 |
| default | String? | 변수가 없을 때의 폴백 값(선택) |

**반환값:** String(환경 변수 값, 기본값, 또는 빈 문자열)

변수가 없고 기본값도 지정하지 않으면 빈 문자열을 반환하고 빌드 경고를 남깁니다.

**예시:**

```jinja
{# Google Analytics #}
{% if env("GA_ID") %}
<script async src="https://www.googletagmanager.com/gtag/js?id={{ env("GA_ID") }}"></script>
{% endif %}

{# API endpoint with fallback #}
<script>
  const API = "{{ env("API_URL", default="https://api.example.com") }}";
</script>
```

---

## URL 함수

### url_for()

base_url이 포함된 URL을 생성합니다.

```jinja
<a href="{{ url_for(path='/about/') }}">About</a>
<img src="{{ url_for(path='/images/logo.png') }}">
```

**파라미터:**

| 이름 | 타입 | 설명 |
|------|------|-------------|
| path | String | 변환할 경로 |

**반환값:** String(절대 URL)

---

### get_url()

`url_for()`의 별칭입니다. 어느 이름을 써도 됩니다.

```jinja
<a href="{{ get_url(path='/about/') }}">About</a>
```

---

### asset()

번들되거나 핑거프린트된 에셋을 최종 URL로 해석합니다. [에셋 파이프라인](/ko/features/asset-pipeline/)이 활성화되어 있으면 입력한 이름을 빌드 매니페스트에서 찾아 항상 해시가 붙은 파일 이름을 돌려줍니다.

```jinja
<link rel="stylesheet" href="{{ asset(name='main.css') }}">
<script src="{{ asset(name='app.js') }}"></script>
```

**파라미터:**

| 이름 | 타입 | 설명 |
|------|------|-------------|
| name | String | 번들 또는 에셋 이름(예: `main.css`, `app.js`) |

**반환값:** String — `base_url` 아래의 절대 URL. 매니페스트에 항목이 없으면 이름을 그대로 `base_url` 아래 경로로 반환하므로, 파이프라인을 켜기 전에도 템플릿이 그대로 동작합니다.

---

### asset_url()

`asset()`의 별칭입니다. 템플릿에서 더 읽기 좋은 쪽을 사용하면 됩니다.

---

### now()

현재 날짜와 시간을 가져옵니다.

```jinja
{# Default format #}
<p>Generated: {{ now() }}</p>

{# Custom format #}
<p>Year: {{ now(format="%Y") }}</p>
<p>Date: {{ now(format="%B %d, %Y") }}</p>
```

**파라미터:**

| 이름 | 타입 | 설명 |
|------|------|-------------|
| format | String? | 날짜 포맷 문자열(선택) |

**반환값:** String

**포맷 코드:**

| 코드 | 설명 | 예시 |
|------|-------------|---------|
| %Y | 연도 | 2025 |
| %m | 월(01-12) | 01 |
| %d | 일(01-31) | 15 |
| %B | 월 이름 | January |
| %b | 월 축약형 | Jan |
| %H | 시(00-23) | 14 |
| %M | 분 | 30 |
| %S | 초 | 45 |

---

## 미디어 함수

### resize_image()

리사이즈된 이미지 변형을 돌려줍니다. [이미지 처리](/ko/features/image-processing/)가 활성화되어 있으면 자동 생성된 리사이즈 이미지의 URL을, 아니면 원본 URL을 반환합니다.

```jinja
{% set img = resize_image(path="/images/hero.jpg", width=640) %}
<img src="{{ img.url }}" width="{{ img.width }}">
```

**파라미터:**

| 이름 | 타입 | 설명 |
|------|------|-------------|
| path | String | 이미지 경로(예: `/images/photo.jpg`) |
| width | Int | 요청 너비(픽셀, 0 = 원본) |
| height | Int | 요청 높이(픽셀, 0 = 원본) |

**반환값:** 다음 속성을 가진 객체:

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| url | String | 리사이즈된 변형의 URL(사용할 수 없으면 원본) |
| width | Int | 요청한 너비 |
| height | Int | 요청한 높이 |
| lqip | String | 작은 JPEG 플레이스홀더의 Base64 데이터 URI(LQIP 비활성 시 빈 문자열) |
| dominant_color | String | 이미지 주요 색상의 16진수 색상 문자열, 예: `#a3b2c1`(LQIP 비활성 시 빈 문자열) |

이 함수는 설정된 `widths` 중 가장 가까운 너비를 고릅니다. `width=500`을 요청했고 설정된 너비가 `[320, 640, 1024]`라면 640px 변형(요청 이상인 가장 작은 너비)을 반환합니다. 충분히 큰 것이 없으면 가장 큰 변형으로 폴백합니다.

`lqip`과 `dominant_color` 속성은 `[image_processing.lqip]`이 활성화되어 있어야 합니다. 꺼져 있으면 빈 문자열을 반환합니다.

**예시:**

```jinja
{# Single resized image #}
{% set img = resize_image(path="/images/hero.jpg", width=800) %}
<img src="{{ img.url }}" alt="Hero">

{# Responsive srcset #}
{% set sm = resize_image(path="/images/hero.jpg", width=320) %}
{% set md = resize_image(path="/images/hero.jpg", width=640) %}
{% set lg = resize_image(path="/images/hero.jpg", width=1024) %}
<img
  src="{{ md.url }}"
  srcset="{{ sm.url }} 320w, {{ md.url }} 640w, {{ lg.url }} 1024w"
  sizes="(max-width: 640px) 320px, (max-width: 1024px) 640px, 1024px"
>

{# With page image from front matter #}
{% if page.image %}
  {% set thumb = resize_image(path=page.image, width=320) %}
  <img src="{{ thumb.url }}" alt="{{ page_title }}">
{% endif %}

{# LQIP blur-up placeholder #}
{% set img = resize_image(path="/images/hero.jpg", width=1024) %}
<img
  src="{{ img.url }}"
  style="background-image: url({{ img.lqip }}); background-size: cover;"
  loading="lazy"
  alt="Hero"
>

{# Dominant color placeholder #}
{% set img = resize_image(path="/images/photo.jpg", width=640) %}
<img
  src="{{ img.url }}"
  style="background-color: {{ img.dominant_color }}"
  loading="lazy"
  alt="Photo"
>
```

`config.toml`에서 `[image_processing]`을 활성화해야 합니다. 설정 방법은 [이미지 처리](/ko/features/image-processing/)를 참고합니다.

---

## 모범 사례

### 항상 nil 확인

```jinja
{% set page = get_page(path="featured.md") %}
{% if page %}
{{ page.title }}
{% else %}
<p>Coming soon</p>
{% endif %}
```

### 함수 결과 재사용

```jinja
{# Good: Single lookup #}
{% set blog = get_section(path="blog") %}
<h2>{{ blog.title }}</h2>
<p>{{ blog.pages_count }} posts</p>

{# Avoid: Multiple lookups #}
<h2>{{ get_section(path="blog").title }}</h2>
<p>{{ get_section(path="blog").pages_count }} posts</p>
```

### 데이터 파일 정리

```
data/
├── navigation/
│   ├── main.json
│   └── footer.json
├── team.yaml
└── products.toml
```

---

## 함께 보기

- [데이터 모델](/ko/templates/data-model/) — Site, Section, Page 타입
- [데이터 모델 › Paginator](/ko/templates/data-model/) — 섹션 템플릿의 페이지네이션 객체
- [필터](/ko/templates/filters/) — 값 변환
