+++
title = "버전별 문서"
description = "버전 전환기와 함께 여러 문서 버전을 나란히 게시"
weight = 23
toc = true
+++

Hwaro는 하나의 사이트에서 같은 문서의 여러 버전(v1, v2, …)을 게시할 수 있습니다. 버전 전환기, 버전별 내비게이션, 그리고 검색 엔진을 최신 릴리스로 안내하는 SEO를 제공합니다. 버전 관리는 **디렉터리 기반**이며 [다국어](/ko/features/multilingual/) 지원을 본떠 설계되었습니다. 페이지는 자신을 담고 있는 콘텐츠 디렉터리의 버전에 속합니다.

## 설정

```toml
[versions]
latest_at_root = true     # 최신 버전은 섹션의 원래 URL에 렌더링
noindex_old = true        # 이전 버전: <meta name="robots" content="noindex"> + 최신 대응 페이지로 canonical
search = "latest"         # "latest" | "all" — search.json과 sitemap.xml에 들어갈 버전
feeds = "latest"          # "latest" | "all" — RSS/Atom에 들어갈 버전
taxonomies = "latest"     # "latest" | "all" — 택소노미 용어 페이지가 수집할 버전

[[versions.list]]
name = "v2"               # URL 세그먼트, URL-safe 문자만 허용 (영문자, 숫자, - _ . ~)
label = "2.x (latest)"    # 전환기 라벨 (기본값: name)
path = "docs/v2"          # content/ 기준 콘텐츠 디렉터리 (기본값: name)
latest = true

[[versions.list]]
name = "v1"
label = "1.x"
path = "docs/v1"
```

TOML에서는 하나의 키가 테이블과 테이블 배열을 동시에 가질 수 없으므로, 스위치는 `[versions]`에, 항목은 `[[versions.list]]`에 둡니다. 기본값만 필요하다면 배열만 써도 됩니다:

```toml
[[versions]]
name = "v2"
path = "docs/v2"
latest = true

[[versions]]
name = "v1"
path = "docs/v1"
```

검증 규칙 (모두 `HWARO_E_CONFIG`로 빌드가 실패합니다):

- `name`은 필수이며 URL-safe하고 고유해야 합니다.
- `path`는 `content/` 기준 디렉터리여야 하며, 두 버전이 같은 경로를 쓰거나 서로 중첩될 수 없습니다.
- `latest = true`는 정확히 하나여야 합니다. 표시된 항목이 없으면 **첫 번째** 항목이 최신이 되고, 둘 이상이면 오류입니다.
- `search`, `feeds`, `taxonomies`는 `"latest"` 또는 `"all"`만 허용합니다.

`hwaro doctor`는 존재하지 않는 콘텐츠 디렉터리를 가리키는 버전이 있으면 `version-path-missing` 경고를 냅니다.

## 콘텐츠 구조

각 버전은 자기 디렉터리 아래의 일반 콘텐츠 트리입니다. 버전 루트 기준 상대 경로가 같은 파일은 다른 버전의 같은 페이지로 취급되며, 전환기는 이 규칙으로 대응 페이지를 찾습니다.

```
content/
└── docs/
    ├── v2/
    │   ├── _index.md
    │   ├── install.md
    │   └── plugins.md      # v2에만 존재
    └── v1/
        ├── _index.md
        ├── install.md
        └── legacy.md       # v1에만 존재
```

### URL 매핑

버전 디렉터리는 그 버전이 *게시되는* 디렉터리로 치환됩니다. `latest_at_root = true`(기본값)이면 최신 버전이 상위 디렉터리의 원래 URL을 차지하고, 이전 버전은 `/<name>/` 세그먼트를 갖습니다:

| 소스 | URL |
|------|-----|
| `content/docs/v2/_index.md` | `/docs/` |
| `content/docs/v2/install.md` | `/docs/install/` |
| `content/docs/v1/_index.md` | `/docs/v1/` |
| `content/docs/v1/install.md` | `/docs/v1/install/` |

`latest_at_root = false`이면 모든 버전이 세그먼트를 유지하고(`/docs/v2/install/`, `/docs/v1/install/`), `/docs/`는 최신 버전 루트로 향하는 리디렉션 스텁이 됩니다. 직접 `content/docs/_index.md`를 작성했다면 그 페이지가 URL을 유지합니다.

URL 세그먼트는 디렉터리 이름이 아니라 버전 **name**입니다. `name = "2.x"`, `path = "docs/v2"`라면 루트가 아닐 때 `/docs/2.x/…`에 게시됩니다. 버전 디렉터리는 최상위(`content/v2/…`)에 둘 수도 있으며, 이 경우 최신 버전이 사이트 루트가 됩니다.

참고:

