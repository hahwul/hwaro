+++
title = "ci (사용 중단)"
description = "CI/CD 워크플로 파일 생성 (사용 중단, tool platform 사용)"
weight = 6
+++

> **사용 중단:** `hwaro tool ci`는 `hwaro tool platform`으로 통합되었습니다. 대신 `hwaro tool platform github-pages`를 사용합니다.

```bash
# 이전 (사용 중단)
hwaro tool ci github-actions

# 새 명령
hwaro tool platform github-pages
```

`tool ci github-actions`는 stderr에 사용 중단 경고를 출력한 뒤 `tool platform github-pages`와 같은 워크플로(`.github/workflows/deploy.yml`)를 생성하며, `-o, --output PATH`, `--stdout`, `-f, --force` 플래그도 똑같이 받습니다.

전체 문서는 [platform](/ko/start/tools/platform/)을 참고합니다.
