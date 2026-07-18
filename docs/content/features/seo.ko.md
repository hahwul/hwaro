+++
title = "SEO"
description = "기본 제공 사이트맵, RSS 피드, robots.txt, 소셜 공유 메타 태그"
weight = 1
+++

Hwaro는 사이트맵, RSS 피드, robots.txt, 소셜 공유 메타 태그 같은 SEO 기능을 기본으로 제공합니다.

## 사이트맵

검색 엔진용 `sitemap.xml`을 자동 생성합니다.

### 설정

```toml
[sitemap]
enabled = true
filename = "sitemap.xml"
changefreq = "weekly"
priority = 0.5
exclude = ["/private", "/drafts"]
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | false | `sitemap.xml` 생성 여부 |
| filename | string | "sitemap.xml" | 출력 파일 이름 |
| changefreq | string | "weekly" | 전체 페이지의 기본 변경 주기 |
| priority | float | 0.5 | 전체 페이지의 기본 우선순위(0.0–1.0) |
| exclude | array | [] | 제외할 경로 접두사 (예: `["/private"]`는 `/private`, `/private/page.html`을 제외) |

### 출력

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://example.com/</loc>
    <lastmod>2024-01-15</lastmod>
  </url>
  <url>
    <loc>https://example.com/about/</loc>
  </url>
</urlset>
```

### 페이지 제외

프론트 매터에 `in_sitemap = false`를 설정합니다:

```markdown
+++
title = "Private Page"
in_sitemap = false
+++
```

---

## RSS 피드

사이트와 섹션의 RSS 피드를 생성합니다.

### 설정

```toml
[feeds]
enabled = true
type = "rss"              # "rss" 또는 "atom"
limit = 20                # 최대 항목 수
truncate = 0              # N자로 자르기 (0 = 자르지 않음)
full_content = true       # true = 전체 HTML 본문, false = description/요약만
filename = ""             # 비워 두면 기본값 (rss.xml 또는 atom.xml)
sections = []             # 특정 섹션으로 제한, 예: ["posts"]
```

| 옵션 | 기본값 | 설명 |
|--------|---------|-------------|
| `enabled` | `false` | 피드 생성 여부 |
| `type` | `"rss"` | 피드 형식: `"rss"` 또는 `"atom"` |
| `limit` | `10` | 피드의 최대 항목 수 |
| `truncate` | `0` | 콘텐츠를 N자로 자르기 (0 = 전체 콘텐츠) |
| `full_content` | `true` | `true` = 피드에 전체 HTML 포함, `false` = 프론트 매터 `description` 또는 자동 생성 요약 사용 |
| `filename` | `""` | 커스텀 파일 이름 (비어 있으면 `rss.xml` 또는 `atom.xml`) |
| `sections` | `[]` | 피드를 특정 섹션으로 제한 |
| `default_language_only` | `true` | 다국어: 메인 피드에 기본 언어만 포함 |

### 섹션 피드

섹션별 피드를 활성화합니다:

```markdown
+++
title = "Blog"
generate_feeds = true
+++
```

이렇게 하면 `/blog/rss.xml`이 생성됩니다.

### 출력

- `/rss.xml` — 사이트 전체 피드
- `/blog/rss.xml` — 섹션 피드 (활성화한 경우)

### 다국어 피드

사이트가 다국어이면 피드는 언어별로 자동 생성됩니다:

| 언어 | 피드 경로 | 내용 |
|----------|-----------|----------|
| 기본 언어 (예: `en`) | `/rss.xml` | 기본 언어 페이지만 (설정 가능) |
| 기본 외 언어 (예: `ko`) | `/ko/rss.xml` | 한국어 페이지만 |
| 기본 외 언어 (예: `ja`) | `/ja/rss.xml` | 일본어 페이지만 |

기본적으로 메인 사이트 피드에는 **기본 언어 페이지만** 포함됩니다(`default_language_only = true`). 메인 피드에 모든 언어를 포함하려면 `default_language_only = false`로 설정합니다. `generate_feed = true`인 기본 외 언어는 이 설정과 무관하게 각자 별도 피드를 갖습니다.

```toml
[feeds]
enabled = true
default_language_only = true   # true (기본값): 메인 피드 = 기본 언어만
                               # false: 메인 피드에 모든 언어 포함
```

언어별 피드 제어:

```toml
[languages.ko]
language_name = "한국어"
generate_feed = true    # /ko/rss.xml 생성 (기본값: true)

[languages.ja]
language_name = "日本語"
generate_feed = false   # /ja/rss.xml을 생성하지 않음
```

