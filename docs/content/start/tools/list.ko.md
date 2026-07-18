+++
title = "list"
description = "상태별 콘텐츠 파일 목록 출력"
weight = 2
+++

상태별로 걸러낸 콘텐츠 파일 목록을 출력합니다.

```bash
# 모든 콘텐츠 파일 나열
hwaro tool list all

# 초안 파일만 나열
hwaro tool list drafts

# 발행된 파일만 나열
hwaro tool list published

# 특정 디렉터리의 파일 나열
hwaro tool list all -c posts

# 결과를 JSON으로 출력
hwaro tool list all --json
```

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -c, --content DIR | 특정 콘텐츠 디렉터리로 목록 범위 제한 |
| -j, --json | 결과를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

## 필터

| 필터 | 설명 |
|--------|-------------|
| all | 모든 콘텐츠 파일 표시 |
| drafts | `draft = true`인 파일만 표시 |
| published | `draft = false`이거나 draft 필드가 없는 파일만 표시 |

## JSON 출력

```json
[
  {
    "path": "content/blog/my-post.md",
    "title": "My Post",
    "draft": false,
    "date": "2024-06-15T00:00:00+00:00"
  },
  {
    "path": "content/blog/draft-post.md",
    "title": "Draft Post",
    "draft": true,
    "date": "2024-06-10T00:00:00+00:00"
  }
]
```
