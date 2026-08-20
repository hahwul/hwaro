+++
title = "check-links"
description = "콘텐츠 파일의 깨진 링크 검사"
weight = 3
+++

콘텐츠 파일에서 깨진 외부·내부 링크를 검사합니다.

```bash
hwaro tool check-links

# 결과를 JSON으로 출력
hwaro tool check-links --json

# 타임아웃과 동시 요청 수 지정
hwaro tool check-links --timeout 30 --concurrency 4

# 외부 또는 내부 링크만 검사
hwaro tool check-links --external-only
hwaro tool check-links --internal-only
```

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -c, --content-dir DIR | 콘텐츠 디렉터리 (기본값: `content`) |
| --timeout SECONDS | HTTP 요청 타임아웃(초, 기본값: 10) |
| --concurrency N | 최대 동시 요청 수 (기본값: 8) |
| --external-only | 외부 링크만 검사 |
| --internal-only | 내부 링크만 검사 |
| -j, --json | 결과를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

## 동작 방식

1. `content/` 디렉터리의 모든 마크다운 파일을 스캔
2. 외부 URL(http/https 링크)과 내부 링크(상대/절대 경로)를 수집
3. 외부 URL에 동시 HEAD 요청 전송
4. 내부 링크 대상이 디스크에 존재하는지 확인 (`.md`, `_index.md`, `index.md` 검사)
5. 빌드가 생성하는 경로는 소스 파일 없이도 유효한 것으로 인정
6. 깨졌거나 접근할 수 없는 링크 보고

### 생성 경로

일부 URL은 원본 파일이 없고 빌드가 직접 씁니다. 이런 경로는 `config.toml`에서
유도하므로, 첫 빌드 **이전**에도 `check-links`를 돌릴 수 있습니다(린트 후 빌드
순서로 도는 CI가 이 경우입니다).

- `/sitemap.xml`, `/robots.txt`, `/llms.txt`, 검색 인덱스, `404.html` — 각각
  설정된 `filename`을 따릅니다
- 피드(`/rss.xml`, `/atom.xml`) — 섹션별·언어별 사본(`/posts/rss.xml`,
  `/ko/rss.xml`) 포함
- 분류 목록·용어 페이지(`/tags/`, `/categories/rust/`)
- 페이지네이션 경로(`/posts/page/2/`) — `paginate_by`를 실제로 선언한 섹션에만
  해당하므로, 페이지네이션이 없는 섹션의 `/page/N/` 링크는 여전히 보고됩니다

## 링크 유형

| 유형 | 설명 |
|------|-------------|
| 외부 | `http://`, `https://` 링크 — HTTP HEAD로 검사 |
| 내부 | 상대·절대 경로 링크 — 파일 시스템에서 검사 |
| 이미지 | `![alt](path)` 이미지 참조 — 파일 시스템에서 검사 |

## 출력 예시

```
hwaro: check-links content
scan: 30 external, 20 internal

    [err] content/blog/post.md
      -> https://old-site.com/page  404
    [err] content/blog/post.md
      -> ../missing-page  Internal link target not found
    [err] content/about.md
      -> /images/photo.png  Image not found
checked: 50 links, 3 dead
```

색상 터미널에서는 깨진 링크마다 `hwaro check-links` 헤딩 아래 `✗ file` 항목과
`→ url status` 상세 줄로 표시되고, 마지막에 `✦ checked` 결과 줄이 붙습니다(모든
링크가 정상이면 `checked: 50 links · all healthy`). 깨진 링크가 발견되면 명령이
0이 아닌 종료 코드를 반환하므로 CI 게이트로 쓸 수 있습니다.

## JSON 출력

```json
{
  "dead_internal": [
    {
      "link": {
        "file": "content/about.md",
        "url": "/images/photo.png",
        "kind": "image"
      },
      "status": -1,
      "error": "Image not found"
    }
  ],
  "dead_external": [
    {
      "link": {
        "file": "content/blog/post.md",
        "url": "https://old-site.com/page",
        "kind": "external"
      },
      "status": 404,
      "error": null
    }
  ]
}
```
