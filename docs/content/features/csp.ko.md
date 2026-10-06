+++
title = "콘텐츠 보안 정책(CSP)"
description = "페이지마다 인라인 스크립트와 스타일의 해시로 엄격한 CSP 만들기"
weight = 28
toc = true
+++

`[csp]`는 Hwaro가 빌드하는 모든 페이지에 Content-Security-Policy를
만들어 줍니다. 최종 HTML에 있는 인라인 `<script>`와 `<style>`을 하나씩
해시해서 정책에 넣기 때문에, `'unsafe-inline'` 없이도 사이트의 인라인
코드는 그대로 동작합니다. 나중에 페이지에 끼어든 스크립트(XSS 페이로드,
침해된 서드파티 태그 등)는 맞는 해시가 없으므로 차단됩니다.

## 빠른 시작

```toml
[csp]
enabled = true
```

이렇게 설정하면 출력 루트에 페이지마다 규칙 하나씩을 담은 `_headers`
파일이 생깁니다.

```
/blog/hello/
  Content-Security-Policy: default-src 'self'; script-src 'self' 'sha256-hI0C…='; style-src 'self' 'sha256-G7+h…='; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'
```

Netlify와 Cloudflare Pages가 이 파일을 읽습니다. 다른 호스트에서는
정책을 각 페이지 안에 넣는 `mode = "meta"`를 쓰세요.

## 설정

```toml
[csp]
enabled = false                  # 기본값은 꺼짐
mode = "headers"                 # headers | meta
headers_file = "_headers"        # headers 모드: 출력 루트 기준 경로
report_only = false              # headers 모드: Content-Security-Policy-Report-Only

[csp.directives]                 # 아래 기본값 위에 덮어씀
img-src = "'self' data: https://images.example.com"
```

