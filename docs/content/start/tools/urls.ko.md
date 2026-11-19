+++
title = "urls"
description = "빌드가 게시할 URL 미리보기"
weight = 9
+++

`hwaro build`가 게시할 모든 URL을 템플릿 렌더링이나 파일 쓰기 없이 나열합니다. 배포 전에 URL 변경을 검토하거나, CI에서 두 커밋의 라우트를 비교할 때 사용합니다.

목록은 빌드 자체에서 나옵니다. 이 명령은 빌드의 읽기·파싱·변환 단계를 실행한 뒤, 각 파일을 쓰는 바로 그 코드에 무엇을 쓸지 묻습니다. 초안, 미래 날짜, 만료된 페이지, `slug` / `path`, `[permalinks]`, 언어 접두사, 문서 버전, `[[content.generate]]` 페이지, 출력 경로 충돌이 모두 빌드와 똑같이 처리되며, 빌드가 출력하는 관련 경고(중복 출력 경로, 거부된 alias)는 stderr에 표시됩니다.

```bash
# 한 줄에 URL 하나, 정렬된 목록
hwaro tool urls

# `hwaro build --drafts`처럼 초안 포함
hwaro tool urls --drafts

# 다른 프로젝트 디렉터리와 환경 오버라이드
hwaro tool urls -i ./site -e production

# 종류와 소스 파일을 포함한 URL
hwaro tool urls --json
```

## 나열되는 항목

| 종류 | URL |
|------|------|
| `page` | 콘텐츠 페이지 (`[[content.generate]]` 페이지 포함) |
| `section` | 섹션 인덱스 페이지 (`_index.md`) |
| `alias` | `aliases`로 작성되는 리다이렉트 스텁. 실제로 쓰이는 파일의 URL로 표시됩니다(`/old/index.htm`은 `/old/`가 아니라 그대로 나옵니다) |
| `pagination` | 섹션과 택소노미 term의 페이저 페이지 (`/posts/page/2/`) |
| `taxonomy` | 택소노미 인덱스 페이지 (`/tags/`) |
| `term` | 택소노미 term 페이지 (`/tags/crystal/`) |
| `feed` | 사이트, 섹션, 언어, 택소노미 피드 (`/rss.xml`) |

URL은 사이트 루트 기준 경로(`/posts/hello/`)이며 빌드가 링크하는 표기 그대로입니다(파일 이름의 공백은 `%20`). `base_url`과 그 하위 경로는 포함되지 않으므로, 같은 콘텐츠를 쓰는 환경이라면 목록이 동일합니다.

그 자체로 라우트가 아닌 파일은 제외됩니다. 정적 파일과 페이지 번들 파일, `sitemap.xml`, `robots.txt`, `llms.txt`, 검색 인덱스, `404.html`, `[outputs]` 형식, AMP 미러가 해당합니다. `[build] hooks`는 실행되지 않으므로, `hooks.pre` 명령이 생성하는 콘텐츠는 디스크에 존재할 때만 나열됩니다. 다른 `hwaro tool` 명령과 마찬가지로 네트워크 요청을 하지 않습니다. `[[content.generate]]` 규칙이 [원격 데이터 소스](/ko/features/remote-data/)로 만드는 페이지는 나열되지 않으며, 해당 규칙을 알리는 경고가 출력됩니다.

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -i, --input DIR | 프로젝트 디렉터리 (기본값: 현재 디렉터리) |
| -e, --env ENV | 환경 이름 (`config.<env>.toml` 로드), 기본값은 `HWARO_ENV` |
| -d, --drafts | 초안 콘텐츠 포함 |
| --include-expired | 만료된 콘텐츠 포함 |
| --include-future | 미래 날짜 콘텐츠 포함 |
| -j, --json | 결과를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

`config.toml`의 `[build] drafts`는 빌드와 동일하게 적용됩니다.

## 출력 예시

```
/
/about/
/old-about/
/posts/
/posts/hello-world/
/posts/page/2/
/posts/rss.xml
/rss.xml
/tags/
/tags/crystal/
```

## JSON 출력

`source`는 URL의 원본 콘텐츠 파일이며 프로젝트 디렉터리 기준 상대 경로입니다. 작성된 파일이 없는 URL(택소노미 페이지, 피드, `[[content.generate]]` 페이지)은 `null`입니다.

```json
{
  "count": 3,
  "urls": [
    {"url": "/", "kind": "page", "source": "content/index.md"},
    {"url": "/old-about/", "kind": "alias", "source": "content/about.md"},
    {"url": "/tags/", "kind": "taxonomy", "source": null}
  ]
}
```

## CI에서 라우트 비교

```bash
# main을 풀 리퀘스트 옆에 체크아웃한 상태, 예: `git worktree add ../base origin/main`
hwaro tool urls -i ../base > before.txt
hwaro tool urls > after.txt
diff before.txt after.txt
```

사라진 줄은 배포 후 더 이상 열리지 않는 URL입니다. 이동한 페이지에 [alias](/ko/writing/pages/)를 추가하면 유지할 수 있습니다.