언어 피드는 `[feeds]` 설정의 `sections`, `limit`, `truncate`, `full_content` 값을 그대로 공유합니다. RSS 언어 피드에는 `<language>` 태그가, Atom 피드에는 `xml:lang` 속성이 들어갑니다. 피드 제목에는 언어 이름이 포함됩니다 (예: `"My Site (한국어)"`).

### 커스텀 피드 템플릿

피드 마크업을 직접 제어하려면 피드 출력 파일 이름을 딴 템플릿을 만듭니다:

| 피드 종류 | 템플릿 파일 | 로드 키 |
|-----------|---------------|---------------|
| RSS | `templates/rss.xml.jinja` | `rss.xml` |
| Atom | `templates/atom.xml.jinja` | `atom.xml` |

템플릿 확장자는 무엇이든 됩니다(`.jinja`, `.j2`, `.jinja2`, `.html`) — 마지막 확장자만 제거되므로 `rss.xml.jinja`는 `rss.xml` 키로 로드됩니다. 확장자와 무관하게 파일은 항상 **Jinja**로 렌더링됩니다(`.ecr` 파일도 인식되지만 ECR `<%= %>` 태그는 문자 그대로 출력되므로 Jinja 문법을 써야 합니다). 템플릿 파일의 존재 자체가 옵트인입니다: 파일이 없으면 Hwaro는 기존과 똑같이 내장 피드를 내보내고, 템플릿을 삭제하면 내장 출력으로 되돌아갑니다. 오버라이드는 **네 가지 피드 전부**에 적용됩니다 — 메인 피드, 섹션별 피드, 언어별 피드, 택소노미 항목별 피드 — 그리고 커스텀 `[feeds] filename`은 여전히 출력 경로를 결정합니다.

피드 템플릿 안에서 `{% include %}`를 쓸 수 있고, 템플릿이 잘못되면 해당 파일 이름을 담은 템플릿 오류와 함께 빌드가 실패합니다.

#### 컨텍스트 변수

`feed` — 렌더링 중인 피드의 메타데이터:

| 변수 | 타입 | 설명 |
|----------|------|-------------|
| `feed.type` | string | `"rss"` 또는 `"atom"` (`[feeds] type`을 따름) |
| `feed.kind` | string | `"main"`, `"section"`, `"language"`, `"taxonomy"` 중 하나 |
| `feed.title` | string | 피드 제목 (사이트 제목, `Site - Section`, `Site (한국어)` 등) |
| `feed.description` | string | 사이트 설명 |
| `feed.url` | string | 이 피드 파일의 절대 self URL (퍼센트 인코딩) |
| `feed.home_url` | string | 피드가 대표하는 표준 HTML URL (사이트 루트, 섹션 페이지, 언어 홈) |
| `feed.base_url` | string | 끝 슬래시를 뺀 `base_url` |
| `feed.language` | string? | 언어별 피드의 언어 코드, 그 외에는 없음 |
| `feed.updated` | time | 가장 최신 항목의 날짜 (결정적; 날짜 있는 항목이 없으면 epoch) |
| `feed.updated_rfc3339` | string | `feed.updated`의 RFC 3339 표현 (Atom `<updated>`) |
| `feed.updated_rfc822` | string | `feed.updated`의 RFC 822 표현 (RSS `<lastBuildDate>`/`<pubDate>` 형식) |
| `feed.author` | string | 사이트 제목 (없으면 피드 제목으로 대체) |
| `feed.section_url` | string? | 섹션 URL — 섹션 피드 전용 |
| `feed.taxonomy` / `feed.term` | string? | 택소노미 이름과 항목 — 택소노미 피드 전용 |

`pages` — 정렬과 `limit`이 적용된 항목 목록. 각 항목:

| 변수 | 타입 | 설명 |
|----------|------|-------------|
| `title` | string | 페이지 제목 (비어 있으면 사이트 제목) |
| `url` | string | 절대 페이지 URL (퍼센트 인코딩) |
| `date` / `updated` | time? | 프론트 매터의 원본 날짜 (`date` 필터에 사용 가능) |
| `date_rfc822` | string? | 미리 형식화된 RFC 822 날짜; 날짜 없는 페이지는 없음 |
| `updated_rfc3339` | string | `updated`/`date` 기반 RFC 3339 타임스탬프 (없으면 epoch) |
| `description` | string? | 프론트 매터 description |
| `summary` | string | 일반 텍스트 요약 (description → `<!-- more -->` 요약 → 발췌 순) |
| `content` | string | `full_content`/`truncate`를 반영한 본문 (자를 때는 일반 텍스트) |
| `content_html` | string | 외부 리더를 위해 링크를 절대 URL로 바꾼 전체 HTML 본문 |
| `content_is_html` | bool | `content`가 HTML인지 여부 (`truncate`/`full_content = false`면 `false`) |
| `authors` | array | 프론트 매터 authors |
| `categories` | array | 택소노미 항목 — `tags`가 먼저, 그다음 다른 택소노미, 중복 제거 |
| `section` | string | 페이지 섹션 경로 |
| `language` | string? | 페이지 언어 코드 |

