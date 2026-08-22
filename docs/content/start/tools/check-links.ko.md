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

# 알려진 불안정 호스트 무시, 봇 차단 상태 코드 허용
hwaro tool check-links --ignore-url twitter.com --allow-status 403,429
```

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -c, --content-dir DIR | 콘텐츠 디렉터리 (기본값: `content`) |
| --timeout SECONDS | HTTP 요청 타임아웃(초, 기본값: 10) |
| --concurrency N | 최대 동시 요청 수 (기본값: 8) |
| --external-only | 외부 링크만 검사 |
| --internal-only | 내부 링크만 검사 |
| --ignore-url PATTERN | URL이 PATTERN과 일치하는 링크는 건너뜀 (반복 가능) |
| --allow-status CODES | 나열한 HTTP 상태 코드를 정상으로 취급 (쉼표 구분) |
| -j, --json | 결과를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

`--ignore-url`은 소스에 적힌 URL을 대소문자 구분 없는 부분 문자열로
매칭합니다 — `--ignore-url twitter.com`은 `twitter.com`(또는 `Twitter.com`)이
포함된 모든 링크를 건너뛰고, `*`는 임의 문자열과 매칭됩니다
(`--ignore-url 'https://example.com/*'`). 여러 번 전달할 수 있으며, 매칭된
링크에는 요청 자체를 보내지 않습니다. 무시된 개수는 스캔 라인과 JSON의
`ignored_count`에 함께 표시되므로, "모두 정상"과 "패턴이 과하게 넓어 아무것도
검사하지 않음"을 기계적으로 구분할 수 있습니다.

`--allow-status`는 브라우저에는 정상 응답하면서 링크 검사기에는 `403`/`429`를
돌려주는 호스트를 위한 것으로, 나열된 상태 코드는 CI를 실패시키지 않습니다.

## 동작 방식

1. `content/` 디렉터리의 모든 마크다운 파일을 스캔
2. 외부 URL(http/https 링크)과 내부 링크(상대/절대 경로)를 수집
3. 외부 URL에 동시 HEAD 요청 전송 (호스트가 HEAD를 405/403/501로 거부하면
   GET으로 재시도, 리다이렉트는 최대 5회 추적)
4. 내부 링크 대상이 디스크에 존재하는지 확인 (`.md`, `_index.md`, `index.md` 검사)
5. 빌드가 생성하는 경로는 소스 파일 없이도 유효한 것으로 인정
6. 깨졌거나 접근할 수 없는 링크 보고

사설/내부 주소(localhost, RFC 1918 대역, `.local`/`.internal` 호스트)로
해석되는 외부 링크에는 요청을 보내지 않습니다. 이런 링크는 사람용 출력과
JSON의 `skipped_external` 항목 모두에 "건너뜀"으로 보고됩니다.

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
  ],
  "skipped_external": [
    {
      "link": {
        "file": "content/notes/intranet.md",
        "url": "http://wiki.internal/page",
        "kind": "external"
      },
      "status": -1,
      "error": "Skipped: private/internal address"
    }
  ],
  "ignored_count": 0
}
```
