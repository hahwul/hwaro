+++
title = "import"
description = "다양한 플랫폼에서 콘텐츠 가져오기"
weight = 11
+++

다른 정적 사이트 생성기나 플랫폼의 콘텐츠를 hwaro로 가져옵니다. [`hwaro tool export`](/ko/start/tools/export/)의 반대 방향 작업입니다.

```bash
# WordPress WXR 파일 가져오기
hwaro tool import wordpress path/to/export.xml

# Jekyll 사이트 디렉터리 가져오기
hwaro tool import jekyll path/to/jekyll-site

# Hugo 사이트 가져오기
hwaro tool import hugo path/to/hugo-site

# Notion 내보내기 가져오기
hwaro tool import notion path/to/notion-export

# Obsidian 볼트 가져오기
hwaro tool import obsidian path/to/vault

# 출력 디렉터리 지정과 초안 포함
hwaro tool import jekyll path/to/site -o content/blog --drafts

# 상세 출력
hwaro tool import hugo path/to/site --verbose
```

## 지원 소스

| 소스 | 입력 | 비고 |
|--------|-------|-------|
| wordpress | WXR XML 파일 | WordPress 내보내기 파일에서 글과 페이지를 가져옴 |
| jekyll | 사이트 디렉터리 | `_posts/`를 읽고 `--drafts` 사용 시 `_drafts/`도 읽음 |
| hugo | 사이트 디렉터리 | 섹션 배치를 유지하며 `content/`를 읽음 |
| notion | 내보내기 디렉터리 | Notion 내보내기의 `.md` 파일을 재귀적으로 가져옴 |
| obsidian | 볼트 디렉터리 | 노트를 재귀적으로 가져옴 (점으로 시작하는 폴더 제외) |
| hexo | 사이트 디렉터리 | `source/_posts/`와 `source/_drafts/`를 읽음 |
| astro | 사이트 디렉터리 | `src/content/` 컬렉션을 읽음 |
| eleventy | 사이트 디렉터리 | Eleventy 프론트 매터가 있는 마크다운 파일을 읽음 |

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -o, --output DIR | 출력 콘텐츠 디렉터리 (기본값: `content`) |
| -d, --drafts | 초안 콘텐츠 포함 |
| --force | 기존 파일을 건너뛰지 않고 덮어쓰기 |
| --dry-run | 아무것도 쓰지 않고 모든 대상 경로 미리보기 |
| -v, --verbose | 상세 출력 표시 |
| -j, --json | 파일별 매니페스트를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

`--dry-run`은 충돌로 인한 이름 변경과 건너뛰기 판정을 포함해 모든 대상 경로를
실제와 동일하게 해석하되 디스크는 건드리지 않으므로, 대규모 임포트가 정확히
무엇을 할지 실행 전에 확인할 수 있습니다.

## JSON 출력

```json
{
  "success": true,
  "dry_run": false,
  "imported_count": 2,
  "skipped_count": 1,
  "error_count": 0,
  "files": [
    { "path": "content/posts/hello.md", "action": "imported" },
    { "path": "content/posts/second.md", "action": "imported" },
    { "path": "content/posts/existing.md", "action": "skipped" }
  ]
}
```

`action`은 `imported`, `skipped`(대상이 이미 존재하고 `--force` 미지정),
`overwritten`(`--force`로 기존 파일 대체) 중 하나입니다.

## 동작

- 프론트 매터는 hwaro 기본 형식인 TOML(`+++`)로 변환됩니다. hwaro는 YAML 프론트 매터(`---`)도 지원합니다: 가져온 뒤 `hwaro tool convert to-yaml`을 실행하거나, 이후 `hwaro new`가 생성할 형식을 바꾸려면 `config.toml`에 `[content.new].front_matter_format = "yaml"`을 설정합니다. 다만 `front_matter_format`은 내장 템플릿에만 적용됩니다 — 아키타입은 자신의 프론트 매터를 그대로 사용하고 모든 스캐폴드가 `archetypes/default.md`를 포함하므로, 이 설정을 적용하려면 해당 파일(또는 매칭되는 아키타입)을 삭제해야 합니다. [아키타입](/ko/writing/archetypes/) 문서를 참고합니다.
- HTML 콘텐츠(예: WordPress)는 마크다운으로 변환됩니다.
- 대상 경로에 이미 있는 파일은 덮어쓰지 않고 **건너뜁니다**. 다시 가져오려면 먼저 삭제하거나 이름을 바꾸거나, `--force`를 사용합니다.
- 두 소스 파일이 **같은** 대상 경로로 해석될 때 — 슬러그 중복, 제목이 같은 두 노트, `YYYY-MM-DD-` 날짜 접두사 제거, 컬렉션 하위 폴더 두 개가 한 섹션으로 병합되는 경우 등 — 두 번째부터는 하나가 다른 하나를 조용히 덮어쓰지 않고 `slug-1.md`, `slug-2.md`, … 로 나란히 저장됩니다. 이름이 바뀐 대상의 개수는 파일마다 한 줄씩이 아니라 실행이 끝날 때 한 번만 보고됩니다.
- `--force`는 "이번 가져오기 이전부터 있던 파일을 덮어쓴다"는 뜻입니다. **같은 실행**에서 방금 쓴 파일을 다른 파일이 덮어쓰게 하지는 않습니다 — 그런 경우는 위의 `-1` / `-2` 접미사가 붙습니다. 따라서 가져오기를 다시 실행해도 결과가 같습니다: 각 소스는 처음에 선택한 대상으로 다시 해석되어 건너뛰거나(`--force`면 덮어쓰기) 처리되며, 실행할 때마다 `-1` 사본이 쌓이지 않습니다.
- 알려진 글 유형만 가져옵니다 (예: WordPress의 `post`와 `page`).

## 출력 예시

```
hwaro: import jekyll
source: ./old-blog
output: content
imported: 42 files, 3 skipped
```

`errors` 수는 오류가 발생했을 때만 덧붙고, 건너뛴 파일이 있으면 `--force`를
안내하는 경고가 표시됩니다. 색상 터미널에서는 같은 보고서가 `hwaro import` 헤딩
아래 정렬된 행과 `✦ imported` 결과 줄로 표시됩니다.

## 함께 보기

- [`hwaro tool export`](/ko/start/tools/export/) — hwaro 콘텐츠를 다른 형식으로 내보내기
- [페이지](/ko/writing/pages/) — 프론트 매터 레퍼런스
