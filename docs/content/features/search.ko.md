+++
title = "검색"
description = "Fuse.js로 동작하는 클라이언트 사이드 검색 인덱스 생성"
weight = 5
+++

Hwaro는 Fuse.js와 함께 사용할 수 있는 클라이언트 사이드 검색 인덱스를 생성합니다.

## 설정

`config.toml`에서 활성화합니다.

```toml
[search]
enabled = true
format = "fuse_json"
fields = ["title", "content", "description", "tags", "url", "section"]
filename = "search.json"
exclude = ["/private", "/drafts"]
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | false | 검색 인덱스 생성 여부 |
| format | string | "fuse_json" | 검색 인덱스 포맷 |
| fields | array | ["title", "content"] | 인덱스에 포함할 필드 — 기본값은 `title`과 `content`뿐 (`url`은 항상 추가) |
| filename | string | "search.json" | 출력 파일 이름 |
| exclude | array | [] | 검색 인덱스에서 제외할 경로(접두사) |
| tokenize_cjk | bool | false | CJK 바이그램 토큰화 활성화 |
| shards | string | "none" | 인덱스를 지연 로드 가능한 샤드로 분할: `"section"`, `"language"`, `"section-language"` — [샤드 인덱스](#샤드-인덱스) 참고 |
| single_file | bool | true | `shards` 사용 시 기존 `search.json`도 함께 생성; `false`면 샤드만 생성 |
| content_max_length | int | 0 | 0보다 크면 각 항목의 `content`를 단어 경계에서 해당 글자 수로 자름; `0`이면 전체 본문 유지 |
| split_by_heading | bool | false | h2/h3 섹션마다 `#heading`으로 바로 연결되는 레코드를 추가로 생성 — [제목 단위 레코드](#제목-단위-레코드) 참고 |
| facets | array | [] | 모든 레코드에 필터용 필드 추가: `"section"`, `"lang"`, `"tags"` 또는 택소노미 이름 — [패싯](#패싯) 참고 |
| ui | bool | false | 내장 검색 UI를 출력하고 `{{ search_tags }}`를 채움 — [내장 UI](#내장-ui) 참고. JSON `format` 필요 |

## 생성 파일

활성화하면 Hwaro가 `/search.json`을 생성합니다(`filename`으로 변경 가능).

```json
[
  {
    "title": "My Post",
    "url": "/blog/my-post/",
    "content": "Page content...",
    "description": "Post description",
    "section": "blog",
    "tags": ["tutorial"]
  }
]
```

## 인덱싱되는 필드

`fields`에 나열한 필드만 출력됩니다(`url`은 항상 포함).

| 필드 | 설명 |
|-------|-------------|
| title | 페이지 제목 |
| url | 페이지 URL |
| content | 페이지 본문(`fields`에 `"content"`가 있을 때) |
| description | 페이지 설명 |
| section | 섹션 이름 |
| tags | 페이지 태그 |

## 내장 UI

Hwaro는 작은 검색 UI를 함께 제공하므로 사이트마다 클라이언트를 직접 만들 필요가 없습니다. 의존성이 없고 다른 호스트로 요청을 보내지 않습니다.

```toml
[search]
enabled = true
format = "fuse_json"        # 또는 "elasticlunr_json"; *_javascript 포맷은 설정 오류
ui = true
split_by_heading = true     # 선택: 결과가 섹션으로 바로 연결됨
facets = ["section", "tags"] # 선택: 필터 칩
```

`<head>`에 `{{ search_tags }}`를 넣고, 검색을 여는 버튼을 추가합니다.

```jinja
<head>
  {{ search_tags }}
</head>
<body>
  <button type="button" data-hwaro-search>검색</button>
  ...
</body>
```

`ui = true`이면 빌드가 `assets/hwaro-search/search.js`와 `assets/hwaro-search/search.css`를 씁니다. `search_tags`에는 이 두 파일을 불러오는 `<link>`와 `<script defer>` 태그가 들어 있습니다.

- 두 URL 모두 `base_url`의 하위 경로와 `?v=` 캐시 버스팅 해시를 포함합니다.
- `[assets] sri = true`이면 `integrity`와 `crossorigin`도 붙습니다(`hwaro serve`에서는 제외).
- 스크립트는 설정을 `data-hwaro-search-config` 속성에서 읽으므로 페이지에 인라인 스크립트가 필요 없습니다. 엄격한 Content-Security-Policy에서도 그대로 동작합니다.

`ui`가 꺼져 있으면 `search_tags`는 빈 문자열이므로 템플릿에 조건 없이 넣어 두어도 됩니다.

### 동작

- **열기:** `/` 또는 `Cmd/Ctrl+K`를 누르거나 `data-hwaro-search` 속성이 있는 요소를 클릭하면 모달 대화상자로 열립니다. 페이지에 `data-hwaro-search-input` 속성을 가진 요소가 있으면 대신 그 요소 안에 인라인 검색창으로 붙고, 단축키는 그 입력창으로 포커스를 옮깁니다.
- **로딩:** 인덱스는 페이지 로드 때가 아니라 처음 열 때 가져옵니다. `shards`를 쓰면 `search/index.json`을 읽고 현재 언어의 샤드만 불러옵니다.
- **매칭:** 질의의 모든 단어에 대해 대소문자를 구분하지 않는 접두사·부분 문자열 매칭을 하며, 모든 단어가 일치해야 합니다. 제목 일치가 제목(heading) 일치보다, 제목(heading) 일치가 본문 일치보다 앞에 옵니다. `tokenize_cjk = true`이면 질의도 인덱스와 같은 CJK 바이그램으로 나눕니다. 결과는 최대 20개입니다.
- **결과:** 각 결과는 제목(› 소제목)과 일치한 단어가 강조된 발췌문을 보여 주고, 페이지나 `#heading`으로 연결됩니다.
- **패싯:** `facets`를 설정하면 결과에 나온 값으로 만든 칩으로 목록을 거를 수 있습니다.
- **언어:** 다국어 사이트에서는 현재 페이지 언어의 결과만 보여 줍니다.
- **키보드와 접근성:** ↑/↓로 결과를 옮기고 Enter로 열고 Esc로 닫습니다. 입력창은 listbox를 가리키는 ARIA combobox이고, 대화상자는 포커스를 가두며, 결과 개수는 `aria-live` 영역으로 알립니다.
- **보안:** 인덱스의 텍스트는 HTML이 아닌 텍스트 노드로만 페이지에 들어가고, 인덱스의 URL은 같은 출처의 `http(s)` URL만 링크합니다.

### 스타일

스타일시트는 CSS 사용자 정의 속성을 쓰고 `prefers-color-scheme`(그리고 `<html>`의 `data-theme="dark"`/`"light"`)를 따릅니다. 내 CSS에서 덮어쓰면 됩니다.

```css
.hwaro-search-overlay, .hwaro-search-inline {
  --hwaro-search-accent: #c2410c;
  --hwaro-search-radius: 4px;
  --hwaro-search-font: "Inter", sans-serif;
}
```

그 밖의 속성은 `--hwaro-search-bg`, `-fg`, `-muted`, `-border`, `-active`, `-mark`, `-backdrop`입니다.

빌드는 항상 자체 `assets/hwaro-search/` 파일을 씁니다. `static/` 아래 같은 경로에 파일이 있으면 덮어쓰고 경고를 남깁니다.

### 번역

UI 문구는 `i18n/<lang>.toml`에서 가져옵니다. 모든 키의 기본값은 영어입니다.

```toml
# i18n/ko.toml
[search]
placeholder = "검색"
no_results = "결과 없음"
results_count = "{count}개 결과"   # {count}는 개수로 바뀜
close = "닫기"
```

단수와 복수 형태를 나누려면 테이블을 씁니다(`pluralize` 필터와 같은 one/other 규칙).

```toml
[search.results_count]
one = "{count} result"
other = "{count} results"
```

키가 없으면 기본 언어, 그다음 영어 문구를 씁니다.

## 제목 단위 레코드

`split_by_heading = true`이면 각 페이지에 `h2`/`h3` 섹션마다 레코드가 하나씩 추가되어, 긴 페이지에서도 결과가 해당 부분으로 바로 이동합니다.

```json
{"title": "Install", "content": "Run the installer...", "url": "/docs/install/", "lang": "en"},
{"title": "Install", "content": "Download the binary...", "url": "/docs/install/#macos", "lang": "en", "heading": "macOS"}
```

- 페이지 레코드는 바뀌지 않습니다(옵션이 없는 빌드와 바이트 단위로 같음).
- `url`은 렌더링된 페이지의 실제 제목 `id`를 쓰며, 사용자 지정 id(`## macOS {#mac}`)도 그대로 따릅니다.
- `content`는 다음 `h2`/`h3`까지의 섹션 텍스트이며, 페이지 본문과 같은 HTML 제거, `tokenize_cjk`, `content_max_length`가 적용됩니다. `h4`–`h6`는 상위 섹션에 포함됩니다.
- 레코드에는 페이지의 나머지 `fields`, `lang`, `version`, 패싯도 들어갑니다.
- id가 없는 제목은 앞 섹션을 끝내지만 자기 레코드는 만들지 않습니다.
- 섹션 레코드는 페이지와 같은 포함 규칙을 따릅니다(`exclude`, `in_search_index = false`, 초안, `[versions] search`, 언어별 `build_search_index`). `shards`를 쓰면 페이지와 같은 샤드에 들어가고, 매니페스트의 `fields` 목록에 `heading`이 추가됩니다.

## 패싯

`facets`는 모든 레코드(페이지와 섹션 레코드)에 필터용 필드를 추가합니다.

```toml
[search]
facets = ["section", "lang", "tags", "category"]
```

| 패싯 | 값 |
|-------|-------|
| `section` | 페이지의 섹션 경로(`blog/news`) |
| `lang` | 페이지 언어(이미 모든 레코드에 있음) |
| `tags` | 페이지 태그 |
| 택소노미 이름 | 해당 택소노미의 페이지 용어(없으면 빈 목록) |

알 수 없는 이름은 유효한 이름 목록과 함께 경고를 남기고 무시합니다. 내장 UI는 패싯을 필터 칩으로 보여 주며, 직접 만든 클라이언트는 필드로 바로 거를 수 있습니다.

## 클라이언트 사이드 구현

### Fuse.js 사용

템플릿에 추가합니다.

```html
<script src="https://cdn.jsdelivr.net/npm/fuse.js@7.0.0"></script>
<script>
let searchIndex = [];

// Load index
fetch('/search.json')
  .then(res => res.json())
  .then(data => {
    searchIndex = data;
  });

// Initialize Fuse.js
function search(query) {
  const fuse = new Fuse(searchIndex, {
    keys: ['title', 'content', 'description', 'tags'],
    threshold: 0.3
  });
  return fuse.search(query);
}
</script>
```

### 검색 폼

```html
<form id="search-form">
  <input type="search" id="search-input" placeholder="Search...">
</form>

<div id="search-results"></div>

<script>
const input = document.getElementById('search-input');
const results = document.getElementById('search-results');

input.addEventListener('input', (e) => {
  const query = e.target.value;
  if (query.length < 2) {
    results.innerHTML = '';
    return;
  }
  
  const matches = search(query);
  results.innerHTML = matches
    .slice(0, 10)
    .map(m => `
      <a href="${m.item.url}">
        <h3>${m.item.title}</h3>
        <p>${m.item.description || ''}</p>
      </a>
    `)
    .join('');
});
</script>
```

## CJK 검색 지원

중국어·일본어·한국어 콘텐츠가 있는 사이트라면 CJK 토큰화를 켜서 검색 정확도를 높일 수 있습니다. CJK 언어는 단어 사이에 공백이 없는 경우가 많아 검색 라이브러리가 텍스트를 제대로 토큰화하기 어렵습니다.

이 옵션을 켜면 연속된 CJK 문자를 겹치는 바이그램(2글자 쌍)으로 분할하므로, 긴 텍스트 안에서도 검색어가 매칭됩니다.

**예:** `"검색엔진"` → `"검색 색엔 엔진"` (이제 검색어 `"검색"`이 매칭됨)

### 설정

```toml
[search]
enabled = true
tokenize_cjk = true
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| tokenize_cjk | bool | false | 검색 인덱스에 CJK 바이그램 토큰화 적용 |

### 동작 방식

- `title`, `content`, `description` 필드만 토큰화됩니다
- `url`, `tags`, `section` 필드는 구조용 필드이므로 그대로 둡니다
- CJK가 아닌 텍스트는 변경 없이 통과합니다
- Fuse.js와 ElasticLunr 포맷 모두에서 동작합니다

### 참고

- 이 옵션을 켜면 검색 인덱스 크기가 약간 커집니다
- 바이그램 방식은 대부분의 CJK 검색 시나리오에서 잘 동작합니다
- 자연스러운 공백이 있는 한국어 텍스트(예: `"검색 엔진"`)도 올바르게 처리됩니다

## 페이지 제외

### 프론트 매터

프론트 매터로 개별 페이지를 검색에서 제외합니다.

```markdown
+++
title = "Terms of Service"
in_search_index = false
+++
```

### 설정

`config.toml`로 섹션이나 경로 전체를 제외합니다.

```toml
[search]
exclude = ["/private", "/drafts"]
```

### 필드 선택

`fields`를 지정해 검색 인덱스에 들어갈 필드를 제어합니다.

```toml
[search]
enabled = true
fields = ["title", "description", "tags", "url"]
```

사용 가능한 필드: `title`, `content`, `description`, `tags`, `url`, `section`.

`fields`에서 `content`를 빼면 대규모 사이트에서 인덱스 파일 크기가 크게 줄어듭니다.

## 성능 팁

### 대규모 사이트

페이지가 많은 사이트라면:

1. `fields`에서 `"content"`를 제거해 인덱스 크기를 줄입니다
2. Fuse.js의 `ignoreLocation` 옵션을 사용합니다
3. 디바운스 검색을 구현합니다

```javascript
function debounce(fn, delay) {
  let timeout;
  return (...args) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => fn(...args), delay);
  };
}

