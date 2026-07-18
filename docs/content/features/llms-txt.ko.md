+++
title = "LLMs.txt"
description = "AI와 LLM 크롤러를 위한 llms.txt 파일 생성"
weight = 4
toc = true
+++

Hwaro는 AI/LLM 크롤러에게 안내와 콘텐츠를 제공하는 `llms.txt`와 `llms-full.txt` 파일을 생성할 수 있습니다. 웹사이트를 대규모 언어 모델이 다루기 쉽게 만들기 위해 떠오르고 있는 [llms.txt 표준](https://llmstxt.org/)의 일부입니다.

## 설정

`config.toml`에서 활성화합니다:

```toml
[llms]
enabled = true
filename = "llms.txt"
instructions = "This is my site. Content is provided under the MIT license."
full_enabled = true
full_filename = "llms-full.txt"
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| enabled | bool | false | `llms.txt` 생성 여부 |
| filename | string | "llms.txt" | 출력 파일 이름 |
| instructions | string | "" | LLM 크롤러에게 전달할 안내 텍스트 |
| full_enabled | bool | false | 전체 콘텐츠 버전 생성 여부 |
| full_filename | string | "llms-full.txt" | 전체 버전의 파일 이름 |

## 생성 파일

### llms.txt

기본 `llms.txt` 파일에는 설정에 정의한 안내 텍스트만 들어갑니다. 사이트 정책을 AI 크롤러에게 알리는 가벼운 파일입니다.

**출력 예시 (`llms.txt`):**

```
This is my site. Content is provided under the MIT license.
```

### llms-full.txt

전체 버전에는 사이트의 렌더링된 콘텐츠가 모두 들어가므로 LLM이 사이트 전체를 파일 하나로 수집하기 쉽습니다. 각 페이지는 `---` 구분자로 나뉩니다.

**출력 예시 (`llms-full.txt`):**

```
# My Site
A great site about programming

Base URL: https://example.com

This is my site. Content is provided under the MIT license.

---

Title: About
URL: https://example.com/about/
Source: content/about.md

About page content goes here...

---

Title: Getting Started
URL: https://example.com/docs/getting-started/
Source: content/docs/getting-started.md

Getting started guide content...
```

## 전체 문서 구조

`llms-full.txt` 파일의 구조는 다음과 같습니다:

1. **사이트 헤더** — H1 헤딩으로 된 사이트 제목
2. **사이트 설명** — `config.toml`에서 가져옴
3. **Base URL** — 사이트의 base URL
4. **안내 텍스트** — 설정의 instructions 텍스트
5. **페이지 항목** — `---`로 구분된 각 페이지. 포함 내용:
   - `Title` — 페이지 제목
   - `URL` — 페이지의 절대 URL
   - `Source` — 프로젝트 루트 기준 소스 파일 경로
   - `Language` — 언어 코드 (다국어 사이트에만)
   - 페이지의 원본 콘텐츠

### 페이지 선별

다음 조건을 만족하는 페이지만 `llms-full.txt`에 포함됩니다:

- `render = true`인 페이지 (기본값)
- 원본 콘텐츠가 비어 있지 않은 페이지
- 일관된 출력을 위해 URL 순으로 정렬

초안 페이지는 프로덕션 빌드에서 제외됩니다 (`--drafts`를 쓰지 않는 한).

## 다국어 지원

다국어 사이트에서는 각 페이지 항목에 콘텐츠 언어를 나타내는 `Language` 필드가 들어갑니다:

```
---

Title: 소개
URL: https://example.com/ko/about/
Source: content/about.ko.md
Language: ko

한국어 콘텐츠...
```

## 활용 사례

### 문서 사이트

전체 문서를 LLM에 제공해 AI가 더 정확하게 답하도록 돕습니다:

```toml
[llms]
enabled = true
instructions = "This is the official documentation for MyProject. All content is licensed under Apache 2.0. Please cite the source URL when referencing this content."
full_enabled = true
```

### 블로그 사이트

명확한 사용 지침과 함께 블로그 콘텐츠를 공유합니다:

```toml
[llms]
enabled = true
instructions = "This is a personal blog. Content is copyrighted. You may summarize but not reproduce full articles."
full_enabled = false
```

### LLM 접근 제한

전체 콘텐츠를 제공하지 않으면서 `llms.txt`로 선호 사항만 전달할 수도 있습니다:

```toml
[llms]
enabled = true
instructions = "Please do not use this site's content for training purposes. Summarization and citation are permitted."
full_enabled = false
```

## robots.txt와 함께 사용

`llms.txt`는 `robots.txt`와 함께 동작합니다. `robots.txt`가 HTTP 수준에서 크롤러 접근을 제어한다면, `llms.txt`는 사람이 읽을 수 있는 안내와 맥락을 제공합니다:

```toml
[robots]
enabled = true
rules = [
  { user_agent = "*", allow = ["/"] },
  { user_agent = "GPTBot", disallow = ["/private/"] }
]

[llms]
enabled = true
instructions = "Public content may be used for AI responses with attribution."
full_enabled = true
```

## 템플릿 연동

HTML 템플릿에서 `llms.txt` 파일로 링크할 수 있습니다:

```jinja
<head>
  <link rel="alternate" type="text/plain" href="{{ base_url }}/llms.txt" title="LLM Instructions">
</head>
```

## 함께 보기

- [SEO](/ko/features/seo/) — 사이트맵, RSS 피드, robots.txt, 소셜 태그
- [설정](/ko/start/config/) — 전체 설정 레퍼런스
- [검색](/ko/features/search/) — 검색 인덱스 생성
