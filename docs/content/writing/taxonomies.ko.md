+++
title = "택소노미"
description = "태그, 카테고리, 커스텀 그룹으로 콘텐츠 구성"
weight = 3
toc = true
+++

택소노미는 태그, 카테고리, 작성자 같은 그룹으로 콘텐츠를 구성합니다.

## 설정

`config.toml`에서 택소노미를 정의합니다:

```toml
[[taxonomies]]
name = "tags"
feed = true
paginate_by = 10

[[taxonomies]]
name = "categories"
feed = true

[[taxonomies]]
name = "authors"
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| `name` | string | — | 택소노미 이름(프론트 매터에서 사용) |
| `feed` | bool | false | 항목별 RSS 피드 생성 |
| `sitemap` | bool | true | 택소노미 페이지를 사이트맵에 포함 |
| `paginate_by` | int | — | 항목 페이지의 페이지당 항목 수 |
| `sort_by` | string | "date" | 항목 안 페이지의 정렬 기준: `"date"`, `"published"`, `"title"`, `"weight"` ([정렬](#정렬) 참고) |
| `reverse` | bool | false | `sort_by`가 만든 순서 뒤집기 |
| `terms_sort_by` | string | "name" | 항목 목록의 정렬 기준: `"name"` 또는 `"count"` ([정렬](#정렬) 참고) |

## 정렬

`sort_by`는 각 택소노미 항목에 속한 페이지의 순서를 결정하며, 생성되는 항목 페이지, `get_taxonomy()`의 `term.pages`, 항목별 페이지네이션 모두에 적용됩니다. 의미는 섹션 정렬과 정확히 같습니다:

- `"date"`(기본값): 최신순. `reverse = true`면 오래된 순.
- `"published"` — `"date"`와 같지만 발행일 `date`만 사용합니다(`updated`는 무시).
- `"title"` — 제목 오름차순(바이트 단위 비교라 대문자가 소문자보다 앞). `reverse = true`면 내림차순.
- `"weight"` — 낮은 weight 우선. `reverse = true`면 내림차순.

`sort_by` 값이 잘못되면 경고를 남기고 기본값 `"date"`를 유지합니다.

`terms_sort_by`는 항목 목록의 순서를 결정하며, 택소노미 인덱스 페이지와 `get_taxonomy().items`에 적용됩니다:

- `"name"`(기본값): 항목 이름 오름차순. 대소문자를 구분하지 않으므로 `apple`이 `Zebra`보다 앞에 옵니다.
- `"count"` — 페이지 수 내림차순, 동률이면 이름 오름차순. 다국어 사이트에서는 각 언어의 인덱스가 해당 언어 자체의 페이지 수를 사용합니다.

**항목 피드는 예외입니다.** `feed = true`일 때 각 항목의 RSS 피드는 `sort_by`와 무관하게 항상 역시간순(최신 우선)을 유지합니다. RSS 소비자는 최신 항목이 먼저 온다고 가정하기 때문입니다.

```toml
[[taxonomies]]
name = "tags"
sort_by = "title"
terms_sort_by = "count"
```

## 택소노미 사용

프론트 매터에서 항목을 지정합니다:

```markdown
+++
title = "My Post"
tags = ["crystal", "tutorial"]
categories = ["Programming"]
authors = ["Alice"]
+++
```

Zola 스타일의 `[taxonomies]` 테이블도 동작합니다(두 표기는 동등하며, 둘 다 있으면 명시적인 최상위 키가 우선합니다):

```markdown
+++
title = "My Post"
[taxonomies]
tags = ["crystal", "tutorial"]
tech = ["crystal", "security"]
+++
```

템플릿에서 페이지 자신의 항목은 `page.taxonomies.<name>`으로 접근합니다(예: `{% for t in page.taxonomies.tech %}`). `section.pages`, `site.pages`, 항목 페이지 목록 안의 페이지 객체에서도 동일하게 쓸 수 있습니다.

## 생성되는 URL

`tags` 택소노미에 `crystal` 항목이 있을 때:

| URL | 내용 |
|-----|---------|
| `/tags/` | 전체 태그 목록 |
| `/tags/crystal/` | "crystal" 태그가 붙은 페이지 |

`paginate_by`를 설정하면 항목 페이지가 `/tags/crystal/page/2/`, `/tags/crystal/page/3/`, … 로 페이지네이션됩니다(1페이지는 `/tags/crystal/`에 그대로 있습니다). 페이저 객체는 [데이터 모델 › Paginator](/ko/templates/data-model/#paginator)에 설명되어 있습니다.

다국어 사이트에서는 기본 언어가 아닌 각 언어가 자기 접두사 아래에 항목 페이지(`/ko/tags/crystal/`)를 따로 만들고, 그 언어의 페이지만 나열합니다. 언어별로 만들 택소노미는 `[languages.<code>] taxonomies`로 고르며, 생략하면 모든 `[[taxonomies]]` 이름이 쓰입니다. 자세한 내용은 [다국어](/ko/features/multilingual/)를 참고하세요.

## 콘텐츠로 항목 페이지 꾸미기

항목 페이지에도 제목, 설명, 본문을 직접 쓸 수 있습니다. `content/<taxonomy>/<slug>/`에 `_index.md`를 두면 되며, `<slug>`는 항목 페이지 URL의 마지막 부분입니다.

```markdown
+++
title = "Crystal"
description = "Crystal 언어에 관한 글"
image = "/images/crystal.png"