input.addEventListener('input', debounce((e) => {
  // search logic
}, 200));
```

### 지연 로딩

검색창에 포커스가 왔을 때만 인덱스를 불러옵니다.

```javascript
let indexLoaded = false;

input.addEventListener('focus', async () => {
  if (indexLoaded) return;
  const res = await fetch('/search.json');
  searchIndex = await res.json();
  indexLoaded = true;
});
```

## 샤드 인덱스

`search.json` 하나는 사이트가 커질수록 함께 커지고, 방문자는 첫 검색 전에 파일 전체를 내려받아야 합니다. 샤딩은 인덱스를 여러 JSON 파일과 매니페스트로 나누어, 클라이언트가 필요한 것만(현재 섹션 먼저, 또는 언어별로) 불러올 수 있게 합니다.

```toml
[search]
enabled = true
shards = "section"          # "section" | "language" | "section-language"
single_file = false         # 샤드만 생성 (기본값 true는 search.json도 유지)
content_max_length = 500    # 선택: 각 항목의 content 길이 제한
```

| 모드 | 샤드 | id 예시 |
|------|------|---------|
| `"section"` | 최상위 콘텐츠 섹션마다 하나; 섹션 밖의 페이지는 `_root` | `blog`, `docs`, `_root` |
| `"language"` | 언어마다 하나(다국어 사이트); 기본 언어는 자신의 코드 사용 | `en`, `ko` |
| `"section-language"` | 언어, 그다음 섹션 | `en/blog`, `ko/blog`, `ko/_root` |

중첩 섹션은 최상위 섹션으로 합쳐집니다. `blog/news/post.md`는 `blog` 샤드에 들어갑니다. 이름이 `index`인 섹션은 `search/index.json`이 매니페스트이므로 `_index` 샤드로 저장됩니다. 기존 인덱스의 포함 규칙(`fields`, `exclude`, `in_search_index = false`, 초안, `render = false`, 언어별 `build_search_index`, `tokenize_cjk`)은 그대로 적용됩니다.

### 생성 파일

```
public/
├── search.json          # single_file = false가 아니면 생성
└── search/
    ├── index.json       # 매니페스트
    ├── _root.json
    ├── blog.json
    └── docs.json        # 중첩 id는 디렉터리 사용: search/ko/blog.json
