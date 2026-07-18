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

- `base_url`이 설정되지 않음
- `base_url`이 `http://` 또는 `https://`로 시작하지 않음
- `base_url`에 끝 슬래시가 있음
- `title`이 기본값 그대로임
- `sitemap.changefreq` 값이 유효하지 않음
- `sitemap.priority`가 범위(0.0–1.0)를 벗어남
- 택소노미 이름 중복
- 언어 코드 중복
- `search.format` 값이 유효하지 않음

**템플릿 진단:**

- 템플릿 디렉터리를 찾을 수 없음
- 필수 템플릿 누락 (`page.html`, `section.html`)
- 닫히지 않은 블록 태그 (`if`, `for`, `block`, `macro`에 대응하는 `end` 없음)
- 짝이 맞지 않는 `{{ }}` 변수 태그

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
    [ok]   referenced files & dirs

  templates/
    [ok]   required files (page.html, section.html)
    [ok]   template syntax

  content/
    [ok]   front matter (TOML/YAML parse)

Config:
  [warn] config.toml: base_url is not set

Structure:
  [info] content/docs: Section directory missing _index.md: docs/

checked: 0 errors, 1 warning, 1 info

Tip: Use 'hwaro tool validate' for content checks
```

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

### 사용 가능한 규칙 ID

| ID | 분류 | 설명 |
|----|----------|-------------|
| `config-not-found` | config | 설정 파일을 찾을 수 없음 |
| `config-parse-error` | config | 설정 파싱 실패 |
| `base-url-missing` | config | base_url이 설정되지 않음 |
| `base-url-scheme` | config | base_url이 http(s)로 시작하지 않음 |
| `base-url-trailing-slash` | config | base_url에 끝 슬래시가 있음 |
| `title-default` | config | title이 기본값 그대로임 |
| `sitemap-changefreq-invalid` | config | 유효하지 않은 sitemap.changefreq |
| `sitemap-priority-range` | config | sitemap.priority가 범위를 벗어남 |
| `taxonomy-duplicate` | config | 택소노미 이름 중복 |
| `search-format-invalid` | config | 지원하지 않는 search.format |
| `language-duplicate` | config | 언어 코드 중복 |
| `missing-config-*` | config_missing | 설정 섹션 누락 (예: `missing-config-pwa`) |
| `template-dir-missing` | template | 템플릿 디렉터리를 찾을 수 없음 |
| `template-required-missing` | template | 필수 템플릿 누락 |
| `template-unclosed-block` | template | 닫히지 않은 블록 태그 |
| `template-mismatched-vars` | template | 짝이 맞지 않는 변수 태그 |
| `template-read-error` | template | 템플릿 읽기 실패 |
| `structure-missing-index` | structure | `_index.md`가 없는 섹션 |

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
  }
}
```
