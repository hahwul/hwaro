+++
title = "validate"
description = "콘텐츠 프론트 매터와 마크업 검증"
weight = 8
+++

콘텐츠 파일의 프론트 매터 완결성, 접근성, 구조 정합성을 검증합니다.

```bash
# 모든 콘텐츠 파일 검증
hwaro tool validate

# 특정 콘텐츠 디렉터리 검증
hwaro tool validate -c posts

# JSON으로 출력
hwaro tool validate --json
```

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -c, --content DIR | 콘텐츠 디렉터리 (기본값: content) |
| -j, --json | 결과를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

## 검사 항목

- 프론트 매터에 `title` 누락
- 프론트 매터에 `description` 누락
- 대체 텍스트가 없는 이미지 (`![](url)`)
- 깨진 내부 링크 (해석되지 않는 `@/` 접두사 경로)
- 프론트 매터 파싱 오류 (TOML/YAML/JSON)
- 유효하지 않은 날짜 형식
- 대소문자가 섞인 태그 (예: `crystal` 대신 `Crystal`)
- 초안 파일 (info로 보고)

## 출력 예시

```
hwaro: validate content

content/blog/draft.md:
      [warn] Missing description in frontmatter
      [info] File is marked as draft

content/about.md:
      [warn] Image missing alt text: ![](photo.jpg)
      [info] Tag has mixed case: "Crystal" (consider lowercase)

checked: 0 errors, 2 warnings, 2 info
```

색상 터미널에서는 발견 항목이 `hwaro validate` 헤딩 아래 `⚠`/`✗`/`ℹ` 기호로
표시되고, 마지막 줄은 심각도별 색이 입혀진 `✦ checked` 결과입니다. 오류 수준
문제가 발견되면 0이 아닌 종료 코드를 반환하므로 CI 게이트로 쓸 수 있습니다.

## 규칙 ID

| ID | 수준 | 설명 |
|----|-------|-------------|
| `content-title-missing` | warning | title이 없거나 "Untitled"임 |
| `content-description-missing` | warning | description 누락 |
| `content-alt-text-missing` | warning | 대체 텍스트가 없는 이미지 |
| `content-internal-link-broken` | warning | 깨진 `@/` 내부 링크 |
| `content-date-invalid` | warning | 인식할 수 없는 날짜 형식 |
| `content-frontmatter-toml-error` | error | TOML 프론트 매터 파싱 오류 |
| `content-frontmatter-yaml-error` | error | YAML 프론트 매터 파싱 오류 |
| `content-frontmatter-json-error` | error | JSON 프론트 매터 파싱 오류 |
| `content-read-error` | error | 콘텐츠 파일 읽기 실패 |
| `content-tag-mixed-case` | info | 대소문자가 섞인 태그 |
| `content-draft` | info | 초안으로 표시된 파일 |

## JSON 출력

```json
{
  "findings": [
    {
      "file": "content/blog/draft.md",
      "line": null,
      "rule": "content-description-missing",
      "severity": "warning",
      "message": "Missing description in frontmatter"
    }
  ]
}
```