| 키 | 기본값 | 의미 |
|----|--------|------|
| `enabled` | `false` | CSP 생성을 켭니다. 꺼져 있으면 출력이 바뀌지 않습니다. |
| `mode` | `"headers"` | `headers`는 [`_headers` 파일](#headers-모드)을 쓰고, `meta`는 각 페이지에 [`<meta>` 태그](#meta-모드)를 넣습니다. |
| `headers_file` | `"_headers"` | 헤더 파일 경로. 출력 디렉터리 기준입니다. |
| `report_only` | `false` | 대신 `Content-Security-Policy-Report-Only`를 보내서 위반을 막지 않고 보고만 합니다. headers 모드 전용입니다. 브라우저는 `<meta>`의 report-only 정책을 무시하므로 `mode = "meta"`와 함께 쓰면 설정 오류입니다. |
| `[csp.directives]` | 아래 참고 | 지시어 이름 = 소스 목록(문자열 하나). |

### 지시어

`[csp.directives]`가 없으면 모든 페이지에 다음 정책이 붙습니다.

| 지시어 | 값 |
|--------|----|
| `default-src` | `'self'` |
| `script-src` | `'self'` + 페이지의 스크립트 해시 |
| `style-src` | `'self'` + 페이지의 스타일 해시 |
| `img-src` | `'self' data:` |
| `font-src` | `'self'` |
| `connect-src` | `'self'` |
| `object-src` | `'none'` |
| `base-uri` | `'self'` |
| `frame-ancestors` | `'self'` |

직접 지정한 지시어는 기본값을 대체합니다. `script-src`와 `style-src`는
지정한 값을 유지한 채 그 뒤에 페이지의 해시를 덧붙입니다. 빈 문자열은
기본 지시어를 없애고(`frame-ancestors = ""`), 그 밖의 지시어에 빈 값을 주면
소스 없이 지시어만 씁니다. `upgrade-insecure-requests = ""`는 이렇게
추가합니다. 값에는 `;`나 `,`를 넣을 수 없습니다.

### Hwaro가 해시할 수 없는 인라인 코드 허용하기

해시가 하나라도 있는 지시어에서는 브라우저가 `'unsafe-inline'`을 무시합니다.
그래서 `script-src`나 `style-src`에 `'unsafe-inline'`이 있으면 Hwaro는 그
지시어에 해시를 넣지 않고, `style-src`에 있으면 `style-src-attr`도 쓰지
않습니다. 페이지가 실행되는 동안 스타일을 만들어서 어떤 해시로도 허용할 수
없는 기능, 즉 Mermaid, MathJax, `gist`와 `tweet` 숏코드를 위한 예외 설정입니다.

```toml
[csp.directives]
style-src = "'self' 'unsafe-inline'"
```

이렇게 하면 스타일만 느슨해지며, 인라인 스크립트에는 여전히 해시가
필요합니다.

## 해시 대상

Hwaro는 다른 출력 처리가 모두 끝난 뒤 자신이 쓴 HTML 페이지를 전부 읽습니다.
`--minify`, [`[privacy]`](/ko/features/privacy/) 재작성, AMP 링크, 택소노미
페이지, 404 페이지, 별칭 리다이렉트까지 반영된 상태입니다. 해시는 태그
사이 바이트의 `sha256`으로, 브라우저가 계산하는 값과 정확히 같습니다.
페이지마다 자기 해시만 받습니다.

- **`<script>`**: `src`가 없고, `type`이 없거나 비었거나 JavaScript MIME
  타입, `module`, `importmap`, `speculationrules`인 것. 브라우저가
  `script-src`로 검사하는 타입들입니다.
- **JSON-LD와 그 밖의 데이터 블록**(`application/ld+json`,
  `text/template` 등)은 실행되지 않으므로 해시가 없고, 필요하지도 않습니다.
- **`<style>`** 본문은 `style-src`에 들어갑니다.
- **`style="…"` 속성.** 해시로 속성을 허용하려면 `'unsafe-hashes'`가 함께
  있어야 합니다. 그래서 스타일 속성이 있는 페이지에는 그 해시를 담은
  `style-src-attr 'unsafe-hashes' 'sha256-…'` 지시어가 붙습니다. 요소에
  쓰이는 `style-src`는 그대로 엄격합니다.
- **이벤트 핸들러 속성**(`onclick="…"`, `onload="…"`)은 해시 기반 정책으로
  허용할 수 없습니다. Hwaro는 이런 속성이 있는 페이지를 나열해 경고합니다.
  코드를 스크립트로 옮기고 `addEventListener`로 연결하세요. Hwaro 자체
  템플릿과 `hwaro init` 스캐폴드에는 없습니다.

HTML 주석, `<textarea>`, `<title>` 안의 내용은 브라우저에게 마크업이
아니므로 해시하지 않습니다. `<noscript>` 안의 내용은 해시합니다. JavaScript가
꺼져 있으면 그 스타일이 적용되고, 정책도 여전히 검사하기 때문입니다.

## Hwaro 기능의 호스트

페이지가 다른 호스트에서 불러오는 기능을 쓰면 그 호스트가 페이지 정책에
추가됩니다. 해당 URL이 페이지의 최종 HTML에 있을 때만 추가하므로,
[`[privacy]`](/ko/features/privacy/)가 사이트로 옮긴 CDN이나 페이지가 쓰지
않는 숏코드는 아무것도 추가하지 않습니다.

| 기능 | 추가되는 값 |
|------|-------------|
| `[highlight]`의 `use_cdn = true`(cdnjs) | `script-src`, `style-src` `https://cdnjs.cloudflare.com` |
| `[markdown] math`, KaTeX | `script-src`, `style-src`, `font-src` `https://cdn.jsdelivr.net` |
| `[markdown] math`, MathJax | `script-src`, `font-src` `https://cdn.jsdelivr.net` |
| `[markdown] mermaid` | `script-src` `https://cdn.jsdelivr.net` |
| `youtube` 숏코드 | `frame-src` `https://www.youtube.com` |
| `vimeo` 숏코드 | `frame-src` `https://player.vimeo.com` |
| `gist` 숏코드 | `script-src` `https://gist.github.com`, `style-src` `https://github.githubassets.com`, `img-src` `https://gist.github.com` `https://gist.githubusercontent.com` |
| `tweet` 숏코드 | `script-src`, `frame-src` `https://platform.twitter.com` |
| `codepen` 숏코드 | `frame-src` `https://codepen.io` |

`gist`와 `tweet` 행은 숏코드 자체의 마크업(`class="sc-gist"`,
`class="twitter-tweet"`)도 찾습니다. `[privacy]`가 이들의 스크립트를 로컬로
옮겨도, 그 스크립트는 실행 중에 원래 호스트에서 스타일과 프레임을 불러오기
때문입니다.

Mermaid, MathJax, `gist`, `tweet`은 실행 중에 스타일도 추가하므로
[스타일 예외 설정](#hwaro가-해시할-수-없는-인라인-코드-허용하기)이 필요합니다.

설정되지 않은 지시어는 브라우저가 대신 썼을 값(`frame-src`라면 `child-src`,
그다음 `default-src`)에서 시작하므로, 프레임 호스트를 추가해도 `'self'`는
남습니다.

템플릿이 다른 호스트에서 불러오는 그 밖의 것은 `[csp.directives]`에 직접
넣어야 합니다.

## headers 모드

`mode = "headers"`는 Netlify와 Cloudflare Pages가 읽는 형식으로
`headers_file`에 페이지마다 규칙을 하나씩 씁니다. 경로는 페이지 URL이며
`base_url`의 하위 경로를 포함합니다: `/`, `/blog/hello/`, `/404.html`.
경로는 사이트맵에 실리는 페이지 URL과 똑같이, 브라우저가 요청하는 대로
인코딩합니다. `#`은 `%23`, `?`는 `%3F`가 되고, 공백과 ASCII가 아닌 문자는
퍼센트 인코딩됩니다.

`static/_headers`가 있으면 덮어쓰지 않습니다. Hwaro는 그 파일을 먼저 그대로
쓰고, `# Content-Security-Policy generated by Hwaro ([csp])` 주석 뒤에 자신의
규칙을 덧붙입니다. 사용자 파일에 어떤 페이지 경로의 블록이 이미 있고 그
블록이 `Content-Security-Policy`(`report_only`라면
`Content-Security-Policy-Report-Only`)를 설정하면 사용자 블록이 우선하며,
Hwaro는 그 경로의 규칙을 쓰지 않습니다.

사용자 블록이 Hwaro의 규칙을 대신한 경로는 로그에 남깁니다.

호스트는 요청에 맞는 규칙을 모두 합칩니다. 직접 만든 `/*` 규칙이
`Content-Security-Policy`를 설정하면 두 번째 정책으로 함께 전송되고
브라우저는 둘 다 적용하므로, `[csp]`와 함께 쓰지 마세요. 사용자 파일에서
`*`나 `:`가 들어간 경로의 블록이 CSP를 설정하면 Hwaro가 경고합니다.

어떤 규칙으로도 맞출 수 없는 경로가 있습니다. 호스트는 경로의 `:name`을
자리표시자로, `*`를 와일드카드로 읽고, 제어 문자는 파일을 깨뜨리며, 파일
이름의 `%`로는 페이지 URL을 하나로 정할 수 없습니다(`a%b`는 `/a%b/`와
`/a%25b/` 모두에서 게시됨). 이런 페이지는 정책을 대신
[`<meta>` 태그](#meta-모드)로 받으며(`frame-ancestors`, `report-uri`,
`sandbox` 제외), Hwaro가 그 페이지를 밝혀 경고합니다. 규칙을 받으려면 이름을
바꾸세요.

이 형식은 규칙 하나에 여러 경로를 담을 수 없어서 규칙이 페이지마다 하나씩
생깁니다. 이 문서 사이트(두 언어, 약 160페이지)에서는 파일이 약 50 KB입니다.
Cloudflare Pages는 규칙을 최대 100개까지만 읽으며, 이를 넘으면 Hwaro가
경고합니다. Netlify에는 이런 제한이 없습니다. Cloudflare에서 큰 사이트라면
meta 모드를 쓰세요.

Cloudflare Pages는 헤더 하나의 길이도 2000자로 제한합니다. 해시 하나가 약
54자를 더하므로, 정책이 이보다 긴 페이지는 Hwaro가 경고합니다.

호스트는 없는 URL에서 `404.html`을 내보내는데, 그 URL에 맞는 규칙이 없으므로
headers 모드에서 404 페이지에는 정책이 붙지 않습니다. 마찬가지로 Cloudflare
Pages는 `/page.html`을 `/page`로 리다이렉트하므로, 파일로 게시되는 페이지
(`/404.html`, `path = "x.html"`)의 규칙은 그곳에서 맞지 않을 수 있고 그
페이지에는 정책이 붙지 않습니다. 이런 페이지가 중요하다면 meta 모드를 쓰세요.

## meta 모드

`mode = "meta"`는 정책을 각 페이지의 `<head>` 첫 자식으로 넣습니다.
스크립트, 스타일, 링크보다 앞에 charset 선언(`<meta charset>` 또는
`<meta http-equiv="Content-Type">`)이 있으면 그 바로 뒤에 넣는데, charset
선언은 처음 1024바이트 안에 있어야 하기 때문입니다.

```html
<head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src &apos;self&apos;; …">
```

브라우저는 `<meta>` 정책의 `frame-ancestors`, `report-uri`, `sandbox`를
무시하므로 Hwaro는 이를 빼고, 직접 설정했다면 경고합니다. `<head>`가 없는
페이지에는 정책이 붙지 않으며, Hwaro가 이를 경고합니다.

Hwaro는 그 위치에 있는 `<meta http-equiv="Content-Security-Policy">`를 자신이
넣은 것으로 보고 빌드할 때마다 바꿉니다. `[csp]`를 켠 동안에는 템플릿에 CSP
`<meta>`를 직접 넣지 마세요.

## 빌드, 캐시, serve

- **`--cache`.** 캐시된 페이지는 디스크에 있는 HTML로 해시하므로, 웜
  빌드도 콜드 빌드와 같은 `_headers` 파일과 같은 페이지를 씁니다.
- **`[build] hooks.post`.** 정책은 빌드 후 훅이 돌기 전에 계산됩니다. 훅이
  페이지의 인라인 스크립트나 스타일을 바꾸면 Hwaro가 그 페이지를 밝혀 정책이
  더 이상 맞지 않는다고 경고합니다. HTML은 템플릿이나 `hooks.pre`에서 바꾸세요.
- **`hwaro serve`.** 정책을 쓰지 않습니다. 라이브 리로드 클라이언트와 오류
  오버레이가 인라인이고 개발 전용이기 때문입니다.
- **`static/`과 `[content.files]`의 HTML**은 사용자 파일이므로 그대로
  게시되고 정책이 붙지 않습니다.
- **AMP 페이지**는 건너뜁니다. AMP 런타임이 실행 중에 스타일을 추가하는데,
  해시 기반 정책은 이를 막기 때문입니다.
- **KaTeX.** `[csp]`가 켜져 있으면 `{{ math_tags }}`가 KaTeX를 `onload`
  속성 대신 작은 인라인 스크립트로 시작하므로 해시할 수 있습니다.

## 제한 사항

- 스크립트가 실행 중에 만드는 스타일(`<style>` 요소, 또는 `setAttribute`나
  `innerHTML`로 넣은 `style` 속성)은
  [예외 설정](#hwaro가-해시할-수-없는-인라인-코드-허용하기)을 하지 않으면
  차단됩니다. Mermaid, MathJax, `gist`와 `tweet` 임베드가 이렇게 하며, KaTeX는
  그렇지 않습니다. 스크립트에서 `element.style.color`를 설정하는 것은
  허용됩니다.
- 인라인 `<svg>`나 `<math>` 안의 `<style>`, `<script>` 내용에
  `<![CDATA[…]]>`나 문자 참조(`&amp;`)가 있으면 차단됩니다. 브라우저는 그곳에서
  디코딩한 텍스트를 해시하지만 Hwaro는 바이트를 해시하기 때문입니다. 디자인
  도구에서 내보낸 SVG 아이콘에는 CDATA가 흔하니, 이를 없애거나 스타일을
  스타일시트로 옮기세요.
- `javascript:` URL은 이벤트 핸들러 속성처럼 차단됩니다.
- 기능 호스트 표는 Hwaro 자체 기능만 다룹니다. 직접 만든 템플릿이나
  Markdown의 임베드는 그 호스트를 `[csp.directives]`에 넣어야 합니다.
- headers 모드에서는 같은 정책을 쓰는 페이지도 규칙을 하나씩 받습니다.