#### 예시

값은 **미리 이스케이프되지 않습니다** — `xml_escape`를 적용하거나 CDATA로 감싸는 일은 템플릿 작성자의 몫입니다:

```jinja
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>{{ feed.title | xml_escape }}</title>
    <link>{{ feed.home_url | xml_escape }}</link>
    <description>{{ feed.description | xml_escape }}</description>
    {% if feed.language %}<language>{{ feed.language | xml_escape }}</language>{% endif %}
    <atom:link href="{{ feed.url | xml_escape }}" rel="self" type="application/rss+xml" />
    {% for p in pages %}
    <item>
      <title>{{ p.title | xml_escape }}</title>
      <link>{{ p.url | xml_escape }}</link>
      <guid>{{ p.url | xml_escape }}</guid>
      <description>{{ p.summary | xml_escape }}</description>
      {% if p.date_rfc822 %}<pubDate>{{ p.date_rfc822 }}</pubDate>{% endif %}
      {% for term in p.categories %}<category>{{ term | xml_escape }}</category>{% endfor %}
    </item>
    {% endfor %}
  </channel>
</rss>
```

### 템플릿 링크

```jinja
<link rel="alternate" type="application/rss+xml" 
      href="{{ base_url }}/rss.xml" 
      title="{{ site.title }}">

{% if page.language and page.language != "en" %}
<link rel="alternate" type="application/rss+xml"
      href="{{ base_url }}/{{ page.language }}/rss.xml"
      title="{{ site.title }} ({{ page.language }})">
{% endif %}
```

---

## Robots.txt

검색 엔진 크롤링을 제어합니다.

### 설정

```toml
[robots]
enabled = true
```

커스텀 규칙 사용:

```toml
[robots]
enabled = true
rules = [
  { user_agent = "*", disallow = ["/admin", "/private"] },
  { user_agent = "GPTBot", disallow = ["/"] }
]
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | true | `robots.txt` 생성 여부 |
| filename | string | "robots.txt" | 출력 파일 이름 |
| rules | array | [] | `allow`/`disallow` 경로를 담은 user-agent 규칙 목록 |

규칙을 설정하지 않으면 Hwaro는 기본 전체 허용 규칙을 생성합니다. 규칙의 `allow`와 `disallow`가 모두 비어 있으면 모호한 동작을 막기 위해 명시적인 `Allow: /`가 추가됩니다.

### 출력

```
User-agent: *
Allow: /
Sitemap: https://example.com/sitemap.xml
```

---

## LLMs.txt

[llms.txt 표준](https://llmstxt.org/)을 따르는 AI/LLM 크롤러용 안내 파일을 생성합니다.

```toml
[llms]
enabled = true
instructions = "This site's content is provided under the MIT license."
full_enabled = true
```

전체 설정과 출력 형식은 [LLMs.txt](/ko/features/llms-txt/)에서 다룹니다.

---

## OpenGraph 태그

Facebook, LinkedIn 등을 위한 소셜 공유 메타 태그입니다.

### 설정

```toml
[og]
default_image = "/images/og-default.png"
type = "website"
fb_app_id = "your_fb_app_id"
```

| 키 | 설명 |
|-----|-------------|
| default_image | 페이지에 이미지가 없을 때 사용할 대체 이미지 |
| type | 콘텐츠 페이지의 OpenGraph 타입 (기본값: `"article"`; 목록 페이지는 항상 `"website"`) |
| fb_app_id | Facebook 앱 ID (선택) |

### 페이지 단위 오버라이드

```markdown
+++
title = "My Article"
description = "Article description"
image = "/images/article-cover.png"
+++
```

### 템플릿에서 사용

```jinja
<head>
  {{ og_tags | safe }}
</head>
```

### 출력

```html
<meta property="og:title" content="My Article">
<meta property="og:type" content="article">
<meta property="og:url" content="https://example.com/my-article/">
<meta property="og:description" content="Article description">
<meta property="og:image" content="https://example.com/images/article-cover.png">
```

---

## Twitter 카드

Twitter 전용 공유 태그입니다.

### 설정

```toml
[og]
twitter_card = "summary_large_image"
twitter_site = "@yourusername"
twitter_creator = "@authorusername"
```

| 키 | 설명 |
|-----|-------------|
| twitter_card | 카드 타입: summary, summary_large_image |
| twitter_site | 사이트의 Twitter 핸들 |
| twitter_creator | 작성자의 Twitter 핸들 |

### 템플릿에서 사용

```jinja
<head>
  {{ twitter_tags | safe }}