[extra]
icon = "gem"
+++

Crystal은 Ruby와 닮은 문법의 컴파일 언어입니다.
```

`content/tags/crystal/_index.md`는 `/tags/crystal/`을 꾸밉니다. 디렉터리 이름은 항목의 표기가 아니라 URL 슬러그입니다. `Rust Lang` 항목은 `/tags/rust-lang/`에 생성되므로 파일은 `content/tags/rust-lang/_index.md`입니다. 두 항목의 슬러그가 겹치면(`C#`과 `C++`는 둘 다 `c`) 두 번째 항목의 페이지는 `/tags/c-2/`가 되고, 파일도 `content/tags/c-2/_index.md`입니다.

항목 페이지에서는 이렇게 쓰입니다.

- `page.title`, `page.description`, `page.image`, `page.extra`가 파일의 값을 따릅니다. `title`이 없으면 생성된 "Tags: crystal"이 그대로 쓰입니다. `<title>`, og/twitter 태그, 항목 RSS 피드 제목도 같은 값을 씁니다.
- `term_content`에는 파일 본문을 렌더링한 HTML이 들어갑니다(Markdown, 숏코드, `@/` 링크를 다른 페이지와 똑같이 처리합니다). `content`는 지금처럼 생성된 페이지 목록이라 기존 템플릿은 그대로 동작하며, 본문을 보여 줄 자리에 `{{ term_content }}`를 넣으면 됩니다.
- [`get_taxonomy()`](#get-taxonomy-함수)의 항목에 파일의 `title`과 `description`이 붙습니다. `get_taxonomy()`는 사이트 전체를 보는 함수라 기본 언어 파일만 반영합니다. 파일이 없는 항목에는 `title` 키가 없으니 `{{ term.title or term.name }}`처럼 씁니다.

다국어 사이트에서는 언어마다 자기 파일을 읽습니다. `content/tags/crystal/_index.ko.md`는 `/ko/tags/crystal/`을 꾸밉니다.

이 파일은 별도 페이지로 게시되지 않습니다. 사이트맵, 피드, 검색 색인, llms.txt, 섹션 목록에 들어가지 않으므로 항목 URL은 한 번만 나옵니다. 어떤 항목 페이지와도 맞지 않는 파일(그 언어에서 해당 항목을 단 게시 페이지가 없거나, 디렉터리 이름이 항목 슬러그가 아닌 경우)도 게시되지 않으며, 빌드가 경고를 출력합니다.

한 단계 위의 `content/<taxonomy>/_index.md`는 다르게 동작합니다. 생성된 항목 목록이 전과 같이 `/tags/`에서 이 파일을 대체하고, 빌드는 대체 경고를 그대로 출력합니다. 택소노미를 메뉴에 넣을 때 쓰는 파일입니다.

## 템플릿

두 템플릿 모두 완성된 목록을 `{{ content }}`로 받습니다. `taxonomy.html`에는 항목 목록이, `taxonomy_term.html`에는 페이지 목록이 들어갑니다. 커스텀 마크업이 필요하면 `content` 대신 [`get_taxonomy()`](#get-taxonomy-함수)를 사용합니다.

### 택소노미 인덱스

`templates/taxonomy.html` — 전체 항목 목록:

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ page.title }}</h1>
{{ content }}
{% endblock %}
```

커스텀 항목 목록:

```jinja
{% set tax = get_taxonomy(kind=taxonomy_name) %}
<ul>
{% for term in tax.items %}
  <li>
    <a href="{{ get_taxonomy_url(kind=taxonomy_name, term=term.name) }}">
      {{ term.name }} ({{ term.count }})
    </a>
  </li>
{% endfor %}
</ul>
```

### 택소노미 항목

`templates/taxonomy_term.html` — 특정 항목의 페이지 목록:

```jinja
{% extends "base.html" %}

