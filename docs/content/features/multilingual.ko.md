+++
title = "다국어"
description = "번역 연결과 hreflang 태그를 갖춘 다국어 사이트 구축"
weight = 22
toc = true
+++

Hwaro는 자동 번역 연결, 언어별 URL, SEO용 hreflang 태그를 갖춘 다국어 사이트 구축을 지원합니다.

## 설정

`config.toml`에서 다국어 지원을 활성화합니다:

```toml
default_language = "en"

[languages.en]
language_name = "English"
weight = 1

[languages.ko]
language_name = "한국어"
weight = 2
generate_feed = true
build_search_index = true
taxonomies = ["tags", "categories"]

[languages.ja]
language_name = "日本語"
weight = 3
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| default_language | string | "en" | 기본 언어 코드 |
| language_name | string | — | 사람이 읽는 언어 이름 |
| weight | int | 0 | 정렬 순서(낮을수록 앞) |
| generate_feed | bool | true | 해당 언어의 RSS/Atom 피드 생성 여부 |
| build_search_index | bool | true | 검색 인덱스 포함 여부 |
| taxonomies | array | [] | 해당 언어의 택소노미 |

## 콘텐츠 구조

파일 이름에 언어 접미사를 붙여 번역을 만듭니다:

```
content/
├── posts/
│   ├── hello.md         # Default language (en)
│   ├── hello.ko.md      # Korean translation
│   └── hello.ja.md      # Japanese translation
├── about.md             # Default language (en)
├── about.ko.md          # Korean translation
└── index.md             # Homepage (default)
```

### URL 매핑

| 파일 | URL |
|------|-----|
| content/about.md | /about/ |
| content/about.ko.md | /ko/about/ |
| content/about.ja.md | /ja/about/ |
| content/posts/hello.md | /posts/hello/ |
| content/posts/hello.ko.md | /ko/posts/hello/ |

기본 언어 페이지는 루트 경로로 서비스되고, 비기본 언어 페이지에는 언어 코드 접두사가 붙습니다.

### 섹션 번역

섹션 인덱스 파일에도 언어 접미사를 쓸 수 있습니다:

```
content/
└── blog/
    ├── _index.md         # /blog/
    ├── _index.ko.md      # /ko/blog/
    └── post.md
```

## 번역 연결

Hwaro는 파일 이름을 기준으로 번역된 페이지를 자동으로 연결합니다. 언어 접미사를 뺀 기본 이름이 같은 페이지들은 서로의 번역으로 간주됩니다.

예를 들어 `hello.md`, `hello.ko.md`, `hello.ja.md`는 모두 번역 관계로 연결됩니다.

### 템플릿 변수

템플릿에서 번역 데이터에 접근합니다:

```jinja
{% if page.translations %}
<nav class="language-switcher">
  {% for t in page.translations %}
    {% if t.is_current %}
      <span class="active">{{ t.code | upper }}</span>
    {% else %}
      <a href="{{ t.url }}">{{ t.code | upper }}</a>
    {% endif %}
  {% endfor %}
</nav>
{% endif %}
```

### 번역 속성

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| code | String | 언어 코드 (예: "en", "ko") |
| url | String | 번역된 페이지의 URL |
| title | String | 번역된 페이지의 제목 |
| is_current | Bool | 현재 페이지의 언어인지 여부 |
| is_default | Bool | 기본 언어인지 여부 |

## SEO 태그

### 캐노니컬 URL

Hwaro는 다국어 페이지의 캐노니컬 링크 태그를 생성합니다:

```jinja
<head>
  {{ canonical_tag | safe }}
</head>
```

출력:

```html
<link rel="canonical" href="https://example.com/about/">
```

### hreflang 태그

번역이 있는 페이지에는 대체 언어 링크 태그가 자동으로 생성됩니다:

```jinja
<head>
  {{ hreflang_tags | safe }}
