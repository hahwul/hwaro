+++
title = "export"
description = "다른 플랫폼으로 콘텐츠 내보내기"
weight = 10
+++

hwaro 콘텐츠를 다른 정적 사이트 생성기 형식으로 내보냅니다. `hwaro tool import`의 반대 방향 작업입니다.

```bash
# Hugo로 내보내기
hwaro tool export hugo

# Jekyll로 내보내기
hwaro tool export jekyll

# 출력·콘텐츠 디렉터리 지정
hwaro tool export hugo -o ~/hugo-site -c posts

# 초안 콘텐츠 포함
hwaro tool export jekyll --drafts

# 상세 출력
hwaro tool export hugo --verbose
```

## 지원 대상

| 대상 | 설명 |
|--------|-------------|
| hugo | Hugo 형식으로 내보내기 (TOML 프론트 매터, content/ 구조) |
| jekyll | Jekyll 형식으로 내보내기 (YAML 프론트 매터, _posts/ 파일명 규칙) |

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -o, --output DIR | 출력 디렉터리 (기본값: export) |
| -c, --content-dir DIR | 콘텐츠 디렉터리 (기본값: content) |
| -d, --drafts | 초안 콘텐츠 포함 |
| --dry-run | 아무것도 쓰지 않고 모든 대상 경로 미리보기 |
| -v, --verbose | 상세 출력 표시 |
| -j, --json | 파일별 매니페스트를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

같은 디렉터리로 다시 내보내면 이전 출력을 **대체**합니다. 이것이 일반적인
갱신 워크플로입니다. 기존 파일을 대체한 실행은 요약에 개수와 함께 경고가
표시되고, JSON 매니페스트에서는 해당 행이 `overwritten`으로 표시됩니다(새
대상은 `exported`). 쓰기 전에 전체 매니페스트를 보려면 `--dry-run`을
사용하세요.

## JSON 출력

```json
{
  "success": true,
  "dry_run": false,
  "exported_count": 2,
  "skipped_count": 0,
  "error_count": 0,
  "files": [
    { "path": "export/_posts/2024-01-01-hello.md", "action": "exported" },
    { "path": "export/about.md", "action": "overwritten" }
  ]
}
```

`files`에는 페이지 번들 에셋을 포함해 기록된 모든 대상 경로가 나열되며,
카운트는 콘텐츠 문서만 셉니다.

## 필드 매핑

### Hugo

| Hwaro | Hugo |
|-------|------|
| title | title |
| date | date |
| description | description |
| draft | draft |
| updated | lastmod |
| tags | tags |
| series | series |
| aliases | aliases |
| image | images (배열) |
| expires | expiryDate |
| weight | weight |
| [taxonomies] 테이블 | 최상위 `tags` / `categories` / … 로 승격 |

그 외 프론트 매터 키는 Hugo 페이지 파라미터로 그대로 전달됩니다.

출력 구조는 `export/content/` 아래에 원본 디렉터리 배치를 그대로 유지합니다.

### Jekyll

| Hwaro | Jekyll |
|-------|--------|
| title | title |
| date | date |
| description | description |
| draft = true | published: false |
| tags | tags |
| categories | categories |
| image | image |
| template | layout |
| [taxonomies] 테이블 | 최상위 `tags` / `categories` / … 로 승격 |

출력 규칙:
- 일반 글은 `_posts/`에 `YYYY-MM-DD-slug.md` 파일명으로 저장
- 초안 글은 날짜 접두사 없이 `_drafts/`에 저장
- 섹션 인덱스 파일(`_index.md`)은 `index.md` 페이지로 변환
- 프론트 매터는 TOML(`+++`)에서 YAML(`---`)로 변환
- `[taxonomies]` 테이블은 최상위 키로 승격됩니다. Hugo도 Jekyll도 중첩 테이블에서
  분류 소속을 읽지 않기 때문입니다. 같은 이름의 최상위 키가 이미 있으면 그쪽이
  우선하며, 이는 빌드가 둘을 해석하는 순서와 같습니다

## 내부 링크

`@/` 접두사를 쓰는 내부 링크는 자동으로 절대 경로로 변환됩니다:

```markdown
<!-- Hwaro -->
[About](@/about/_index.md)

<!-- Exported -->
[About](/about)
```

## 출력 예시

```
hwaro: export hugo
source: content
output: export
exported: 38 files, 4 skipped
```

`errors` 수는 오류가 발생했을 때만 덧붙습니다. 색상 터미널에서는 같은 보고서가
`hwaro export` 헤딩 아래 정렬된 행과 `✦ exported` 결과 줄로 표시됩니다.
