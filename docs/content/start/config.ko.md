+++
title = "설정"
description = "config.toml 사이트 설정 레퍼런스"
weight = 4
toc = true
+++

모든 사이트 설정은 프로젝트 루트의 `config.toml`에 있습니다.

최상위 키에 오타가 있으면 조용히 무시하지 않고 경고합니다. `[markdonw]`나
`titel = "…"` 같은 오타는 아무 안내 없이 기능을 꺼버리기 때문입니다. 실제
키와 비슷하면 다음처럼 후보를 함께 알려줍니다.

```
Unknown key 'markdonw' in config.toml — hwaro does not read it. Did you mean 'markdown'?
```

이 검사는 최상위 키만 대상으로 하며, 섹션 안에 중첩된 키는 각 섹션의
로더가 검증합니다.

## 사이트 설정

```toml
title = "My Site"
description = "Site description for SEO"
base_url = "https://example.com"
```

| 키 | 타입 | 설명 |
|-----|------|-------------|
| title | string | 사이트 제목 |
| description | string | 사이트 설명 |
| base_url | string | 프로덕션 URL (끝 슬래시 없음) |

## 환경 변수

`config.toml`에서 환경 변수를 참조할 수 있습니다. 값은 TOML 파싱 전에 치환됩니다.

```toml
base_url = "${SITE_URL}"
title = "$SITE_TITLE"
description = "${SITE_DESC:-My awesome site}"
```

| 문법 | 설명 |
|--------|-------------|
| `${VAR}` | 환경 변수 값으로 치환 |
| `$VAR` | 위와 동일 (축약형) |
| `${VAR:-default}` | `VAR`가 없거나 비어 있으면 `default` 사용 |

기본값 없이 누락된 변수는 그대로 남고 빌드 경고가 발생합니다. 템플릿에서의 사용법은 [환경 변수](/ko/features/env-variables/)를 참고합니다.

## 빌드 옵션

