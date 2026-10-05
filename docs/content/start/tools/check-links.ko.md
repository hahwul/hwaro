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

# #fragment 링크는 검사하지 않음
hwaro tool check-links --skip-anchors

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
| --skip-anchors | `#fragment` 링크를 빌드된 HTML과 대조하지 않음 |
| -j, --json | 결과를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

`--ignore-url`은 소스에 적힌 URL을 대소문자 구분 없는 부분 문자열로
매칭합니다. `--ignore-url twitter.com`은 `twitter.com`(또는 `Twitter.com`)이
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
4. 내부 링크 대상을 기본 빌드가 게시하는 페이지와 대조
   ([페이지 링크](#페이지-링크) 참고)
5. 빌드가 생성하는 경로는 소스 파일 없이도 유효한 것으로 인정
6. 파이프라인이 만들어 내는 에셋은 직전 빌드 출력에서 확인
   ([빌드 출력을 근거로 사용하기](#빌드-출력을-근거로-사용하기) 참고)
7. 내부 링크의 `#fragment`를 빌드된 HTML과 대조 ([앵커](#앵커) 참고)
8. 깨졌거나 접근할 수 없는 링크 보고

사설/내부 주소(localhost, RFC 1918 대역, `.local`/`.internal` 호스트)로
해석되는 외부 링크에는 요청을 보내지 않습니다. 이런 링크는 사람용 출력과
JSON의 `skipped_external` 항목 모두에 "건너뜀"으로 보고됩니다.

### 페이지 링크

페이지로 가는 링크는 기본 `hwaro build`가 그 URL에 페이지를 쓸 때만 유효합니다.
URL은 빌드와 같은 방식으로 원본에서 계산하므로 첫 빌드 전에도 그대로 적용됩니다.

- `slug`, `path`, `[permalinks]`로 정해진 URL과 모든 `aliases` 항목은 유효합니다
  (`/posts/original-name/`이 아니라 `/posts/renamed/`). 다른 곳에 게시되는
  페이지의 원본 경로로 링크하면, 실제로 게시되는 URL과 함께 보고됩니다.
- 초안, 미래 날짜·만료된 페이지, `render = false` 페이지로의 링크는 보고됩니다.
  빌드가 그 자리에 아무것도 쓰지 않기 때문입니다.
- `/about/`, `/about`, `/about/index.html`은 모두 `content/about.md`에 닿지만
  `/about.md`는 아닙니다. 빌드는 마크다운 원본을 원래 이름으로 게시하지 않습니다.
- 페이지 번들이나 섹션 인덱스 옆의 파일은 그 페이지의 URL 아래에서 유효하며,
  번역본에도 해당합니다(`/ko/posts/my-trip/photo.jpg`).
- 상대 링크는 원본 파일의 폴더가 아니라 브라우저처럼 페이지의 URL을 기준으로
  해석합니다. `/posts/a/`로 게시되는 `content/posts/a.md`에서 `../b/`는
  `/posts/b/`에 닿고, `![](photo.png)`는 `/posts/a/photo.png`를 요청합니다.
  페이지 이미지는 번들(`content/posts/a/index.md`)에 함께 두세요.

### 생성 경로

일부 URL은 원본 파일이 없고 빌드가 직접 씁니다. 이런 경로는 `config.toml`에서
유도하므로, 첫 빌드 **이전**에도 `check-links`를 돌릴 수 있습니다(린트 후 빌드
순서로 도는 CI가 이 경우입니다).

- `/sitemap.xml`, `/robots.txt`, `/llms.txt`, 검색 인덱스, `404.html`. 각각
  설정된 `filename`을 따릅니다
- 피드(`/rss.xml`, `/atom.xml`). 언어별 사본(`/ko/rss.xml`)과 섹션별
  사본(`/posts/rss.xml`) 포함. 섹션 피드는 해당 섹션의 `_index.md`가
  `generate_feeds = true`를 선언했을 때만 인정합니다. 빌드가 그때만 파일을
  쓰기 때문입니다
- 분류 목록·용어 페이지(`/tags/`, `/categories/rust/`)
- 페이지네이션 경로(`/posts/page/2/`). `paginate_by`를 실제로 선언한 섹션에만
  해당하므로, 페이지네이션이 없는 섹션의 `/page/N/` 링크는 여전히 보고됩니다

`@/posts/hello.md` 같은 콘텐츠 루트 링크는 빌드와 같은 방식으로 해석합니다.
기본 빌드가 게시하는 페이지 중에서 `content/` 아래의 정확한 원본 경로를
찾습니다(대소문자 구분, 퍼센트 디코딩 없음, `./`·`../` 정규화 없음). 원본 파일
확장자를 포함하고, 섹션은 `_index.md`로 링크하세요. `@/posts/hello`와
`@/posts/`는 보고되며, 초안·미래 날짜·만료된 페이지로의 링크도 보고됩니다.

### 앵커

프래그먼트가 붙은 내부 링크(`#intro`, `/guide/#install`, `../b/#faq`,
`@/posts/hello.md#setup`)는 빌드 출력에 있는 대상 HTML 파일의 `id`·`name`
속성과 대조합니다. 따라서 제목, `{#id}` 속성, 숏코드와 템플릿 출력, 각주 등
페이지가 실제로 가진 모든 id가 인정됩니다. `#top`과 텍스트 조각 링크(`#:~:text=…`)는
항상 유효하며, id는 적힌 그대로 또는 퍼센트 디코딩한 값으로 대조합니다. 없는
앵커는 별도 분류(`Anchor not found: #id`, kind `anchor`, JSON의
`dead_anchors`)로 보고되며 깨진 링크와 마찬가지로 실행을 실패시킵니다.

이 검사에는 `hwaro build` 출력이 필요합니다
([빌드 출력을 근거로 사용하기](#빌드-출력을-근거로-사용하기) 참고). 출력이
없거나 대상 페이지의 HTML 파일이 없으면 프래그먼트는 검사하지 않습니다.
`--skip-anchors`로 검사를 끌 수 있습니다. 빌드 중에 같은 문제를 잡으려면
`[links] broken_anchors`를 설정하세요 ([설정](/ko/start/config/#링크) 참고).

## 링크 유형

| 유형 | 설명 |
|------|-------------|
| 외부 | `http://`, `https://` 링크 — HTTP HEAD로 검사 |
| 내부 | 상대·절대 경로 링크 — 파일 시스템에서 검사 |
| 이미지 | `![alt](path)` 이미지 참조 — 파일 시스템에서 검사 |
| 앵커 | 내부 링크의 `#fragment` — 빌드된 HTML에서 검사 |

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
`-q`/`--quiet`를 주면 보고서는 출력되지 않지만, 깨진 링크는 각각
`파일: url  상태` 한 줄로 stderr에 계속 출력됩니다.

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
  "dead_anchors": [
    {
      "link": {
        "file": "content/guide.md",
        "url": "/install/#linux",
        "kind": "anchor"
      },
      "status": -1,
      "error": "Anchor not found: #linux"
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
  "ignored_count": 0,
  "output_hint": null
}
```

`output_hint`는 빌드 출력 때문에 결과를 다르게 읽어야 할 때만 값이 들어가고,
그 외에는 `null`입니다(아래 참고). 사람용 출력에도 같은 문장이 나오며, JSON에
같이 담아 두어 터미널 출력을 보지 않는 CI에서도 놓치지 않게 했습니다.

## 빌드 출력을 근거로 사용하기

컴파일된 스타일시트, 리사이즈된 이미지 변형, `[content.files]`나 에셋
파이프라인으로 발행된 파일처럼 원본 소스로는 설명되지 않는 링크가 있습니다.
`check-links`는 이런 경로를 직전 빌드 결과인 `[build] output_dir`(기본값
`public/`)에서 찾으면 유효한 것으로 인정합니다. 빌드 밖에서 도는 명령에게는
그것이 유일한 근거이기 때문입니다.

이 디렉터리는 `hwaro build`가 만든 것이어야 합니다. Hwaro 0.19부터
`hwaro serve`는 `.hwaro/serve/`에 빌드하고 `output_dir`은 건드리지 않으므로,
serve만 쓰는 작업 흐름에는 아무것도 없습니다. 이제 이유 없이 깨진 링크 목록만
쏟아내는 대신 그 사실을 알려줍니다:

```
checked: 4 links, 1 dead
  [info] public/ holds no build output — run `hwaro build` first; check-links
         validates build output, not `hwaro serve` output (.hwaro/serve/)
```

- **없거나 비어 있음** — 그 때문에 죽은 것으로 보고된 링크와 함께 안내가
  출력됩니다.
- **`hwaro serve` 출력** (`.hwaro-dev` 마커가 남은 경우) — `hwaro deploy`와 같은
  규칙으로 근거에서 제외합니다. 마커는 `hwaro build`가 지웁니다.
- **가장 최근 소스 파일보다 오래됨** — 문제가 없어 보이는 결과 아래에 안내가
  붙습니다. 삭제한 페이지의 `index.html`이 그 트리에 남아 있으면 링크가 계속
  통과하기 때문입니다.

CI에서는 `check-links` 전에 `hwaro build`를 돌려 실제 출력과 대조하세요.
소스만으로 판단되는 경로(`/about/`, `/tags/`, 피드, 사이트맵)는 빌드 출력이
없어도 됩니다.