</head>
```

출력:

```html
<link rel="alternate" hreflang="en" href="https://example.com/about/">
<link rel="alternate" hreflang="ko" href="https://example.com/ko/about/">
<link rel="alternate" hreflang="ja" href="https://example.com/ja/about/">
```

### SEO 태그 결합

캐노니컬 태그와 hreflang 태그를 함께 넣습니다:

```jinja
<head>
  {{ canonical_tag | safe }}
  {{ hreflang_tags | safe }}
  {{ og_all_tags | safe }}
</head>
```

## 페이지 언어

템플릿에서 현재 페이지의 언어에 접근합니다:

```jinja
<html lang="{{ page.language }}">
```

```jinja
{% if page.language == "ko" %}
<p>한국어 콘텐츠</p>
{% endif %}
```

## 다국어 스캐폴드

다국어를 지원하는 새 사이트를 만듭니다:

```bash
hwaro init mysite --include-multilingual en,ko,ja
```

지정한 언어별로 설정과 샘플 콘텐츠 파일이 생성됩니다.

## 템플릿 예시

### 언어 전환 (드롭다운)

```jinja
{% if page.translations %}
<div class="lang-dropdown">
  <button>{{ page.language | upper }} ▾</button>
  <ul>
    {% for t in page.translations %}
    <li>
      <a href="{{ t.url }}"{% if t.is_current %} class="current"{% endif %}>
        {{ t.code | upper }}
      </a>
    </li>
    {% endfor %}
  </ul>
</div>
{% endif %}
```

### 언어별 내비게이션

```jinja
<nav>
  {% if page.language == "ko" %}
    <a href="/ko/">홈</a>
    <a href="/ko/blog/">블로그</a>
  {% elif page.language == "ja" %}
    <a href="/ja/">ホーム</a>
    <a href="/ja/blog/">ブログ</a>
  {% else %}
    <a href="/">Home</a>
    <a href="/blog/">Blog</a>
  {% endif %}
</nav>
```

### i18n을 적용한 베이스 템플릿

```jinja
<!DOCTYPE html>
<html lang="{{ page.language | default(value='en') }}">
<head>
  <meta charset="utf-8">
  <title>{{ page.title }} - {{ site.title }}</title>
  {{ canonical_tag | safe }}
  {{ hreflang_tags | safe }}
  {{ og_all_tags | safe }}
</head>
<body>
  {% if page.translations %}
  <nav class="i18n">
    {% for t in page.translations %}
      {% if t.is_current %}
        <strong>{{ t.code }}</strong>
      {% else %}
        <a href="{{ t.url }}">{{ t.code }}</a>
      {% endif %}
    {% endfor %}
  </nav>
  {% endif %}

  <main>
    {% block content %}{% endblock %}
  </main>
</body>
</html>
```

## i18n 번역 파일

내비게이션 레이블, 버튼 텍스트 같은 UI 문자열은 `i18n/` 디렉터리에 언어별 TOML 파일을 두어 번역할 수 있습니다.

### 파일 구조

언어마다 TOML 파일을 하나씩 만듭니다:

```
i18n/
├── en.toml
├── ko.toml
└── ja.toml
```

### 번역 파일 형식

```toml
# i18n/en.toml
[nav]
home = "Home"
blog = "Blog"
about = "About"

[common]
read_more = "Read more"
back = "Back"
```

```toml
# i18n/ko.toml
[nav]
home = "홈"
blog = "블로그"
about = "소개"

[common]
read_more = "더 읽기"
back = "뒤로"
```

중첩된 TOML 섹션은 점으로 구분한 키로 평탄화됩니다 (예: `nav.home`, `common.read_more`).

### 템플릿 사용

`t` 필터로 키를 번역합니다:

```jinja
<nav>
  <a href="/">{{ "nav.home" | t }}</a>
  <a href="/blog/">{{ "nav.blog" | t }}</a>
  <a href="/about/">{{ "nav.about" | t }}</a>