- `latest_at_root = true`일 때는 `content/docs/_index.md`를 함께 두지 마세요. 최신 버전 루트와 같은 `/docs/` URL을 차지하므로 빌드가 출력 경로 중복을 보고합니다(작성한 파일이 우선하고 버전 루트는 기록되지 않습니다).
- `[permalinks]` 규칙과 `slug`는 소스 경로가 아니라 게시 경로(`docs/install.md`)에 적용됩니다.
- 프론트 매터의 명시적 `path = "…"`는 언어와 마찬가지로 항상 우선합니다. 커스텀 경로에는 접두어가 붙지 않으므로 버전 간에 서로 다르게 유지해야 합니다.
- 버전 디렉터리 아래의 모든 것이 버전에 속합니다: 페이지 번들, 에셋, `_index.md` 캐스케이드, 대상 경로가 그 안에 있는 `[[content.generate]]` 결과물까지.

### 다국어

언어와 버전은 함께 사용할 수 있습니다. 언어 접두어가 먼저, 버전이 그 뒤에 옵니다. `content/docs/v1/install.ko.md`는 `/ko/docs/v1/install/`에 렌더링되며, 버전 디렉터리 안의 `foo.ko.md` 파일은 다른 곳과 똑같이 동작합니다(번역 연결, hreflang, 언어별 메뉴).

## 템플릿 변수

### page.version

버전이 없는 페이지에서는 `nil`이므로(`{% if page.version %}`이 가드), 그 외에는:

| 속성 | 타입 | 설명 |
|------|------|------|
| `.name` | String | 버전 이름 (`"v2"`) |
| `.label` | String | 표시 라벨 (`"2.x (latest)"`) |
| `.latest` | Bool | 최신 버전인지 |
| `.url` | String | 페이지 언어 기준 버전 루트 URL (`/docs/`, `/ko/docs/v1/`) |

### page.version_links

설정된 버전마다 하나씩, 설정 순서대로 나열되며, 전환기의 각 행이 됩니다. 버전이 없는 페이지에서는 비어 있습니다.

| 속성 | 타입 | 설명 |
|------|------|------|
| `.name` | String | 버전 이름 |
| `.label` | String | 표시 라벨 |
| `.latest` | Bool | 최신 버전인지 |
| `.url` | String | 그 버전에 **같은 페이지**가 있으면 그 URL, 없으면 그 버전의 루트 |
| `.exists` | Bool | 대응 페이지 존재 여부 (`false`면 `url`은 버전 루트) |
| `.current` | Bool | 이 행이 현재 페이지의 버전인지 |

대응 페이지는 같은 언어에서 버전 루트 기준 상대 경로로 매칭됩니다: `docs/v1/install.md` ↔ `docs/v2/install.md`, `docs/v1/install.ko.md` ↔ `docs/v2/install.ko.md`. `render = false`인 대응 페이지는 존재하지 않는 것으로 취급합니다.

### versions (전역)

버전 사이트의 모든 페이지에서 사용할 수 있습니다. `{name, label, latest, url}` 항목의 리스트(`{% for v in versions %}`)이며 `url`은 현재 페이지 언어 기준 각 버전의 루트입니다. 추가로:

| 속성 | 설명 |
|------|------|
| `versions.latest` | 최신 버전 항목 |
| `versions.all` | 같은 리스트를 일반 배열로 |
| `versions.size` | 버전 개수 |

