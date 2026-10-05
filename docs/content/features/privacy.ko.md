+++
title = "프라이버시 모드"
description = "외부 폰트, 스크립트, 이미지를 빌드 시 직접 호스팅하기"
weight = 27
toc = true
+++

`[privacy]`는 페이지가 불러오는 외부 에셋(웹 폰트, CDN 스타일시트와
스크립트, 원격 이미지)을 빌드할 때 내려받아 사이트에서 직접 제공합니다.
그러면 방문자의 브라우저가 그 에셋 때문에 외부 호스트에 접속하지 않습니다.
[로컬로 옮기는 대상](#로컬로-옮기는-대상)에 나열된 태그만 해당하며, 그 밖에
페이지나 스크립트가 불러오는 것([제한 사항](#제한-사항) 참고)은 여전히 원래
호스트에서 받습니다.

주된 이유는 GDPR입니다. `fonts.googleapis.com`에서 Google Fonts를 불러오면
방문자마다 IP 주소가 Google로 전송되며, 독일 법원은 이에 동의가 필요하다고
판결했습니다. 폰트를 직접 호스팅하면 이 요청이 사라지고, 동의를 받을 필요도
없어집니다.

## 빠른 시작

```toml
[privacy]
enabled = true
```

이렇게 설정하면 템플릿의 Google Fonts 태그

```html
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter&display=swap">
```

는 다음과 같이 출력됩니다.

```html
<link rel="stylesheet" href="/assets/external/3f2a9c01b7de-css2.css">
```

로컬 스타일시트는 사용하는 `.woff2` 파일의 로컬 사본을 가리킵니다.

## 설정

```toml
[privacy]
enabled = false                 # 기본값은 꺼짐
include = []                    # 로컬로 옮길 호스트, 비우면 모든 외부 호스트
exclude = []                    # 절대 옮기지 않을 호스트, 예: ["www.youtube.com"]
output_dir = "assets/external"  # 빌드 출력 안의 디렉터리
cache_ttl = "7d"                # 요청 없이 다운로드를 재사용하는 기간
on_error = "warn-and-keep"      # warn-and-keep | fail
```

| 키 | 기본값 | 의미 |
|----|--------|------|
| `enabled` | `false` | 프라이버시 모드를 켭니다. 꺼져 있으면 출력이 바뀌지 않습니다. |
| `include` | `[]` | 로컬로 옮길 호스트. 정확히 일치해야 합니다(`fonts.googleapis.com`). 비우면 모든 외부 호스트가 대상입니다. 여기 적은 호스트는 네트워크 검사에서도 신뢰합니다([네트워크 안전](#네트워크-안전) 참고). |
| `exclude` | `[]` | 외부에 그대로 둘 호스트. `include`보다 우선합니다. |
| `output_dir` | `"assets/external"` | 내려받은 파일을 게시할 위치. URL에는 `base_url`의 하위 경로가 붙습니다. |
| `cache_ttl` | `"7d"` | 다운로드 캐시 수명. `[[data.remote]]`와 같은 기간 문법(`"90s"`, `"12h"`, `"7d"`)을 씁니다. |
| `on_error` | `"warn-and-keep"` | 캐시 사본 없이 다운로드가 실패했을 때: `warn-and-keep`은 경고 후 외부 URL을 그대로 두고, `fail`은 빌드를 멈춥니다. |

## 로컬로 옮기는 대상

모든 페이지, 섹션, 페이지네이션 페이지, 택소노미 페이지, 404 페이지에서
다음 속성을 다시 씁니다.

- `rel`이 `stylesheet`, `preload`, `modulepreload`인 `<link href>`
- `<script src>`
- `<img src>`, `<img srcset>`, `<source src>`, `<source srcset>`
- `<video src>`, `<video poster>`, `<audio src>`

다른 호스트를 가리키는 절대 `http(s)://` URL과 프로토콜 상대 `//` URL만
바꿉니다. 상대 URL, `data:` URL, `base_url` 호스트의 URL은 그대로 둡니다.
HTML 주석과 인라인 `<script>`, `<style>` 본문도 바꾸지 않습니다.

내려받은 스타일시트도 다시 씁니다. `@import`와 `url(...)` 참조를 스타일시트
자신의 URL 기준으로 해석해 로컬로 옮기며, 네 단계까지 중첩을 따라갑니다.
이 참조는 스타일시트에 필요하므로 `include`와 상관없이 따라가지만,
`exclude`는 그대로 적용됩니다. 외부에 남는 참조는 절대 URL로 다시 씁니다.
`image-set(...)` 안의 문자열도 `url(...)`과 같이 처리합니다.

에셋을 로컬에서 제공하게 된 호스트로 향하는 `<link rel="preconnect">`와
`<link rel="dns-prefetch">` 힌트는 지웁니다. 남겨 두면 브라우저가 여전히 그
호스트에 연결하기 때문입니다.

### 파일 형식

파일은 그 파일을 불러오는 태그에 맞는 확장자로만 게시하며, 확장자는 응답의
`Content-Type`(일반적인 형식이면 URL 경로)에서 정합니다. `<img>`, `<source>`,
`poster`는 이미지, `<video>`와 `<audio>`는 오디오와 비디오, 스타일시트는 CSS,
스크립트는 JavaScript, 스타일시트 안의 참조는 폰트, 이미지, CSS입니다. 그 밖의
경우(예: HTML로 응답한 `<img>`)는 경고와 함께 외부 URL을 그대로 둡니다. HTML이나
XML은 절대 게시하지 않습니다.

SVG는 `<img>` 계열 태그에서만 게시하며 경고를 출력합니다. SVG를 사이트에서
직접 열면 스크립트가 실행될 수 있습니다. 믿을 수 없는 호스트라면 `exclude`에
추가하세요.

### Hwaro가 출력하는 태그

`[markdown] math = "mathjax"`는 `cdn.jsdelivr.net`에서 MathJax를 불러오는데,
MathJax는 폰트와 확장을 자기 URL 기준으로 불러오므로 외부에 그대로 둡니다.
Mermaid(`[markdown] mermaid = true`)는 인라인 모듈 `import`로 불러오며, 프라이버시
모드는 이를 다시 쓰지 않습니다. KaTeX와 highlight.js는 그대로 로컬로 옮깁니다.

게시되는 파일 이름은 `<해시>-<이름>.<확장자>`이며, 해시는 바이트의 SHA-256
앞 12자리입니다. 같은 파일은 한 번만 저장되고, 원본이 바뀌면 이름도 바뀌므로
브라우저가 오래된 사본을 쓰지 않습니다.

### User-Agent

다운로드에는 데스크톱 브라우저 `User-Agent`를 보냅니다. Google Fonts는 이
값으로 폰트 형식을 고르는데, 알 수 없는 클라이언트에는 woff2 대신 훨씬 큰
TrueType을 보냅니다. 쿠키나 인증 정보는 보내지 않습니다.

### 네트워크 안전

프라이버시 모드가 내려받는 URL이 모두 직접 작성한 것은 아닙니다. 리다이렉트와
내려받은 스타일시트 안의 `url(...)` 참조는 외부에서 정합니다. 그래서 모든 요청과
모든 리다이렉트 단계를 먼저 검사합니다. 루프백, 사설(10/8, 172.16/12,
192.168/16, fc00::/7), 링크 로컬(169.254/16, fe80::/10), CGNAT(100.64/10),
미지정, 멀티캐스트 주소로 해석되는 호스트는 거부하며, 거부는 `on_error`를
따릅니다. 이렇게 해서 외부가 빌드에게 내부 서비스나 클라우드 메타데이터를 읽게
하고 그 응답을 사이트에 게시하게 만드는 것을 막습니다. 연결은 검사한 주소에
고정됩니다.

`include`에 적은 호스트는 이 검사를 건너뜁니다. 사내 CDN이나 로컬 테스트
서버는 이렇게 허용하세요.

실패한 다운로드는 같은 프로세스에서 10분 동안 다시 시도하지 않으므로, 응답하지
않는 호스트가 `hwaro serve`를 느리게 하는 것은 한 번뿐입니다. 파일마다 20MiB
상한이 있으며, 그보다 큰 파일(긴 동영상 등)은 경고와 함께 외부 URL을 유지합니다.

## 캐시와 오프라인 빌드

다운로드는 `config.toml` 옆의 `.hwaro/external/`에 보관되며, `index.json`에
URL마다 파일, 가져온 시각, Content-Type, SHA-256이 기록됩니다. 이 디렉터리는
빌드 캐시 밖, 그리고 `hwaro serve`가 감시하는 경로 밖에 있으므로 여기에 쓰는
일로 다시 빌드가 일어나지 않습니다.

- `cache_ttl`보다 최근에 받은 파일은 요청 없이 사용합니다. 캐시가 채워진
  빌드는 완전히 오프라인으로 동작합니다.
- 더 오래된 파일은 다시 받습니다. 실패하면 이전 사본을 쓰고 경고를
  출력합니다.
- 사본이 전혀 없으면 `on_error`를 따릅니다.

`hwaro serve`도 같은 캐시를 쓰므로 다시 빌드할 때 네트워크에 접근하지
않습니다. 외부 호스트 상태와 상관없이 빌드하려면 CI에서 `.hwaro/external/`을
캐시하거나 커밋하세요. Hwaro는 `.hwaro/` 안의 모든 것을 무시하는
`.hwaro/.gitignore`를 만들므로 `git add -f .hwaro/external`로 추가해야 합니다.
이 디렉터리의 오래된 다운로드는 지우지 않으니, 처음부터 다시 받으려면
디렉터리를 삭제하세요.

다시 쓰기는 페이지를 쓸 때, `--minify` 다음에 일어납니다. 따라서 `--cache`
빌드가 페이지를 건너뛰어도 이미 바뀐 HTML과 그 페이지가 쓰는 파일은 그대로
유지됩니다.

## 다른 기능과의 관계

- **하위 리소스 무결성.** 다시 쓴 `<link>`나 `<script>`의 `integrity` 값이
  Hwaro가 제공하는 바이트와 일치하면 그대로 둡니다. 일치하지 않으면
  `integrity`와 `crossorigin`을 지우고 URL마다 한 번 경고합니다.
  [`[assets] sri = true`](/ko/features/asset-pipeline/#sri)이면 로컬로 옮긴
  스타일시트와 스크립트마다 Hwaro가 직접 `integrity`를 붙입니다.
- **PWA.** `[pwa] precache_urls`의 외부 URL은 로컬 사본으로 바뀝니다.
- **AMP.** AMP 페이지는 다시 쓴 HTML로 만들어집니다. AMP는 폰트 제공자의
  외부 스타일시트만 허용하므로 로컬로 옮긴 폰트 스타일시트는 AMP 페이지에서
  제거되며, AMP 페이지는 여전히 `cdn.ampproject.org`에서 AMP 런타임을
  불러옵니다.

## 제한 사항

- 인라인 `style="…url(…)"` 속성, `<style>` 블록, 인라인 모듈 `import`, import
  map, 그 밖의 속성(`<link rel="icon">`, `<link imagesrcset>`, `<track src>`
  등)은 바꾸지 않으므로 원래 호스트에서 불러옵니다.
- 자기 URL 기준으로 다른 파일을 불러오는 스크립트(MathJax, 절대 `/npm/...`
  import를 쓰는 ESM 번들, pdf.js 워커)는 옮기면 동작하지 않습니다. 해당
  호스트를 `exclude`에 추가하세요.
- HTML 주석 안의 태그(IE 조건부 주석 포함)와 따옴표로 감싼 속성 값 안에 `>`가
  있는 태그는 경고 없이 그대로 둡니다.
- `include`와 `exclude`는 호스트 이름 전체를 비교합니다. 하위 도메인은 따로
  적어야 합니다.
- 드물게 스타일시트가 서로를 순환 import하거나 네 단계보다 깊게 이어지면,
  어느 참조가 절대 URL로 남을지는 어느 페이지가 먼저 그 체인에 닿는지에 따라
  달라집니다.
- 빌드당 다운로드 전체 크기나 개수에는 제한이 없습니다.
- `content/`에서 복사되는 `.html` 파일은 그대로 게시됩니다.

## 함께 보기

- [원격 데이터 소스](/ko/features/remote-data/)는 같은 HTTP 클라이언트와 캐시
  규칙을 씁니다
- 하위 리소스 무결성은 [에셋 파이프라인](/ko/features/asset-pipeline/)을
  참고하세요
- [설정](/ko/start/config/)
