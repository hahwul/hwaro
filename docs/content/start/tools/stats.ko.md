+++
title = "stats"
description = "콘텐츠 통계 표시"
weight = 7
+++

글 개수, 단어 수 지표, 태그 분포, 월별 발행 빈도 등 콘텐츠 통계를 표시합니다.

`published`는 기본 `hwaro build`가 실제로 내보내는 파일 수입니다. 빌드가 제외하는
파일은 각각의 이유로 따로 집계됩니다 — `drafts`(자체 또는 상위 섹션에서 캐스케이드),
`future`(`date`가 미래), `expired`(`expires`가 지남). 단어 수·태그 분포·월별 차트는
발행되는 파일만 대상으로 합니다. 태그는 최상위 `tags` 목록에서 읽고, 없으면
`[taxonomies] tags` 테이블로 대체합니다 — 빌드와 동일한 규칙입니다.

```bash
# 콘텐츠 디렉터리 통계 표시
hwaro tool stats

# 사용자 지정 콘텐츠 디렉터리 사용
hwaro tool stats -c posts

# 기본 15개 대신 상위 30개 태그 차트
hwaro tool stats --top 30

# JSON으로 출력
hwaro tool stats --json
```

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -c, --content-dir DIR | 콘텐츠 디렉터리 (기본값: content) |
| --top N | 차트에 상위 N개 태그 표시 (기본값: 15) |
| -j, --json | 결과를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

## 출력 예시

```
hwaro: stats content
total: 42 files, 4 drafts · 1 future
words: 28,500 total, 678 avg
range: 120 min, 3,200 max

tags:
      crystal     12  ####################
      web          8  #############
      tutorial     5  ########

monthly:
      2024-01      3  ############
      2024-02      5  ####################
      2024-03      2  ########

counted: 42 files, 37 published, 4 drafts · 1 future
```

색상 터미널에서는 같은 보고서가 `hwaro stats` 헤딩, 정렬된 영수증 형식 행,
비례 막대 차트, `✦ counted` 결과 줄로 표시됩니다. 태그가 차트 예산을 넘으면
상위 N개만 차트로 그립니다(기본 `tags: top 15`, `--top N`으로 조정). JSON
출력은 `--top`과 무관하게 항상 모든 태그를 담습니다.

## JSON 출력

```json
{
  "total": 42,
  "published": 37,
  "drafts": 4,
  "future": 1,
  "expired": 0,
  "word_count": {
    "total": 28500,
    "average": 678,
    "min": 120,
    "max": 3200
  },
  "tags": {
    "crystal": 12,
    "web": 8,
    "tutorial": 5
  },
  "monthly": {
    "2024-01": 3,
    "2024-02": 5,
    "2024-03": 2
  }
}
```
