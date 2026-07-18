+++
title = "도구와 자동 완성"
description = "콘텐츠 관리 유틸리티 도구와 셸 자동 완성"
weight = 5
toc = true
sort_by = "weight"
+++

Hwaro는 콘텐츠 관리를 돕는 유틸리티 도구와, CLI를 더 편하게 쓰기 위한 셸 자동 완성 스크립트를 제공합니다.

## 도구 명령

`hwaro tool` 명령은 콘텐츠 파일을 다루는 유틸리티 하위 명령을 제공합니다.

| 하위 명령 | 설명 |
|------------|-------------|
| [convert](/ko/start/tools/convert/) | 프론트 매터를 YAML과 TOML 형식 간에 변환 |
| [list](/ko/start/tools/list/) | 상태별 콘텐츠 파일 목록 출력 |
| [check-links](/ko/start/tools/check-links/) | 콘텐츠 파일의 깨진 링크 검사 |
| [stats](/ko/start/tools/stats/) | 콘텐츠 통계 표시 |
| [validate](/ko/start/tools/validate/) | 콘텐츠 프론트 매터와 마크업 검증 |
| [unused-assets](/ko/start/tools/unused-assets/) | 참조되지 않는 정적 파일 찾기 |
| [doctor](/ko/start/tools/doctor/) | 설정·템플릿·구조 문제 진단 |
| [platform](/ko/start/tools/platform/) | 호스팅 플랫폼 설정 파일 생성 |
| [import](/ko/start/tools/import/) | 다양한 플랫폼에서 콘텐츠 가져오기 |
| [export](/ko/start/tools/export/) | 다른 플랫폼으로 콘텐츠 내보내기 |
| [agents-md](/ko/start/tools/agents-md/) | AGENTS.md 파일 생성·갱신 |

> **사용 중단:** [ci (사용 중단)](/ko/start/tools/ci/)는 도움말에서 숨겨졌으며 [platform](/ko/start/tools/platform/)으로 대체되었습니다(예: `hwaro tool platform github-pages`).

---

## 셸 자동 완성

Hwaro는 셸별 자동 완성 스크립트를 생성해 명령, 하위 명령, 플래그를 탭으로 완성할 수 있게 합니다.

### 지원 셸

| 셸 | 명령 |
|-------|---------|
| Bash | `hwaro completion bash` |
| Zsh | `hwaro completion zsh` |
| Fish | `hwaro completion fish` |

### 설치

#### Bash

`~/.bashrc`에 추가합니다:

```bash
eval "$(hwaro completion bash)"
```

파일로 저장해도 됩니다:

```bash
hwaro completion bash > /etc/bash_completion.d/hwaro
```

#### Zsh

`~/.zshrc`에 추가합니다:

```bash
eval "$(hwaro completion zsh)"
```

fpath에 저장해도 됩니다:

```bash
hwaro completion zsh > ~/.zsh/completions/_hwaro
```

#### Fish

`~/.config/fish/config.fish`에 추가합니다:

```fish
hwaro completion fish | source
```

completions 디렉터리에 저장해도 됩니다:

```bash
hwaro completion fish > ~/.config/fish/completions/hwaro.fish
```

### 완성 대상

자동 완성 스크립트는 다음을 탭으로 완성합니다.

- **명령**: `hwaro <TAB>` → `init`, `build`, `serve`, `new`, `deploy`, `tool`, `completion`
- **하위 명령**: `hwaro tool <TAB>` → `convert`, `list`, `stats`, `validate`, `export` 등
- **플래그**: `hwaro build <TAB>` → `--output`, `--drafts`, `--minify` 등
- **위치 인자**: `hwaro completion <TAB>` → `bash`, `zsh`, `fish`
- **위치 인자 선택지**: `hwaro tool convert <TAB>` → `to-yaml`, `to-toml`

### 자동 갱신

자동 완성 스크립트는 명령 메타데이터에서 동적으로 생성됩니다. 새 명령이나 플래그가 추가된 버전으로 Hwaro를 업데이트한 뒤 스크립트를 다시 생성하면 자동으로 반영됩니다.

```bash
# hwaro 업데이트 후 다시 생성
eval "$(hwaro completion bash)"
```

## 함께 보기

- [CLI](/ko/start/cli/) — 전체 CLI 명령 레퍼런스
- [설정](/ko/start/config/) — 사이트 설정
- [빌드 훅](/ko/features/build-hooks/) — 커스텀 빌드 명령
