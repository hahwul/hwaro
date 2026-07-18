+++
title = "캐시 버스팅"
description = "에셋 URL에 콘텐츠 해시를 붙여 캐시를 무효화합니다"
weight = 18
toc = true
+++

캐시 버스팅은 로컬에서 제공되는 CSS/JS 리소스 URL에 `?v=<hash>` 쿼리 파라미터를 자동으로 붙입니다. 에셋 내용이 바뀌면 브라우저가 최신 버전을 다시 받아오므로, 오래된 캐시 파일이 쓰이는 일을 막습니다.

## 동작 방식

Hwaro는 로컬 CSS/JS 파일의 MD5 콘텐츠 해시를 계산해 앞 8자를 쿼리 파라미터로 붙입니다. 해시는 파일 내용이 실제로 바뀔 때만 달라지므로, 진짜 업데이트가 있기 전까지 브라우저는 캐시를 계속 사용합니다.

```html
<!-- With cache busting (default) -->
<link rel="stylesheet" href="/assets/css/highlight/github.min.css?v=3a8f1b2c">
<script src="/assets/js/highlight.min.js?v=3a8f1b2c"></script>
<link rel="stylesheet" href="/assets/css/style.css?v=3a8f1b2c">

<!-- Without cache busting -->
<link rel="stylesheet" href="/assets/css/highlight/github.min.css">
<script src="/assets/js/highlight.min.js"></script>
<link rel="stylesheet" href="/assets/css/style.css">
```

## 콘텐츠 해시 vs 타임스탬프

Hwaro는 빌드 타임스탬프가 아니라 **콘텐츠 기반 해시**를 사용합니다. 따라서:

- 파일이 바뀌지 않으면 빌드를 반복해도 해시가 그대로 유지됩니다 — 불필요한 캐시 무효화가 없습니다
- CSS/JS 파일 내용이 수정되면 해시가 즉시 바뀝니다
- 파일이 같으면 다른 빌드 머신에서도 같은 해시가 나옵니다

## CDN URL은 수정하지 않음

캐시 버스팅은 **로컬** 리소스 URL에만 적용됩니다. CDN URL(예: cdnjs.cloudflare.com)은 경로에 이미 버전 번호가 들어 있으므로 수정하지 않습니다.

```html
<!-- CDN URL — unchanged -->
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">

<!-- Local URL — cache busted -->
<link rel="stylesheet" href="/assets/css/highlight/github.min.css?v=3a8f1b2c">
```

## 적용 대상 템플릿 변수

캐시 버스팅은 다음 템플릿 변수에 적용됩니다.

| 변수 | 설명 |
|----------|-------------|
| `highlight_css` | 구문 강조 CSS(로컬만) |
| `highlight_js` | 구문 강조 JS(로컬만) |
| `highlight_tags` | 구문 강조 CSS + JS 결합(로컬만) |
| `auto_includes_css` | 자동 인클루드된 CSS 파일 |
| `auto_includes_js` | 자동 인클루드된 JS 파일 |
| `auto_includes` | 자동 인클루드된 CSS + JS 결합 |

## 캐시 버스팅 비활성화

캐시 버스팅은 기본으로 활성화되어 있습니다. 끄려면 `--skip-cache-busting` 플래그를 사용합니다.

```bash
# 캐시 버스팅 없이 빌드
hwaro build --skip-cache-busting

# 캐시 버스팅 없이 serve
hwaro serve --skip-cache-busting
```

파일명 해싱이나 CDN 퍼지 등 다른 방법으로 캐시 무효화를 관리한다면 유용합니다.

## 함께 보기

- [구문 강조](/ko/features/syntax-highlighting/) — Highlight.js 설정
- [자동 인클루드](/ko/features/auto-includes/) — CSS/JS 자동 로드
- [CLI](/ko/start/cli/) — 명령줄 옵션
