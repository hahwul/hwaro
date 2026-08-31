+++
title = "데이터 모델"
description = "템플릿에서 사용하는 Site, Section, Page 데이터 타입"
weight = 2
toc = true
+++

Hwaro의 템플릿 시스템은 **Site**, **Section**, **Page** 세 가지 핵심 타입을 중심으로 동작합니다. 이 페이지는 **템플릿 쪽 레퍼런스**로, 템플릿을 만들 때 쓸 수 있는 모든 속성과 변수를 다룹니다. 콘텐츠 작성과 프론트 매터 필드 설정은 [콘텐츠 작성](/ko/writing/)을 참고합니다.

## 계층 구조

```
Site
├── Config (title, base_url, ...)
├── Pages[] (standalone pages)
├── Sections[]
│   ├── Pages[] (pages in section)
│   └── Subsections[]
│       ├── Pages[]
│       └── Subsections[] (recursive)
└── Taxonomies{}
    └── Terms{}
        └── Pages[]
```

### 관계

- **Site**는 여러 **Section**과 독립 **Page**를 포함합니다
- **Section**은 **Page**와 자식 **Subsection**을 포함합니다
- **Subsection**은 제한 없이 중첩됩니다
- **Taxonomy**는 항목별로 **Page**를 묶습니다

## Site

최상위 컨테이너입니다. `config.toml`에서 설정합니다.

