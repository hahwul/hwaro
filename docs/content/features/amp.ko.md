+++
title = "AMP"
description = "콘텐츠 페이지의 AMP 호환 버전 생성"
weight = 25
toc = true
+++

Hwaro는 일반 페이지와 함께 콘텐츠의 AMP(Accelerated Mobile Pages) 버전을 자동으로 생성할 수 있습니다.

## 동작 방식

1. 일반 페이지를 먼저 렌더링합니다
2. 렌더링이 끝나면 Hwaro가 각 페이지의 HTML을 읽어 AMP 호환 버전을 만듭니다
3. AMP 페이지는 설정 가능한 경로 접두사(기본값: `/amp/`) 아래에 기록됩니다
4. 캐노니컬 페이지의 `<head>`에 `<link rel="amphtml">` 태그가 주입됩니다

## 설정

```toml
[amp]
enabled = true
path_prefix = "amp"
sections = ["posts"]
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | false | AMP 페이지 생성 활성화 |
| path_prefix | string | "amp" | AMP 페이지의 URL 접두사 |
| sections | array | [] | AMP를 생성할 섹션 (비워 두면 전체) |

## 변환 내용

AMP 변환기는 다음 변환을 자동으로 적용합니다:

| 원본 | AMP 버전 |
|----------|-------------|
| `<html>` | `<html amp>` |
| `<img>` | `<amp-img layout="responsive">` |
| `<video>` | `<amp-video layout="responsive">` |
| `<iframe>` | `<amp-iframe layout="responsive">` |
| `<script>` (인라인) | 제거 |
| `style="..."` 속성 | 제거 |
| `onclick` 핸들러 | 제거 |

추가로 다음이 주입됩니다:
- AMP 보일러플레이트 CSS
- AMP 런타임 스크립트 (`cdn.ampproject.org/v0.js`)
- 원본 페이지를 가리키는 `<link rel="canonical">`

## 출력 구조

`/posts/hello/` 페이지가 있을 때 출력은 다음과 같습니다:

```
public/
  posts/hello/index.html       ← canonical (has <link rel="amphtml">)
  amp/posts/hello/index.html   ← AMP version
```

## 섹션 필터링

기본적으로 AMP 페이지는 모든 섹션에 대해 생성됩니다. `sections`로 대상을 제한합니다:

```toml
[amp]
enabled = true
sections = ["posts", "blog"]   # 이 섹션들만 AMP 버전 생성
```

## 사용자 지정 경로 접두사

```toml
[amp]
enabled = true
path_prefix = "mobile"    # /amp/posts/hello/ 대신 /mobile/posts/hello/
```

## 함께 보기

- [설정](/ko/start/config/) — 전체 설정 레퍼런스
- [SEO](/ko/features/seo/) — 사이트맵, 피드, OpenGraph