`page.url`처럼 위의 모든 URL은 사이트 상대 경로입니다. [서브패스 배포](/ko/start/config/#base-url)가 동작하도록 링크에는 `{{ base_url }}`(또는 `{{ base_path }}`)을 앞에 붙이세요.

## 버전 전환기 예시

```jinja
{% if page.version %}
<details class="version-switch">
  <summary aria-label="문서 버전 전환">
    {{ page.version.label }}
    {% if not page.version.latest %}<span class="badge">old</span>{% endif %}
  </summary>
  <ul>
    {% for v in page.version_links %}
    <li>
      <a href="{{ base_url }}{{ v.url }}"
         {% if v.current %}class="current" aria-current="page"{% endif %}
         {% if not v.exists %}title="이 페이지는 {{ v.label }}에 없습니다 — {{ v.label }} 시작 페이지로 이동"{% endif %}>
        {{ v.label }}{% if v.latest %} (latest){% endif %}
      </a>
    </li>
    {% endfor %}
  </ul>
</details>

{% if not page.version.latest %}
<div class="version-banner">
  {{ page.version.label }} 문서를 보고 있습니다.
  {% for v in page.version_links %}{% if v.latest %}
  <a href="{{ base_url }}{{ v.url }}">{% if v.exists %}{{ v.label }}에서 이 페이지 보기{% else %}{{ v.label }} 문서로 이동{% endif %}</a>
  {% endif %}{% endfor %}
</div>
{% endif %}
{% endif %}
```

현재 페이지에 의존하지 않는 사이트 전역 진입점:

```jinja
<a href="{{ base_url }}{{ versions.latest.url }}">Docs ({{ versions.latest.label }})</a>
<select onchange="location.href=this.value">
  {% for v in versions %}
  <option value="{{ base_url }}{{ v.url }}">{{ v.label }}</option>
  {% endfor %}
</select>
```

## 범위 규칙

각 버전은 독립된 트리이며, 경계를 넘어 새는 것은 없습니다:

| 대상 | 동작 |
|------|------|
| `page.lower` / `page.higher` | 읽기 순서는 `{언어, 버전}`별로 만들어집니다. 마지막 v1 페이지에는 "다음"이 없고 v2로 넘어가지 않습니다. |
| `page.ancestors` (브레드크럼) | 버전 루트에서 멈춥니다. 버전 없는 `docs/_index.md`는 `docs/v1/…`의 조상이 아닙니다. |
| `get_section()`, `section.pages`, `section.subsections` | 버전 루트는 버전 없는 상위 섹션의 하위 섹션이나 페이지가 아니며, 버전 안의 목록은 그 버전만 봅니다. |
| 메뉴 (`get_menu`) | 설정의 `[[menus.*]]` 항목은 어디에나 나타납니다. 버전 페이지의 프론트 매터 `menus = […]` 등록은 그 버전의 메뉴에만 나타나고, 버전 없는 페이지는 **최신** 버전의 등록을 추가로 봅니다. |
| 관련 글 | 버전 경계를 넘지 않습니다. |
| 택소노미 | 용어 페이지는 버전 없는 콘텐츠와 최신 버전에서 수집합니다(`taxonomies = "latest"`, 기본값). 모든 버전을 나열하려면 `taxonomies = "all"`. |

시리즈는 버전을 인식하지 않습니다. v1 페이지와 v2 페이지가 같은 `series`를 쓰면 함께 묶입니다.

## SEO와 탐색 표면

### Canonical과 noindex

이전 버전의 페이지는 **최신 대응 페이지**가 있으면 그쪽으로 canonical 링크를 내고(없으면 자기 자신), `noindex_old = true`(기본값)이면 바로 뒤에 `<meta name="robots" content="noindex">`를 붙입니다. 둘 다 `{{ canonical_tag }}`에서 나오므로 이미 이 변수를 출력하는 템플릿은 수정이 필요 없습니다. `seo.canonical_url`도 같은 규칙을 따르고 `seo.noindex`가 플래그를 노출합니다.

```html
<link rel="canonical" href="https://example.com/docs/install/">
<meta name="robots" content="noindex">
```

최신 버전 페이지는 평소처럼 자기 자신을 canonical로 가리킵니다. 페이지네이션된 목록은 계속 자기 자신을 가리킵니다(이전 섹션의 `page/2/`는 새 섹션의 `page/2/`가 아닙니다). `hreflang_tags`는 영향을 받지 않으며 같은 버전의 번역본을 연결합니다.

### 탐색 표면

| 표면 | 스위치 | 기본값 |
|------|--------|--------|
| `search.json` | `[versions] search` | 최신만 |
| `sitemap.xml` | `[versions] search` (같은 스위치) | 최신만 |
| RSS / Atom (메인, 섹션, 언어별) | `[versions] feeds` | 최신만 |
| 택소노미 용어 페이지 | `[versions] taxonomies` | 최신만 |
| `llms.txt` / `llms-full.txt` | — | 항상 최신만 |

버전 없는 페이지는 항상 포함됩니다. `search = "all"`이면 `search.json`의 모든 레코드에 `version` 필드(버전 이름)가 들어가므로 클라이언트에서 읽고 있는 버전으로 결과를 필터링할 수 있습니다:

```js
const current = document.documentElement.dataset.version; // 예: data-version="{{ page.version.name }}"
const hits = results.filter((r) => !r.version || r.version === current);
```

## 빌드 캐시, serve, doctor

- `[versions]`는 설정 해시에, 버전 소속은 페이지 집합 지문에 포함됩니다. 따라서 파일을 버전 디렉터리 간에 옮기거나, 대응 페이지를 추가하거나(다른 버전의 `version_links`에서 `exists`가 바뀜), 스위치를 바꾸면 `hwaro build --cache`가 바뀐 것을 다시 빌드합니다.
- `hwaro serve`는 버전 사이트도 다른 사이트처럼 빌드하며, 버전 디렉터리 안의 편집은 증분으로 반영됩니다.
- `hwaro doctor`는 디렉터리가 없는 `[[versions.list]]` 항목에 `version-path-missing`을 보고합니다.

## 포함되지 않은 것

- 최신 버전에만 존재하는 URL에 대한 리디렉션 규칙(이전 버전의 404는 그냥 404입니다).
- 버전을 인식하는 시리즈.
- `docs` 스캐폴드는 바뀌지 않았습니다. 생성된 사이트에는 위 스니펫으로 `[versions]`를 직접 추가하세요.

## 참고

- [다국어](/ko/features/multilingual/) — 버전과 결합되는 언어 계층
- [데이터 모델](/ko/templates/data-model/) — 모든 `page.*`와 전역 변수
- [SEO](/ko/features/seo/) — canonical, robots, 사이트맵 세부 사항
- [설정](/ko/start/config/) — 전체 `config.toml` 레퍼런스