### 속성

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| site.title | String | 사이트 제목 |
| site.description | String | 사이트 설명 |
| site.base_url | String | 기본 URL(끝 슬래시 없음) |
| site.pages | Array<Page> | 섹션에 속하지 않은 모든 페이지 |
| site.sections | Array<Section> | 모든 섹션 인덱스 페이지 |
| site.taxonomies | Object | 모든 택소노미 그룹과 항목 |
| site.data | Object | `data/` 디렉터리에서 불러온 데이터 |
| site.authors | Object | 집계된 작성자 데이터 |
| site.menus | Object | **기본 언어**의 이름 있는 메뉴([메뉴](#메뉴) 참고) |

### 플랫 별칭

| 변수 | 동일 표현 |
|----------|------------|
| site_title | site.title |
| site_description | site.description |
| base_url | site.base_url |

### 데이터 디렉터리

보조 데이터는 `data/` 디렉터리에 둡니다. `.yml`, `.yaml`, `.json`, `.toml`로 끝나는 파일은 자동으로 로드되어 `site.data`로 노출됩니다.

#### 파일 구조

```text
data/
├── authors.yml
├── products.json
├── config.toml
└── users/
    ├── alice.yml
    ├── bob.yml
    └── cho.yml
```

#### 데이터 접근

데이터는 확장자를 뺀 파일 이름으로 접근합니다.

예를 들어 `data/products.json`이 다음과 같다면:

```json
[
  {"name": "Widget", "price": 10},
  {"name": "Gadget", "price": 20}
]
```

템플릿에서 이렇게 접근합니다.

```jinja
{% for product in site.data.products %}
  <h2>{{ product.name }}</h2>
  <p>{{ product.price }}</p>
{% endfor %}
```

#### 하위 디렉터리

`data/` 아래의 하위 디렉터리는 중첩된 맵이 됩니다. 각 파일은 확장자를 뺀 파일 이름을 키로 하는 자식이 되고, 부모 디렉터리 자체는 순회할 수 있습니다.

위 구조에서 `data/users/alice.yml`, `data/users/bob.yml`, `data/users/cho.yml`은 다음과 같이 노출됩니다.

- `site.data.users.alice`, `site.data.users.bob`, `site.data.users.cho` — 개별 파일 내용
- `site.data.users` — 모든 사용자를 순회할 수 있는 맵

```jinja
{% for name, user in site.data.users %}
  <h3>{{ name }}</h3>
  <p>{{ user.bio }}</p>
{% endfor %}
```

디렉터리는 얼마든지 중첩됩니다: `data/users/admins/root.yml` → `site.data.users.admins.root`.

**타임아웃.** 소스마다 연결 10초, 읽기 1회당 30초, 그리고 전체 120초가 주어집니다. 마지막 제한은 모든 리디렉션 구간과 본문 전체를 아우르므로, 읽기 타임아웃을 아슬아슬하게 피하며 바이트를 흘려보내는 소스가 빌드를 붙잡아 둘 수 없습니다. 어느 하나라도 초과하면 다른 실패와 마찬가지로 `on_error`가 처리합니다.

**충돌.** 디렉터리와 파일이 같은 이름을 공유하면(예: `data/users.yml`과 `data/users/`가 나란히 있는 경우) **디렉터리가 우선**하고 파일은 무시됩니다. 가려진 파일이 조용히 사라지지 않도록 Hwaro는 빌드 중에 경고를 출력합니다.

### 원격 데이터 소스

`site.data`는 `config.toml`에 선언한 HTTP(S) 엔드포인트에서도 채울 수 있습니다. 각 소스는 **빌드당 한 번, 렌더링이 시작되기 전에** 가져옵니다. 템플릿은 네트워크 요청을 일으키지 않고, 빌드가 접근하는 모든 엔드포인트를 한곳에서 볼 수 있습니다.

```toml
[[data.remote]]
key = "team"                # site.data.team으로 노출
url = "https://api.example.com/team"
format = "json"             # json | toml | yaml | csv (생략 가능, 아래 추론 참고)
headers = { Authorization = "Bearer ${API_TOKEN}" }
cache = "1h"                # 캐시된 사본이 이 시간보다 젊으면 요청을 건너뜀
on_error = "fail"           # fail | warn-and-use-cache | warn-and-skip
```

템플릿에서는 로컬 데이터 파일과 똑같이 `site.data.team`으로 사용합니다. 따라서 어떤 키를 `data/team.json`과 원격 소스 사이에서 옮겨도 템플릿은 손댈 필요가 없습니다. 레코드를 템플릿에 공급하는 대신 페이지 자체로 만들려면 [콘텐츠 생성](/ko/features/content-generation/)을 참고하세요.

| 필드 | 필수 | 의미 |
|------|------|------|
| `key` | 예 | `site.data` 아래의 이름. 문자, 숫자, `_`, `-`만 허용하며 각 키는 한 번만 선언할 수 있습니다. 키는 대소문자를 구분하지 않고 비교합니다 — macOS와 Windows에서는 `Team`과 `team`이 같은 캐시 파일을 쓰게 되므로 중복으로 거부됩니다. |
| `url` | 예 | 절대 `http://` 또는 `https://` URL. 다른 스킴은 설정을 읽는 시점에 거부됩니다. |
| `format` | 아니요 | `json`, `toml`, `yaml`, `csv`. 생략하면 응답의 `Content-Type`, 그다음 (리디렉션을 모두 따라간 뒤) 실제로 도달한 URL의 파일 확장자에서 추론합니다. 둘 다 실패하면 `format`을 명시하라는 안내와 함께 가져오기가 실패합니다. |
| `headers` | 아니요 | 추가 요청 헤더. 자격 증명으로 취급되어 로그에 남지 않으며, 리디렉션이 원래 출처(origin)를 벗어나면 전송하지 않습니다. |
| `cache` | 아니요 | `"90s"`, `"30m"`, `"1h"`, `"7d"` 같은 디스크 캐시 TTL(`"1h30m"`처럼 조합 가능). 캐시가 신선한 동안에는 요청 자체를 건너뜁니다. `cache`가 없으면 매 빌드마다 다시 가져오지만, 마지막 페이로드는 `warn-and-use-cache`를 위해 항상 저장됩니다. |
| `on_error` | 아니요 | 가져오기나 파싱이 실패했을 때의 동작. `fail`(기본값)은 빌드를 중단하고, `warn-and-use-cache`는 경고 후 마지막으로 성공한 페이로드(나이 무관)로 빌드하며, `warn-and-skip`은 경고 후 이번 빌드에서 `site.data.<key>`를 비워 둡니다. |

CSV 페이로드는 행의 배열로 파싱되며 각 행은 공백을 제거한 문자열 셀의 배열입니다 — `load_data()`가 `.csv` 파일에 대해 만드는 것과 같은 모양입니다.

**환경 변수.** `url`과 `headers` 값의 `${VAR}`는 환경 변수로 치환됩니다. 참조한 변수가 설정되어 있지 않으면 변수 이름을 명시한 오류와 함께 빌드가 실패합니다(`config.toml`의 다른 곳에서는 경고에 그칩니다). 기본값이 필요하면 `${VAR:-default}`를 쓰세요. 이 오류는 소스를 실제로 가져오는 시점에 발생하므로, 네트워크를 쓰지 않는 `hwaro deploy`, `hwaro new`, `hwaro tool ...`은 변수를 내보내지 않아도 그대로 동작합니다.

**캐싱.** 페이로드는 `.hwaro/remote_data/` 아래에 캐시됩니다. `data/`를 비롯해 `hwaro serve`가 감시하는 어떤 디렉터리에도 속하지 않으므로, TTL 안의 serve 재빌드는 API를 다시 호출하는 대신 캐시를 재사용하고, 캐시 기록이 재빌드를 유발하지도 않습니다. 이 캐시는 `hwaro build --full`에도 지워지지 않으며(페이지 캐시만 초기화됩니다), `on_error = "warn-and-use-cache"`와 함께 오프라인 빌드를 가능하게 하는 것도 이 캐시입니다. `.hwaro/`는 `.gitignore`에 추가하세요. 긴 `hwaro serve` 세션에서는 각 소스를 한 번 가져와 메모리에서 재사용합니다. `cache` TTL이 있는 항목은 TTL이 만료된 뒤 첫 전체 재빌드에서 다시 가져오고, TTL이 없는 항목은 저장할 때마다가 아니라 세션당 한 번만 가져옵니다. 세션이 이미 페이로드를 갖고 있는 상태에서 재요청이 실패하면 `on_error` 설정과 무관하게 경고를 남기고 기존 페이로드를 계속 사용하므로, 오프라인에서도 편집을 이어갈 수 있습니다. `hwaro build`는 빌드마다 별도 프로세스이므로 영향이 없으며 `cache`/`on_error`를 그대로 따릅니다. 페이로드가 바뀌면 `data/` 파일을 편집했을 때와 같은 방식으로 캐시된 페이지가 무효화됩니다.

**충돌.** 원격 `key`가 디스크에도 존재하면(예: `key = "team"` 옆에 `data/team.json`) 두 소스를 모두 명시한 설정 오류가 발생합니다. 하나의 키는 정확히 하나의 소스만 가져야 하므로, `site.data.team`이 어느 쪽이 이기는지에 따라 조용히 달라지는 일은 없습니다.

원격 소스는 의도적으로 설정 전용입니다. `load_data()`와 숏코드는 URL을 받을 수 없습니다. 소스마다 GET 요청 하나 이상이 필요하다면 — 페이지네이션, POST 본문, 응답 가공 — [사전 빌드 훅](/ko/features/build-hooks/#api에서-데이터-가져오기)으로 `data/`에 받아 두세요.

### 사이트 작성자

Hwaro는 프론트 매터의 `authors` 필드(`authors = ["id"]`)에 정의된 모든 작성자를 `site.authors`로 자동 집계합니다.

#### 작성자 정의

`data/authors.yml`(또는 `.json`, `.toml`) 파일을 만들어 작성자 데이터를 보강할 수 있습니다. 키는 페이지 프론트 매터에서 쓴 작성자 ID와 일치해야 합니다.

**content/my-post.md**

```yaml
---
title: "My Post"
authors: ["john-doe"]
---
```

**data/authors.yml**

```yaml
john-doe:
  name: "John Doe"
  bio: "Creator of things."
  avatar: "/images/john.jpg"
```

#### 템플릿에서 사용

`site.authors` 객체는 사이트에서 발견된 모든 작성자를 담습니다. 각 작성자 객체는 다음을 갖습니다.
- `key`: 작성자 ID(예: "john-doe")
- `name`: 작성자 이름(데이터에서 가져오거나, 없으면 ID로 폴백)
- `pages`: 이 작성자가 쓴 페이지 목록(날짜순 정렬)
- `data/authors.yml`에 정의한 모든 커스텀 필드

```jinja
{% for id, author in site.authors %}
  <div class="author">
    <img src="{{ author.avatar }}" alt="{{ author.name }}">
    <h3>{{ author.name }}</h3>
    <p>{{ author.bio }}</p>

    <h4>Recent Posts</h4>
    <ul>
    {% for p in author.pages %}
      <li><a href="{{ p.url }}">{{ p.title }}</a></li>
    {% endfor %}
    </ul>
  </div>
{% endfor %}
```

### 예시

```jinja
<title>{{ site.title }}</title>
<link rel="canonical" href="{{ site.base_url }}{{ page.url }}">
```

---

## Section

관련 콘텐츠를 묶는, `_index.md`가 있는 디렉터리입니다.

### 속성

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| section.title | String | 섹션 제목 |
| section.description | String? | 섹션 설명 |
| section.pages | Array<Page> | 이 섹션의 페이지 |
| section.pages_count | Int | 페이지 수 |
| section.list | String | 미리 렌더링된 HTML 목록(`section_list`) |
| section.subsections | Array<Section> | 자식 섹션 |
| section.assets | Array<String> | 섹션의 정적 파일 |
| section.page_template | String? | 페이지 기본 템플릿 |
| section.paginate_path | String | 페이지네이션 URL 패턴 |
| section.redirect_to | String? | 리다이렉트 URL |

`section.html`에서 현재 섹션의 URL이 필요하면 `page.url`을 사용합니다.

### 플랫 별칭

| 변수 | 동일 표현 |
|----------|------------|
| section_title | section.title |
| section_description | section.description |
| section_list | 미리 렌더링된 페이지 HTML 목록 |

### 프론트 매터에서 오는 속성

| 속성 | 타입 | 기본값 | 설명 |
|----------|------|---------|-------------|
| sort_by | String? | "date" | 정렬 기준: date(최신순), weight(낮은 값 우선), title(A→Z) |
| reverse | Bool? | false | 기본 정렬 순서 뒤집기 — [콘텐츠 작성 › 섹션 › 정렬 방향](/ko/writing/sections/#정렬-방향) 참고 |
| paginate | Int? | — | 한 페이지에 표시할 페이지 수 |
| transparent | Bool | false | 페이지를 부모 섹션으로 전달 |
| generate_feeds | Bool | false | RSS 피드 생성 |

### 페이지 순회

```jinja
{% for p in section.pages %}
<article>
  <h2><a href="{{ p.url }}">{{ p.title }}</a></h2>
  <time>{{ p.date }}</time>
  {% if p.description %}
  <p>{{ p.description }}</p>
  {% endif %}
</article>
{% endfor %}
```

### 하위 섹션 순회

```jinja
{% for sub in section.subsections %}
<div class="category">
  <a href="{{ sub.url }}">{{ sub.title }}</a>
  <span>({{ sub.pages_count }} articles)</span>
</div>
{% endfor %}
```

### section_list 사용

단순한 목록에는 미리 렌더링된 HTML을 사용합니다.

```jinja
<ul>{{ section_list | safe }}</ul>
```

마크업을 직접 구성하려면 `section.pages`를 순회합니다.

```jinja
<ul>
{% for p in section.pages %}
  <li>
    <a href="{{ p.url }}">{{ p.title }}</a>
    {% if p.date %}<time>{{ p.date }}</time>{% endif %}
  </li>
{% endfor %}
</ul>
```

---

## Page

개별 콘텐츠 파일(`.md`)입니다.

### 핵심 속성

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| page.title | String | 페이지 제목 |
| page.description | String? | 페이지 설명 |
| page.url | String | 상대 URL 경로 |
| page.permalink | String? | base_url을 포함한 절대 URL |
| page.section | String | 부모 섹션 이름 |
| page.date | String? | 발행일(YYYY-MM-DD) |
| page.updated | String? | 마지막 수정일 |
| page.language | String | 적용된 언어 코드 |
| page.translations | Array<TranslationLink> | 언어별 번역본 |

렌더링된 HTML 콘텐츠는 최상위 `content` 변수로 제공됩니다.

### 메타데이터 속성

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| page.draft | Bool | 초안 여부 |
| page.weight | Int | 정렬 가중치 |
| page.image | String? | 대표 이미지 경로 |
| page.authors | Array<String> | 작성자 이름 |
| page.taxonomies | Object | 이 페이지의 택소노미 항목(`page.taxonomies.tags`, `page.taxonomies.<name>`) |
| page.extra | Object | 커스텀 프론트 매터 필드 |

### 계산 속성

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| page.word_count | Int | 단어 수 |
| page.reading_time | Int | 읽기 시간(분) |
| page.summary | String? | `<!-- more -->` 앞부분을 렌더링한 HTML. 마커가 없으면 `page.description`으로 폴백. 삽입할 때는 `\| safe`와 함께 사용(예: `{{ page.summary \| safe }}`). `<meta name="description">`에는 `page.description`을 직접 사용 |
| page.assets | Array<String> | 페이지 번들의 정적 파일 |
| page.series | String | 프론트 매터의 시리즈 이름(없으면 빈 문자열) |
| page.series_index | Int | 시리즈 안에서 1부터 시작하는 순번(`[series]` 활성화 필요) |
| page.series_pages | Array<Page> | 같은 시리즈의 모든 페이지(`series_weight` 순 정렬) |
| page.related_posts | Array<Page> | 택소노미 항목을 공유하는 페이지(`[related]` 활성화 필요) |

### 불리언 플래그

| 속성 | 타입 | 기본값 | 설명 |
|----------|------|---------|-------------|
| page.toc | Bool | false | 목차 표시 여부 |
| page.render | Bool | true | 렌더링 여부 |
| page.is_index | Bool | — | 인덱스 파일 여부 |
| page.generated | Bool | false | 자동 생성된 페이지 여부 |
| page.in_sitemap | Bool | true | 사이트맵 포함 여부 |
| page.in_search_index | Bool | true | 검색 인덱스 포함 여부 |

### 내비게이션 속성

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| page.lower | Page? | 읽기 순서상 이전 페이지 |
| page.higher | Page? | 읽기 순서상 다음 페이지 |
| page.ancestors | Array<Page> | 부모 섹션 체인 |
| page.translations | Array<TranslationLink> | 언어별 번역본 |

### 커스텀 메타데이터

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| page.extra | Object | 커스텀 프론트 매터 필드 |

### 플랫 별칭

| 변수 | 동일 표현 |
|----------|------------|
| page_title | page.title |
| page_description | page.description |
| page_url | page.url |
| page_section | page.section |
| page_date | page.date |
| page_image | page.image |
| page_summary | page.summary |
| page_word_count | page.word_count |
| page_reading_time | page.reading_time |
| page_permalink | page.permalink |
| page_authors | page.authors |
| page_weight | page.weight |
| page_language | page.language |
| page_translations | page.translations |
| taxonomy_name | 현재 택소노미 이름(택소노미 페이지) |
| taxonomy_term | 현재 택소노미 항목(택소노미 항목 페이지) |
| content | 렌더링된 HTML 콘텐츠 |

---

## 내비게이션 객체

### page.lower / page.higher

내비게이션은 mdBook이나 Docusaurus처럼 사이트 전체를 하나로 펼친 읽기 순서를 따릅니다. 페이지는 섹션 트리를 깊이 우선으로 순회하는 순서로 정렬됩니다: **섹션 인덱스 → 섹션 페이지 → 하위 섹션(재귀)**. 각 섹션 안에서는 그 섹션의 `sort_by` 설정(weight, date, title)에 따라 정렬됩니다.

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| .title | String | 페이지 제목 |
| .url | String | 페이지 URL |
| .description | String? | 페이지 설명 |
| .date | String? | 페이지 날짜 |

```jinja
<nav class="post-nav">
  {% if page.lower %}
  <a href="{{ page.lower.url }}">← {{ page.lower.title }}</a>
  {% endif %}
  
  {% if page.higher %}
  <a href="{{ page.higher.url }}">{{ page.higher.title }} →</a>
  {% endif %}
</nav>
```

### page.ancestors

브레드크럼에 쓰는 부모 섹션 목록:

```jinja
<nav class="breadcrumbs">
  <a href="/">Home</a>
  {% for ancestor in page.ancestors %}
  / <a href="{{ ancestor.url }}">{{ ancestor.title }}</a>
  {% endfor %}
  / <span>{{ page.title }}</span>
</nav>
```

### page.translations

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| .code | String | 언어 코드(예: "en") |
| .url | String | 번역된 페이지 URL |
| .title | String | 해당 언어의 제목 |
| .is_current | Bool | 현재 페이지의 언어인지 |
| .is_default | Bool | 기본 언어인지 |

```jinja
{% if page.translations %}
<nav class="lang-switcher">
{% for t in page.translations %}
  {% if t.is_current %}
  <span>{{ t.code | upper }}</span>
  {% else %}
  <a href="{{ t.url }}">{{ t.code | upper }}</a>
  {% endif %}
{% endfor %}
</nav>
{% endif %}
```

---

## page.extra 접근

프론트 매터의 커스텀 메타데이터:

```markdown
+++
title = "Review"

[extra]
rating = 4.5
featured = true
pros = ["Fast", "Reliable"]
+++
```

```jinja
{% if page.extra.featured %}
<span class="badge">Featured</span>
{% endif %}

<div class="rating">{{ page.extra.rating }} / 5</div>

<ul>
{% for pro in page.extra.pros %}
  <li>{{ pro }}</li>
{% endfor %}
</ul>
```

프론트 매터 최상위에 쓴 `outputs = ["json"]`도 마찬가지로 알려지지 않은 일반 키로 취급되어 `page.extra.outputs`에 들어갑니다 — 해당 페이지/섹션에 한해 `[outputs]` 설정 기본값을 재정의합니다. [출력 포맷](/ko/features/output-formats/)을 참고합니다.

---

### 시간 변수

| 변수 | 타입 | 설명 |
|----------|------|-------------|
| current_year | Int | 현재 연도(예: 2025) |
| current_date | String | 현재 날짜(YYYY-MM-DD) |
| current_datetime | String | 현재 날짜와 시간 |

```jinja
<footer>&copy; {{ current_year }} {{ site.title }}</footer>
```

---

### SEO 변수

**미리 렌더링된 HTML**(하위 호환):

| 변수 | 설명 |
|----------|-------------|
| og_tags | OpenGraph 메타 태그 |
| twitter_tags | Twitter Card 메타 태그 |
| og_all_tags | OG와 Twitter 태그 전부 |
| canonical_tag | 캐노니컬 링크 태그 |
| hreflang_tags | Hreflang 대체 링크 태그(다국어) |
| pagination_seo_links | `<link rel="prev/next">` 태그 |

```jinja
<head>
  {{ og_all_tags | safe }}
  {{ canonical_tag | safe }}
  {{ hreflang_tags | safe }}
  {{ pagination_seo_links | safe }}
</head>
```

메타 태그 마크업을 직접 구성할 때 쓰는 **구조화된 데이터**:

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| seo.canonical_url | String | 전체 캐노니컬 URL(base_url + 페이지 URL) |
| seo.og_type | String | OpenGraph 타입(기본: "article") |
| seo.og_image | String | 절대 경로로 해석된 이미지 URL |
| seo.twitter_card | String | Twitter 카드 타입(기본: "summary_large_image") |
| seo.twitter_site | String | Twitter 사이트 핸들 |
| seo.twitter_creator | String | Twitter 작성자 핸들 |
| seo.fb_app_id | String | Facebook 앱 ID |
| seo.hreflang | Array | `page.translations`와 동일 |

페이지 제목, 설명, URL, 이미지는 `page.title`, `page.description`, `page.url`, `page.image`로 얻습니다. `seo` 객체는 SEO에 특화된 계산 값(해석된 URL, 설정 값)을 제공합니다.

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
  <meta name="twitter:card" content="{{ seo.twitter_card }}">
  {% if seo.twitter_site %}
  <meta name="twitter:site" content="{{ seo.twitter_site }}">
  {% endif %}
</head>
```

---

### 에셋 변수

편의를 위해 미리 렌더링된 `<link>`·`<script>` 태그입니다. `config.toml` 설정에서 생성됩니다.

| 변수 | 설명 |
|----------|-------------|
| highlight_css | 구문 강조 CSS `<link>` 태그 |
| highlight_js | 구문 강조 JS `<script>` 태그 |
| highlight_tags | CSS와 JS 태그 전부 |
| auto_includes_css | 자동 인클루드된 CSS `<link>` 태그 |
| auto_includes_js | 자동 인클루드된 JS `<script>` 태그 |
| auto_includes | 모든 자동 인클루드 태그 |
| pwa_tags | PWA manifest 링크, theme-color 메타, 서비스 워커 등록 태그(`[pwa]` 비활성 시 빈 문자열) |

```jinja
<head>
  {{ highlight_css | safe }}
  {{ auto_includes_css | safe }}
</head>
<body>
  ...
  {{ highlight_js | safe }}
  {{ auto_includes_js | safe }}
</body>
```

---

### 목차

프론트 매터에 `toc = true`가 있을 때만 사용할 수 있습니다.

**미리 렌더링된 HTML**(하위 호환):

| 변수 | 타입 | 설명 |
|----------|------|-------------|
| toc | String | 생성된 목차 HTML |
| toc_obj.html | String | 같은 목차 HTML의 객체 형태 |

```jinja
{% if page.toc %}
<aside class="toc">
  {{ toc | safe }}
</aside>
{% endif %}
```

목차 마크업을 직접 구성할 때 쓰는 **구조화된 데이터**:

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| toc_obj.headers | Array | 구조화된 목차 헤더 객체 |
| toc_obj.headers[].level | Int | 헤딩 레벨(2-6) |
| toc_obj.headers[].id | String | 앵커 ID |
| toc_obj.headers[].title | String | 헤딩 텍스트 |
| toc_obj.headers[].permalink | String | 전체 앵커 퍼머링크 |
| toc_obj.headers[].children | Array | 중첩된 자식 헤더(같은 구조) |

```jinja
{% if page.toc %}
<nav class="toc">
  <ul>
  {% for h in toc_obj.headers %}
    <li>
      <a href="{{ h.permalink }}">{{ h.title }}</a>
      {% if h.children %}
      <ul>
        {% for child in h.children %}
        <li><a href="{{ child.permalink }}">{{ child.title }}</a></li>
        {% endfor %}
      </ul>
      {% endif %}
    </li>
  {% endfor %}
  </ul>
</nav>
{% endif %}
```

---

### Paginator

섹션·택소노미 항목 템플릿에서 페이지네이션이 활성화된 경우([섹션 프론트 매터](/ko/writing/sections/#프론트-매터)의 `paginate`, 택소노미는 `paginate_by`) 사용할 수 있습니다. 1페이지는 섹션 URL에, 이후 페이지는 `{url}/{paginate_path}/{n}/`에 생성됩니다.

| 속성 | 타입 | 설명 |
|----------|------|-------------|
| paginator.paginate_by | Int | 페이지당 항목 수 |
| paginator.base_url | String | 페이저 기본 URL(`{url}/{paginate_path}/`) |
| paginator.number_pagers | Int | 전체 페이지 수 |
| paginator.first | String | 첫 페이지 URL |
| paginator.last | String | 마지막 페이지 URL |
| paginator.previous | String? | 이전 페이지 URL(첫 페이지에서는 nil) |
| paginator.next | String? | 다음 페이지 URL(마지막 페이지에서는 nil) |
| paginator.pages | Array<Page> | 현재 페이저의 페이지 목록 |
| paginator.current_index | Int | 현재 페이지 번호(1부터 시작) |
| paginator.total_pages | Int | `number_pagers`와 동일 |

같은 데이터를 `pagination_obj` 변형으로도 쓸 수 있습니다. `previous_url`, `next_url`, `first_url`, `last_url`, `current_page`, `total_pages`, `total_items`, `per_page`, `has_previous`, `has_next`, 그리고 `html`(미리 렌더링된 내비게이션, 플랫 변수 `pagination`으로도 제공)을 노출합니다.

```jinja
{% if paginator is defined and paginator.number_pagers > 1 %}
<nav>
  {% if paginator.previous %}<a href="{{ paginator.previous }}">Prev</a>{% endif %}
  <span>{{ paginator.current_index }} / {{ paginator.number_pagers }}</span>
  {% if paginator.next %}<a href="{{ paginator.next }}">Next</a>{% endif %}
</nav>
{% endif %}
```

---

### 택소노미 변수

택소노미 템플릿에서 사용할 수 있습니다.

| 변수 | 타입 | 설명 |
|----------|------|-------------|
| taxonomy_name | String | 택소노미 이름(예: "tags") |
| taxonomy_term | String | 현재 항목 이름(인덱스 페이지에서는 빈 문자열) |
| content | String | 미리 렌더링된 목록 HTML(항목 또는 페이지) |

목록을 직접 구성하려면 `get_taxonomy()`를 사용합니다 — [택소노미](/ko/writing/taxonomies/) 참고.

---

## 메뉴

`site.menus`는 **기본 언어**의 이름 있는 메뉴(설정의 `[[menus.*]]` + 프론트 매터의 `menus`/`menu` 등록)를 노출합니다. 템플릿 안에서는 `site.menus.<name>`보다 `get_menu(name="...")`을 권장합니다 — **현재 페이지**의 언어를 기준으로 해석하고, 없으면 기본 언어로 폴백합니다.

```jinja
{% for item in get_menu(name="main") %}
<a href="{{ item.href }}"{% if item.url | active_path %} aria-current="page"{% endif %}>{{ item.name }}</a>
{% endfor %}
```

### 엔트리 속성

| 속성 | 타입 | 설명 |
|----------|------|--------------|
| name | String | 표시 레이블 |
| url | String | 아무것도 붙지 않은 루트 상대 경로, 또는 손대지 않은 외부 URL — `page.url`과 비교 가능 |
| href | String | 내부 링크면 `url`에 사이트 `base_path`를 적용한 값, 외부면 그대로 — `<a href>`에는 이 값을 사용 |
| identifier | String | 메뉴 안에서 고유한 키 |
| weight | Int | 정렬 순서 |
| external | Bool | `http://`, `https://`, `//` URL이면 `true` |
| children | Array\<Entry\> | `parent`가 이 엔트리의 `identifier`와 일치하는 중첩 엔트리 |
| page | Page? | 등록한 페이지의 데이터(프론트 매터로 등록된 엔트리만; 설정으로만 등록됐거나 섹션에서 등록된 엔트리는 nil) |

전체 설정/프론트 매터 레퍼런스, 계층 구조, 언어별 동작은 [메뉴](/ko/features/menus/)를 참고합니다.

---

## 타입 레퍼런스

### 요약표

| 타입 | 설명 |
|------|-------------|
| String | 텍스트 값 |
| String? | 선택적 텍스트(nil 가능) |
| Int | 정수 |
| Bool | true/false |
| Array<T> | T 타입의 목록 |
| Object | 키-값 맵 |

### 템플릿에서 확인

```jinja
{# Check for nil #}
{% if page.description %}...{% endif %}

{# Check for empty array #}
{% if page.authors %}...{% endif %}

{# Check for empty string #}
{% if page.description is present %}...{% endif %}

{# Default value #}
{{ page.description | default(value=site.description) }}
```

---

## 함께 보기

- [문법](/ko/templates/syntax/) — Jinja2 기본
- [함수](/ko/templates/functions/) — 데이터 조회 함수
- [필터](/ko/templates/filters/) — 값 변환