```toml
[build]
output_dir = "public"
drafts = false
parallel = true
cache = false
hooks.pre = ["npm install", "npx tsc"]
hooks.post = ["npm run minify"]
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| output_dir | string | "public" | 출력 디렉터리 |
| drafts | bool | false | 초안 콘텐츠 포함 |
| parallel | bool | true | 병렬 처리 |
| cache | bool | false | 빌드 캐시 사용 |
| hooks.pre | array | [] | 빌드 전에 실행할 명령 |
| hooks.post | array | [] | 빌드 후에 실행할 명령 |

오류 처리와 활용 사례는 [빌드 훅](/ko/features/build-hooks/)을 참고합니다.

## 마크다운

```toml
[markdown]
safe = false
lazy_loading = true
emoji = true
footnotes = true
task_lists = true
definition_lists = true
mermaid = false
math = false
math_engine = "katex"
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| safe | bool | false | 마크다운의 원시 HTML 제거 |
| lazy_loading | bool | false | 이미지에 `loading="lazy"` 자동 추가 |
| emoji | bool | false | 이모지 숏코드(예: `:smile:`)를 이모지 문자로 변환 |
| footnotes | bool | true | 각주 문법(`[^1]`) 사용 |
| task_lists | bool | true | 작업 목록 문법(`- [ ]` / `- [x]`) 사용 |
| task_list_classes | bool | false | 작업 목록 마크업에 GFM 클래스(`task-list-item`, `contains-task-list`) 추가 |
| definition_lists | bool | true | 정의 목록 문법(`Term\n: Definition`) 사용 |
| mermaid | bool | false | ` ```mermaid ` 블록을 `<div class="mermaid">`로 렌더링 |
| math | bool | false | 수식 문법(`$...$`, `$$...$$`) 사용 |
| math_engine | string | "katex" | 수식 렌더링 엔진 (`"katex"` 또는 `"mathjax"`) |
| smart_punctuation | bool | false | 타이포그래피용 인용부호/대시/줄임표 (`"x"` → “x”, `--` → –, `...` → …) |
| containers | bool | false | `:::note Title` … `:::` 커스텀 컨테이너 (admonition 마크업) |
| insert_anchor_links | string | "none" | 사이트 전역 헤딩 앵커 링크: `"none"`, `"left"`, `"right"` (페이지 프론트 매터가 우선) |
| external_links_target_blank | bool | false | 절대 http(s) 링크에 `target="_blank" rel="noopener"` 추가 |
| external_links_no_follow | bool | false | 절대 http(s) 링크에 `rel="nofollow"` 추가 |
| external_links_no_referrer | bool | false | 절대 http(s) 링크에 `rel="noreferrer"` 추가 |

문법 상세와 예시는 [마크다운 확장](/ko/features/markdown-extensions/)을 참고합니다.

## 퍼머링크

콘텐츠 디렉터리 경로를 다른 URL 경로로 다시 씁니다. 링크를 깨뜨리지 않고 사이트 구조를 바꿀 때 유용합니다.

```toml
[permalinks]
"old/posts" = "posts"
"2023/drafts" = "archive/2023"
```

| 원본 (디렉터리) | 대상 (URL 경로) | 적용 예 |
|-------------------|-------------------|----------------|
| `content/old/posts/a.md` | `posts/` | `/old/posts/a/` -> `/posts/a/` |

규칙은 선언 순서대로 평가되고, 페이지의 디렉터리와 (정확히 또는 상위 접두사로) **처음** 일치하는 원본이 선택됩니다 — 그 페이지에 대해 이후 규칙은 아예 확인하지 않습니다. 구체적인 접두사를 넓은 접두사보다 먼저 선언합니다(`"posts/tech"`를 `"posts"`보다 앞에). 그러지 않으면 넓은 규칙이 구체적인 규칙을 가립니다. 토큰 패턴에도 똑같이 적용되며, 특히 `""` catch-all 규칙은 다른 모든 규칙 **뒤에**, 맨 마지막에 둡니다.

### 토큰 패턴

`:token` 세그먼트가 들어간 대상은 Hugo 스타일 패턴으로, 디렉터리를 다시 매핑하는 대신 URL 전체를 새로 만듭니다:

```toml
[permalinks]
"posts" = "/:year/:month/:day/:slug/"
```

`content/posts/hello.md`의 날짜가 `2026-03-05`라면 페이지는 `/2026/03/05/hello/`에 게시됩니다.

| 토큰 | 확장 결과 |
|-------|------------|
| `:year` | 페이지 날짜의 연도 (`2026`) |
| `:month` | 페이지 날짜의 월, 0 채움 (`03`) |
| `:day` | 페이지 날짜의 일, 0 채움 (`05`) |
| `:slug` | 프론트 매터 `slug`, 없으면 파일명 스템 |
| `:title` | 슬러그화한 프론트 매터 `title` (슬러그화 결과가 비면 `:slug`로 대체) |
| `:section` | 페이지의 섹션 경로 (`posts/tech`); 루트 페이지는 비어 있어 세그먼트가 사라짐 |
| `:filename` | 파일명 스템, `slug` 오버라이드 무시 |

참고:

- 토큰은 경로 세그먼트 전체여야 하며, 알 수 없는 토큰은 설정 로드를 실패시킵니다.
- 패턴은 리프 페이지에만 적용됩니다. 섹션 `_index`와 번들 `index` 페이지는 패턴 규칙을 건너뜁니다(디렉터리 URL을 유지하거나, 뒤에 오는 일반 재매핑 규칙을 따릅니다).
- `date`가 없는 페이지가 `:year`/`:month`/`:day`를 쓰는 패턴에 걸리면 빌드가 실패합니다 — 날짜를 넣거나, 프론트 매터에 명시적 `path`를 설정하거나, 날짜 토큰을 뺍니다. 게시되지 않는 페이지는 예외입니다: 초안(`--drafts` 없이), 만료/미래 날짜 페이지, 헤드리스 `render: false` 페이지는 빌드를 막지 않습니다.
- 프론트 매터의 명시적 `path`는 어떤 퍼머링크 규칙보다 항상 우선합니다.
- 원본 키가 비어 있으면(`""` 또는 `"/"`) 패턴 규칙이 모든 페이지의 catch-all이 됩니다 — 처음 일치하는 규칙이 이기는 순서 규칙상 뒤의 규칙을 전부 가리므로 반드시 마지막에 선언합니다.
- 기본 언어가 아닌 언어에서는 `/lang/` 접두사가 먼저 옵니다: `/ko/2026/03/05/hello/`.

## 링크

빌드 중 해석되지 않는 `@/path.md` 내부 링크를 어떻게 처리할지 제어합니다.

```toml
[links]
broken_internal = "error"
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| broken_internal | string | "warn" | `"warn"`은 해석되지 않은 `@/` 링크를 하나씩 로그로 남기고 원본 마크업을 유지; `"error"`는 위반 전체를 하나의 목록으로 모아 빌드를 실패시킴 (종료 코드 5) |

`@/` 링크 문법과 strict 모드의 `--cache` 주의 사항은 [페이지](/ko/writing/pages/)를 참고합니다.

## 택소노미