```

각 샤드는 `search.json`과 완전히 동일한 항목 스키마를 가진 JSON 배열입니다(`format` 설정과 무관하게 샤드는 항상 JSON입니다. `*_javascript` 래퍼는 `<script src>` 로딩 전용입니다). `search/index.json`은 전체 구조를 설명합니다.

```json
{
  "version": 1,
  "fields": ["title", "content", "url", "lang"],
  "shards": [
    {"id": "_root", "url": "/search/_root.json", "language": null, "section": "", "count": 2, "bytes": 200},
    {"id": "blog",  "url": "/search/blog.json",  "language": null, "section": "blog", "count": 42, "bytes": 12345}
  ]
}
```

- `url`은 `base_url`의 하위 경로를 반영하고(`https://example.com/docs` 배포라면 `/docs/search/blog.json`), 섹션 이름은 퍼센트 인코딩됩니다.
- `language`는 `language`·`section-language` 모드에서, `section`은 `section`·`section-language` 모드에서 채워지고 나머지는 `null`입니다.
- 샤드는 id 순으로 나열되며 타임스탬프가 없어 출력이 결정적이고 diff하기 좋습니다. 마지막 페이지가 사라진 샤드는 다음 빌드에서 삭제됩니다.
- `--cache` 빌드와 `hwaro serve`도 `search.json`과 같은 페이지 집합에서 샤드를 다시 생성합니다.

