+++
title = "doctor"
description = "설정·템플릿·구조 문제 진단"
weight = 4
+++

Hwaro 사이트의 설정, 템플릿, 구조 문제를 진단합니다.

> 콘텐츠 검증(프론트 매터, 대체 텍스트, 내부 링크)은 [`hwaro tool validate`](/ko/start/tools/validate/)를 사용합니다.

```bash
hwaro doctor

# 특정 콘텐츠 디렉터리만 검사
hwaro doctor -c posts

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
- `sitemap.priority`가 범위(0.0–1.0)를 벗어남
- 택소노미 이름 또는 언어 코드 중복
- `search.format`, `markdown.math_engine`, `pwa.cache_strategy` 값이 유효하지 않음
- `default_language`에 대응하는 `[languages.<code>]` 블록이 없음
- `deployment.target` / `[related] taxonomies`가 정의되지 않은 대상을 참조함
- `[[menus.*]]` 항목의 `parent`가 같은 메뉴의 어떤 identifier와도 맞지 않음
- 참조한 파일·디렉터리가 존재하지 않음 (`[og] default_image`, `[pwa] icons`,
  `[auto_includes] dirs`, `[[assets.bundles]] files` 등). 자체 origin을 가진 값
  (`https://…`, `//cdn…`, `data:…`)은 원격 URL이라 검증할 수 없으므로 건너뜁니다.

**템플릿 진단:**

- 템플릿 디렉터리를 찾을 수 없음
- 필수 템플릿 누락 (`page.html`, `section.html`)
- 빌드와 동일한 Crinja 파서로 검사한 템플릿 문법 오류
  (프로젝트 전용 숏코드 태그는 오류로 보지 않습니다)

**콘텐츠 진단:**

- 콘텐츠 디렉터리를 찾을 수 없음 (빌드해도 페이지가 생성되지 않음)
- 파싱에 실패하는 front matter (TOML/YAML)
- `[[menus.*]]`에 선언되지 않은 메뉴 이름을 front matter가 등록함

**구조 진단:**

- `_index.md`가 없는 섹션 디렉터리

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
    [ok]   markdown / pwa (valid enums)
    [ok]   deployment / related (refs resolve)
    [ok]   menus (parent references)
    [ok]   referenced files & dirs

  templates/
    [ok]   required files (page.html, section.html)
    [ok]   template syntax

  content/
    [ok]   directory present
    [ok]   front matter (TOML/YAML parse)
    [ok]   front matter menus (declared in config)
    [info] section index files (_index.md)

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
> 넣어도 CI 게이트를 끌 수 없습니다 — doctor는 계속 보고하고, 해당 항목이
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
| `deployment-target-undefined` | config | deployment.target에 대응하는 `[[deployment.targets]]` 없음 |
| `related-taxonomy-undefined` | config | `[related]`가 정의되지 않은 택소노미를 참조 |
| `menu-parent-undefined` | config | 메뉴 항목의 `parent`가 같은 메뉴의 identifier와 맞지 않음 |
| `config-path-missing` | config | 참조한 파일이 존재하지 않음 |
| `config-dir-missing` | config | 참조한 디렉터리가 존재하지 않음 |
| `missing-config-*` | config_missing | 설정 섹션 누락 (예: `missing-config-pwa`) |
| `template-dir-missing` | template | 템플릿 디렉터리를 찾을 수 없음 ✗ |
| `template-required-missing` | template | 필수 템플릿 누락 ✗ |
| `template-syntax-error` | template | 템플릿 파싱 실패 ✗ |
| `template-read-error` | template | 템플릿 읽기 실패 ✗ |
| `content-dir-missing` | content | 콘텐츠 디렉터리를 찾을 수 없음 |
| `content-frontmatter-invalid` | content | front matter 파싱 실패 ✗ |
| `content-read-error` | content | 콘텐츠 파일 읽기 실패 ✗ |
| `menu-undeclared` | content | front matter의 메뉴 이름이 설정에 선언되지 않음 |
| `structure-missing-index` | structure | `_index.md`가 없는 섹션 |

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
