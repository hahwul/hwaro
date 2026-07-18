+++
title = "GitHub Pages"
description = "Hwaro 사이트를 GitHub Pages에 배포"
weight = 2
+++

GitHub Pages에 Hwaro 사이트를 배포해 무료로 호스팅합니다.

## 사전 준비

- GitHub 저장소
- 빌드할 수 있는 Hwaro 사이트

## 방법 1: GitHub Actions (권장)

공식 [`hahwul/hwaro`](https://github.com/hahwul/hwaro) 액션을 사용하면 Hwaro를 직접 설치하지 않고도 빌드와 배포를 처리할 수 있습니다.

### 워크플로 생성

다음 명령으로 워크플로 파일을 자동 생성합니다:

```bash
hwaro tool platform github-pages
```

또는 `.github/workflows/deploy.yml`을 직접 작성합니다:

```yaml
---
name: Hwaro CI/CD

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Build Only
        uses: hahwul/hwaro@main
        with:
          build_only: true

  deploy:
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - name: Checkout
        uses: actions/checkout@v6

      - name: Build and Deploy
        uses: hahwul/hwaro@main
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
```

### 액션 입력값

| 입력 | 설명 | 기본값 |
|-------|-------------|---------|
| `build_dir` | Hwaro 사이트가 있는 디렉터리 | `.` (저장소 루트) |
| `build_only` | 배포 없이 빌드만 수행 | `false` |
| `token` | 배포에 사용할 GitHub 토큰 | — |

Hwaro 사이트가 하위 디렉터리(예: `docs/`)에 있다면 `build_dir`를 지정합니다:

```yaml
- name: Build and Deploy
  uses: hahwul/hwaro@main
  with:
    build_dir: "docs"
    token: ${{ secrets.GITHUB_TOKEN }}
```

### OG 이미지 캐시

이 액션은 배포 사이에 OG 이미지를 자동으로 캐시합니다. 매 빌드 전에 `gh-pages` 브랜치에서 이전에 생성한 이미지를 복원하고 `--cache` 모드를 켭니다. 제목·설명·URL 같은 콘텐츠가 바뀌었거나 OG 설정이 갱신된 페이지만 이미지를 다시 생성하므로, 규모가 큰 사이트에서 빌드가 크게 빨라집니다.

### GitHub Pages 설정

1. 저장소 **Settings** → **Pages**로 이동
2. "Build and deployment"에서 **Deploy from a branch** 선택
3. `gh-pages` 브랜치와 `/ (root)` 폴더 선택
4. `main` 브랜치에 푸시하면 배포가 시작됩니다

### Base URL 설정

`config.toml`을 수정합니다:

```toml
# 사용자/조직 사이트 (username.github.io)
base_url = "https://username.github.io"

# 프로젝트 사이트 (username.github.io/repo)
base_url = "https://username.github.io/repo"
```

## 방법 2: `hwaro deploy`로 배포

배포 스크립트 `scripts/deploy-ghpages.sh`를 작성합니다:

```bash
#!/bin/bash
set -e

SOURCE_DIR="${1:?Usage: deploy-ghpages.sh <source-dir>}"
REMOTE_URL=$(git remote get-url origin)
TMPDIR=$(mktemp -d)

cp -r "$SOURCE_DIR"/. "$TMPDIR"
touch "$TMPDIR/.nojekyll"

cd "$TMPDIR"
git init -b gh-pages
git add -A
git commit -m "Deploy to GitHub Pages"
git push --force "$REMOTE_URL" gh-pages

rm -rf "$TMPDIR"
```

```bash
chmod +x scripts/deploy-ghpages.sh
```

`config.toml`에 타깃을 추가합니다:

```toml
[[deployment.targets]]
name = "github-pages"
command = "scripts/deploy-ghpages.sh {source}"
```

이제 빌드하고 배포합니다:

```bash
hwaro build
hwaro deploy github-pages

# 배포하지 않고 미리 보기
hwaro deploy github-pages --dry-run
```

### GitHub Pages 설정

1. 저장소 **Settings** → **Pages**로 이동
2. "Build and deployment"에서 **Deploy from a branch** 선택
3. `gh-pages` 브랜치와 `/ (root)` 폴더 선택
4. **Save** 클릭

## 방법 3: 브랜치 수동 배포

```bash
hwaro build

# orphan 브랜치 생성
git checkout --orphan gh-pages

# 모든 파일 제거
git rm -rf .

# 빌드된 사이트 복사
cp -r public/* .

# 커밋 후 푸시
git add .
git commit -m "Deploy site"
git push origin gh-pages --force

# main 브랜치로 복귀
git checkout main
```

## 커스텀 도메인

### DNS 설정

`username.github.io`를 가리키는 CNAME 레코드를 추가합니다:

| 타입 | 이름 | 값 |
|------|------|-------|
| CNAME | www | username.github.io |
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |

### CNAME 파일 추가

`static/CNAME` 파일을 만듭니다:

```
www.yourdomain.com
```

### 설정 변경

```toml
base_url = "https://www.yourdomain.com"
```

### HTTPS 활성화

1. 저장소 **Settings** → **Pages**로 이동
2. **Enforce HTTPS** 체크

## 문제 해결

### 404 오류

- `base_url`이 GitHub Pages URL과 일치하는지 확인합니다
- CNAME 파일이 `static/` 디렉터리에 있는지 확인합니다
- 배포가 완료될 때까지 몇 분 기다립니다

### 에셋이 로드되지 않을 때

- `base_url` 끝에 슬래시가 없는지 확인합니다
- 에셋 경로가 `{{ base_url }}` 접두사를 사용하는지 확인합니다

### 빌드 실패

- Actions 로그에서 오류 메시지를 확인합니다
- `build_dir`가 올바른 디렉터리를 가리키는지 확인합니다

## 저장소 구조 예시

```
my-site/
├── .github/
│   └── workflows/
│       └── deploy.yml
├── content/
├── templates/
├── static/
│   └── CNAME
├── config.toml
└── README.md
```

## 함께 보기

- [배포 설정](/ko/deploy/config/) — 타깃 설정과 매처
- [CLI](/ko/start/cli/) — 배포 명령 옵션 전체
- 다른 플랫폼: [GitLab CI](/ko/deploy/gitlab-ci/) | [Netlify](/ko/deploy/netlify/) | [Vercel](/ko/deploy/vercel/) | [Codeberg Pages](/ko/deploy/codeberg-pages/)