{% block content %}
<h1>{{ taxonomy_name }}: {{ taxonomy_term }}</h1>
{{ content }}
{% endblock %}
```

커스텀 페이지 목록으로, 현재 항목의 페이지를 `get_taxonomy()`로 조회합니다:

```jinja
{% set tax = get_taxonomy(kind=taxonomy_name) %}
{% for term in tax.items if term.name == taxonomy_term %}
<ul>
{% for p in term.pages %}
  <li><a href="{{ p.url }}">{{ p.title }}</a></li>
{% endfor %}
</ul>
{% endfor %}
```

## 템플릿 변수

`taxonomy.html`과 `taxonomy_term.html` 모두에서 사용 가능:

| 변수 | 타입 | 설명 |
|----------|------|-------------|
| taxonomy_name | String | 택소노미 이름("tags") |
| taxonomy_term | String | 현재 항목 이름(인덱스 페이지에서는 빈 문자열) |
| content | String | 미리 렌더링된 목록 HTML(항목 또는 페이지) |
| term_content | String | 항목 `_index.md` 본문을 렌더링한 HTML(항목 페이지 전용, 파일이 없으면 빈 문자열). [콘텐츠로 항목 페이지 꾸미기](#콘텐츠로-항목-페이지-꾸미기) 참고 |

### 항목 객체

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| name | String | 항목 이름 |
| slug | String | URL에 안전한 이름 |
| pages | Array<Page> | 이 항목이 붙은 페이지 |
| count | Int | 페이지 수 |
| title | String | 항목 `_index.md`의 제목(파일이 있을 때만) |
| description | String | 항목 `_index.md`의 설명(파일이 있을 때만) |

## get_taxonomy() 함수

어디서든 택소노미 데이터에 접근합니다:

```jinja
{% set tags = get_taxonomy(kind="tags") %}
{% if tags %}
<div class="tag-cloud">
{% for term in tags.items %}
  <a href="/tags/{{ term.slug }}/">{{ term.name }}</a>
{% endfor %}
</div>
{% endif %}
```

## get_taxonomy_url() 함수

택소노미 항목의 URL을 생성합니다:

```jinja
<a href="{{ get_taxonomy_url(kind='tags', term='crystal') }}">
  Crystal articles
</a>
```

## 자주 쓰는 패턴

### 태그 클라우드

```jinja
{% set tags = get_taxonomy(kind="tags") %}
<div class="tags">
{% for term in tags.items %}
  <a href="/tags/{{ term.slug }}/" 
     class="tag count-{{ term.count }}">
    {{ term.name }}
  </a>
{% endfor %}
</div>
```

### 페이지 태그 표시

```jinja
{% if page.tags %}
<div class="post-tags">
{% for tag in page.tags %}
  <a href="{{ get_taxonomy_url(kind="tags", term=tag) }}">{{ tag }}</a>
{% endfor %}
</div>
{% endif %}
```

`{{ tag | slugify }}` 대신 `get_taxonomy_url()`(또는 `get_taxonomy()`의 `term.slug`)을 사용합니다. 두 항목이 같은 슬러그로 충돌하면(`Crystal`과 `crystal`) 생성기는 `/tags/crystal/`과 `/tags/crystal-2/`를 만드는데, 어느 쪽이 어느 항목인지는 함수만 알고 있습니다.

### 카테고리 내비게이션

```jinja
{% set categories = get_taxonomy(kind="categories") %}
<nav class="categories">
{% for cat in categories.items %}
  <a href="/categories/{{ cat.slug }}/">
    {{ cat.name }} ({{ cat.count }})
  </a>
{% endfor %}
</nav>
```

## 함께 보기

- [섹션](/ko/writing/sections/) — 디렉터리로 콘텐츠 묶기
- [설정](/ko/start/config/) — 택소노미 설정 레퍼런스
- [데이터 모델](/ko/templates/data-model/) — 템플릿의 택소노미 변수
