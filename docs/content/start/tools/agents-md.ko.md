+++
title = "agents-md"
description = "AGENTS.md 파일 생성 및 갱신"
weight = 12
+++

AI 에이전트 지침용 AGENTS.md 파일을 생성하거나 갱신합니다. 기존 프로젝트를 최신 AGENTS.md로 업데이트하거나 콘텐츠 모드를 전환할 때 유용합니다.

```bash
# 로컬(전체 내장) 버전을 stdout으로 출력
hwaro tool agents-md

# 원격(경량) 버전을 stdout으로 출력
hwaro tool agents-md --remote

# AGENTS.md 파일로 저장
hwaro tool agents-md --write

# 원격 버전을 파일로 저장
hwaro tool agents-md --remote --write

# 확인 없이 덮어쓰기
hwaro tool agents-md --write --force
```

## 콘텐츠 모드

| 모드 | 설명 |
|------|-------------|
| `--local` (기본값) | 전체 내장 레퍼런스(약 260줄). 콘텐츠 형식, 템플릿 변수, 설정 레퍼런스, AI 에이전트 참고 사항 포함. 오프라인이나 로컬 LLM 환경에 적합 |
| `--remote` | 경량 버전(약 50줄). 프로젝트 구조, 핵심 명령, 그리고 [온라인 문서](https://hwaro.hahwul.com)와 [LLM 레퍼런스](https://hwaro.hahwul.com/llms-full.txt) 링크가 담긴 AI 에이전트 참고 사항 포함 |

두 모드 모두 프로젝트 고유의 규칙과 컨벤션을 적을 수 있는 **Site-Specific Instructions** 섹션을 포함합니다.

## 옵션

| 플래그 | 설명 |
|------|-------------|
| --remote | 온라인 문서 링크가 있는 경량 버전 생성 |
| --local | 전체 내장 레퍼런스 생성 (기본값) |
| --write | stdout 대신 AGENTS.md 파일로 저장 |
| -f, --force | 기존 파일을 확인 없이 덮어쓰기 |
| -h, --help | 도움말 표시 |

기본적으로 stdout에 출력하므로 저장하기 전에 내용을 살펴볼 수 있습니다. 파일로 저장하려면 `--write`를 사용합니다. `AGENTS.md`가 이미 있으면 `--force`를 쓰지 않는 한 확인을 요청합니다.

## `hwaro init`와의 관계

새 프로젝트를 만들 때는 `hwaro init`도 AGENTS.md 파일을 생성합니다. 콘텐츠 모드는 `--agents` 플래그로 지정합니다:

```bash
hwaro init my-site                  # 기본값: remote (경량)
hwaro init my-site --agents local   # 전체 내장 레퍼런스
hwaro init my-site --skip-agents-md # AGENTS.md 생성 생략
```

## 함께 보기

- [CLI](/ko/start/cli/) — init 명령 옵션
- [CLI](/ko/start/cli/) — 전체 tool 명령
