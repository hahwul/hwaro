+++
title = "빌드 훅"
description = "빌드 전후에 사용자 정의 셸 명령을 실행합니다"
weight = 15
toc = true
+++

빌드 훅으로 빌드 전후에 사용자 정의 셸 명령을 실행할 수 있습니다. 의존성 설치, 데이터 전처리, 에셋 최적화, 배포 트리거 같은 작업에 유용합니다.

## 설정

`config.toml`에 훅을 정의합니다.

```toml
[build]
hooks.pre = ["npm install", "npx tsc"]
hooks.post = ["npm run minify", "npx pagefind --site public"]
```

| 키 | 타입 | 기본값 | 설명 |
|-----|------|---------|-------------|
| hooks.pre | array | [] | 빌드 **전에** 실행할 명령 |
| hooks.post | array | [] | 빌드 **후에** 실행할 명령 |

## 동작 방식

### 빌드 전 훅

빌드 전 훅은 콘텐츠 처리가 시작되기 **전에** 실행됩니다. 다음 작업에 적합합니다.

- 의존성 설치
- 에셋 컴파일(TypeScript, Tailwind/PostCSS 등 — SCSS는 [Sass/SCSS](/ko/features/sass/) 내장 컴파일러로 처리합니다)
- 데이터 가져오기 스크립트 실행
- 콘텐츠 전처리

```toml
[build]
hooks.pre = [
  "npm ci",
  "npx tailwindcss -i src/input.css -o static/assets/css/main.css",
  "python scripts/fetch-data.py"
]
```

빌드 전 훅이 **실패**하면(0이 아닌 상태로 종료) 빌드가 **중단**됩니다. 의존성이 빠졌거나 에셋이 깨진 상태로 빌드되는 일을 막기 위해서입니다.

### 빌드 후 훅

빌드 후 훅은 사이트가 출력 디렉터리에 생성된 **후에** 실행됩니다. 다음 작업에 적합합니다.

- 이미지 최적화
- 에셋 압축(minify)
- 검색 인덱스 생성(예: Pagefind)
- 사이트 배포
- 검증 검사 실행

```toml
[build]
hooks.post = [
  "npx imagemin public/images/* --out-dir=public/images",
  "npx pagefind --site public",
  "./scripts/deploy.sh"
]
```

빌드 후 훅이 **실패**하면 경고만 표시되고 빌드 자체는 실패로 처리되지 **않습니다**. 생성된 사이트는 그대로 유지됩니다.

## 실행 순서

명령은 정의된 순서대로 **차례로** 실행됩니다.

```toml
[build]
hooks.pre = ["echo Step 1", "echo Step 2", "echo Step 3"]
```

출력:

```
Running pre-build hook: echo Step 1
Step 1
Running pre-build hook: echo Step 2
Step 2
Running pre-build hook: echo Step 3
Step 3
```

## serve 모드

빌드 훅은 `hwaro serve` 중에도 실행됩니다.

- 서버 시작 시 **최초 빌드**에서 훅이 실행됩니다
- 파일 변경으로 트리거되는 **재빌드마다 다시 실행**됩니다
- 설정 변경은 자동으로 반영됩니다 — `config.toml`의 `hooks.pre`나 `hooks.post`를 수정하면 다음 재빌드부터 새 명령이 적용됩니다

## 활용 사례

### TypeScript 컴파일

```toml
[build]
hooks.pre = ["npx tsc --outDir static/assets/js"]
```

### Tailwind CSS

```toml
[build]
hooks.pre = [
  "npx tailwindcss -i src/styles.css -o static/assets/css/styles.css --minify"
]
```

### Pagefind 검색

빌드 후 클라이언트 사이드 검색 인덱스를 생성합니다.

```toml
[build]
hooks.post = ["npx pagefind --site public"]
```

### 이미지 최적화

```toml
[build]
hooks.post = [
  "npx imagemin public/**/*.{jpg,png} --out-dir=public"
]
```

### 사용자 정의 배포 스크립트

```toml
[build]
hooks.post = ["./scripts/deploy.sh"]
```

### 전체 파이프라인 예시

```toml
[build]
hooks.pre = [
  "npm ci",
  "npx tsc",
  "npx tailwindcss -i src/input.css -o static/assets/css/main.css --minify"
]
hooks.post = [
  "npx pagefind --site public",
  "npx imagemin public/images/* --out-dir=public/images",
  "echo 'Build complete!'"
]
```

## 오류 처리

| 훅 유형 | 실패 시 |
|-----------|------------|
| 빌드 전 | ❌ 빌드 **중단** — 콘텐츠를 처리하지 않음 |
| 빌드 후 | ⚠️ 경고 표시 — 생성된 사이트는 유지 |

필수 준비 작업(빌드 전)은 반드시 성공해야 하고, 선택적 최적화 작업(빌드 후)은 빌드 출력을 막지 않도록 설계되어 있습니다.

## 팁

- **훅은 빠르게 유지**: 느린 훅은 `hwaro serve` 중 재빌드할 때마다 실행됩니다. 캐싱이나 조건부 실행을 고려합니다.
- **복잡한 작업은 스크립트로**: 여러 단계가 필요하면 셸 스크립트를 작성해 훅에서 호출합니다: `hooks.pre = ["./scripts/setup.sh"]`
- **의존성 확인**: 도구를 실행하기 전에 `command -v`로 사용 가능 여부를 확인합니다:
  ```bash
  command -v npx >/dev/null 2>&1 && npx pagefind --site public
  ```
- **자동 인클루드와 조합**: 빌드 전 훅으로 CSS/JS를 컴파일하고, [자동 인클루드](/ko/features/auto-includes/)가 자동으로 불러오게 합니다.

## 함께 보기

- [설정](/ko/start/config/) — 설정 전체 참조
- [자동 인클루드](/ko/features/auto-includes/) — CSS/JS 자동 로드
- [검색](/ko/features/search/) — Pagefind 빌드 후 훅으로 만드는 검색 인덱스
- [배포](/ko/deploy/) — 배포 옵션