```toml
[[taxonomies]]
name = "tags"
feed = true
paginate_by = 10

[[taxonomies]]
name = "categories"
feed = true
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| name | string | — | 택소노미 이름 (프론트 매터에서 사용) |
| feed | bool | false | 택소노미 항목마다 RSS 피드 생성 |
| sitemap | bool | true | 택소노미 페이지를 사이트맵에 포함 |
| paginate_by | int | — | 택소노미 항목 페이지의 페이지당 글 수 |
| sort_by | string | "date" | 항목 안 페이지 정렬 기준: `"date"`(최신순), `"title"`, `"weight"` |
| reverse | bool | false | `sort_by`가 만든 순서를 뒤집음 |
| terms_sort_by | string | "name" | 택소노미 인덱스의 항목 목록 정렬: `"name"` 또는 `"count"` |

항목 피드는 `sort_by`와 무관하게 항상 최신순을 유지합니다. 전체 정렬
규칙은 [택소노미](/ko/writing/taxonomies/#정렬)를 참고합니다.

## 메뉴

이름을 붙인 내비게이션 메뉴로, 템플릿에서 `site.menus` / `get_menu()`로 렌더링합니다.

```toml
[[menus.main]]
name = "Posts"
url = "/posts/"
weight = 1

[[menus.main]]
name = "About"
url = "/about/"
weight = 2
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| name | string | — | **필수.** 없으면 경고와 함께 항목을 건너뜀 |
| url | string | "" | 루트 상대 경로 또는 절대 `http(s)://`/`//` URL |
| weight | int | 0 | 메뉴 내 정렬 순서 |
| identifier | string | `name` | 다른 항목이 `parent`로 참조하는 고유 키 |
| parent | string | none | 다른 항목의 `identifier` 아래에 이 항목을 중첩 |

페이지/섹션은 이 파일을 건드리지 않고도 자기 프론트 매터(`menus = ["main"]`)로 메뉴에 참여할 수 있습니다. 메뉴 테이블이 없는 `[languages.<code>]` 블록은 이 전역 메뉴를 상속하고, `[[languages.<code>.menus.<name>]]`을 선언하면 그 언어에서는 전역 메뉴를 대체합니다. 전체 레퍼런스(계층 구조, 언어별 동작, `active_path` 스타일링)는 [메뉴](/ko/features/menus/)를 참고합니다.

## 정적 파일

`static/` 아래의 모든 것은 디렉터리 구조를 유지한 채 사이트 루트로 그대로 복사됩니다 — `static/css/app.css`는 `/css/app.css`로 서빙됩니다. 숨김 항목도 포함되므로 `static/.well-known/security.txt`는 `/.well-known/security.txt`로 게시됩니다. 기본적으로 Hwaro는 흔한 OS·에디터·VCS 잔여 파일을 걸러내 프로덕션에 실려 가지 않게 합니다.

