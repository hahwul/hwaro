+++
title = "프라이버시 모드"
description = "외부 폰트, 스크립트, 이미지를 빌드 시 직접 호스팅하기"
weight = 27
toc = true
+++

`[privacy]`는 페이지가 불러오는 외부 에셋(웹 폰트, CDN 스타일시트와
스크립트, 원격 이미지)을 빌드할 때 내려받아 사이트에서 직접 제공합니다.
빌드된 사이트는 다른 호스트로 요청을 보내지 않습니다.

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
| `include` | `[]` | 로컬로 옮길 호스트. 정확히 일치해야 합니다(`fonts.googleapis.com`). 비우면 모든 외부 호스트가 대상입니다. |
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

게시되는 파일 이름은 `<해시>-<이름>.<확장자>`이며, 해시는 바이트의 SHA-256
앞 12자리입니다. 같은 파일은 한 번만 저장되고, 원본이 바뀌면 이름도 바뀌므로
브라우저가 오래된 사본을 쓰지 않습니다.

### User-Agent

다운로드에는 데스크톱 브라우저 `User-Agent`를 보냅니다. Google Fonts는 이
값으로 폰트 형식을 고르는데, 알 수 없는 클라이언트에는 woff2 대신 훨씬 큰
TrueType을 보냅니다. 쿠키나 인증 정보는 보내지 않습니다.

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
않습니다. 외부 호스트 상태와 상관없이 빌드해야 한다면 `.hwaro/external/`을
커밋하거나 CI에서 캐시하세요.

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

- 인라인 `style="…url(…)"` 속성, `<style>` 블록, 그 밖의 속성
  (`<link rel="icon">` 등)은 바꾸지 않습니다.
- `srcset`은 쉼표로 나누므로, 쉼표가 들어간 후보 URL은 인식하지 못합니다.
- `include`와 `exclude`는 호스트 이름 전체를 비교합니다. 하위 도메인은 따로
  적어야 합니다.
- `content/`에서 복사되는 `.html` 파일은 그대로 게시됩니다.

## 함께 보기

- [원격 데이터 소스](/ko/features/remote-data/)는 같은 HTTP 클라이언트와 캐시
  규칙을 씁니다
- 하위 리소스 무결성은 [에셋 파이프라인](/ko/features/asset-pipeline/)을
  참고하세요
- [설정](/ko/start/config/)
