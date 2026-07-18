+++
title = "CLI"
description = "사이트를 만들고, 빌드하고, 서빙하는 명령"
weight = 3
toc = true
+++

Hwaro는 사이트를 만들고, 빌드하고, 서빙하는 명령을 제공합니다.

## 전역 플래그

이 플래그들은 모든 최상위 명령에서 동작하며 CLI가 터미널에 출력하는
방식을 제어합니다. 스크립트, CI 로그, 깔끔한 출력이 필요한 AI 에이전트에
특히 유용합니다.

| 플래그 / 환경 변수 | 설명 |
|----------------|-------------|
| `-q`, `--quiet` | 정보성 출력과 시작 배너를 숨김. 경고와 오류는 stderr에 계속 표시 |
| `NO_COLOR` (env) | 비어 있지 않은 값이면 모든 명령 출력에서 ANSI 색상 코드를 제거. [no-color.org](https://no-color.org)의 도구 공통 규약을 따름 |

stdout이 TTY가 아니면(예: `cat`으로 파이프, 파일로 리디렉션, 대부분의
CI 환경) 색상은 자동으로 꺼집니다. 어디서든 색상을 강제로 끄려면
`NO_COLOR=1`만 설정하면 됩니다. 별도 플래그는 필요 없습니다.

```bash
# 스크립트·CI용 무음 빌드 — 경고와 오류만 표시됨
hwaro build --quiet

# stdout이 TTY여도 ANSI 이스케이프 없는 일반 텍스트 출력
NO_COLOR=1 hwaro doctor
```

### 오류 분류

분류된 실패 경로는 안정적인 오류 코드와 그에 대응하는 프로세스 종료
코드를 함께 내보냅니다. 스크립트, CI, 에이전트가 사람 대상 메시지를
파싱하지 않고도 안정적으로 분기할 수 있습니다.

텍스트 모드에서는 오류 줄 앞에 코드가 붙습니다:

```
Error [HWARO_E_USAGE]: missing <path> argument
```

`--json`(또는 `--quiet`)에서는 분류된 오류가 stdout에 구조화된
페이로드로 출력됩니다:

```json
{
  "status": "error",
  "error": {
    "code": "HWARO_E_USAGE",
    "category": "usage",
    "message": "missing <path> argument",
    "hint": "Usage: hwaro new <path> [options] — run 'hwaro new --help' for details."
  }
}
```

분류되지 않은 실패는 기존 `Error: <message>` 형식과 종료 코드 `1`을
그대로 유지하므로, 이 규약은 기존 동작에 순수하게 추가만 됩니다.

| 코드 | 분류 | 종료 코드 | 설명 |
|------|----------|------|-------------|
| `HWARO_E_USAGE` | usage | 2 | 잘못되거나 누락된 플래그, 필수 인자 누락, 알 수 없는 명령 |
| `HWARO_E_CONFIG` | config | 3 | `config.toml` 누락, 파싱 불가 또는 유효하지 않음 |
| `HWARO_E_TEMPLATE` | template | 4 | Crinja 템플릿 렌더링 오류 |
| `HWARO_E_CONTENT` | content | 5 | 콘텐츠 파일 파싱 오류, 유효하지 않은 프론트 매터 |
| `HWARO_E_IO` | io | 6 | 파일시스템 접근 오류 (디렉터리 없음, 권한 거부) |
| `HWARO_E_NETWORK` | network | 7 | 배포 업로드, 원격 스캐폴드 가져오기 실패 |
| `HWARO_E_INTERNAL` | internal | 70 | 복구 불가능한 버그 또는 예기치 않은 상태 |
| *(미분류)* | — | 1 | 기존/일반 실패 경로 |
| *(성공)* | — | 0 | 명령 정상 완료 |

## 명령

### init

새 사이트를 만듭니다:

```bash
hwaro init                    # 기본값으로 즉시 초기화
hwaro init my-site            # my-site/에 초기화
hwaro init --wizard           # 대화형 위저드(TTY): 스캐폴드, 제목
hwaro init my-site --wizard   # 위저드; 디렉터리 프롬프트 생략 (경로는 인자 사용)
hwaro init my-site --scaffold blog
hwaro init my-site --scaffold docs
hwaro init my-site --scaffold book
```

**대화형 모드:**

대화형 터미널에서 `--wizard`를 주면 안내 흐름이 열립니다. 디렉터리,
스캐폴드, 사이트 제목을 차례로 묻고, 요약을 보여 준 뒤 확인을 받고
나서야 파일을 씁니다. 경로 인자를 함께 주면(`hwaro init my-site --wizard`)
위저드는 디렉터리 프롬프트를 건너뛰고 그 경로를 그대로 사용합니다.

`--wizard` 없이 실행하면 `hwaro init`은 기본값으로 즉시 초기화합니다 —
스크립트와 CI가 기존에 의존하던 동작 그대로입니다.

모든 스캐폴드는 읽는 사람의 OS 색상 모드를 자동으로 따릅니다(공유 토큰
시스템이 CSS `light-dark()` 쌍을 사용). 스타일이 있는 스캐폴드에는
auto → light → dark로 순환하며 선택을 `localStorage`에 기억하는 헤더
테마 전환 버튼이 들어 있습니다. 한 가지 모드로 고정하려면
`css/style.css` 끝에 `:root { color-scheme: dark; }`(또는 `light`)를
추가합니다.

GitHub 저장소의 원격 스캐폴드도 사용할 수 있습니다:

```bash
# GitHub 축약형
hwaro init my-site --scaffold github:user/repo
hwaro init my-site --scaffold github:user/repo/docs

# 전체 URL
hwaro init my-site --scaffold https://github.com/user/repo
hwaro init my-site --scaffold https://github.com/user/repo/tree/main/docs
```

원격 스캐폴드는 저장소에서 `config.toml`, `templates/`, `static/`,
콘텐츠 구조를 가져옵니다. 콘텐츠 파일은 프론트 매터(메타데이터)만
유지하므로 원본 본문 없이도 기대되는 페이지 구조를 확인할 수 있습니다.
API 요청 제한을 피하려면 `GITHUB_TOKEN` 환경 변수를 설정합니다.

**옵션:**

| 플래그 | 설명 |
|------|-------------|
| --scaffold TYPE | 내장 스캐폴드(`simple`, `bare`, `blog`, `docs`, `book`) 또는 원격 소스(`github:user/repo[/path]`, URL) |
| --wizard | 대화형 위저드 실행 (TTY 전용) |
| --agents MODE | AGENTS.md 콘텐츠 모드: `remote`(가벼움, 기본값) 또는 `local`(전체 레퍼런스 내장) |
| -f, --force | 디렉터리가 비어 있지 않아도 강제로 생성 |
| --skip-agents-md | AGENTS.md 파일 생성 생략 |
| --skip-sample-content | 샘플 콘텐츠 파일 생성 생략 |
| --skip-taxonomies | 택소노미 설정과 템플릿 생략 |
| --include-multilingual LANGS | 다국어 지원 활성화 (예: `en,ko,ja`) |
| --minimal-config | 주석과 선택 섹션 없는 최소 `config.toml` 생성 |
| --list-scaffolds | 사용 가능한 내장 스캐폴드 목록 출력 후 종료 |
| --json | 기계가 읽을 수 있는 JSON 출력 (--list-scaffolds와 함께) |

### new

새 콘텐츠 파일을 만듭니다:

```bash
hwaro new                                     # 대화형 위저드(TTY): 모든 항목을 프롬프트로 입력
hwaro new content/about.md
hwaro new content/blog/my-post.md
hwaro new posts/my-post.md -a posts
hwaro new my-post.md --section blog --draft --tags "go,web" --date 2026-03-22
```

프론트 매터 템플릿이 채워진 마크다운 파일을 만듭니다. 커스터마이즈
가능한 템플릿인 **아키타입**을 지원합니다.

**대화형 모드:**

대화형 터미널에서 `<path>` 없이 `hwaro new`를 실행하면 안내 위저드가 열립니다.
제목, 설명, (제목과 섹션에서 만들어 낸) **추천 경로**, 태그, 날짜, 초안 여부,
아키타입을 차례로 묻고, 요약을 보여 준 뒤 확인을 받고 나서 파일을 씁니다.
이미 넘긴 플래그는 해당 프롬프트를 미리 채우므로 `hwaro new -t "My Post"`는
나머지만 묻습니다. 마지막 확인에서 `Ctrl-D`를 누르거나 `n`으로 답하면 아무것도
만들지 않고 취소합니다.

위저드는 비대화형 컨텍스트 — 파이프, CI, 에이전트, `--json`, `--quiet` — 에서는
절대 실행되지 않고 대신 분류된 `HWARO_E_USAGE` 오류를 출력하므로, 스크립트
호출은 예측 가능하게 유지됩니다. `<path>`(그리고 필요한 플래그)를 주면
프롬프트를 완전히 건너뜁니다.

**옵션:**

| 플래그 | 설명 |
|------|-------------|
| -t, --title TITLE | 콘텐츠 제목 |
| --date DATE | 콘텐츠 날짜 (기본값: 현재, 예: `2026-03-22`) |
| --draft | 초안으로 표시 |
| --tags TAGS | 쉼표로 구분한 태그 |
| -s, --section NAME | 섹션 디렉터리 (예: `blog`, `docs`) |
| -a, --archetype NAME | 사용할 아키타입 |
| --bundle | 단일 파일 대신 리프 번들 디렉터리(`foo/index.md`) 생성 |
| --no-bundle | 단일 파일(`foo.md`) 강제; `[content.new].bundle = true`보다 우선 |
| --list-archetypes | 현재 프로젝트의 아키타입 목록 출력 후 종료 |
| --json | 기계가 읽을 수 있는 JSON 출력 (아키타입 목록과 분류된 오류) |

**아키타입:**

아키타입은 새 콘텐츠의 기본 프론트 매터를 정의하는 `archetypes/` 디렉터리의 템플릿 파일입니다:

- `archetypes/default.md` - 모든 콘텐츠의 기본 템플릿
- `archetypes/posts.md` - `hwaro new posts/...`에 사용
- `archetypes/tools/develop.md` - `hwaro new tools/develop/...`에 사용

아키타입 파일은 플레이스홀더를 지원합니다: `{{ title }}`, `{{ date }}`, `{{ draft }}`, `{{ tags }}`, `{{ description }}`

아키타입 예시 (`archetypes/posts.md`):
```
---
title: "{{ title }}"
date: {{ date }}
draft: false
tags: []
---

# {{ title }}
```

아키타입 매칭 우선순위:
1. 명시적 `-a` 플래그 (예: `-a posts`는 `archetypes/posts.md` 사용)
2. 경로 기반 매칭 (예: `posts/hello.md`는 `archetypes/posts.md` 확인)
3. 중첩 경로는 상위 아키타입을 시도 (예: `tools/dev/x.md`는 `tools/dev.md`, 그다음 `tools.md`)
4. `archetypes/default.md`로 대체
5. 아키타입이 없으면 내장 템플릿 사용

### build

사이트를 `public/`으로 빌드합니다:

```bash
hwaro build
hwaro build --drafts
hwaro build --minify
hwaro build -i /path/to/my-site
hwaro build -i /path/to/my-site -o ./dist
```

**옵션:**

| 플래그 | 설명 |
|------|-------------|
| -i, --input DIR | 빌드할 프로젝트 디렉터리 (기본값: 현재 디렉터리) |
| -o, --output DIR | 출력 디렉터리 (기본값: public) |
| --base-url URL | `config.toml`의 `base_url`을 일시적으로 오버라이드 |
| -e, --env ENV | 환경 이름 (`config.<env>.toml` 오버라이드 로드) |
| -d, --drafts | 초안 콘텐츠 포함 |
| --include-expired | 만료된 콘텐츠 포함 |
| --include-future | 미래 날짜 콘텐츠 포함 |
| --minify | 출력 파일 압축(minify) (아래 참고) |
| --no-parallel | 병렬 처리 끄기 |
| --jobs N | 동시 렌더 워커 수 (기본값: 자동). 템플릿이 많은 사이트는 `1`-`2` 시도 (아래 참고) |
| --cache | 증분 빌드 캐시 사용 (아래 참고) |
| --full | 캐시를 비우고 전체 재빌드 강제 |
| --skip-highlighting | 구문 강조 끄기 |
| --skip-og-image | 자동 OG 이미지 생성 생략 |
| --skip-image-processing | 이미지 리사이즈와 LQIP 생성 생략 |
| --skip-cache-busting | CSS/JS 리소스의 캐시 버스팅 쿼리 파라미터 끄기 |
| --stream | 메모리 사용을 줄이는 스트리밍 빌드 사용 |
| --memory-limit SIZE | 스트리밍 빌드 메모리 제한 (예: `2G`, `512M`) |
| -v, --verbose | 상세 출력 |
| --profile | 단계별·템플릿별 빌드 시간 출력 |
| --debug | 빌드 후 디버그 정보 출력 |

**`--stream` / `--memory-limit` (스트리밍 빌드):**

페이지가 수천 개인 사이트에서는 렌더링된 HTML을 전부 메모리에 올리면 메모리 사용량이 커질 수 있습니다. 스트리밍 빌드는 Render 단계에서 페이지를 배치 단위로 처리하고, 각 배치를 디스크에 쓴 뒤 렌더링된 HTML을 해제합니다.

- `--stream`은 기본 배치 크기 500페이지로 스트리밍을 켭니다.
- `--memory-limit SIZE`는 스트리밍을 켜고 주어진 제한에 맞춰 배치 크기를 자동 계산합니다(휴리스틱: 페이지당 약 50KB). `G`, `M`, `K` 접미사를 받습니다(예: `2G`, `512M`, `256K`).
- 대체 수단으로 `HWARO_MEMORYLIMIT` 환경 변수도 설정할 수 있습니다. CLI 플래그가 환경 변수보다 우선합니다.

| `--stream` | `--memory-limit` | `HWARO_MEMORYLIMIT` | 결과 |
|---|---|---|---|
| - | - | - | 일반 빌드 |
| yes | - | - | 스트리밍, 배치=500 |
| - | 2G | - | 스트리밍, 배치≈20000 |
| - | - | 1G | 스트리밍, 배치≈10000 |
| yes | 512M | - | 스트리밍, 배치≈5000 |
| - | 2G | 1G | CLI 우선 (2G) |

빌드 결과물은 동일합니다 — 스트리밍은 빌드 중 메모리 사용량에만 영향을 줍니다.

**`--minify`:**

이 플래그는 생성된 파일을 줄이되 압축 전 출력과 시각적으로 동일하게 유지합니다:

- **HTML**: 주석을 제거하고(조건부 주석, SSI 지시문, `<!-- more -->`는 보존), 줄 끝 공백을 지우고, 태그 내부 공백을 접고(속성 사이 연속 공백은 한 칸으로, 따옴표로 감싼 속성 값은 그대로), 태그 사이 공백은 이웃 요소 분류에 따라 접습니다. 어느 한쪽 이웃이라도 블록 레벨 요소면 공백을 완전히 제거합니다(블록 형제의 시작·끝·사이 공백은 어차피 브라우저가 접습니다). 양쪽 이웃이 *모두* 인라인일 때만 한 칸을 남겨 `<a>x</a> <a>y</a>`처럼 눈에 보이는 간격을 보존합니다.
- **JSON**: 공백과 줄바꿈을 제거해 압축된 출력을 만듭니다.
- **XML**: 태그 사이 공백을 제거해 파일 크기를 줄입니다.

공백에 민감한 요소 — `<pre>`, `<code>`, `<textarea>`, `<script>`, `<style>`, `<svg>`, `<math>`, `<noscript>` — 는 공백 처리 전에 추출했다가 그대로 복원하므로 내용을 절대 건드리지 않습니다.

더 공격적인 축소(속성 따옴표 처리, 엔티티 축약 등)가 필요하면 `html-minifier-terser`나 `minify-html` 같은 전용 도구로 `public/`을 후처리합니다.

**`--cache` (증분 빌드):**

켜면 Hwaro가 파일 수정 시각과 콘텐츠 체크섬을 프로젝트 루트의 `.hwaro_cache.json` 파일에 기록합니다. 이후 빌드에서는 지난 빌드 이후 바뀐 파일만 다시 렌더링합니다. 캐시는 템플릿과 설정 체크섬도 추적합니다 — 템플릿이나 `config.toml`이 바뀌면 모든 항목이 자동으로 무효화되어 전체 페이지가 재빌드됩니다.

`--full`을 `--cache`와 함께 쓰면 깨끗하게 재빌드하면서도 다음 실행을 위한 캐시는 저장합니다:

```bash
hwaro build --cache --full
```

자세한 내용은 [증분 빌드](/ko/features/incremental-build/)를 참고합니다.

**`--jobs` (렌더 동시성):**

기본적으로 Hwaro는 CPU 기반으로 자동 산정한 수의 동시 워커로 페이지를 렌더링합니다. `--jobs N`은 그 수의 상한을 정합니다. 생성 결과물은 절대 바뀌지 않고, 한 번에 렌더링하는 페이지 수만 달라집니다.

값을 낮추면 **템플릿/Crinja 비중이 큰** 사이트의 빌드가 빨라질 수 있습니다. 이런 페이지는 작은 객체를 많이 할당해서, 워커가 약 2개를 넘어가면 코어를 더 쓰는 이득보다 가비지 컬렉터의 할당 락 경합이 더 커집니다. **마크다운 비중이 큰** 사이트(본문이 큰 페이지)는 계속 확장되므로 기본값은 자동으로 둡니다.

```bash
hwaro build --jobs 2   # 템플릿/숏코드가 많은 빌드라면 시도해 볼 것
```

설정하지 않으면 자동 기본값을 사용합니다. `--no-parallel`과 함께 쓰면 `--jobs`는 효과가 없습니다.

**`-i, --input`:**

지정하면 Hwaro가 빌드 전에 작업 디렉터리를 해당 경로로 바꿉니다. 먼저 `cd`하지 않고도 다른 디렉터리에 있는 사이트를 빌드할 수 있습니다.

- 모든 사이트 소스(`config.toml`, `content/`, `templates/`, `static/`)를 입력 디렉터리에서 읽습니다.
- **`-o` 없이:** 기본 출력 디렉터리 `public/`은 입력 디렉터리 안에 만들어집니다(즉, 그 사이트 자신의 `public/` 폴더). 이것이 자연스러운 동작입니다 — `hwaro build -i ../my-site`는 `../my-site/public/`을 만듭니다.
- **`-o`와 함께:** 출력 경로는 (입력 디렉터리가 아니라) **현재 디렉터리** 기준으로 해석되므로, `hwaro build -i ../my-site -o ./dist`는 셸의 CWD에 있는 `./dist`에 출력합니다.
- `-i`를 생략하면 동작은 그대로입니다 — 현재 디렉터리를 사용합니다.

### serve

라이브 리로드(기본 활성화)가 있는 개발 서버를 시작합니다:

```bash
hwaro serve
hwaro serve --port 8080
hwaro serve --open
hwaro serve --access-log
hwaro serve --no-live-reload
hwaro serve -i /path/to/my-site
hwaro serve -i /path/to/my-site -p 8080
```

**옵션:**

| 플래그 | 설명 |
|------|-------------|
| -i, --input DIR | 서빙할 프로젝트 디렉터리 (기본값: 현재 디렉터리) |
| -b, --bind HOST | 바인드 주소 (기본값: 127.0.0.1) |
| -p, --port PORT | 포트 번호 (기본값: 3000) |
| --base-url URL | `config.toml`의 `base_url`을 일시적으로 오버라이드 |
| -e, --env ENV | 환경 이름 (`config.<env>.toml` 오버라이드 로드) |
| --minify | 압축된 출력 서빙 |
| --jobs N | 동시 렌더 워커 수 (기본값: 자동). 템플릿이 많은 사이트는 `1`-`2` 시도 |
| --open | 시작 후 브라우저 열기 |
| -d, --drafts | 초안 콘텐츠 포함 |
| --include-expired | 만료된 콘텐츠 포함 |
| --include-future | 미래 날짜 콘텐츠 포함 |
| -v, --verbose | 상세 출력 |
| --debug | 재빌드마다 디버그 정보 출력 |
| --access-log | HTTP 접근 로그 표시 (예: GET 요청) |
| --no-error-overlay | 브라우저 내 오류 오버레이 끄기 (기본값: 활성화) |
| --live-reload | 파일 변경 시 브라우저 라이브 리로드 켜기 (기본값: 활성화; 하위 호환용으로 유지) |
| --no-live-reload | 파일 변경 시 브라우저 라이브 리로드 끄기 |
| --header "NAME: VALUE" | 커스텀 응답 헤더 추가 (반복 가능). `config.toml`의 `[serve.headers]`와 병합 (CLI 우선). `hwaro serve`에만 적용 |
| --cache | 빌드 캐시 사용 (변경 없는 파일 생략) |
| --stream | 메모리 사용을 줄이는 스트리밍 빌드 사용 |
| --memory-limit SIZE | 스트리밍 빌드 메모리 제한 (예: `2G`, `512M`) |
| --fast-start | 홈페이지 + 최신 N개 페이지를 먼저 렌더링하고 나머지는 백그라운드에서 렌더링 |
| --fast-start-count N | `--fast-start`로 먼저 렌더링할 최근 페이지 수 (기본값: 20) |
| --skip-cache-busting | CSS/JS 리소스의 캐시 버스팅 쿼리 파라미터 끄기 |
| --skip-og-image | 자동 OG 이미지 생성 생략 |
| --skip-image-processing | 이미지 리사이즈와 LQIP 생성 생략 |
| --profile | 단계별·템플릿별 빌드 시간 출력 |

> **대규모 사이트의 빠른 개발 서버:** `config.toml`에 `[og.auto_image] lazy_generate = true`를 설정하면 `hwaro serve` 중 일괄 OG 생성을 생략합니다. 이미지는 첫 요청 시 생성됩니다. 전체 설명과 `--fast-start`를 곁들인 권장 워크플로는 [자동 OG 이미지](/ko/features/og-images/) 문서를 참고합니다.

서버는 파일 변경을 감시해 자동으로 재빌드합니다. 무엇이 바뀌었는지에 따라 **스마트 재빌드 전략**을 사용합니다:

| 변경 유형 | 전략 | 설명 |
|-------------|----------|-------------|
| `config.toml` | 전체 재빌드 | 사이트 전체 재빌드 |
| `content/`만 | 증분 | 영향받는 콘텐츠 페이지만 재빌드 |
| `templates/`만 | 템플릿 재렌더링 | 기존 콘텐츠로 전체 페이지 재렌더링 |
| `static/`만 | 정적 복사 | 변경된 정적 파일만 복사 |
| 혼합 / 새 파일 / 삭제된 파일 | 전체 재빌드 | 사이트 전체 재빌드 |

**라이브 리로드:**

라이브 리로드는 **기본으로 켜져 있습니다**. 서버가 모든 HTML 응답에 작은 WebSocket 클라이언트 스크립트를 주입하고, 재빌드가 성공할 때마다 연결된 브라우저가 자동으로 페이지를 새로 고칩니다 — 수동 새로 고침이 필요 없습니다. 클라이언트는 재연결에 지수 백오프(1초–30초)를 사용하므로 서버를 재시작해도 연결이 영구히 끊기지 않습니다.

이 동작을 끄려면 `--no-live-reload`를 줍니다(프로덕션과 비슷한 전달 방식을 로컬에서 테스트할 때 유용합니다). `--live-reload` 플래그는 기존 호출과의 하위 호환을 위해 아무 동작 없는 별칭으로 남아 있습니다.

`-i`를 지정하면 서버는 해당 디렉터리로 `cd`한 것처럼 동작합니다 — 그 프로젝트 루트를 감시하고 서빙합니다.

**커스텀 응답 헤더 (`--header` / `[serve.headers]`):**

프로덕션 리버스 프록시, CDN, 정적 호스팅이 설정하는 헤더(보안 헤더, `Cache-Control`, 커스텀 CORS 등)를 재현해, 정적 출력을 배포하기 전에 로컬에서 테스트하는 용도입니다.

```toml
[serve.headers]
X-Frame-Options = "SAMEORIGIN"
X-Content-Type-Options = "nosniff"
Referrer-Policy = "strict-origin-when-cross-origin"
# Cache-Control = "public, max-age=3600"
```

```bash
hwaro serve --header "X-Custom: foo" --header "Cache-Control: no-store"
```

- CLI `--header` 값이 `config.toml`의 같은 키보다 우선합니다.
- 헤더는 **모든** 개발 서버 응답(HTML, 에셋, 404, 리디렉션, 라이브 리로드가 주입된 페이지)에 붙습니다.
- 이 기능은 `hwaro serve`에만 적용됩니다. `public/`에 쓰이는 파일은 그대로입니다.

### deploy

생성된 사이트를 설정된 대상에 배포합니다.

```bash
hwaro deploy [target ...]
hwaro deploy --dry-run
```

**옵션:**

| 플래그 | 설명 |
|------|-------------|
| -s, --source DIR | 배포할 소스 디렉터리 (기본값: deployment.source_dir 또는 public) |
| --dry-run | 실제로 쓰지 않고 계획된 변경만 표시 |
| --confirm | 배포 전 확인 요청 |
| --force | 강제 업로드/복사 (파일 비교 무시) |
| --max-deletes N | 최대 삭제 수 (기본값: deployment.maxDeletes 또는 256, -1이면 제한 없음) |
| --list-targets | 설정된 배포 대상 목록 출력 후 종료 |
| --json | 기계가 읽을 수 있는 JSON 출력 (--list-targets와 함께) |

### doctor

설정, 템플릿, 구조 문제를 진단합니다 (최상위 단축 명령):

```bash
hwaro doctor               # 설정, 템플릿, 구조 문제 진단
hwaro doctor --fix         # 설정 값 정규화 (base_url 끝 슬래시, sitemap priority…)
hwaro doctor --approve     # 권장 설정 섹션을 config.toml에 추가
hwaro doctor --full        # 둘 다 (--fix --approve와 동일)
```

**종료 코드.** `doctor`는 보고된 가장 심각한 문제를 기준으로 분류된
종료 코드를 반환하므로, CI 파이프라인이 이 값으로 바로 게이트를 걸 수
있습니다:

| 결과 | 종료 코드 |
|---|---|
| 문제 없음, 경고만, 또는 info 수준 발견 | `0` |
| 설정 오류 (`config.toml` 누락/손상) | `3` (`HWARO_E_CONFIG`) |
| 템플릿 오류 (필수 파일 누락, 닫히지 않은 태그) | `4` (`HWARO_E_TEMPLATE`) |
| 콘텐츠 오류 (잘못된 프론트 매터, 해당 검사가 도입되면) | `5` (`HWARO_E_CONTENT`) |
| 그 외 error 수준 문제 | `1` |

경고(빈 `base_url`, 끝 슬래시, 중복 택소노미 이름 등)는 참고용이며
종료 코드를 바꾸지 않습니다.

콘텐츠 검증에는 `hwaro tool validate`를 사용합니다. 자세한 내용은 [doctor](/ko/start/tools/doctor/)를 참고합니다.

### tool

콘텐츠 관리를 위한 유틸리티 도구:

```bash
# 콘텐츠 도구
hwaro tool list all             # 전체 콘텐츠 파일 목록
hwaro tool list drafts          # 초안 파일 목록
hwaro tool convert to-yaml      # 프론트 매터를 YAML로 변환
hwaro tool convert to-toml      # 프론트 매터를 TOML로 변환
hwaro tool convert to-json      # 프론트 매터를 JSON으로 변환
hwaro tool check-links          # 죽은 외부 링크 검사
hwaro tool stats                # 콘텐츠 통계 표시
hwaro tool validate             # 콘텐츠 프론트 매터와 마크업 검증
hwaro tool unused-assets        # 참조되지 않는 정적 파일 찾기

# 사이트 도구
hwaro tool platform netlify       # Netlify 설정 생성
hwaro tool platform vercel        # Vercel 설정 생성
hwaro tool platform cloudflare    # Cloudflare Pages 설정 생성
hwaro tool platform github-pages  # GitHub Pages 배포 워크플로 생성
hwaro tool platform gitlab-ci     # GitLab CI 설정 생성
hwaro tool platform codeberg-pages # Codeberg Pages(Forgejo Actions) 워크플로 생성
hwaro tool doctor                 # 설정/템플릿/구조 문제 진단
hwaro tool import hugo /path      # Hugo에서 가져오기
hwaro tool import jekyll /path    # Jekyll에서 가져오기
hwaro tool export hugo            # Hugo 형식으로 내보내기
hwaro tool export jekyll          # Jekyll 형식으로 내보내기
hwaro tool agents-md --write      # AGENTS.md를 파일로 쓰기

# JSON 출력
hwaro tool list all --json
hwaro tool stats --json
hwaro tool validate --json
hwaro tool unused-assets --json
hwaro tool doctor --json
hwaro tool check-links --json
```

**서브커맨드:**

| 분류 | 서브커맨드 | 설명 |
|----------|------------|-------------|
| 콘텐츠 | [list](/ko/start/tools/list/) | 상태별 콘텐츠 파일 목록 (all, drafts, published) |
| 콘텐츠 | [convert](/ko/start/tools/convert/) | 프론트 매터를 TOML, YAML, JSON 형식 간 변환 |
| 콘텐츠 | [check-links](/ko/start/tools/check-links/) | 콘텐츠 파일의 죽은 링크 검사 |
| 콘텐츠 | [stats](/ko/start/tools/stats/) | 콘텐츠 통계 표시 |
| 콘텐츠 | [validate](/ko/start/tools/validate/) | 콘텐츠 프론트 매터와 마크업 검증 |
| 콘텐츠 | [unused-assets](/ko/start/tools/unused-assets/) | 참조되지 않는 정적 파일 찾기 |
| 사이트 | [platform](/ko/start/tools/platform/) | 플랫폼 설정과 CI/CD 워크플로 파일 생성 |
| 사이트 | [doctor](/ko/start/tools/doctor/) | 설정, 템플릿, 구조 문제 진단 |
| 사이트 | import | WordPress, Jekyll, Hugo, Notion, Obsidian, Hexo, Astro, Eleventy에서 콘텐츠 가져오기 |
| 사이트 | [export](/ko/start/tools/export/) | 콘텐츠를 Hugo 또는 Jekyll로 내보내기 |
| 사이트 | [agents-md](/ko/start/tools/agents-md/) | AGENTS.md 파일 생성 또는 갱신 |

**공통 옵션:**

| 플래그 | 설명 |
|------|-------------|
| -c, --content DIR | 특정 콘텐츠 디렉터리로 제한 |
| -j, --json | 결과를 JSON으로 출력 |
| -h, --help | 도움말 표시 |

자세한 사용법은 [도구와 자동 완성](/ko/start/tools/)을 참고합니다.

### completion

셸 자동 완성 스크립트를 생성합니다:

```bash
hwaro completion bash    # Bash 자동 완성 스크립트
hwaro completion zsh     # Zsh 자동 완성 스크립트
hwaro completion fish    # Fish 자동 완성 스크립트
```

**설치:**

```bash
# Bash (~/.bashrc에 추가)
eval "$(hwaro completion bash)"

# Zsh (~/.zshrc에 추가)
eval "$(hwaro completion zsh)"

# Fish (~/.config/fish/config.fish에 추가)
hwaro completion fish | source
```

자세한 설치 방법은 [도구와 자동 완성](/ko/start/tools/)을 참고합니다.

## 예시

```bash
# 개발 워크플로
hwaro serve --drafts --verbose

# HTTP 접근 로그를 켠 개발
hwaro serve --access-log

# 라이브 리로드 없는 개발 (프로덕션과 비슷한 서빙)
hwaro serve --no-live-reload

# 프로덕션 빌드
hwaro build

# 커스텀 출력 디렉터리
hwaro build -o dist

# 특정 포트에서 미리 보기
hwaro serve -p 8000 --open

# 다른 디렉터리의 사이트 빌드
hwaro build -i ~/projects/my-blog

# 다른 위치의 프로젝트를 빌드해 현재 디렉터리에 출력
hwaro build -i ~/projects/my-blog -o ./output

# 증분 빌드 (변경 없는 파일 생략)
hwaro build --cache

# 전체 재빌드 강제 + 캐시 재생성
hwaro build --cache --full

# 대규모 사이트용 스트리밍 빌드
hwaro build --stream
hwaro build --memory-limit 512M

# 환경 변수로 스트리밍 빌드
HWARO_MEMORYLIMIT=1G hwaro build

# 다른 디렉터리의 사이트 서빙
hwaro serve -i ~/projects/my-blog --open
```

## 전역 옵션

| 플래그 | 설명 |
|------|-------------|
| -h, --help | 도움말 표시 |
| -v, --verbose | 상세 출력 |

## 함께 보기

- [설정](/ko/start/config/) — CLI 플래그가 오버라이드하는 설정 옵션
- [빌드 훅](/ko/features/build-hooks/) — 빌드 전/후 명령
- [도구와 자동 완성](/ko/start/tools/) — 유틸리티 서브커맨드
