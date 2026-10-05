+++
title = "doctor"
description = "설정·템플릿·구조 문제 진단"
weight = 4
+++

Hwaro 사이트의 설정, 템플릿, 구조 문제를 진단합니다.

> 콘텐츠 검증(프론트 매터, 대체 텍스트, 내부 링크)은 [`hwaro tool validate`](/ko/start/tools/validate/)를 사용합니다.

```bash
hwaro doctor

# ./content가 아닌 콘텐츠 디렉터리 검사
hwaro doctor -c src/content

# 설정 값 정규화 (base_url 끝 슬래시, sitemap priority 등)
hwaro doctor --fix

# 권장 설정 섹션을 config.toml에 추가
hwaro doctor --approve

# 둘 다 수행 (--fix --approve와 동일)
hwaro doctor --full

# config.toml을 수정하지 않고 변경 사항 미리 보기
hwaro doctor --full --dry-run

# 결과를 JSON으로 출력
hwaro doctor --json
```

> `hwaro tool doctor`도 하위 호환 별칭으로 동작합니다.

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -c, --content-dir DIR | 검사할 콘텐츠 디렉터리 (기본값: content) |
| --fix | 실제 수정 수행 — 값 정규화 (base_url 끝 슬래시, sitemap priority 등) |
| --approve | 권장 선택 설정 섹션을 승인하고 추가 |
| --full | `--fix`와 `--approve`를 모두 수행 |
| --dry-run | `config.toml`을 수정하지 않고 변경 사항 미리 보기 |
| --strict | 종료 코드 계산 시 경고를 오류로 취급 |
| --max-warnings N | 경고 수가 N을 초과하면 0이 아닌 코드로 종료 |
| -j, --json | 결과를 JSON으로 출력 |
| -q, --quiet | 정보 출력과 배너 숨김 |
| -h, --help | 도움말 표시 |

## 검사 항목

**설정 진단:**

- `base_url`이 설정되지 않았거나 끝 슬래시가 있음
- `title`이 아직 자리표시자(`Hwaro Site`, `My Hwaro Site`)임
- `sitemap.changefreq` 값이 유효하지 않음
- `sitemap.priority`가 범위(0.0~1.0)를 벗어나거나 유한한 수가 아님 (`inf`, `nan`)
- 택소노미 이름 중복, 또는 대소문자만 다른 언어 코드 (`en` / `EN`)
- `search.format`, `markdown.math_engine`, `pwa.cache_strategy` 값이 유효하지 않음
- `default_language`에 대응하는 `[languages.<code>]` 블록이 없음
- `deployment.target` / `[related] taxonomies`가 정의되지 않은 대상을 참조함
- `[[menus.*]]` 항목의 `parent`가 같은 메뉴의 어떤 identifier와도 맞지 않음
- `[[versions.list]]` 항목의 콘텐츠 경로가 존재하지 않음
- 참조한 파일·디렉터리가 존재하지 않음 (`[og] default_image`, `[pwa] icons`,
  `[auto_includes] dirs`, `[[assets.bundles]] files` 등). 자체 origin을 가진 값
  (`https://…`, `//cdn…`, `data:…`)은 원격 URL이라 검증할 수 없으므로 건너뜁니다.
  - `[og] default_image`와 `[pwa] icons`는 URL 경로이므로 사이트가 실제로
    게시하는 파일, 즉 `static/`(사이트 루트로 복사됨) 아래의 파일,
    `[content.files]`가 게시하는 `content/` 파일, 또는 마지막 빌드 출력의 파일을
    가리켜야 합니다. `default_image`에 `static/` 접두사를 붙이면 파일이
    접두사 없이 게시되므로 이를 보고합니다.
  - `[auto_includes] dirs`는 빌드와 마찬가지로 `static/` 아래에서 찾습니다.
- 빌드가 컴파일하지 않는 SCSS 소스 (루트 `sass/` 디렉터리, 또는 `[sass]`가
  꺼진 상태의 `static/` 아래 엔트리 파일)