</head>
```

또는 OG와 Twitter 태그를 함께 포함합니다:

```jinja
<head>
  {{ og_all_tags | safe }}
</head>
```

### 출력

```html
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="My Article">
<meta name="twitter:description" content="Article description">
<meta name="twitter:image" content="https://example.com/images/article-cover.png">
<meta name="twitter:site" content="@yourusername">
```

---

## JSON-LD 구조화된 데이터

Hwaro는 모든 페이지에 Article과 BreadcrumbList JSON-LD를 자동 생성합니다.

```jinja
<head>
  {{ jsonld | safe }}
</head>
```

FAQ, HowTo, WebSite, Organization 같은 추가 스키마 타입도 사용할 수 있습니다. 전체 타입, 설정, 출력 예시는 [구조화된 데이터](/ko/features/structured-data/)에서 다룹니다.

---

## 템플릿 변수

### 미리 렌더링된 HTML

다음 변수는 바로 쓸 수 있는 HTML 태그를 출력합니다:

| 변수 | 설명 |
|----------|-------------|
| og_tags | OpenGraph 메타 태그 |
| twitter_tags | Twitter 카드 메타 태그 |
| og_all_tags | OG와 Twitter 태그 전체 |
| canonical_tag | canonical 링크 태그 |
| hreflang_tags | hreflang 대체 링크 태그 |
| jsonld | Article + BreadcrumbList JSON-LD |
| jsonld_article | Article JSON-LD만 |
| jsonld_breadcrumb | BreadcrumbList JSON-LD만 |
| page_description | 페이지 설명 (없으면 사이트 설명) |
| page_image | 페이지 이미지 (없으면 og.default_image) |

### SEO 객체

`seo` 객체는 커스텀 메타 태그를 만들 수 있도록 필드 단위 접근을 제공합니다:

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| seo.canonical_url | String | 전체 canonical URL |
| seo.og_type | String | OpenGraph 타입 (기본값: "article") |
| seo.og_image | String | 해석된 절대 이미지 URL |
| seo.twitter_card | String | Twitter 카드 타입 |
| seo.twitter_site | String | Twitter 사이트 핸들 |
| seo.twitter_creator | String | Twitter 작성자 핸들 |
| seo.fb_app_id | String | Facebook 앱 ID |
| seo.hreflang | Array | 언어 번역 링크 |

```jinja
<head>
  <link rel="canonical" href="{{ seo.canonical_url }}">
  <meta property="og:title" content="{{ page.title }}">
  <meta property="og:type" content="{{ seo.og_type }}">
  <meta property="og:url" content="{{ seo.canonical_url }}">
  {% if page.description %}
  <meta property="og:description" content="{{ page.description }}">
  {% endif %}
  {% if seo.og_image %}
  <meta property="og:image" content="{{ seo.og_image }}">
  {% endif %}
  {% if seo.fb_app_id %}
  <meta property="fb:app_id" content="{{ seo.fb_app_id }}">
  {% endif %}
  <meta name="twitter:card" content="{{ seo.twitter_card }}">
  <meta name="twitter:title" content="{{ page.title }}">
  {% if seo.twitter_site %}
  <meta name="twitter:site" content="{{ seo.twitter_site }}">
  {% endif %}
</head>
```

---

## 전체 예시

### config.toml

```toml
title = "My Site"
description = "A great site"
base_url = "https://example.com"

[sitemap]
enabled = true

[feeds]
enabled = true
limit = 20

[robots]
enabled = true

[og]
default_image = "/images/og-default.png"
type = "website"
twitter_card = "summary_large_image"
twitter_site = "@mysite"
```

### templates/base.html

```jinja
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>{{ page.title }} - {{ site.title }}</title>
  <meta name="description" content="{{ page.description | default(value=site.description) }}">
  {{ og_all_tags | safe }}
  {{ canonical_tag | safe }}
  {{ hreflang_tags | safe }}
  {{ jsonld | safe }}
  <link rel="alternate" type="application/rss+xml" href="{{ base_url }}/rss.xml">
</head>
<body>
  {% block content %}{% endblock %}
</body>
</html>
```

## 함께 보기

- [LLMs.txt](/ko/features/llms-txt/) — AI/LLM 크롤러 안내
- [다국어](/ko/features/multilingual/) — i18n을 위한 hreflang과 canonical 태그
- [설정](/ko/start/config/) — 전체 설정 레퍼런스
