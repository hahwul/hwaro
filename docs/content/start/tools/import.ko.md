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
| -v, --verbose | 상세 출력 표시 |
| -h, --help | 도움말 표시 |

## 동작

- 프론트 매터는 hwaro 기본 형식인 TOML(`+++`)로 변환됩니다. hwaro는 YAML 프론트 매터(`---`)도 지원하므로, 기본값을 바꾸려면 `config.toml`에 `[content.new].front_matter_format = "yaml"`을 설정하거나 가져온 뒤 `hwaro tool convert to-yaml`을 실행하면 됩니다.
- HTML 콘텐츠(예: WordPress)는 마크다운으로 변환됩니다.
- 대상 경로에 이미 있는 파일은 덮어쓰지 않고 **건너뜁니다**. 다시 가져오려면 먼저 삭제하거나 이름을 바꿔야 합니다.
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
