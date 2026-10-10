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
`files`에는 페이지 번들 에셋을 포함해 실행이 해석한 모든 대상 경로가
나열되며, 카운트는 콘텐츠 문서만 셉니다. 대상 경로를 해석하기 전에 건너뛴
소스(`--drafts` 없는 초안, 안전하지 않은 슬러그)는 카운트에만 반영되고 행은
없습니다.

## 동작

- 프론트 매터는 hwaro 기본 형식인 TOML(`+++`)로 변환됩니다. hwaro는 YAML 프론트 매터(`---`)도 지원합니다: 가져온 뒤 `hwaro tool convert to-yaml`을 실행하거나, 이후 `hwaro new`가 생성할 형식을 바꾸려면 `config.toml`에 `[content.new].front_matter_format = "yaml"`을 설정합니다. 다만 `front_matter_format`은 내장 템플릿에만 적용됩니다. 아키타입은 자신의 프론트 매터를 그대로 사용하고 모든 스캐폴드가 `archetypes/default.md`를 포함하므로, 이 설정을 적용하려면 해당 파일(또는 매칭되는 아키타입)을 삭제해야 합니다. [아키타입](/ko/writing/archetypes/) 문서를 참고합니다.
- HTML 콘텐츠(예: WordPress)는 마크다운으로 변환됩니다. 목록 항목과 표 셀 안의 링크·강조·코드는 그대로 유지되고, `[caption]` 숏코드는 이미지와 그 아래 캡션으로 바뀝니다. `&lt;script&gt;`처럼 엔티티로 인코딩된 마크업은 보이는 텍스트로 남습니다.
- WordPress의 "더 보기(Read more)" 태그와 Hexo의 `more` 주석은 hwaro의 요약 구분자로 유지되므로, 글의 [요약](/ko/writing/pages/)은 작성자가 정한 위치에서 그대로 끊깁니다.
- 날짜는 원본 생성기가 받아들이는 형식으로 읽습니다. RFC 3339, `2024-01-15 10:30:00 +0900`, 분 단위(`2024-01-15 10:30`), 슬래시 날짜(`2024/01/15 10:30:00`, 오프셋 포함 여부 무관), 영문 날짜(`July 8, 2022`, Astro 블로그 템플릿의 `Jul 08 2022`)를 지원합니다.
- 대상 경로에 이미 있는 파일은 덮어쓰지 않고 **건너뜁니다**. 다시 가져오려면 먼저 삭제하거나 이름을 바꾸거나, `--force`를 사용합니다.
- 두 소스 파일이 **같은** 대상 경로로 해석될 때(슬러그 중복, 제목이 같은 두 노트, `YYYY-MM-DD-` 날짜 접두사 제거, 컬렉션 하위 폴더 두 개가 한 섹션으로 병합되는 경우 등), 두 번째부터는 하나가 다른 하나를 조용히 덮어쓰지 않고 `slug-1.md`, `slug-2.md`, … 로 나란히 저장됩니다. 이름이 바뀐 대상의 개수는 파일마다 한 줄씩이 아니라 실행이 끝날 때 한 번만 보고됩니다.
- `--force`는 "이번 가져오기 이전부터 있던 파일을 덮어쓴다"는 뜻입니다. **같은 실행**에서 방금 쓴 파일을 다른 파일이 덮어쓰게 하지는 않습니다. 그런 경우는 위의 `-1` / `-2` 접미사가 붙습니다. 따라서 가져오기를 다시 실행해도 결과가 같습니다: 각 소스는 처음에 선택한 대상으로 다시 해석되어 건너뛰거나(`--force`면 덮어쓰기) 처리되며, 실행할 때마다 `-1` 사본이 쌓이지 않습니다.
- 알려진 글 유형만 가져옵니다 (예: WordPress의 `post`와 `page`).
- 페이지는 게시 주소를 유지합니다. Hugo `url`과 Jekyll의 리터럴 `permalink`(`:placeholder` 패턴이 아닌 것)는 `path`가 됩니다. `.html` 주소는 확장자 없는 `path`와 옛 주소의 별칭이 되고, 끝의 `index.html`은 별칭 없이 그 디렉터리로 매핑됩니다. 쿼리와 프래그먼트는 버립니다. 다른 종류의 파일을 가리키는 URL(`/feed.xml`)은 경고와 함께 매핑하지 않습니다. Jekyll `redirect_from` 항목은 `aliases`가 됩니다.
- Hugo: Hugo와 마찬가지로 프론트 매터 키의 대소문자를 구분하지 않습니다(`Title`, `Draft`, `publishdate` 모두 인식). JSON 프론트 매터도 TOML·YAML처럼 읽으며, `slug`가 있는 리프 번들은 슬러그 디렉터리 아래 번들(`posts/<slug>/index.md`)로 씁니다. 그 디렉터리에 이미 다른 번들이 있으면 경고와 함께 원래 디렉터리에 그대로 둡니다.
- Hugo: 미래의 `publishDate`로 예약된 페이지는 그 값을 `date`로 받아 그때까지 게시되지 않습니다(지난 `publishDate`라면 `date`를 유지). 출력이 없는 페이지(`headless = true`, 또는 `build`/`_build`의 `render = "never"`)는 `render = false`가 되고, `sitemap.disable = true`는 `in_sitemap = false`가 됩니다.
- Hexo: `published: false`인 글은 초안으로 가져옵니다.
- Hugo: `layout`은 `template`이 됩니다. Hugo에서 의미가 없는 hwaro 키(`toc`, `template`, `page_template`, `image`, `updated` 등)는 그대로 유지하고, 그 밖의 페이지 파라미터(최상위 사용자 키와 `[params]` 테이블)는 `[extra]`로 옮겨 템플릿에서 `page.extra.<key>`로 읽을 수 있습니다. `tool export hugo`가 쓰는 `[extra]` 테이블도 `[extra]`에 합쳐집니다.
- Jekyll: `last_modified_at`은 `updated`가 되고, `image: {path: …}` 형식은 `image`가 됩니다. 그 밖의 프론트 매터 키(Jekyll 템플릿이 `page.<key>`로 읽는 값)는 모두 `[extra]`로 옮겨집니다.
- Obsidian: Obsidian이 화면에 표시하지 않는 `%%주석%%`(한 줄 안이든 여러 줄에 걸치든)은 제거됩니다. 코드 안의 `%%`는 그대로 둡니다.
- 글자나 숫자가 하나도 없는 이름·제목(예: 이모지만 있는 Notion 페이지)은 건너뛰지 않고 원본 텍스트에서 만든 이름으로 저장합니다. 어떤 파일 이름도 만들 수 없는 소스는 그 사실을 알리는 경고와 함께 건너뜁니다.
- 비어 있는 `title:`은 제목이 없는 것으로 취급합니다. Obsidian은 파일 이름으로, Astro와 Eleventy는 파일 이름에서 만든 제목으로, Notion은 페이지의 첫 제목으로 대체합니다. 따옴표 없는 날짜 제목(`title: 2024-05-01`)은 작성한 그대로 유지됩니다.
- 페이지 사이의 링크는 대상이 실제로 저장된 파일을 가리킵니다. 제목이 같은 페이지의 `-1` 사본도 마찬가지입니다(Notion 페이지 링크, Obsidian `[[위키링크]]`). 표 안에서 필요한 Obsidian `[[노트\|별칭]]` 링크는 `[[노트|별칭]]`과 똑같이 처리되고, HTML 태그와 수식 안의 `#태그`·`[[링크]]`는 건드리지 않습니다.
- Jekyll·Hexo: `title`이 없는 글은 파일 이름에서 제목을 얻고, 날짜 접두사가 붙은 파일 이름도 다른 이름처럼 슬러그로 바뀝니다(`2024-01-01-Hello World.md` → `hello-world`).
- Hugo: 번역 파일(`about.ko.md`, `index.ko.md`)은 `slug`가 있어도 언어 접미사를 유지하고, 번역된 번들은 기본 언어 번들의 디렉터리를 따릅니다. `index.<lang>.md`와 `_index.md` 옆의 에셋도 함께 복사합니다. 에셋이 있는 Astro 번들은 파일과 함께 번들(`blog/<name>/index.md`)로 저장됩니다.
- Notion: 이모지 콜아웃(`> 💡 텍스트`)만 평탄화하고, 일반 인용문·코드 펜스·인라인 코드는 그대로 둡니다.
- WordPress: `<script>`와 `<style>`은 내용과 함께 제거되고, `<iframe>`, `<video>`, `<audio>` 임베드는 `src`(와 숫자 크기)만 가진 HTML로 유지됩니다.

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