### Fuse.js로 샤드 지연 로드

매니페스트를 한 번 받은 뒤 필요할 때 샤드를 불러옵니다. 전역 검색창은 모든 샤드를, 섹션 인식 검색창은 현재 섹션 샤드를 먼저 받고 나머지는 백그라운드에서 받습니다.

```html
<script src="https://cdn.jsdelivr.net/npm/fuse.js@7.0.0"></script>
<script>
const loaded = new Map();       // 샤드 id → 항목 배열
let manifest = null;
let fuse = null;

async function loadManifest() {
  if (manifest) return manifest;
  manifest = await (await fetch('/search/index.json')).json();
  return manifest;
}

async function loadShard(shard) {
  if (loaded.has(shard.id)) return;
  loaded.set(shard.id, await (await fetch(shard.url)).json());
  fuse = new Fuse([...loaded.values()].flat(), {
    keys: ['title', 'content', 'description', 'tags'],
    threshold: 0.3,
    ignoreLocation: true
  });
}

// 이 페이지에 필요한 샤드는? 문서 언어와 URL 첫 세그먼트로
// 매니페스트를 거르고, 해당 없으면 전체를 불러옵니다.
async function loadRelevantShards() {
  const { shards } = await loadManifest();
  const lang = (document.documentElement.lang || '').split('-')[0];
  const section = location.pathname.split('/').filter(Boolean)[0] || '';
  const local = shards.filter(s =>
    (s.language === null || s.language === lang) &&
    (s.section === null || s.section === section));
  await Promise.all((local.length ? local : shards).map(loadShard));
  // 첫 결과를 막지 않고 나머지 샤드를 미리 받아 둡니다.
  shards.filter(s => !loaded.has(s.id)).forEach(s => loadShard(s));
}

function search(query) {
  return fuse ? fuse.search(query) : [];
}

document.getElementById('search-input').addEventListener('focus', loadRelevantShards, { once: true });
</script>
```

전역 검색만 필요하면 `loadRelevantShards` 대신 `shards.map(loadShard)`를 사용하세요. 로드 이후는 위의 단일 파일 예제와 같은 Fuse.js 코드입니다.

## 대안: Pagefind

더 큰 사이트라면 [Pagefind](https://pagefind.app/)를 고려해 볼 만합니다.

```bash
# 빌드 후 실행
npx pagefind --site public
```

빌드 후 훅으로 설정에 추가합니다.

```toml
[build]
hooks.post = ["npx pagefind --site public"]
```

## 함께 보기

- [설정](/ko/start/config/) — 검색 설정 레퍼런스
- [다국어](/ko/features/multilingual/) — CJK 토큰화와 i18n 검색
