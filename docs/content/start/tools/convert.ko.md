+++
title = "convert"
description = "프론트 매터를 TOML, YAML, JSON 형식 간에 변환"
weight = 1
+++

콘텐츠 파일 전체의 프론트 매터를 TOML, YAML, JSON 형식 간에 변환합니다.

```bash
# 모든 프론트 매터를 YAML로 변환
hwaro tool convert to-yaml

# 모든 프론트 매터를 TOML로 변환
hwaro tool convert to-toml

# 모든 프론트 매터를 JSON으로 변환
hwaro tool convert to-json

# 특정 디렉터리만 변환
hwaro tool convert to-yaml -c posts

# 결과를 JSON으로 출력
hwaro tool convert to-yaml --json
```

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -c, --content DIR | 특정 콘텐츠 디렉터리로 변환 범위 제한 |
| -j, --json | 결과를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

## JSON 출력

```json
{
  "success": true,
  "message": "Converted 5 files to YAML",
  "converted_count": 5,
  "skipped_count": 2,
  "error_count": 0
}
```

## 예시

변환 전:

```markdown
+++
title = "My Post"
date = "2024-01-15"
tags = ["crystal", "tutorial"]
+++

Content here.
```

`hwaro tool convert to-yaml` 실행 후:

```markdown
---
title: "My Post"
date: "2024-01-15"
tags:
  - crystal
  - tutorial
---

Content here.
```

`hwaro tool convert to-json` 실행 후:

```markdown
{
  "title": "My Post",
  "date": "2024-01-15",
  "tags": [
    "crystal",
    "tutorial"
  ]
}

Content here.
```
