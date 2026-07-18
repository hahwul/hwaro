+++
title = "PWA"
description = "manifest.json과 서비스 워커를 이용한 프로그레시브 웹 앱 지원"
weight = 24
toc = true
+++

Hwaro는 프로그레시브 웹 앱(PWA) 파일을 생성해 사이트의 오프라인 접근과 앱 설치를 지원합니다.

## 생성되는 파일

`[pwa]`를 활성화하면 빌드 출력에 두 파일이 추가됩니다:

- **`manifest.json`** — 앱 이름, 아이콘, 테마, 표시 모드를 기술하는 웹 앱 매니페스트
- **`sw.js`** — 캐시 우선 전략으로 오프라인 캐싱을 처리하는 서비스 워커

## 설정

```toml
[pwa]
enabled = true
name = "My Blog"
short_name = "Blog"
theme_color = "#1a1a2e"
background_color = "#ffffff"
display = "standalone"
start_url = "/"
icons = ["static/icon-192.png", "static/icon-512.png"]
offline_page = "/offline.html"
precache_urls = ["/", "/about/", "/css/main.css"]
cache_strategy = "cache-first"
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | false | PWA 파일 생성 활성화 |
| name | string | 사이트 제목 | 전체 애플리케이션 이름 |
| short_name | string | name | 홈 화면용 짧은 이름 |
| theme_color | string | "#ffffff" | 브라우저 툴바/상태 표시줄 색상 |
| background_color | string | "#ffffff" | 스플래시 화면 배경색 |
| display | string | "standalone" | 표시 모드 |
| start_url | string | "/" | 앱 실행 시 열리는 URL |
| icons | array | [] | 아이콘 파일 경로 |
| offline_page | string | — | 오프라인일 때 보여줄 폴백 페이지 |
| precache_urls | array | [] | 서비스 워커 설치 시 미리 캐시할 URL |
| cache_strategy | string | `"cache-first"` | 에셋 요청 전략: `cache-first`, `network-first`, `stale-while-revalidate` |

> `start_url`, `icons`, `offline_page`, `precache_urls`는 `base_url` 접두사 **없이** 루트 기준 경로로 적습니다 (예: `"/repo/"`가 아니라 `start_url = "/"`). `base_url`에 서브패스가 포함된 경우(GitHub Pages 프로젝트 사이트)에는 생성되는 `manifest.json`과 `sw.js`에 Hwaro가 자동으로 접두사를 붙입니다.

## 아이콘 크기

아이콘 크기는 파일 이름에서 자동으로 추출됩니다:

| 파일 이름 | 인식되는 크기 |
|----------|--------------|
| `icon-192.png` | 192x192 |
| `icon-512x512.png` | 512x512 |
| `logo-180.svg` | 180x180 |

아이콘 파일은 빌드 출력으로 복사되도록 `static/` 디렉터리에 둡니다.

## 템플릿 연동

베이스 템플릿에 매니페스트 링크와 서비스 워커 등록 코드를 추가합니다:

```html
<head>
  <link rel="manifest" href="{{ base_url }}/manifest.json">
  <meta name="theme-color" content="{{ config.pwa.theme_color }}">
</head>
<body>
  ...
  <script>
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('{{ base_url }}/sw.js');
    }
  </script>
</body>
```

> 서브패스 배포(예: `https://user.github.io/repo/`로 서비스되는 GitHub Pages
> 프로젝트 사이트)에서 매니페스트와 서비스 워커가 올바르게 로드되려면
> `{{ base_url }}` 접두사가 필요합니다. 생성된 `manifest.json`/`sw.js` 내부에는
> 이미 서브패스가 반영되어 있지만, `<link>`/`register()`의 URL에는 여기서 직접
> 붙여야 합니다.

## 캐싱 전략

생성되는 서비스 워커는 다음과 같이 동작합니다:

- **설치 시 프리캐시** — `precache_urls`에 나열한 URL과 `start_url`을 즉시 캐시합니다
- **에셋 요청** — `cache_strategy`로 제어합니다 (아래 참고)
- **내비게이션은 네트워크 우선** — 페이지 이동은 항상 네트워크를 먼저 시도하고, 실패하면 오프라인 페이지로 폴백합니다
- **자동 캐시 버전 관리** — 서비스 워커 활성화 시 오래된 캐시를 정리합니다

에셋(내비게이션 이외 요청)을 어떻게 제공할지는 `cache_strategy`로 선택합니다:

| 값 | 동작 |
|-------|----------|
| `cache-first` (기본값) | 캐시에 있으면 캐시에서 제공하고, 없으면 네트워크에서 가져와 캐시. 정적 사이트에서 가장 빠름 |
| `network-first` | 네트워크를 먼저 시도하고 실패하면 캐시로 폴백. 최신 콘텐츠와 오프라인 대응이 모두 필요할 때 사용 |
| `stale-while-revalidate` | 캐시된 사본을 즉시 제공하고 백그라운드에서 캐시를 갱신. 속도와 최신성의 균형 |

알 수 없는 값은 경고를 남기고 `cache-first`로 폴백합니다.

## 오프라인 페이지

`offline_page`를 설정했다면 해당 경로에 정적 HTML 페이지(예: `content/offline.md` 또는 `static/offline.html`)를 만들어 둡니다. 사용자가 오프라인 상태에서 페이지를 이동하면 이 페이지가 표시됩니다.

## 함께 보기

- [설정](/ko/start/config/) — 전체 설정 레퍼런스
- [SEO](/ko/features/seo/) — 사이트맵, 피드, OpenGraph
