+++
title = "에이전트 스킬"
description = "Claude Code, Cursor, OpenCode, Codex 등 스킬 지원 에이전트에 바로 설치하는 SKILL.md 파일"
weight = 1
toc = true
+++

Hwaro는 두 개의 [에이전트 스킬](https://github.com/hahwul/hwaro/tree/main/skills)을 제공합니다. 스킬을 지원하는 AI 에이전트에게 Hwaro 사용법을 가르치는 독립적인 `SKILL.md` 파일로, 설치해 두면 에이전트가 Hwaro 작업을 감지했을 때 해당 스킬을 자동으로 불러옵니다.

| 스킬 | 가르치는 내용 |
|-------|-----------------|
| **`hwaro`** | CLI 운용 — 스캐폴드(`init`), 콘텐츠 작성(`new`), 미리 보기(`serve`), 프로덕션 빌드(`build`), 그리고 `doctor`/`tool`/`deploy` 하위 명령. 에이전트에 안전한 출력 계약 — `--json`, `--quiet`, `NO_COLOR`, 분류된 `HWARO_E_*` 오류/종료 코드 — 과 안전한 `config.toml`·Crinja 템플릿 수정을 강조합니다. |
| **`hwaro-design`** | 사이트 디자인과 리스타일링. **요구 사항을 읽고 한 줄짜리 Design Read를 선언한 뒤 세 가지 디자인 다이얼을 설정**하고(의도가 정말 모호할 때만 질문), Hwaro의 Crinja 템플릿과 CSS 변수 토큰 시스템 안에서 개성 있는 프로덕션 수준의 디자인을 만들어 냅니다. 뻔한 AI 미감을 걸러내는 엄격한 anti-slop 원칙과 기계적인 사전 점검을 따릅니다. |

## `npx skills`로 설치

[`skills` CLI](https://www.npmjs.com/package/skills)를 사용하면 스킬 설치와 업데이트가 가장 간편합니다. 저장소를 추가하면 두 Hwaro 스킬(`hwaro`, `hwaro-design`)이 **모두** 설치됩니다.

```bash
# 현재 프로젝트에 추가 — 에이전트를 고르라는 프롬프트 표시 (.claude/skills, .cursor/, …)
npx skills add hahwul/hwaro

# 모든 프로젝트에서 쓰도록 전역 설치
npx skills add hahwul/hwaro -g

# 특정 에이전트 지정 (예: Claude Code)
npx skills add hahwul/hwaro -a claude-code

# 비대화형 — CI에 적합
npx skills add hahwul/hwaro -g -a claude-code -y
```

나중에 스킬 이름으로 업데이트하거나 제거합니다:

```bash
npx skills update hwaro hwaro-design
npx skills remove hwaro hwaro-design
```

## 수동 설치

`npx`를 쓰고 싶지 않다면 저장소에서 파일을 직접 복사합니다. **Claude Code**의 설치 경로는 `~/.claude/skills/<name>/SKILL.md`입니다:

```bash
# hwaro — CLI 스킬
mkdir -p ~/.claude/skills/hwaro
curl -o ~/.claude/skills/hwaro/SKILL.md \
  https://raw.githubusercontent.com/hahwul/hwaro/main/skills/hwaro/SKILL.md

# hwaro-design — 디자인 스킬
mkdir -p ~/.claude/skills/hwaro-design
curl -o ~/.claude/skills/hwaro-design/SKILL.md \
  https://raw.githubusercontent.com/hahwul/hwaro/main/skills/hwaro-design/SKILL.md
```

다른 에이전트는 다른 스킬 디렉터리를 사용합니다(예: `.cursor/`, 프로젝트 로컬 `skills/` 폴더). 정확한 위치는 사용하는 에이전트의 문서를 확인합니다.

## 스킬이 다루는 내용

### `hwaro` — CLI 다루기

- **트리거 시점:** Hwaro 관련 작업이거나, `config.toml`과 함께 `content/`·`templates/`가 있는 디렉터리를 만났을 때.
- **출력 계약:** 사람이 읽는 텍스트를 긁어내는 대신 `--json`을 우선 사용하고, 분류된 종료 코드(`HWARO_E_USAGE`, `HWARO_E_CONFIG`, `HWARO_E_TEMPLATE`, `HWARO_E_CONTENT`, …)로 분기합니다.
- **워크플로:** `init` 스캐폴드, `new`와 아키타입, `serve` 라이브 리로드 개발 루프, 프로덕션 `build`(`--minify`, `--cache`, `--base-url`, 환경 변수 재정의), `doctor` / `tool validate` / `tool check-links`, 콘텐츠 도구, `tool platform`, `deploy`.
- **안전한 수정:** TOML 설정 규칙과 Crinja 템플릿 주의점(`| safe`, nil 가드, URL에는 `url_for`/`asset`), 그리고 종료 코드로 검증하는 루프.

### `hwaro-design` — 사이트 디자인

- **Design Read 우선:** CSS를 한 줄이라도 쓰기 전에 요구 사항을 읽고 한 줄짜리 디자인 방향과 세 가지 다이얼(`DESIGN_VARIANCE` / `MOTION_INTENSITY` / `VISUAL_DENSITY`)을 선언합니다. 의도가 정말 모호할 때만 짧고 집중된 질문을 하고, 전체 취향 인터뷰는 요청할 때만 진행하므로, 결과물은 기본값이 아니라 **사용자의** 취향을 반영합니다.
- **Anti-slop 원칙:** AI가 만든 디자인의 전형적 신호를 강하게 금지하는 방대한 목록 — 본문 카피의 em-dash, eyebrow 라벨 남용, 반복되는 섹션 레이아웃, hero 오버플로, `<div>`로 만든 가짜 스크린샷, AI 특유의 보라색 그라디언트, 장식용 점과 로케일 스트립, "Jane Doe" 데모 콘텐츠 — 에 레이아웃·카피 밀도·이미지 규칙을 더해, 완료를 선언하기 전에 기계적인 사전 점검 체크리스트로 전부 강제합니다.
- **Hwaro 메커니즘:** Crinja 템플릿 구조, 세 가지 CSS 전달 방식(인라인, `[auto_includes]`, `[assets]` 파이프라인), 모든 내장 스캐폴드가 테마의 기반으로 공유하는 `light-dark()` 디자인 토큰 어휘(라이트/다크는 자동 지원, 토큰 쌍만 재정의하면 리테마), `resize_image`를 이용한 반응형 이미지, CSS 스크롤 기반 애니메이션과 `IntersectionObserver`를 이용한 정적 사이트 모션 — 프레임워크가 필요 없습니다.

## 사전 요구 사항

에이전트가 실제로 빌드와 미리 보기를 실행할 수 있도록 Hwaro CLI를 설치합니다. [설치](/ko/start/installation/)를 참고합니다. 스킬은 그것이 다루는 바이너리가 있어야 비로소 쓸모가 있습니다.

`hwaro` 스킬은 프로젝트의 `AGENTS.md`를 보완합니다. 스킬이 어느 Hwaro 프로젝트에서든 에이전트를 따라다니는 이동 가능한 지침이라면, [`hwaro tool agents-md`](/ko/start/tools/agents-md/)로 생성하는 `AGENTS.md`는 프로젝트별 규칙을 담습니다. 에이전트는 `AGENTS.md`를 먼저 읽어야 하며, 이 파일이 스킬의 기본값을 재정의할 수 있습니다.

## 작성 팁

두 스킬 모두 Hwaro 저장소의 [`skills/`](https://github.com/hahwul/hwaro/tree/main/skills) 아래에 있습니다. 기여할 때는 다음을 지킵니다:

- CLI/템플릿 레퍼런스 전체를 복제하는 대신(그 내용은 이 문서로 링크), **에이전트의 상호작용 패턴** — 무엇을 언제 실행하고 어떻게 복구하는지 — 을 중심으로 작성합니다.
- 프론트 매터의 `description`을 정확하게 유지합니다. 에이전트는 이 값을 읽고 스킬을 *언제* 불러올지 결정합니다.
- [GitHub](https://github.com/hahwul/hwaro)에 풀 리퀘스트를 엽니다.

## 함께 보기

- [CLI](/ko/start/cli/) — `hwaro` 스킬이 다루는 모든 명령과 플래그.
- [agents-md](/ko/start/tools/agents-md/) — AI 에이전트를 위한 프로젝트별 지침.
- [템플릿](/ko/templates/) — 디자인 스킬이 기반으로 삼는 데이터 모델, 함수, 필터.
