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

# 가장 최근 발행 파일 5개
hwaro tool list published --limit 5

# 제목순 정렬(A→Z), 또는 임의 정렬의 역순
hwaro tool list all --sort title
hwaro tool list all --sort path --reverse

# 결과를 JSON으로 출력
hwaro tool list all --json
```

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -c, --content-dir DIR | 특정 콘텐츠 디렉터리로 목록 범위 제한 |
| --sort KEY | 정렬 키: `date`(최신순, 기본값), `title`, `path` |
| -r, --reverse | 정렬 순서 뒤집기 |
| -n, --limit N | 최대 N개 파일만 표시 (정렬 후 적용) |
| -j, --json | 결과를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

`--limit`은 정렬 후에 적용되므로 `--sort date --limit 5`는 "가장 최신 5개",
`--sort date --reverse --limit 5`는 가장 오래된 5개를 의미합니다.

필터 인자는 축약형 `draft`(`drafts`)와 `pub`(`published`)도 허용합니다.

## 필터

| 필터 | 설명 |
|--------|-------------|
| all | 모든 콘텐츠 파일 표시 |
| drafts | 초안만 표시 — `draft = true` 또는 상위 섹션에서 캐스케이드된 `draft` |
| published | 기본 `hwaro build`가 실제로 발행하는 파일만 표시 |

`published`는 "draft 표시가 없음"이 아니라 "빌드가 실제로 내보냄"을 뜻합니다.
기본 빌드는 미래 날짜(`date`가 미래) 페이지와 만료된(`expires`가 지난) 페이지도
제외하므로, 이들은 별도 상태로 보고됩니다.

| 상태 | 의미 |
|--------|---------|
| `[pub]` | 기본 빌드가 발행 |
| `[draft]` | 자체 또는 캐스케이드된 `draft = true` |
| `[future]` | `date`가 미래 (`--include-future`로 빌드 가능) |
| `[expired]` | `expires`가 지남 (`--include-expired`로 빌드 가능) |

## JSON 출력

```json
[
  {
    "path": "content/blog/my-post.md",
    "title": "My Post",
    "draft": false,
    "date": "2024-06-15T00:00:00+00:00",
    "status": "published",
    "expires": null
  },
  {
    "path": "content/blog/draft-post.md",
    "title": "Draft Post",
    "draft": true,
    "date": "2024-06-10T00:00:00+00:00",
    "status": "draft",
    "expires": null
  }
]
```

`status`는 `published`, `draft`, `future`, `expired` 중 하나입니다. `draft`는
기존 소비자를 위해 유지되며 실제 초안일 때만 true입니다.
