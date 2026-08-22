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

# 아무것도 바꾸지 않고 어떤 파일이 변환될지 미리보기
hwaro tool convert to-yaml --dry-run

# 결과를 JSON으로 출력
hwaro tool convert to-yaml --json
```

## 옵션

| 플래그 | 설명 |
|------|-------------|
| -c, --content-dir DIR | 특정 콘텐츠 디렉터리로 변환 범위 제한 |
| --dry-run | 파일을 변경하지 않고 변환 대상만 미리보기 |
| -j, --json | 결과를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

변환은 파일을 제자리에서 다시 쓰며 프런트매터 주석을 보존할 수 없으므로,
중요한 트리에는 `--dry-run`을 먼저 실행하세요. 파일을 쓰지 않을 뿐 파일별
"dropping N comment line(s)" 경고를 포함한 전체 파이프라인이 동일하게
동작합니다.

## JSON 출력

```json
{
  "success": true,
  "message": "Converted 5 files to YAML",
  "converted_count": 5,
  "skipped_count": 2,
  "error_count": 0,
  "dry_run": false
}
```

## 건너뛴 파일

사람이 읽는 요약에는 건너뛴 이유가 함께 표시됩니다 — `already TOML`,
`without front matter`, `not front matter`:

```
converted: 5 files · 2 skipped (1 already TOML, 1 not front matter)
```

이 중 `not front matter`를 눈여겨보세요. 파일 첫머리의 `---`/`+++` 쌍 안이
키/값 매핑이 아니라 본문(예: 수평선)이라는 뜻입니다. 그대로 변환하면 작성자의
글이 지워지므로 파일을 건드리지 않고 stderr에 파일명을 남깁니다.

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
