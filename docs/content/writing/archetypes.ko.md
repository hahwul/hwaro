+++
title = "아키타입"
description = "일관된 프론트 매터와 구조를 위한 콘텐츠 템플릿"
weight = 5
toc = true
+++

아키타입은 새 페이지의 기본 프론트 매터와 콘텐츠 구조를 정의하는 콘텐츠 템플릿입니다. `hwaro new`로 콘텐츠를 만들 때 아키타입이 일관된 출발점을 제공합니다.

`hwaro init`은 기본 `archetypes/default.md`를(블로그 스캐폴드의 `posts.md`처럼 스캐폴드별 아키타입도 함께) 만들어 주므로, `hwaro new`는 별도 설정 없이 `description` 필드가 포함된 프론트 매터(기본 TOML, YAML과 JSON도 지원)를 바로 사용합니다. 사이트 관례에 맞게 수정하거나 확장하면 됩니다.

## 개요

아키타입은 프로젝트 루트의 `archetypes/` 디렉터리에 둡니다:

```
my-site/
├── archetypes/
│   ├── default.md      # Default template
│   ├── posts.md        # For content/posts/
│   └── tools/
│       └── develop.md  # For content/tools/develop/
├── content/
├── templates/
└── config.toml
```

## 아키타입 작성

아키타입은 프론트 매터와 선택적 본문이 있는 마크다운 파일입니다. 새 콘텐츠를 만들 때 치환되는 플레이스홀더를 사용합니다.

### 사용 가능한 플레이스홀더

| 플레이스홀더 | 설명 |
|-------------|-------------|
| `{{ title }}` | 콘텐츠 제목(`-t` 플래그 또는 파일명에서) |
| `{{ date }}` | 현재 로컬 날짜(`YYYY-MM-DD`) 또는 `--date` 값 그대로 |
| `{{ tags }}` | `--tags`로 받은 태그의 TOML 배열(없으면 `[]`) |
| `{{ draft }}` | `--draft`를 줬거나 대상 경로에 `drafts` 디렉터리가 포함되면 `true`, 그 외에는 `false` |
| `{{ description }}` | 대화형 `hwaro new` 마법사에서 입력받은 설명. 없으면 빈 문자열 |

### 아키타입 예시

`archetypes/posts.md`를 만듭니다:

```markdown
+++
title = "{{ title }}"
date = {{ date }}
draft = false
authors = ["Your Name"]
tags = []
categories = []
+++

# {{ title }}

Write your introduction here.

## Main Content

Add your content...
```

## 아키타입 매칭

`hwaro new`를 실행하면 아키타입이 다음 순서로 매칭됩니다:

### 1. 명시적 플래그(`-a`)

```bash
hwaro new -t "My Article" -a posts
```

출력 경로와 무관하게 `archetypes/posts.md`를 사용합니다.

### 2. 경로 기반 매칭

```bash
hwaro new posts/hello-world.md
```

`archetypes/posts.md`가 있는지 확인합니다.

### 3. 중첩 경로 매칭

```bash
hwaro new tools/develop/mytool.md
```

다음 순서로 시도합니다:
1. `archetypes/tools/develop.md`
2. `archetypes/tools.md`
3. `archetypes/default.md`

### 4. 기본 아키타입

일치하는 아키타입이 없으면 `archetypes/default.md`를 사용합니다.

### 5. 내장 템플릿

아키타입이 하나도 없으면 내장 기본 템플릿을 사용합니다. 이 템플릿의 포맷과 기본 필드는 `config.toml`의 `[content.new]`로 제어합니다:

```toml
[content.new]
front_matter_format = "toml"         # "toml"(기본값), "yaml", "json"
default_fields = ["description"]      # 빈 값으로 스캐폴드할 추가 키
bundle = false                        # true: foo.md 대신 foo/index.md 스캐폴드
```

내장 필드(`title`, `date`, `draft`, `tags`)와 겹치는 항목은 빈 값으로 중복 생성되지 않도록 무시됩니다.

### 리프 번들(디렉터리) 레이아웃

다국어 형제 파일(`index.ko.md`)이나 페이지 옆에 함께 둘 이미지를 계획하고 있다면 페이지당 디렉터리 레이아웃이 필요합니다:

```
content/abcd/
└── index.md
```

레이아웃은 실행 단위, 아키타입 단위, 사이트 단위로 고를 수 있습니다:

- **CLI:** `hwaro new posts/hello.md --bundle`(단일 파일 형태를 강제하려면 `--no-bundle`).
- **아키타입:** 아키타입 첫 줄에 `<!-- hwaro: bundle -->`을 두면 그 아키타입을 쓰는 모든 `hwaro new`가 번들 모드를 기본으로 사용합니다. 이 지시자는 생성된 콘텐츠에서 제거됩니다.
- **설정:** `[content.new]` 아래 `bundle = true`로 사이트 전체 기본을 정합니다.

우선순위는 CLI > 아키타입 > 설정 > 단일 파일(기본값) 순입니다.

## 사용 예시

### 기본 사용법

```bash
# 경로 기반 아키타입 매칭 사용
hwaro new posts/my-first-post.md

# 제목을 명시적으로 지정
hwaro new posts/my-post.md -t "My First Post"

# 특정 아키타입 사용
hwaro new -t "Quick Note" -a posts
```

### 콘텐츠 유형별 생성

```bash
# 블로그 글 (archetypes/posts.md 사용)
hwaro new posts/new-article.md

# 문서 (archetypes/docs.md 사용)
hwaro new docs/getting-started.md

# 도구 페이지 (archetypes/tools.md 또는 archetypes/tools/develop.md 사용)
hwaro new tools/develop/my-tool.md
```

## 추천 아키타입

### 블로그 글(`archetypes/posts.md`)

```markdown
+++
title = "{{ title }}"
date = {{ date }}
draft = false
authors = []
tags = []
categories = []
description = "{{ description }}"
image = ""
+++

# {{ title }}

Introduction paragraph.

## Content
```

### 문서(`archetypes/docs.md`)

```markdown
+++
title = "{{ title }}"
date = {{ date }}
weight = 10
toc = true
+++

Brief description of this documentation page.

## Overview

## Usage

## Examples
```

### 기본(`archetypes/default.md`)

```markdown
+++
title = "{{ title }}"
date = "{{ date }}"
draft = {{ draft }}
description = "{{ description }}"
tags = {{ tags }}
+++

# {{ title }}
```

`hwaro init`이 만들어 주는 `archetypes/default.md`와 같은 내용입니다. `{{ description }}` 플레이스홀더는 플래그 방식에서는 빈 문자열로, 대화형 `hwaro new` 마법사에서는 입력한 값으로 치환됩니다.

## 팁

- **일관된 메타데이터**: 자주 쓰는 프론트 매터 필드를 아키타입에 모두 정의합니다
- **섹션별 아키타입**: 콘텐츠 섹션마다 알맞은 기본값을 가진 아키타입을 만듭니다
- **중첩 구성**: 콘텐츠 구조에 맞춰 `archetypes/` 안에 하위 디렉터리를 사용합니다
- **초안 처리**: `{{ draft }}`는 `--draft`를 줬을 때, 대화형 마법사에서 초안 토글을 켰을 때, 대상 경로에 `drafts/` 세그먼트가 포함될 때 `true`가 됩니다

## 함께 보기

- [페이지](/ko/writing/pages/) — 프론트 매터 필드 레퍼런스
- [CLI](/ko/start/cli/) — `hwaro new` 명령