- 라우트 검사를 뒷받침할 수 없는 빌드 출력 (아래 [빌드 출력을 근거로 사용하기](#빌드-출력을-근거로-사용하기) 참고)

**템플릿 진단:**

- 템플릿 디렉터리를 찾을 수 없음
- `page.html` 누락 (error: 페이지가 레이아웃 없는 원본 콘텐츠로 렌더링됨).
  빌드가 `page.html` 대신 `default.html`을 사용하므로 `default.html`도 인정합니다.
- `section.html` 누락 (warning: 섹션 페이지가 `page.html`로 렌더링됨)
- 빌드와 동일한 Crinja 파서로 검사한 템플릿 문법 오류
  (빌드가 파싱 전에 펼치는 `{% alert(type="info") %}…{% end %}` 같은 블록 숏코드는
  오류로 보지 않지만, `{% includ %}`처럼 철자가 틀린 알 수 없는 태그는 오류입니다)

**콘텐츠 진단:**

- 콘텐츠 디렉터리를 찾을 수 없음 (빌드해도 페이지가 생성되지 않음)
- 파싱에 실패하는 front matter (TOML/YAML)
- `[[menus.*]]`에 선언되지 않은 메뉴 이름을 front matter가 등록함. 다른 언어의
  페이지는 그 언어가 자체 메뉴를 선언했다면 `[[languages.<code>.menus.*]]`
  기준으로 검사합니다.
- front matter의 `template`(또는 섹션의 `page_template`, `[cascade] template`)이
  존재하지 않는 템플릿을 가리킴. 빌드는 이를 조용히 기본 템플릿으로 대체합니다.

**구조 진단:**

- `_index.md`가 없는 섹션 디렉터리

**번역 보고** (언어가 둘 이상인 사이트):

- 기본 언어에는 있지만 다른 설정 언어에는 대응 페이지가 없는 페이지나 섹션
  (`translation-missing`)
- 기본 언어 원본이 없는 번역 (`translation-orphan`)

페이지는 빌드가 `page.translations`를 만들 때와 똑같이 짝지어집니다 (언어
접미사를 뺀 기본 이름이 같으면 한 묶음이므로 `about.md`, `about.en.md`,
`about.ko.md`는 서로 짝). 기본 빌드가 게시하는 페이지만 셈하므로, 초안이나
미래 날짜 페이지는 번역이 있다고도 없다고도 보지 않습니다. 둘 다 `info`
수준이라 `--strict`가 부분 번역 때문에 실패하지 않습니다. 사람용 보고서는 언어별로
묶어 개수와 함께 보여 줍니다.

```
Translations:
  ko: 2 missing · 1 without original
  [info] content/about.md: No 'ko' translation
  [info] content/blog/_index.md: No 'ko' translation
  [info] content/notes.ko.md: 'ko' translation has no 'en' original
```

`--json`에서는 이 항목들에 `language` 필드가 추가됩니다. 두 종류 모두
`[doctor] ignore`로 숨길 수 있습니다.

## 출력 예시

```
hwaro: doctor

  config.toml
    [ok]   file present & parseable
    [warn] base_url, title
    [ok]   sitemap (changefreq, priority)
    [ok]   taxonomies (duplicates)
    [ok]   search (format)
    [ok]   languages (default_language resolves)
    [ok]   versions (content paths exist)
    [ok]   markdown / pwa (valid enums)
    [ok]   image processing (widths set)
    [ok]   deployment / related (refs resolve)
    [ok]   menus (parent references)
    [ok]   referenced files & dirs
    [ok]   build output (route evidence)
    [ok]   sass (sources & enablement)

  templates/
    [ok]   required files (page.html, section.html)
    [ok]   template syntax

  content/
    [ok]   directory present
    [ok]   front matter (TOML/YAML parse)
    [ok]   front matter menus (declared in config)
    [ok]   front matter templates (exist)
    [info] section index files (_index.md)
    [ok]   translations (pages in every language)

Config:
  [warn] config.toml: base_url is not set

Structure:
  [info] content/docs: Section directory missing _index.md: docs/

checked: 0 errors, 1 warning, 1 info

Tip: Use 'hwaro tool validate' for content checks
```

스캔 자체가 실행되지 않은 검사는 통과(✓)가 아니라 `[--] … (skipped)`로
표시됩니다. 예를 들어 `templates/`가 없으면 `template syntax`가 그렇습니다.

색상 터미널에서는 검사 줄이 `hwaro doctor` 헤딩 아래 `✓`/`⚠`/`✗`/`ℹ` 기호로
표시되고, 요약은 심각도별 색이 입혀진 `✦ checked` 결과 줄로 출력됩니다. 문제가
없으면 `checked: no issues found — your site looks great`로 끝납니다.

## 빌드 출력을 근거로 사용하기

`[pwa] offline_page`와 `[pwa] precache_urls`는 파일이 아니라 라우트입니다.
doctor는 먼저 `content/`에서 찾고, 확장자가 있는 값(컴파일된 스타일시트,
리사이즈된 이미지 변형 등)은 마지막 빌드 결과인 `[build] output_dir`
(기본값 `public/`)에서 찾습니다.

이 디렉터리는 `hwaro build`가 만든 것이어야 합니다. Hwaro 0.19부터
`hwaro serve`는 `.hwaro/serve/`에 빌드하고 `output_dir`은 건드리지 않으므로,
serve만 쓰는 작업 흐름에서는 이 디렉터리가 없거나 예전 빌드에 멈춰 있습니다.
이제 doctor가 그 사실을 알려줍니다:

- **없거나 비어 있음** — 검증하지 못한 라우트와 함께 `build-output-unusable`로
  보고합니다: *"public/ holds no build output — run `hwaro build` first"*.
- **`hwaro serve` 출력** (`.hwaro-dev` 마커가 남은 경우) — `hwaro deploy`와 같은
  규칙으로 근거에서 제외합니다. 마커는 `hwaro build`가 지웁니다.
- **가장 최근 소스 파일보다 오래됨** — 그 트리로 통과시킨 라우트가 있으면
  `build-output-stale`로 보고합니다. 삭제한 페이지의 `index.html`이 아직 남아
  있을 수 있기 때문입니다.

둘 다 `info` 수준이며, 실제로 그 트리가 필요했을 때만 나타납니다. 빌드가
생성하는 경로를 참조하지 않는 사이트는 `public/` 이야기를 듣지 않습니다.

## 알려진 문제 무시

doctor가 보고하는 문제 중 이미 알고 있어 숨기고 싶은 것이 있으면, 해당 규칙 ID를 `config.toml`의 `[doctor]` 섹션에 추가합니다:

```toml
[doctor]
ignore = [
  "title-default",
  "structure-missing-index",
]
```

규칙 ID는 `hwaro doctor --json` 출력에서 확인하면 됩니다. 무시된 문제는 사람이 읽는 출력과 JSON 출력 모두에서 완전히 제외됩니다.

> `ignore`는 **warning**과 **info** 수준의 문제만 숨깁니다. 아래 표에서 ✗로
> 표시된 error 수준 규칙은 어차피 `hwaro build`를 실패시키는 문제라서 목록에
> 넣어도 CI 게이트를 끌 수 없습니다. doctor는 계속 보고하고, 해당 항목이
> 효과가 없다는 경고를 출력합니다.

### 사용 가능한 규칙 ID

✗ 표시가 있는 항목은 error 수준이며 무시할 수 **없습니다**.

| ID | 분류 | 설명 |
|----|----------|-------------|
| `config-not-found` | config | 설정 파일을 찾을 수 없음 ✗ |
| `config-parse-error` | config | 설정 파싱 실패 ✗ |
| `base-url-missing` | config | base_url이 설정되지 않음 |
| `base-url-trailing-slash` | config | base_url에 끝 슬래시가 있음 |
| `title-default` | config | title이 아직 자리표시자임 |
| `sitemap-changefreq-invalid` | config | 유효하지 않은 sitemap.changefreq |
| `sitemap-priority-range` | config | sitemap.priority가 범위를 벗어남 |
| `taxonomy-duplicate` | config | 택소노미 이름 중복 |
| `language-duplicate` | config | 언어 코드 중복 |
| `search-format-invalid` | config | 지원하지 않는 search.format |
| `default-language-undefined` | config | default_language에 대응하는 `[languages.<code>]` 없음 |
| `markdown-math-engine-invalid` | config | 지원하지 않는 markdown.math_engine |
| `pwa-cache-strategy-invalid` | config | 지원하지 않는 pwa.cache_strategy |
| `pwa-display-invalid` | config | 지원하지 않는 pwa.display |
| `image-processing-widths-empty` | config | image_processing이 켜져 있으나 widths가 비어 있음 (무음 no-op) |
| `deployment-target-undefined` | config | deployment.target에 대응하는 `[[deployment.targets]]` 없음 |
| `related-taxonomy-undefined` | config | `[related]`가 정의되지 않은 택소노미를 참조 |
| `menu-parent-undefined` | config | 메뉴 항목의 `parent`가 같은 메뉴의 identifier와 맞지 않음 |
| `version-path-missing` | config | `[[versions.list]]` 경로가 `content/` 아래에 없음 |
| `config-path-missing` | config | 참조한 파일이 존재하지 않음 |
| `config-dir-missing` | config | 참조한 디렉터리가 존재하지 않음 |
| `build-output-unusable` | config | `[build] output_dir`로 라우트를 검증할 수 없음 (없거나 `hwaro serve` 출력) |
| `build-output-stale` | config | 소스보다 오래된 빌드 출력으로 라우트를 통과시킴 |
| `sass-dir-not-scanned` | config | 빌드가 스캔하지 않는 루트 `sass/` 디렉터리에 SCSS 파일이 있음 |
| `sass-disabled-with-sources` | config | `[sass]`가 꺼진 상태에서 `static/` 아래에 SCSS 엔트리 파일이 있음 |
| `missing-config-*` | config_missing | 설정 섹션 누락 (예: `missing-config-pwa`) |
| `template-dir-missing` | template | 템플릿 디렉터리를 찾을 수 없음 ✗ |
| `template-required-missing` | template | `page.html`(또는 `default.html`) 누락 ✗ |
| `template-section-missing` | template | `section.html` 누락, 섹션은 `page.html`로 렌더링됨 |
| `template-syntax-error` | template | 템플릿 파싱 실패 ✗ |
| `template-read-error` | template | 템플릿 읽기 실패 ✗ |
| `content-dir-missing` | content | 콘텐츠 디렉터리를 찾을 수 없음 |
| `content-frontmatter-invalid` | content | front matter 파싱 실패 ✗ |
| `content-read-error` | content | 콘텐츠 파일 읽기 실패 ✗ |
| `menu-undeclared` | content | front matter의 메뉴 이름이 설정에 선언되지 않음 |
| `content-template-missing` | content | front matter의 `template` / `page_template` / `[cascade] template`이 없는 템플릿을 가리킴 |
| `structure-missing-index` | structure | `_index.md`가 없는 섹션 |
| `translation-missing` | i18n | 설정된 언어에 대응 페이지가 없는 페이지나 섹션 |
| `translation-orphan` | i18n | 기본 언어 원본이 없는 번역 |

어떤 규칙 ID와도 맞지 않는 항목은 "효과 없음" 경고로 알려주므로, 오타가 조용히
넘어가지 않습니다.

## JSON 출력

```json
{
  "schema_version": 1,
  "issues": [
    {
      "id": "base-url-missing",
      "level": "warning",
      "category": "config",
      "file": "config.toml",
      "message": "base_url is not set"
    }
  ],
  "summary": {
    "errors": 0,
    "warnings": 1,
    "infos": 0,
    "total": 1
  },
  "exit_code": 0
}
```
