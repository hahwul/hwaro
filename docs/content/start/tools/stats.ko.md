+++
title = "stats"
description = "콘텐츠 통계 표시"
weight = 7
+++

글 개수, 단어 수 지표, 태그 분포, 월별 발행 빈도 등 콘텐츠 통계를 표시합니다.

```bash
# 콘텐츠 디렉터리 통계 표시
hwaro tool stats

# 사용자 지정 콘텐츠 디렉터리 사용
hwaro tool stats -c posts

# JSON으로 출력
hwaro tool stats --json
```

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -c, --content DIR | 콘텐츠 디렉터리 (기본값: content) |
| -j, --json | 결과를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

## 출력 예시

```
hwaro: stats content
total: 42 files, 4 drafts
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

counted: 42 files, 38 published, 4 drafts
```

색상 터미널에서는 같은 보고서가 `hwaro stats` 헤딩, 정렬된 영수증 형식 행,
비례 막대 차트, `✦ counted` 결과 줄로 표시됩니다. 태그가 15개를 넘으면 상위
15개만 차트로 그립니다(`tags: top 15`).

## JSON 출력

```json
{
  "total": 42,
  "published": 38,
  "drafts": 4,
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