</nav>

<a href="{{ page.url }}">{{ "common.read_more" | t }}</a>
```

### 폴백 동작

1. 현재 페이지 언어에서 키를 찾습니다
2. 없으면 기본 언어(`default_language`)로 폴백합니다
3. 그래도 없으면 키 자체를 반환합니다 (예: `"nav.home"`)

### 복수형 처리

개수에 따라 달라지는 문자열에는 `pluralize` 필터를 사용합니다:

```jinja
{{ post_count }} {{ post_count | pluralize(singular="post", plural="posts") }}
```

## 언어별 피드

다국어 사이트에서는 Hwaro가 언어별로 별도의 RSS/Atom 피드를 자동 생성합니다:

| 언어 | 피드 경로 | 내용 |
|----------|-----------|----------|
| 기본 언어 (예: `en`) | `/rss.xml` | 기본 언어 페이지만 (설정으로 변경 가능) |
| 비기본 언어 (예: `ko`) | `/ko/rss.xml` | 한국어 페이지만 |
| 비기본 언어 (예: `ja`) | `/ja/rss.xml` | 일본어 페이지만 |

기본적으로 메인 사이트 피드(`/rss.xml` 또는 `/atom.xml`)에는 **기본 언어 페이지만** 포함됩니다. 이 동작은 `default_language_only` 옵션으로 바꿀 수 있습니다. `generate_feed = true`인 비기본 언어는 이 설정과 무관하게 각자의 언어 접두사 아래에 자체 피드를 갖습니다.

### 설정

#### 메인 피드 언어 제어

```toml
[feeds]
enabled = true
default_language_only = true   # true(기본값): 메인 피드에 기본 언어만 포함
                               # false: 메인 피드에 모든 언어 포함
```

#### 언어별 피드 제어

```toml
[languages.ko]
language_name = "한국어"
generate_feed = true    # Generates /ko/rss.xml (default: true)

[languages.ja]
language_name = "日本語"
generate_feed = false   # No /ja/rss.xml will be generated
```

언어 피드는 전역 `[feeds]` 설정의 `sections`, `limit`, `truncate`, `full_content` 값을 그대로 사용합니다:

```toml
[feeds]
enabled = true
type = "rss"           # 또는 "atom"
limit = 20
truncate = 0
full_content = true    # false = 설명/요약만 포함
sections = []          # 비워 두면 모든 섹션
default_language_only = true
```

### 피드 세부 사항

- **RSS 피드**에는 `<language>` 태그가 포함됩니다 (예: `<language>ko</language>`)
- **Atom 피드**에는 `xml:lang` 속성이 포함됩니다 (예: `<feed xmlns="..." xml:lang="ko">`)
- 피드 제목에 언어 이름이 붙습니다: `"My Site (한국어)"`
- 자기 참조 링크는 해당 언어 경로를 가리킵니다 (예: `https://example.com/ko/rss.xml`)
- 초안 페이지와 섹션 인덱스 페이지는 제외됩니다
- 언어 피드는 메인 피드의 `enabled` 설정과 무관하게 생성됩니다

### 템플릿 링크

템플릿에 언어별 피드 링크를 추가합니다:

```jinja
{# Main feed (default language) #}
<link rel="alternate" type="application/rss+xml"
      href="{{ base_url }}/rss.xml"
      title="{{ site.title }}">

{# Language-specific feed #}
{% if page.language and page.language != "en" %}
<link rel="alternate" type="application/rss+xml"
      href="{{ base_url }}/{{ page.language }}/rss.xml"
      title="{{ site.title }} ({{ page.language }})">
{% endif %}
```

## 함께 보기

- [설정](/ko/start/config/) — 전체 설정 레퍼런스
- [SEO](/ko/features/seo/) — 피드, 캐노니컬, hreflang 등 SEO 기능
- [데이터 모델](/ko/templates/data-model/) — 번역 링크 속성