```toml
[static]
use_default_excludes = true              # 내장 잔여 파일 필터 (기본값)
exclude = ["*.bak", "drafts/**"]         # 추가로 건너뛸 패턴
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| use_default_excludes | bool | true | 내장 잔여 파일 차단 목록 필터링 (`.DS_Store`, `Thumbs.db`, `desktop.ini`, `.git`, vim 스왑 파일, …) |
| exclude | array | [] | 추가로 건너뛸 패턴. `*.bak` 같은 글롭은 모든 깊이에서 매칭, `drafts/**`는 하위 트리로 한정, 리터럴 이름은 정확한 파일이나 디렉터리에 고정 (`drafts`는 `drafts/…`를 제외) |

내장 차단 목록은 잔여 파일만 제거합니다 — `.well-known/`, `.domains` 같은 정상적인 점(dot) 경로는 **절대** 걸러지지 않고 항상 게시되며, 콜드 빌드와 `--cache`/증분 빌드에서 동일하게 동작합니다. 내장 필터링을 완전히 끄려면 `use_default_excludes = false`로 설정합니다.

## 개발 서버

`hwaro serve`에만 적용되는 옵션입니다 — `hwaro build` 출력에는 영향을 주지 않습니다.

```toml
[serve]
fast = true                          # 항상 빠른 개발 모드로 서빙

[serve.headers]
X-Frame-Options = "SAMEORIGIN"
Cache-Control = "no-store"
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| fast | bool | false | `--fast`를 준 것처럼 서빙 (OG 이미지 생성과 이미지 처리 생략); 명시적 CLI skip 플래그는 그대로 적용 |
| headers | table | {} | 모든 개발 서버 응답에 추가하는 커스텀 HTTP 응답 헤더; 키가 겹치면 CLI `--header` 값이 우선 |

대응하는 CLI 플래그는 [CLI](/ko/start/cli/)의 serve 명령을 참고합니다.

## 기능 설정 레퍼런스

기능마다 전체 설정을 다루는 별도 문서가 있습니다. 아래는 `config.toml`의 모든 섹션을 정리한 빠른 레퍼런스입니다.

| 설정 섹션 | 문서 | 설명 |
|----------------|---------------|-------------|
| `[feeds]` | [SEO](/ko/features/seo/) | RSS/Atom 피드 생성 |
| `[sitemap]` | [SEO](/ko/features/seo/) | 사이트맵 XML 생성 |
| `[robots]` | [SEO](/ko/features/seo/) | robots.txt 생성 |
| `[og]` | [SEO](/ko/features/seo/) | OpenGraph & Twitter Card 메타 태그 |
| `[og.auto_image]` | [자동 OG 이미지](/ko/features/og-images/) | OG 미리보기 이미지 자동 생성 (빠른 개발 서버용 `lazy_generate` 포함) |
| `[search]` | [검색](/ko/features/search/) | 클라이언트 사이드 검색 인덱스 |
| `[highlight]` | [구문 강조](/ko/features/syntax-highlighting/) | 코드 구문 강조 |
| `[pagination]` | [페이지네이션](/ko/features/pagination/) | 섹션 페이지네이션 |
| `[auto_includes]` | [자동 인클루드](/ko/features/auto-includes/) | CSS/JS 파일 자동 인클루드 |
| `[assets]` | [에셋 파이프라인](/ko/features/asset-pipeline/) | CSS/JS 압축(minify) & 핑거프린팅 |
| `[sass]` | [Sass/SCSS](/ko/features/sass/) | 내장 SCSS 컴파일 (순수 Crystal) |
| `[image_processing]` | [이미지 처리](/ko/features/image-processing/) | 이미지 리사이즈 & LQIP |
| `[image_processing.lqip]` | [이미지 처리](/ko/features/image-processing/) | Base64 블러업 플레이스홀더 |
| `[content.files]` | [콘텐츠 파일](/ko/features/content-files/) | 마크다운이 아닌 파일 게시 |
| `[static]` | [정적 파일](#정적-파일) | `static/` 복사에서 잔여 파일 필터링 / 경로 제외 |
| `[serve]` | [개발 서버](#개발-서버) | 개발 서버 응답 헤더 & 빠른 모드 |
| `[links]` | [링크](#링크) | 깨진 내부 `@/` 링크 처리 (경고 또는 빌드 실패) |
| `[series]` | [시리즈](/ko/features/series/) | 글을 순서 있는 시리즈로 묶기 |
| `[related]` | [관련 글](/ko/features/related-posts/) | 관련 콘텐츠 추천 |
| `[llms]` | [LLMs.txt](/ko/features/llms-txt/) | AI/LLM 크롤러 안내 |
| `[pwa]` | [PWA](/ko/features/pwa/) | 프로그레시브 웹 앱 지원 |
| `[amp]` | [AMP](/ko/features/amp/) | Accelerated Mobile Pages |
| `[deployment]` | [배포](/ko/deploy/) | 배포 대상 설정 |
| `[doctor]` | [doctor](/ko/start/tools/doctor/) | 알려진 진단 이슈 숨기기 |
| `languages.*` | [다국어](/ko/features/multilingual/) | 다국어 지원 |
| `[[menus.*]]` | [메뉴](/ko/features/menus/) | 이름을 붙인 내비게이션 메뉴 |

## 플러그인

```toml
[plugins]
processors = ["markdown"]
```

## 전체 예시

핵심 섹션을 모두 담은 완전한 `config.toml`입니다. 복사해서 필요에 맞게 고치면 됩니다.

```toml
title = "My Blog"
description = "A blog about programming"
base_url = "https://myblog.com"
default_language = "en"

[build]
output_dir = "public"
drafts = false
parallel = true
cache = false
hooks.pre = ["npm ci"]
hooks.post = ["npm run optimize"]

[markdown]
safe = false
lazy_loading = true
emoji = false
footnotes = true
task_lists = true

[permalinks]
"old/posts" = "posts"
"posts" = "/:year/:month/:day/:slug/"

[plugins]
processors = ["markdown"]

[[taxonomies]]
name = "tags"
feed = true

[[taxonomies]]
name = "categories"

[[menus.main]]
name = "Posts"
url = "/posts/"

# 기능 섹션 — 위 기능 설정 레퍼런스 참고
# [feeds], [sitemap], [robots], [og], [search], [highlight],
# [pagination], [auto_includes], [assets], [sass], [image_processing],
# [series], [related], [llms], [pwa], [amp], [deployment], etc.
```

## 함께 보기

- [CLI](/ko/start/cli/) — 설정을 오버라이드하는 명령줄 옵션
- [환경별 설정](/ko/features/env-config/) — 환경별 오버라이드 (`config.production.toml`)
